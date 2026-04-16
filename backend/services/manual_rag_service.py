import logging
import os
import re
import uuid
import time
from datetime import datetime, timezone
from uuid import UUID
from typing import List, Optional
from db import supabase
from services.manual_parser import parse, NoExtractableTextError
from services.manual_chunker import chunk_paragraphs, Chunk
from services.ollama_embedder import embed_many, embed_single, EmbedderTimeoutError
from services.manual_storage_service import save, delete as delete_file
from services.system_registry import detect_system, get_manual_ids_for_system
import services.validated_qa_service as validated_qa_service
from services.document_search_service import (
    search_document_chunks,
    fetch_parent_context,
)
from pydantic import BaseModel, Field
from typing import Optional as TypingOptional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class LatencyBreakdown(BaseModel):
    embed_ms: TypingOptional[int] = Field(default=None, ge=0)
    hyde_ms: TypingOptional[int] = Field(default=None, ge=0)
    rewrite_ms: TypingOptional[int] = Field(default=None, ge=0)
    retrieval_ms: TypingOptional[int] = Field(default=None, ge=0)
    rerank_ms: TypingOptional[int] = Field(default=None, ge=0)
    generator_ms: TypingOptional[int] = Field(default=None, ge=0)
    total_ms: int = Field(ge=0)


class _StageTimer:
    """Context manager for timing a pipeline stage."""

    def __init__(self, breakdown: dict, key: str):
        self.breakdown = breakdown
        self.key = key
        self._start = 0.0

    def __enter__(self):
        self._start = time.perf_counter()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is not None:
            self.breakdown[self.key] = None
        else:
            self.breakdown[self.key] = round((time.perf_counter() - self._start) * 1000)
        return False


def _empty_latency_breakdown() -> dict:
    return {
        "embed_ms": None,
        "hyde_ms": None,
        "rewrite_ms": None,
        "retrieval_ms": None,
        "rerank_ms": None,
        "generator_ms": None,
        "total_ms": None,
    }


# System instructions cache (avoids DB round-trip on every question)
_si_cache: dict = {"value": "", "ts": 0.0}
_SI_CACHE_TTL = 60.0  # seconds

# Chunk reranking thresholds (spec 044)
# MAX_CHUNK_DISTANCE: cosine distance ceiling; 0.30 distance = 0.70 similarity
MAX_CHUNK_DISTANCE = 0.55
# MAX_PROMPT_CHUNKS: max chunks sent to LLM after filtering
MAX_PROMPT_CHUNKS = 3

# Cross-manual synthesis limits (spec 046)
MAX_CHUNKS_PER_MANUAL = 3
MAX_MANUALS_FOR_SYNTHESIS = 8

# --- Validated QA confidence thresholds (spec 069) ---
RAG_CONFIDENCE_THRESHOLD = 0.70  # Minimum similarity to proceed to LLM
RAG_HIGH_CONFIDENCE = 0.85  # Score >= this → confidence: "high"

# --- Strict system prompt for validated QA RAG (spec 069) ---
VALIDATED_QA_SYSTEM_PROMPT = (
    "You are a technical assistant for a civil aviation maintenance management system (CMMS).\n\n"
    "Your job is to answer maintenance and operations questions using ONLY the context provided below.\n\n"
    "Rules:\n"
    "- Answer ONLY from the provided context. Do not use outside knowledge.\n"
    "- If the answer is not clearly stated in the context, respond with exactly: "
    '"I don\'t have that information in the knowledge base."\n'
    "- Never guess, infer, or make up technical specifications, procedures, or values.\n"
    "- Be concise and direct. Use bullet points for procedures.\n"
    '- Always refer to the source when answering (e.g. "According to source 1...").\n'
    "- If multiple sources are relevant, synthesize them into one clear answer."
)

