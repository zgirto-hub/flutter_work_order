import logging
import re
from datetime import datetime, timezone
from typing import Optional, List
from uuid import UUID
from db import supabase
from services.ollama_embedder import embed_single, EmbedderTimeoutError
from utils.activity import log_activity

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REFLAG_THRESHOLD = 0.30
REFLAG_MIN_TOTAL = 3
_ALLOWED_SORTS = {"recent", "most_used", "most_problematic"}

# Simple patterns for equipment type and fault code extraction (FR-019)
_EQUIPMENT_PATTERNS = [
    re.compile(
        r"\b(Boeing|Airbus|Bombardier|Embraer|Cessna|ATR)\s*(\d{2,4}[A-Z]?(?:-\d{1,4})?)\b",
        re.IGNORECASE,
    ),
    re.compile(r"\b(B7[0-9]{2}|A3[0-9]{2}|A2[0-9]{2}|CRJ|ERJ|DHC-\d)\b", re.IGNORECASE),
]
_FAULT_CODE_PATTERNS = [
    re.compile(
        r"\bATA\s*(?:chapter\s*)?(\d{2}(?:-\d{2}(?:-\d{2})?)?)\b", re.IGNORECASE
    ),
    re.compile(r"\b(\d{2}-\d{2}-\d{2})\b"),  # ATA format: XX-XX-XX
]


def _extract_equipment_type(text: str) -> Optional[str]:
    for pat in _EQUIPMENT_PATTERNS:
        m = pat.search(text)
        if m:
            return m.group(0).strip()
    return None


def _extract_fault_code(text: str) -> Optional[str]:
    for pat in _FAULT_CODE_PATTERNS:
        m = pat.search(text)
        if m:
            return m.group(0).strip()
    return None


async def _rewrite_with_summary(question: str, session_summary: Optional[str]) -> str:
    """Rewrite a (possibly context-dependent) question into a self-contained form
    using the session summary captured at rating time. Returns the original
    question if there's no summary or the rewrite fails.

    This matters on the validation write path: without expansion, a bare
    follow-up like "in english" would be embedded as-is into validated_qa and
    could match unrelated future queries.
    """
    if not session_summary or not question.strip():
        return question

    try:
        from services.ollama_generator import generate

        prompt = (
            "You are a search query rewriter. Given a session summary and a "
            "follow-up question, rewrite the question into a single self-contained "
            "query. Resolve all pronouns and references (e.g. 'it', 'that', 'in "
            "english') using the summary. Preserve the original language. "
            "Reply with ONLY the rewritten query — no explanation.\n\n"
            f"SESSION SUMMARY:\n{session_summary}\n\n"
            f"FOLLOW-UP QUESTION: {question}"
        )
        result = await generate(prompt, timeout=10.0)
        rewritten = result.strip().strip('"').strip("'").strip()
        if not rewritten:
            return question
        return rewritten
    except Exception as e:
        logger.warning("Summary-aware rewrite failed, using original question: %s", e)
        return question


def save_rating(
    question_text: str,
    answer_text: str,
    source_chunks: List[dict],
    rating: str,
    rater_email: str,
    manual_id: Optional[str] = None,
    model_used: Optional[str] = None,
    session_summary: Optional[str] = None,
) -> str:
    review_status = None if rating == "positive" else "pending"
    row = {
        "question_text": question_text,
        "answer_text": answer_text,
        "source_chunks": source_chunks,
        "rating": rating,
        "review_status": review_status,
        "rater_email": rater_email,
    }
    if manual_id:
        row["manual_id"] = manual_id
    if model_used:
        row["model_used"] = model_used
    if session_summary:
        row["session_summary"] = session_summary

    result = supabase.table("answer_ratings").insert(row).execute()
    return result.data[0]["id"]


