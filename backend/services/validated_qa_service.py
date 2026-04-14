import logging
import re
from datetime import datetime, timezone
from typing import Optional, List
from uuid import UUID
from db import supabase
from services.ollama_embedder import embed_single
from utils.activity import log_activity

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REFLAG_THRESHOLD = 0.30
REFLAG_MIN_TOTAL = 3

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

    embedding = await embed_single(rating_row["question_text"])
    embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"

    question = rating_row["question_text"]
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


async def check_validated_match(question_text: str) -> dict:
    embedding = await embed_single(question_text)
    embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"

    rpc_resp = supabase.rpc(
        "search_validated_qa", {"q_embedding": embedding_str, "match_count": 1}
    ).execute()
    if not rpc_resp.data:
        return {"match_type": "none"}

    match = rpc_resp.data[0]
    distance = match.get("distance", 1.0)

    if distance <= 0.10:
        return {"match_type": "direct", "validated_qa": match}
    elif distance <= 0.25:
        return {"match_type": "context", "validated_qa": match}
    else:
        return {"match_type": "none"}


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
    search: Optional[str] = None, limit: int = 50, offset: int = 0
) -> dict:
    columns = (
        "id, question_text, validated_answer, equipment_type, fault_code, "
        "validated_by, validated_at, thumbs_up_count, thumbs_down_count, "
        "is_reflagged, updated_at"
    )
    query = supabase.table("validated_qa").select(columns)

    if search:
        query = query.ilike("question_text", f"%{search}%")

    query = query.order("updated_at", desc=True).range(offset, offset + limit - 1)
    data = query.execute().data

    count_query = supabase.table("validated_qa").select("id", count="exact")
    if search:
        count_query = count_query.ilike("question_text", f"%{search}%")
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

    columns = (
        "id, question_text, validated_answer, equipment_type, fault_code, "
        "validated_by, validated_at, thumbs_up_count, thumbs_down_count, "
        "is_reflagged, updated_at"
    )
    result = (
        supabase.table("validated_qa")
        .update(update_data)
        .eq("id", qa_id)
        .select(columns)
        .execute()
    )

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

    supabase.table("validated_qa").delete().eq("id", qa_id).execute()

    supabase.table("answer_ratings").update({"review_status": "pending"}).eq(
        "id", rating_id
    ).execute()

    return qa_id