# --- System prompt for document-sourced RAG (spec 070) ---
DOCUMENT_QA_SYSTEM_PROMPT = (
    "You are a technical assistant for a civil aviation maintenance management system (CMMS).\n\n"
    "Your job is to answer maintenance and operations questions using ONLY the context provided below.\n"
    "The context comes from uploaded technical manuals.\n\n"
    "Rules:\n"
    "- Answer ONLY from the provided context. Do not use outside knowledge.\n"
    "- If the answer is not clearly stated in the context, respond with exactly: "
    '"I don\'t have that information in the knowledge base."\n'
    "- Never guess, infer, or make up technical specifications, procedures, or values.\n"
    "- When the context contains step-by-step procedures, list ALL steps in order. Do not summarize or skip steps.\n"
    "- When the context contains lists, thresholds, or specific values, include them exactly as written.\n"
    "- Use numbered steps for procedures, bullet points for lists.\n"
    '- Cite the document and page (e.g. "According to CNMS Manual, page 58").\n'
    "- If multiple sources are relevant, synthesize them into one clear answer."
)

# Sentinel phrases indicating an ungrounded answer (shared by single- and cross-manual paths)
_SENTINEL_PHRASES = [
    "this information is not in the available manuals",
    "المعلومات المطلوبة غير موجودة في الأدلة المتاحة",
]


def _get_system_instructions() -> str:
    """Read system instructions from DB, cached for 60 seconds."""
    now = time.monotonic()
    if now - _si_cache["ts"] < _SI_CACHE_TTL:
        return _si_cache["value"]
    try:
        resp = (
            supabase.table("manual_assistant_settings")
            .select("system_instructions")
            .eq("id", 1)
            .execute()
        )
        val = resp.data[0]["system_instructions"] if resp.data else ""
    except Exception:
        val = ""
    _si_cache["value"] = val
    _si_cache["ts"] = now
    return val


def _build_prompt(
    retrieved_chunks: str,
    user_question: str,
    history: list[dict] | None = None,
    memory: str | None = None,
    validated_context: str | None = None,
) -> str:
    """Assemble the 3-layer prompt: system instructions → chunks → memory → history → question."""
    parts = []

    si = _get_system_instructions()
    if si.strip():
        parts.append(si.strip())

    parts.append(
        "You are a technical assistant for a civil aviation maintenance department.\n"
        "Answer the technician's question using ONLY the manual sections provided below.\n\n"
        "Rules:\n"
        "1. LEAD with the direct answer in 1-2 sentences. No preamble like "
        '"Based on the manual..." or "According to the provided section...".\n'
        "2. Only add section headers if the answer spans 3+ genuinely distinct topics. "
        "For simple lookups (credentials, values, single procedures), write prose, not sections.\n"
        "3. Keep procedures as numbered steps only when the manual itself presents steps; "
        "do not invent structure.\n"
        "4. If the answer is not found in the sections, reply exactly: "
        '"This information is not in the available manuals."\n'
        "5. Reply in the same language as the question (Arabic or English)."
    )

    if validated_context:
        parts.append(
            "[VERIFIED REFERENCE — Expert-validated answer to a similar question]\n"
            f"{validated_context}\n\n"
        )

    parts.append(f"MANUAL SECTIONS:\n{retrieved_chunks}")

    if memory:
        parts.append(f"CONVERSATION MEMORY:\n{memory}")

    if history:
        history_block = "\n\n".join(
            f"User: {turn['question']}\nAssistant: {turn['answer']}"
            for turn in history[-10:]
        )
        parts.append(f"CONVERSATION HISTORY:\n{history_block}")

    parts.append(f"QUESTION: {user_question}\n\nANSWER:")

    return "\n\n".join(parts)


_SENT_RE = re.compile(r"(?<=[.!?؟])\s+")


class NoContentAfterChunkingError(Exception):
    pass


class CorpusFullError(Exception):
    def __init__(self, ceiling_mb: int):
        self.ceiling_mb = ceiling_mb


class EmbedderUnavailableError(Exception):
    pass


class GeneratorUnavailableError(Exception):
    pass


class ManualNotFoundError(Exception):
    pass


class UploadFailedError(Exception):
    pass


def split_sentences(text: str) -> list[tuple[int, int, str]]:
    results: list[tuple[int, int, str]] = []
    cursor = 0
    for part in _SENT_RE.split(text):
        if not part.strip():
            cursor += len(part) + 1
            continue
        start = text.find(part, cursor)
        if start < 0:
            continue
        end = start + len(part)
        results.append((start, end, part))
        cursor = end
    return results