def get_flagged_answers() -> List[dict]:
    pending = (
        supabase.table("answer_ratings")
        .select("*")
        .eq("review_status", "pending")
        .order("created_at", desc=True)
        .execute()
    )

    reflagged = (
        supabase.table("validated_qa")
        .select(
            "id, question_text, validated_answer, source_chunks, "
            "validated_by, validated_at, updated_at, "
            "thumbs_up_count, thumbs_down_count, is_reflagged, rating_id"
        )
        .eq("is_reflagged", True)
        .order("updated_at", desc=True)
        .execute()
    )

    items = []
    for row in pending.data:
        items.append({**row, "is_reflagged": False, "source": "rating"})
    for row in reflagged.data:
        items.append(
            {
                **row,
                "answer_text": row["validated_answer"],
                "created_at": row["validated_at"],
                "source": "validated_qa",
            }
        )

    items.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    return items


async def review_answer(
    rating_id: str,
    action: str,
    corrected_answer: Optional[str],
    reviewer_email: str,
) -> str:
    # Check if this is a re-flagged validated_qa entry or a fresh answer_ratings entry
    vqa_resp = supabase.table("validated_qa").select("*").eq("id", rating_id).execute()
    vqa_data = vqa_resp.data[0] if vqa_resp.data else None

    if vqa_data and vqa_data.get("is_reflagged"):
        # Re-flagged validated_qa entry - update in place
        if action not in ("approve", "correct"):
            raise ValueError(f"Invalid action: {action}")

        if action == "approve":
            new_answer = vqa_data["validated_answer"]
        else:
            if not corrected_answer:
                raise ValueError("corrected_answer required for 'correct' action")
            new_answer = corrected_answer

        # Re-generate embedding in case context changed
        new_embedding = await embed_single(vqa_data["question_text"])
        embedding_str = "[" + ",".join(str(x) for x in new_embedding) + "]"

        now = datetime.now(timezone.utc).isoformat()
        supabase.table("validated_qa").update(
            {
                "validated_answer": new_answer,
                "question_embedding": embedding_str,
                "validated_by": reviewer_email,
                "validated_at": now,
                "thumbs_up_count": 0,
                "thumbs_down_count": 0,
                "is_reflagged": False,
                "updated_at": now,
            }
        ).eq("id", rating_id).execute()

        log_activity(
            reviewer_email,
            "manual",
            "reviewed_answer",
            target_label=vqa_data["question_text"][:80],
            detail=f"re-reviewed {action} -> is_reflagged=FALSE",
        )

        return rating_id

    # Fresh answer_ratings entry
    rating_resp = (
        supabase.table("answer_ratings")
        .select("*")
        .eq("id", rating_id)
        .single()
        .execute()
    )
    if not rating_resp.data:
        raise ValueError(f"Rating {rating_id} not found")

    rating_row = rating_resp.data

    if action == "approve":
        answer_to_validate = rating_row["answer_text"]
        new_status = "approved"
    elif action == "correct":
        if not corrected_answer:
            raise ValueError("corrected_answer required for 'correct' action")
        answer_to_validate = corrected_answer
        new_status = "corrected"
    else:
        raise ValueError(f"Invalid action: {action}")

    # Expand context-dependent questions (e.g. "in english") into self-contained
    # form using the session summary captured at rating time, so the stored
    # embedding reflects the real topic and can't cross-match unrelated queries.
    question = await _rewrite_with_summary(
        rating_row["question_text"], rating_row.get("session_summary")
    )
    embedding = await embed_single(question)
    embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"

    validated_row = {
        "question_text": question,
        "validated_answer": answer_to_validate,
        "question_embedding": embedding_str,
        "source_chunks": rating_row.get("source_chunks", []),
        "validated_by": reviewer_email,
        "rating_id": rating_id,
        "equipment_type": _extract_equipment_type(question),
        "fault_code": _extract_fault_code(question),
    }

    if rating_row.get("manual_id"):
        validated_row["manual_ids"] = [rating_row["manual_id"]]

    result = supabase.table("validated_qa").insert(validated_row).execute()
    validated_id = result.data[0]["id"]

    supabase.table("answer_ratings").update({"review_status": new_status}).eq(
        "id", rating_id
    ).execute()

    log_activity(
        reviewer_email,
        "manual",
        "reviewed_answer",
        target_label=rating_row["question_text"][:80],
        detail=f"{action} -> {new_status}",
    )

    return validated_id


async def check_validated_match(
    question_text: str, detected_system: Optional[str] = None
) -> dict:
    embedding = await embed_single(question_text)
    embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"

    rpc_resp = supabase.rpc(
        "search_validated_qa", {"q_embedding": embedding_str, "match_count": 3}
    ).execute()
    if not rpc_resp.data:
        return {"matches": []}

    # Apply topic guard to the best match (lowest distance)
    best_match = rpc_resp.data[0]
    best_distance = best_match.get("distance", 1.0)

    if detected_system and best_distance <= 0.25:
        try:
            row_resp = (
                supabase.table("validated_qa")
                .select("manual_ids")
                .eq("id", best_match["id"])
                .single()
                .execute()
            )
            row_manual_ids = (row_resp.data or {}).get("manual_ids") or []
            if row_manual_ids:
                from services.system_registry import get_manual_ids_for_system

                system_manual_ids = await get_manual_ids_for_system(
                    detected_system, supabase
                )
                if system_manual_ids and not (
                    set(str(m) for m in row_manual_ids)
                    & set(str(m) for m in system_manual_ids)
                ):
                    logger.info(
                        "[validated-qa] topic mismatch: row manual_ids=%s, detected_system=%s — rejecting cache match",
                        row_manual_ids,
                        detected_system,
                    )
                    return {"matches": []}
        except Exception as e:
            logger.warning("Topic guard lookup failed, allowing match: %s", e)

    # Build matches with similarity scores
    matches = []
    for match in rpc_resp.data:
        similarity = round(1.0 - match.get("distance", 1.0), 2)
        matches.append(
            {
                "id": str(match["id"]),
                "question_text": match["question_text"],
                "validated_answer": match["validated_answer"],
                "validated_by": match["validated_by"],
                "validated_at": match["validated_at"],
                "similarity": similarity,
            }
        )

    return {"matches": matches}


def update_validated_rating(validated_qa_id: str, rating: str) -> None:
    # Atomic increment via RPC to avoid read-then-write race condition
    col = "thumbs_up_count" if rating == "positive" else "thumbs_down_count"
    supabase.rpc(
        "increment_validated_rating",
        {"row_id": validated_qa_id, "col_name": col},
    ).execute()

    # Read back to check re-flagging threshold
    current = (
        supabase.table("validated_qa")
        .select("thumbs_up_count, thumbs_down_count")
        .eq("id", validated_qa_id)
        .single()
        .execute()
    )

    up = current.data.get("thumbs_up_count", 0) or 0
    down = current.data.get("thumbs_down_count", 0) or 0
    total = up + down

    if total >= REFLAG_MIN_TOTAL:
        ratio = down / total
        if ratio > REFLAG_THRESHOLD:
            supabase.table("validated_qa").update({"is_reflagged": True}).eq(
                "id", validated_qa_id
            ).execute()
            logger.info(
                f"Validated QA {validated_qa_id} re-flagged: {ratio:.2%} thumbs-down"
            )


def get_all_verified_answers(
    search: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    sort: str = "recent",
) -> dict:
    if sort not in _ALLOWED_SORTS:
        raise ValueError(f"Invalid sort: {sort}")

    columns = (
        "id, question_text, validated_answer, equipment_type, fault_code, "
        "validated_by, validated_at, thumbs_up_count, thumbs_down_count, "
        "is_reflagged, updated_at"
    )
    query = supabase.table("validated_qa").select(columns)
    count_query = supabase.table("validated_qa").select("id", count="exact")

    # Apply vote-count filter based on sort
    if sort == "most_used":
        query = query.gt("thumbs_up_count", 0)
        count_query = count_query.gt("thumbs_up_count", 0)
    elif sort == "most_problematic":
        query = query.gt("thumbs_down_count", 0)
        count_query = count_query.gt("thumbs_down_count", 0)

    # Apply search filter (ANDed with sort filter)
    if search:
        query = query.ilike("question_text", f"%{search}%")
        count_query = count_query.ilike("question_text", f"%{search}%")

    # Apply ordering
    if sort == "most_used":
        query = query.order("thumbs_up_count", desc=True).order(
            "updated_at", desc=True
        )
    elif sort == "most_problematic":
        query = query.order("thumbs_down_count", desc=True).order(
            "updated_at", desc=True
        )
    else:  # recent
        query = query.order("updated_at", desc=True)

    data = query.range(offset, offset + limit - 1).execute().data
    count = count_query.execute().count

    return {"items": data, "count": count}