def _tokens(text: str) -> set[str]:
    return {
        w.strip(".,;:!?()[]\"'؟،").lower()
        for w in text.split()
        if len(w.strip(".,;:!?()[]\"'؟،")) >= 2
    }


def compute_highlight(
    chunk_content: str,
    answer_text: str,
    jaccard_threshold: float = 0.35,
) -> tuple[int | None, int | None]:
    chunk_sents = split_sentences(chunk_content)
    answer_sents = split_sentences(answer_text)
    if not chunk_sents or not answer_sents:
        return (None, None)

    answer_token_sets = [_tokens(s[2]) for s in answer_sents]

    best_score = 0.0
    best_range: tuple[int, int] | None = None
    for start, end, sent in chunk_sents:
        chunk_tokens = _tokens(sent)
        if not chunk_tokens:
            continue
        for a_tokens in answer_token_sets:
            if not a_tokens:
                continue
            inter = len(chunk_tokens & a_tokens)
            union = len(chunk_tokens | a_tokens)
            jaccard = inter / union if union else 0.0
            if jaccard > best_score:
                best_score = jaccard
                best_range = (start, end)

    if best_range and best_score >= jaccard_threshold:
        return best_range
    return (None, None)


async def upload_manual(
    title: str,
    file_bytes: bytes,
    file_name: str,
    file_extension: str,
    file_size_bytes: int,
    uploaded_by: str,
) -> dict:
    # Step 1: Parse with manual_parser
    paragraphs = parse(
        file_bytes, file_extension
    )  # raises NoExtractableTextError directly

    # Step 2: Chunk with manual_chunker
    chunks: List[Chunk] = chunk_paragraphs(paragraphs)
    if not chunks:
        raise NoContentAfterChunkingError("No content after chunking")

    # Step 3: Embed via ollama_embedder
    try:
        texts = [chunk.content for chunk in chunks]
        embeddings = await embed_many(texts)
    except EmbedderTimeoutError as e:
        raise EmbedderUnavailableError() from e

    # Step 4: Allocate manual_id
    manual_id = uuid.uuid4()

    # Step 5: Compute projected_bytes (research §10)
    # Sum of len(chunk.content.encode("utf-8")) + len(chunks) * 3072 + 200 * len(chunks) + 500
    projected_bytes = sum(len(chunk.content.encode("utf-8")) for chunk in chunks)
    projected_bytes += len(chunks) * 3072
    projected_bytes += 200 * len(chunks)
    projected_bytes += 500

    # Step 6: Pre-check corpus ceiling
    ceiling_bytes = int(os.getenv("MANUAL_CORPUS_CEILING_MB", "400")) * 1024 * 1024
    stats_response = (
        supabase.table("manual_corpus_stats")
        .select("total_bytes")
        .eq("id", 1)
        .execute()
    )
    current_bytes = stats_response.data[0]["total_bytes"] if stats_response.data else 0

    if current_bytes + projected_bytes > ceiling_bytes:
        ceiling_mb = int(os.getenv("MANUAL_CORPUS_CEILING_MB", "400"))
        raise CorpusFullError(ceiling_mb)

    # Step 6.5: Resolve user UUID from email (uploaded_by is an email per repo convention)
    user_row = (
        supabase.table("users").select("id").eq("email", uploaded_by).limit(1).execute()
    )
    user_uuid = user_row.data[0]["id"] if user_row.data else None

    # Step 7: Save file to disk
    try:
        file_path = save(manual_id, file_bytes, file_extension)
    except Exception as e:
        raise UploadFailedError("Something went wrong while saving the manual.") from e

    # Step 8: Atomic DB write via RPC (rollback on any error)
    try:
        chunk_payload = [
            {
                "chunk_index": i,
                "source_page": chunks[i].source_page,
                "content": chunks[i].content,
                "embedding": embeddings[i],
            }
            for i in range(len(chunks))
        ]
        supabase.rpc(
            "create_manual_with_chunks",
            {
                "p_id": str(manual_id),
                "p_title": title,
                "p_file_name": file_name,
                "p_file_extension": file_extension,
                "p_file_size_bytes": file_size_bytes,
                "p_uploaded_by": user_uuid,
                "p_chunks": chunk_payload,
                "p_projected_bytes": projected_bytes,
            },
        ).execute()
    except Exception as e:
        try:
            delete_file(manual_id, file_extension)
        except Exception:
            pass
        raise UploadFailedError("database transaction failed") from e

    return {
        "manual_id": str(manual_id),
        "title": title,
        "file_name": file_name,
        "file_extension": file_extension,
        "file_size_bytes": file_size_bytes,
        "chunk_count": len(chunks),
        "created_at": datetime.now(timezone.utc).isoformat(),
    }