async def update_verified_answer(
    qa_id: str,
    question_text: Optional[str],
    validated_answer: Optional[str],
    editor_email: str,
) -> dict:
    existing_resp = (
        supabase.table("validated_qa").select("*").eq("id", qa_id).single().execute()
    )
    if not existing_resp.data:
        raise ValueError("not found")

    existing = existing_resp.data
    update_data = {"updated_at": datetime.now(timezone.utc).isoformat()}

    if question_text is not None and question_text != existing.get("question_text"):
        embedding = await embed_single(question_text)
        embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"
        update_data["question_embedding"] = embedding_str
        update_data["question_text"] = question_text
        update_data["equipment_type"] = _extract_equipment_type(question_text)
        update_data["fault_code"] = _extract_fault_code(question_text)

    if validated_answer is not None:
        update_data["validated_answer"] = validated_answer

    result = (
        supabase.table("validated_qa").update(update_data).eq("id", qa_id).execute()
    )

    if not result.data:
        raise ValueError("not found")

    return result.data[0]


async def create_verified_answer(
    question_text: str,
    validated_answer: str,
    editor_email: str,
    source_manual_id: Optional[str] = None,
) -> dict:
    import uuid as _uuid

    if not question_text.strip() or not validated_answer.strip():
        raise ValueError("question and answer required")

    embedding = await embed_single(question_text)
    embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"

    equipment_type = _extract_equipment_type(question_text)
    fault_code = _extract_fault_code(question_text)

    # Synthetic rating_id groups primary + variants for cascade delete
    # (spec 080 fix: variants copy rating_id via _retro_expand_multi,
    # so using a fresh UUID groups them even without a real rating)
    synthetic_rating_id = str(_uuid.uuid4())

    insert_data = {
        "question_text": question_text,
        "validated_answer": validated_answer,
        "question_embedding": embedding_str,
        "validated_by": editor_email,
        "equipment_type": equipment_type,
        "fault_code": fault_code,
        "source_chunks": [],
        "manual_ids": [],
        "rating_id": synthetic_rating_id,
    }
    if source_manual_id:
        insert_data["source_manual_id"] = source_manual_id

    result = supabase.table("validated_qa").insert(insert_data).execute()

    return result.data[0]


def delete_verified_answer(qa_id: str) -> str:
    existing_resp = (
        supabase.table("validated_qa")
        .select("id, rating_id")
        .eq("id", qa_id)
        .single()
        .execute()
    )
    if not existing_resp.data:
        raise ValueError("not found")

    rating_id = existing_resp.data["rating_id"]

    if rating_id:
        supabase.table("validated_qa").delete().eq("rating_id", rating_id).execute()
        rating_lookup = (
            supabase.table("answer_ratings")
            .select("id")
            .eq("id", rating_id)
            .maybe_single()
            .execute()
        )
        if rating_lookup and rating_lookup.data:
            supabase.table("answer_ratings").update(
                {"review_status": "pending"}
            ).eq("id", rating_id).execute()
    else:
        supabase.table("validated_qa").delete().eq("id", qa_id).execute()

    return qa_id


async def review_answer_multi(
    rating_id: str,
    action: str,
    corrected_answer: Optional[str],
    reviewer_email: str,
    variant_texts: List[str],
    existing_validated_qa_id: Optional[str] = None,
) -> dict:
    """Insert multiple validated_qa rows from one approval, each with its own question variant.

    Args:
        rating_id: UUID of the answer_ratings row being approved.
        action: One of "approve", "correct", "retro_expand".
        corrected_answer: Required if action == "correct".
        reviewer_email: Email of the admin performing the review.
        variant_texts: List of question texts (including original) to insert as separate rows.
        existing_validated_qa_id: Required if action == "retro_expand"; the validated_qa row to expand.

    Returns:
        Dict with inserted_count, validated_qa_ids, rating_id, status.
    """
    if action not in ("approve", "correct", "retro_expand"):
        raise ValueError(f"Invalid action: {action}")

    if action == "retro_expand":
        if not existing_validated_qa_id:
            raise ValueError("existing_validated_qa_id required for retro_expand")
        return await _retro_expand_multi(
            existing_validated_qa_id, reviewer_email, variant_texts
        )

    # approve or correct flow
    if action == "correct" and not corrected_answer:
        raise ValueError("corrected_answer required for 'correct' action")

    # The Review Queue mixes two sources. If the rating_id is actually a
    # validated_qa.id (reflagged entry), handle via retro_expand path —
    # update the existing row + insert variants sharing its rating_id.
    vqa_lookup = (
        supabase.table("validated_qa").select("*").eq("id", rating_id).execute()
    )
    if vqa_lookup.data and vqa_lookup.data[0].get("is_reflagged"):
        vqa_row = vqa_lookup.data[0]
        new_answer = (
            corrected_answer if action == "correct" else vqa_row["validated_answer"]
        )
        now = datetime.now(timezone.utc).isoformat()
        new_embedding = await embed_single(vqa_row["question_text"])
        embedding_str = "[" + ",".join(str(x) for x in new_embedding) + "]"
        supabase.table("validated_qa").update(
            {
                "validated_answer": new_answer,
                "question_embedding": embedding_str,
                "validated_by": reviewer_email,
                "validated_at": now,
                "thumbs_up_count": 0,
                "thumbs_down_count": 0,
                "is_reflagged": False,
                "updated_at": now,
            }
        ).eq("id", rating_id).execute()

        # Expand with variants (they share the same rating_id as primary)
        extra_ids: List[str] = []
        if variant_texts:
            variants_result = await _retro_expand_multi(
                rating_id, reviewer_email, variant_texts
            )
            extra_ids = variants_result.get("validated_qa_ids", [])

        log_activity(
            reviewer_email,
            "manual",
            "reviewed_answer",
            target_label=vqa_row["question_text"][:80],
            detail=f"re-reviewed {action} with {len(extra_ids)} variants",
        )

        return {
            "inserted_count": 1 + len(extra_ids),
            "validated_qa_ids": [rating_id] + extra_ids,
            "rating_id": vqa_row.get("rating_id"),
            "status": "reviewed",
        }

    # Lookup the answer_ratings row
    rating_resp = (
        supabase.table("answer_ratings")
        .select("*")
        .eq("id", rating_id)
        .single()
        .execute()
    )
    if not rating_resp.data:
        raise ValueError(f"Rating {rating_id} not found")

    rating_row = rating_resp.data

    # Resolve the validated answer text
    if action == "approve":
        answer_to_validate = rating_row["answer_text"]
        new_status = "approved"
    else:
        answer_to_validate = corrected_answer
        new_status = "corrected"

    # Resolve shared fields
    manual_ids = [rating_row["manual_id"]] if rating_row.get("manual_id") else []
    source_chunks = rating_row.get("source_chunks", [])
    session_summary = rating_row.get("session_summary")

    # Pre-compute all embeddings - fail fast before any insert (FR-013 atomicity)
    embedded_rows = []
    for i, variant_text in enumerate(variant_texts):
        # Only apply session-summary rewrite to the first variant (original question).
        # Generated paraphrases are already self-contained; rewriting them could
        # unpredictably mutate admin-curated text if session_summary is non-null.
        if i == 0:
            question = await _rewrite_with_summary(variant_text, session_summary)
        else:
            question = variant_text
        embedding = await embed_single(question)
        embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"

        embedded_rows.append(
            {
                "question_text": question,
                "question_embedding": embedding_str,
                "equipment_type": _extract_equipment_type(question),
                "fault_code": _extract_fault_code(question),
            }
        )

    # Build the shared row dict (INV-2: same validated_answer across all variants)
    now = datetime.now(timezone.utc).isoformat()
    shared_row = {
        "validated_answer": answer_to_validate,
        "validated_by": reviewer_email,
        "rating_id": rating_id,
        "manual_ids": manual_ids,
        "source_chunks": source_chunks,
        "validated_at": now,
    }

    # Combine shared + per-variant fields
    rows_to_insert = []
    for variant in embedded_rows:
        row = {**shared_row}
        row["question_text"] = variant["question_text"]
        row["question_embedding"] = variant["question_embedding"]
        row["equipment_type"] = variant["equipment_type"]
        row["fault_code"] = variant["fault_code"]
        rows_to_insert.append(row)

    # Single batch insert (atomic)
    result = supabase.table("validated_qa").insert(rows_to_insert).execute()
    inserted_ids = [row["id"] for row in result.data]

    # Update answer_ratings status once
    supabase.table("answer_ratings").update({"review_status": new_status}).eq(
        "id", rating_id
    ).execute()

    # Log one activity for the batch
    log_activity(
        reviewer_email,
        "manual",
        "reviewed_answer",
        target_label=rating_row["question_text"][:80],
        detail=f"{action} -> {new_status} ({len(rows_to_insert)} variants)",
    )

    return {
        "inserted_count": len(inserted_ids),
        "validated_qa_ids": inserted_ids,
        "rating_id": rating_id,
        "status": new_status,
    }