async def _rewrite_query(question: str, history: list[dict] | None) -> str:
    """Rewrite a follow-up question into a self-contained search query using conversation context."""
    from services.ollama_generator import generate

    if not history:
        return question

    try:
        conversation_block = "\n".join(
            f"User: {turn['question']}\nAssistant: {turn['answer']}"
            for turn in history[-3:]
        )

        rewrite_prompt = (
            """You are a search query rewriter. Given a conversation history and a follow-up question, rewrite the follow-up question into a single self-contained search query. The rewritten query must:
- Resolve all pronouns and references (e.g., "it", "that", "the second point") using the conversation context
- Be a complete, standalone question that would make sense without any conversation history
- Preserve the original language (Arabic or English)
- Be concise (one sentence)

Reply with ONLY the rewritten query. No explanation, no preamble.

CONVERSATION:
"""
            + conversation_block
            + """

FOLLOW-UP QUESTION: """
            + question
        )

        result = await generate(rewrite_prompt, timeout=10.0)
        rewritten = result.strip().strip('"').strip("'").strip()
        if not rewritten:
            logger.warning("Query rewrite returned empty, using original query")
            return question
        return rewritten
    except Exception as e:
        logger.warning("Query rewrite failed, using original query: %s", e)
        return question


async def _compress_history(
    history: list[dict],
    existing_summary: str | None = None,
    model: str | None = None,
) -> str | None:
    """Compress conversation history into a 3-4 sentence summary.

    Args:
        history: List of conversation turns (each with 'question' and 'answer' keys)
        existing_summary: Optional existing summary to potentially reuse
        model: Optional model override

    Returns:
        3-4 sentence summary string, or None on failure
    """
    from services.ollama_generator import generate, get_default_model

    turns_to_compress = history[:-4] if len(history) > 4 else history

    conversation_block = "\n".join(
        f"User: {turn['question']}\nAssistant: {turn['answer']}"
        for turn in turns_to_compress
    )

    if existing_summary:
        compression_prompt = (
            "You have a previous conversation summary and new conversation turns. "
            "Produce an updated summary of exactly 3-4 sentences that incorporates both. "
            "Preserve ALL technical facts: part numbers, specifications, procedures, "
            "measurements, and component names. "
            "Do not add information not present in the inputs.\n\n"
            f"PREVIOUS SUMMARY:\n{existing_summary}\n\n"
            f"NEW CONVERSATION:\n{conversation_block}\n\nUPDATED SUMMARY:"
        )
    else:
        compression_prompt = (
            "Summarize the following technical conversation between a user and an assistant. "
            "Produce exactly 3-4 sentences. Preserve ALL technical facts: part numbers, "
            "specifications, procedures, measurements, and component names. "
            "Do not add information not present in the conversation.\n\n"
            "CONVERSATION:\n" + conversation_block + "\n\nSUMMARY:"
        )

    try:
        result = await generate(
            compression_prompt,
            model=model or get_default_model(),
            timeout=30.0,
        )
        summary = result.strip()
        if not summary:
            logger.warning("Compression returned empty summary")
            return None
        logger.info(
            "[COMPRESS] Compressed %d turns into summary (%d chars)",
            len(turns_to_compress),
            len(summary),
        )
        return summary
    except Exception as e:
        logger.warning("[COMPRESS] Compression failed: %s", e)
        return None


async def _generate_hypothetical_answer(query: str) -> str | None:
    """Generate a hypothetical document passage for better retrieval (HyDE)."""
    from services.ollama_generator import generate

    hyde_prompt = f"""You are a technical writer for civil aviation maintenance manuals.
Given the following question, write a short passage (1-2 paragraphs) that would appear in a civil aviation technical manual answering this question.
Write in the same language as the question (Arabic or English).
Do not add any preamble, disclaimer, or explanation. Write ONLY the manual passage.

QUESTION: {query}

MANUAL PASSAGE:
"""

    try:
        result = await generate(hyde_prompt, timeout=30.0)
        result = result.strip()
        if not result:
            logger.warning(
                "HyDE generation returned empty, falling back to direct query embedding"
            )
            return None
        logger.info("HyDE generated hypothetical answer (%d chars)", len(result))
        return result
    except Exception as e:
        logger.warning(
            "HyDE generation failed, falling back to direct query embedding: %s", e
        )
        return None


# --- Layer 3 functions removed (spec 072 Phase 7) ---
# _retrieve_chunks_per_manual, _generate_sub_answers, _synthesize_answers
# replaced by document_search_service.py functions.


_LAYER3_RETIRED = True  # Layer 3 functions removed (spec 072 Phase 7)
# _retrieve_chunks_per_manual, _generate_sub_answers, _synthesize_answers
# _build_prompt, _compress_history — all retired and replaced by
# document_search_service.py functions.
# ----SPLICE_START----