async def _retro_expand_multi(
    existing_validated_qa_id: str,
    reviewer_email: str,
    variant_texts: List[str],
) -> dict:
    """Expand an existing verified entry with additional question variants.

    Reads shared fields from the existing validated_qa row and inserts new rows
    sharing the same validated_answer, rating_id, manual_ids, source_chunks.
    """
    # Lookup the existing validated_qa row
    existing_resp = (
        supabase.table("validated_qa")
        .select("*")
        .eq("id", existing_validated_qa_id)
        .single()
        .execute()
    )
    if not existing_resp.data:
        raise ValueError(f"Validated QA {existing_validated_qa_id} not found")

    existing = existing_resp.data

    # Shared fields from the existing row (INV-1, INV-2)
    now = datetime.now(timezone.utc).isoformat()
    shared_row = {
        "validated_answer": existing["validated_answer"],
        "validated_by": reviewer_email,
        "validated_at": now,
        "rating_id": existing.get("rating_id"),
        "manual_ids": existing.get("manual_ids", []),
        "source_chunks": existing.get("source_chunks", []),
        "equipment_type": existing.get("equipment_type"),
        "fault_code": existing.get("fault_code"),
    }

    # Pre-compute all embeddings - fail fast before any insert
    embedded_rows = []
    for variant_text in variant_texts:
        embedding = await embed_single(variant_text)
        embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"

        embedded_rows.append(
            {
                "question_text": variant_text,
                "question_embedding": embedding_str,
                "equipment_type": _extract_equipment_type(variant_text),
                "fault_code": _extract_fault_code(variant_text),
            }
        )

    # Build rows to insert
    rows_to_insert = []
    for variant in embedded_rows:
        row = {**shared_row}
        row["question_text"] = variant["question_text"]
        row["question_embedding"] = variant["question_embedding"]
        row["equipment_type"] = variant["equipment_type"]
        row["fault_code"] = variant["fault_code"]
        rows_to_insert.append(row)

    # Single batch insert (atomic)
    result = supabase.table("validated_qa").insert(rows_to_insert).execute()
    inserted_ids = [row["id"] for row in result.data]

    # Log activity (does NOT update answer_ratings - retro_expand leaves it untouched)
    log_activity(
        reviewer_email,
        "manual",
        "reviewed_answer",
        target_label=existing["question_text"][:80],
        detail=f"retro_expand -> {len(rows_to_insert)} variants",
    )

    return {
        "inserted_count": len(inserted_ids),
        "validated_qa_ids": inserted_ids,
        "rating_id": shared_row["rating_id"],
        "status": "expanded",
    }