async def ask(
    question: str,
    manual_id_filter: Optional[UUID] = None,
    model: Optional[str] = None,
    history: list[dict] | None = None,
    session_summary: str | None = None,
    user_email: str | None = None,
    latency_breakdown: dict | None = None,
) -> dict:
    from services.ollama_embedder import embed_single, EmbedderTimeoutError
    from services.ollama_generator import generate, GeneratorTimeoutError

    # Use passed-in breakdown or create new one
    if latency_breakdown is None:
        latency_breakdown = _empty_latency_breakdown()
    breakdown = latency_breakdown
    _total_start = time.perf_counter()

    detected_system = detect_system(question)
    retrieval_info: dict = {
        "detected_system": detected_system,
        "filtered_manual_ids": [],
        "filter_applied": False,
        "fallback_reason": None,
    }
    system_manual_ids: list[str] = []
    no_manuals_directive: str | None = None
    validated_context: str | None = None

    # Check corpus is not empty
    count_response = (
        supabase.table("manual_corpus_stats")
        .select("manual_count")
        .eq("id", 1)
        .execute()
    )
    if not count_response.data or count_response.data[0]["manual_count"] == 0:
        return {
            "answer": "This information is not in the available manuals.",
            "grounded": False,
            "sources": [],
            "session_summary": None,
            "retrieval_info": retrieval_info,
        }

    # Pre-rewrite validated-QA fast-path lookup (spec 067, spec 069).
    # Check for cached answer using the raw question BEFORE rewriting, so that
    # identical repeated questions hit the cache regardless of conversation history.
    import time as _time

    _vqa_pre_start = _time.monotonic()
    try:
        pre_rewrite_match = await validated_qa_service.check_validated_match(
            question, detected_system=detected_system
        )
        vqa_matches = pre_rewrite_match.get("matches", [])

        if vqa_matches:
            max_score = max(m["similarity"] for m in vqa_matches)
            logger.info(
                "[validated-qa] pre-rewrite check: max_similarity=%.2f threshold=%.2f",
                max_score,
                RAG_CONFIDENCE_THRESHOLD,
            )

            if max_score >= RAG_CONFIDENCE_THRESHOLD:
                # Build combined context from top 3 matches
                context_parts = []
                for i, m in enumerate(vqa_matches):
                    context_parts.append(f"[Source {i + 1}]\n{m['validated_answer']}")
                combined_context = "\n\n".join(context_parts)

                # Build the strict prompt
                prompt = (
                    f"{VALIDATED_QA_SYSTEM_PROMPT}\n\n"
                    f"CONTEXT:\n{combined_context}\n\n"
                    f"QUESTION: {question}\n\nANSWER:"
                )

                # Call LLM
                from services.ai_providers.resolver import generate as provider_generate

                gen_start = _time.monotonic()
                (
                    answer,
                    vqa_provider_used,
                    vqa_provider_display_name,
                    vqa_fallback_used,
                    vqa_fallback_info,
                ) = await provider_generate(
                    prompt, [], user_email, latency_breakdown=breakdown
                )
                gen_elapsed = _time.monotonic() - gen_start

                vqa_provider_display_name = (
                    vqa_provider_display_name or "Local (Ollama)"
                )

                # Build enriched response
                if max_score >= RAG_HIGH_CONFIDENCE:
                    confidence = "high"
                elif max_score >= RAG_CONFIDENCE_THRESHOLD:
                    confidence = "medium"
                else:
                    confidence = "low"

                sources = [
                    {
                        "id": m["id"],
                        "question_text": m["question_text"],
                        "score": m["similarity"],
                    }
                    for m in vqa_matches
                ]

                return {
                    "answer": answer,
                    "grounded": True,
                    "sources": sources,
                    "confidence": confidence,
                    "score": max_score,
                    "model": vqa_provider_display_name,
                    "provider_display_name": vqa_provider_display_name,
                    "duration_seconds": round(gen_elapsed, 1),
                    "is_verified": True,
                    "verified_source": {
                        "validated_qa_id": str(vqa_matches[0]["id"]),
                        "validated_by": vqa_matches[0]["validated_by"],
                        "validated_at": vqa_matches[0]["validated_at"].isoformat()
                        if hasattr(vqa_matches[0]["validated_at"], "isoformat")
                        else str(vqa_matches[0]["validated_at"]),
                        "similarity": max_score,
                    },
                    "retrieval_info": retrieval_info,
                    "provider_used": vqa_provider_used,
                    "fallback_used": vqa_fallback_used,
                    "session_summary": None,
                    "latency_breakdown": breakdown,
                    "source_type": "validated_qa",
                }
            else:
                # Below threshold - continue to post-rewrite check
                logger.info(
                    "[validated-qa] pre-rewrite below threshold (%.2f < %.2f), trying post-rewrite",
                    max_score,
                    RAG_CONFIDENCE_THRESHOLD,
                )
        else:
            logger.info("[validated-qa] pre-rewrite: no matches")
    except Exception as e:
        logger.warning(
            "Pre-rewrite validated_qa check failed, falling back to normal pipeline: %s",
            e,
        )

    # Rewrite query for better retrieval (uses conversation context for follow-up questions).
    # NOTE: rewrite must happen BEFORE the validated_qa cache check so context-dependent
    # follow-ups like "in english" get expanded into self-contained queries — otherwise
    # a bare "in english" could match an unrelated validated answer across sessions.
    with _StageTimer(breakdown, "rewrite_ms"):
        search_query = await _rewrite_query(question, history)

    # Follow-up detection: if the original question had no system keyword but the
    # history-aware rewrite surfaced one (e.g. turn-1 "how to restart CADAS-ATS"
    # → turn-2 "any other steps?" → rewritten to "any other steps for CADAS-ATS?"),
    # re-run detection on the rewrite so multi-turn conversations stay scoped.
    if detected_system is None and search_query and search_query != question:
        followup_system = detect_system(search_query)
        if followup_system:
            detected_system = followup_system
            retrieval_info["detected_system"] = followup_system
            logger.info(
                "[hybrid-retrieval] detected_system=%s via-rewrite (original question had no keyword)",
                followup_system,
            )

    # Check for validated QA match using the context-resolved query (spec 048, spec 069).
    # Pass detected_system so cross-topic matches (e.g. "in english" retrieving a
    # CADAS-ATS answer in an unrelated session) are rejected at the filter layer.

    _vqa_start = _time.monotonic()
    try:
        match_result = await validated_qa_service.check_validated_match(
            search_query, detected_system=detected_system
        )
        vqa_matches = match_result.get("matches", [])

        if vqa_matches:
            max_score = max(m["similarity"] for m in vqa_matches)
            logger.info(
                "[validated-qa] post-rewrite check: max_similarity=%.2f threshold=%.2f",
                max_score,
                RAG_CONFIDENCE_THRESHOLD,
            )

            if max_score >= RAG_CONFIDENCE_THRESHOLD:
                # Build combined context from top 3 matches
                context_parts = []
                for i, m in enumerate(vqa_matches):
                    context_parts.append(f"[Source {i + 1}]\n{m['validated_answer']}")
                combined_context = "\n\n".join(context_parts)

                # Build the strict prompt
                prompt = (
                    f"{VALIDATED_QA_SYSTEM_PROMPT}\n\n"
                    f"CONTEXT:\n{combined_context}\n\n"
                    f"QUESTION: {search_query}\n\nANSWER:"
                )

                # Call LLM
                from services.ai_providers.resolver import generate as provider_generate

                gen_start = _time.monotonic()
                (
                    answer,
                    vqa_provider_used,
                    vqa_provider_display_name,
                    vqa_fallback_used,
                    vqa_fallback_info,
                ) = await provider_generate(
                    prompt, [], user_email, latency_breakdown=breakdown
                )
                gen_elapsed = _time.monotonic() - gen_start

                vqa_provider_display_name = (
                    vqa_provider_display_name or "Local (Ollama)"
                )

                # Build enriched response
                if max_score >= RAG_HIGH_CONFIDENCE:
                    confidence = "high"
                elif max_score >= RAG_CONFIDENCE_THRESHOLD:
                    confidence = "medium"
                else:
                    confidence = "low"

                sources = [
                    {
                        "id": m["id"],
                        "question_text": m["question_text"],
                        "score": m["similarity"],
                    }
                    for m in vqa_matches
                ]

                logger.info(
                    "validated_qa hit (post-rewrite)",
                    extra={
                        "validated_qa_id": str(vqa_matches[0]["id"]),
                        "detected_system": detected_system,
                        "max_similarity": max_score,
                    },
                )

                return {
                    "answer": answer,
                    "grounded": True,
                    "sources": sources,
                    "confidence": confidence,
                    "score": max_score,
                    "model": vqa_provider_display_name,
                    "provider_display_name": vqa_provider_display_name,
                    "duration_seconds": round(gen_elapsed, 1),
                    "is_verified": True,
                    "verified_source": {
                        "validated_qa_id": str(vqa_matches[0]["id"]),
                        "validated_by": vqa_matches[0]["validated_by"],
                        "validated_at": vqa_matches[0]["validated_at"].isoformat()
                        if hasattr(vqa_matches[0]["validated_at"], "isoformat")
                        else str(vqa_matches[0]["validated_at"]),
                        "similarity": max_score,
                    },
                    "retrieval_info": retrieval_info,
                    "provider_used": vqa_provider_used,
                    "fallback_used": vqa_fallback_used,
                    "session_summary": None,
                    "latency_breakdown": breakdown,
                    "source_type": "validated_qa",
                }
            else:
                # Below threshold - let flow continue to manual-chunks pipeline
                logger.info(
                    "[validated-qa] post-rewrite below threshold (%.2f < %.2f), falling through to manual-chunks",
                    max_score,
                    RAG_CONFIDENCE_THRESHOLD,
                )
        else:
            logger.info("[validated-qa] post-rewrite: no matches")
    except Exception as e:
        logger.warning(
            "Validated QA check failed, falling back to normal pipeline: %s", e
        )

    # --- Layer 2: Document chunk search (spec 072) ---
    # Enhanced search with HyDE + per-document retrieval + sub-answers + synthesis.
    # HyDE + embedding are computed ONCE here and reused by Layer 3 if Layer 2 falls through.
    from services.document_search_service import (
        retrieve_chunks_per_document,
        generate_document_sub_answers,
        synthesize_document_answers,
    )

    _layer2_hyde_text = None
    _layer2_embedding = None

    try:
        # HyDE: generate hypothetical answer for better embedding
        with _StageTimer(breakdown, "hyde_ms"):
            _layer2_hyde_text = await _generate_hypothetical_answer(search_query)
        embed_input = _layer2_hyde_text if _layer2_hyde_text else search_query
        with _StageTimer(breakdown, "embed_ms"):
            _layer2_embedding = await embed_single(embed_input)
        embedding_str = "[" + ",".join(str(x) for x in _layer2_embedding) + "]"

        # Per-document retrieval
        chunks_by_doc = await retrieve_chunks_per_document(embedding_str)
        logger.info(
            "[document-search] found %d documents with chunks",
            len(chunks_by_doc) if chunks_by_doc else 0,
        )

        if not chunks_by_doc:
            logger.info(
                "[document-search] no chunks found, falling through to manual-chunks"
            )
        else:
            # Sub-answer generation
            (
                sub_answers,
                provider_used,
                fallback_used,
                provider_display_name,
            ) = await generate_document_sub_answers(
                chunks_by_doc, search_query, history, None, user_email, breakdown
            )

            # Synthesis
            result = await synthesize_document_answers(
                sub_answers, search_query, user_email, breakdown
            )

            if result.get("grounded"):
                max_score = max(
                    (
                        c.get("similarity", 0)
                        for doc_chunks in chunks_by_doc.values()
                        for c in doc_chunks
                    ),
                    default=0,
                )
                confidence = (
                    "high"
                    if max_score >= RAG_HIGH_CONFIDENCE
                    else "medium"
                    if max_score >= RAG_CONFIDENCE_THRESHOLD
                    else "low"
                )

                docs_consulted = result.get("documents_consulted", [])

                # Build sources array
                sources = []
                for doc_id, chunks in chunks_by_doc.items():
                    for chunk in chunks[:3]:
                        sources.append(
                            {
                                "type": "document",
                                "document_id": chunk["document_id"],
                                "display_name": chunk.get("display_name", ""),
                                "section_title": chunk.get("section_title", ""),
                                "page_number": chunk.get("page_number"),
                                "score": chunk.get("similarity", 0),
                            }
                        )

                logger.info(
                    "document_chunk hit",
                    extra={
                        "documents": len(chunks_by_doc),
                        "max_score": max_score,
                    },
                )

                _total_elapsed = time.perf_counter() - _total_start
                return {
                    "answer": result["answer"],
                    "grounded": True,
                    "sources": sources,
                    "confidence": confidence,
                    "score": max_score,
                    "source_type": "document",
                    "model": provider_display_name,
                    "provider_display_name": provider_display_name,
                    "duration_seconds": round(_total_elapsed, 1),
                    "is_verified": False,
                    "verified_source": None,
                    "manuals_consulted": docs_consulted,
                    "has_conflicts": result.get("has_conflicts", False),
                    "retrieval_info": retrieval_info,
                    "provider_used": provider_used,
                    "fallback_used": fallback_used,
                    "session_summary": None,
                    "latency_breakdown": breakdown,
                }
            else:
                logger.info(
                    "[document-search] not grounded (answer=%s), falling through to manual-chunks",
                    result.get("answer", "")[:100],
                )
    except Exception as e:
        logger.warning(
            "Document chunk search failed, falling through to manual-chunks: %s", e
        )

    # --- End Layer 2 ---

    # No grounded answer from validated_qa or documents — return fallback.
    # Layer 3 (old manual-chunks pipeline) has been retired (spec 072 Phase 7).
    breakdown["total_ms"] = round((time.perf_counter() - _total_start) * 1000)
    return {
        "answer": "This information is not in the available manuals.",
        "grounded": False,
        "sources": [],
        "session_summary": None,
        "retrieval_info": retrieval_info,
        "latency_breakdown": breakdown,
    }


async def delete_manual(manual_id: UUID) -> dict:
    from services.manual_storage_service import delete as delete_file

    response = supabase.rpc(
        "delete_manual_with_stats",
        {"p_manual_id": str(manual_id)},
    ).execute()

    if not response.data:
        raise ManualNotFoundError(f"Manual {manual_id} not found")

    row = response.data[0]
    file_extension = row["file_extension"]
    title = row["title"]

    try:
        delete_file(manual_id, file_extension)
    except Exception:
        pass

    return {"file_extension": file_extension, "title": title}
