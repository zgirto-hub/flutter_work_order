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
from services.document_preprocessor import preprocess_pages
from services.contextual_prefix import apply_contextual_prefix
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
    "You are a technical assistant for a civil aviation maintenance department.\n"
    "The department uses multiple systems: CADAS-ATS, CADAS-IMS, AIDA-NG, IRTOS, and others.\n\n"
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
    '- Cite the document and section (e.g. "According to CADAS-ATS Admin, Section: Database Backup").\n'
    "- If multiple sources are relevant, synthesize them into one clear answer.\n"
    "- If the question is ambiguous about WHICH system it refers to and the conversation history "
    "does not clarify, ask the user to specify which system they mean.\n"
    "- If the conversation history already establishes which system is being discussed, "
    "use that context — do NOT ask again."
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
        "The department uses multiple systems: CADAS-ATS, CADAS-IMS, AIDA-NG, IRTOS, and others.\n"
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
        "5. Reply in the same language as the question (Arabic or English).\n"
        "6. If the question is ambiguous about WHICH system it refers to (e.g. 'forgot the admin password' "
        "without specifying CADAS-ATS or CADAS-IMS), AND the conversation history does not clarify, "
        "ask the user to specify which system they mean. List the relevant systems you have documentation for.\n"
        "7. If the conversation history already establishes which system is being discussed, "
        "use that context — do NOT ask again."
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

    # Step 1.5: Allocate manual_id (needed for activity logging)
    manual_id = uuid.uuid4()

    pages_for_preprocessing = [
        (page_num, text) for page_num, text in paragraphs if page_num is not None
    ]
    if pages_for_preprocessing:
        preprocessed_pages, raw_mapping = await preprocess_pages(
            pages_for_preprocessing, document_title=title, document_id=str(manual_id)
        )
        preprocessed_dict = dict(preprocessed_pages)
        processed_paragraphs = []
        for page_num, text in paragraphs:
            if page_num is not None and page_num in preprocessed_dict:
                processed_paragraphs.append((page_num, preprocessed_dict[page_num]))
            else:
                processed_paragraphs.append((page_num, text))
        paragraphs = processed_paragraphs
    else:
        raw_mapping = {}

    # Step 2: Chunk with manual_chunker
    chunks: List[Chunk] = chunk_paragraphs(paragraphs)
    if not chunks:
        raise NoContentAfterChunkingError("No content after chunking")

    # Step 3: Embed via ollama_embedder
    try:
        texts = [
            apply_contextual_prefix(content=chunk.content, doc_title=title)
            for chunk in chunks
        ]
        embeddings = await embed_many(texts)
        logger.info(
            "Embedding %d chunks with contextual prefix for manual '%s'",
            len(texts),
            title,
        )
    except EmbedderTimeoutError as e:
        raise EmbedderUnavailableError() from e

    # Step 4: Use manual_id allocated in Step 1.5

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
                "raw_content": raw_mapping.get(chunks[i].source_page)
                if raw_mapping
                else None,
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
    # Spec 076: Intentionally hardcoded to Ollama — NOT routed through provider resolver
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
            """You are a search query rewriter for a civil aviation maintenance department that uses multiple systems (CADAS-ATS, CADAS-IMS, AIDA-NG, IRTOS, etc.).

Given a conversation history and a follow-up question, rewrite the follow-up question into a single self-contained search query. The rewritten query must:
- Resolve all pronouns and references (e.g., "it", "that", "the second point") using the conversation context
- Include the specific system name if the conversation context makes it clear which system is being discussed
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
    # Spec 076: Intentionally hardcoded to Ollama — NOT routed through provider resolver
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

    # --- Layer 2: Document chunk search (spec 072, spec 074) ---
    # Enhanced search with HyDE + per-document retrieval + direct generation.
    # Replaces sub-answer + synthesis with single generation call (spec 074).
    # HyDE + embedding are computed ONCE here and reused by Layer 3 if Layer 2 falls through.
    from services.document_search_service import (
        retrieve_chunks_per_document,
        build_direct_generation_prompt,
    )
    from services.ai_providers.resolver import generate as provider_generate

    _layer2_hyde_text = None
    _layer2_embedding = None
    provider_used = "local"
    fallback_used = False
    provider_display_name = "Local (Ollama)"

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
            # Direct generation: build combined prompt from all document chunks (spec 074)
            prompt, sources, docs_consulted = build_direct_generation_prompt(
                chunks_by_doc, search_query, DOCUMENT_QA_SYSTEM_PROMPT
            )

            # Single generation call (replaces up to 9 LLM calls)
            with _StageTimer(breakdown, "generator_ms"):
                (
                    answer,
                    provider_used,
                    provider_display_name,
                    fallback_used,
                    _fallback_info,
                ) = await provider_generate(
                    prompt, [], user_email, latency_breakdown=breakdown
                )

            # Check if answer is grounded
            grounded = answer and not any(
                phrase in answer.lower() for phrase in _SENTINEL_PHRASES
            )

            if grounded:
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

                # Format sources for response
                response_sources = []
                for s in sources:
                    response_sources.append(
                        {
                            "type": "document",
                            "document_id": s["document_id"],
                            "display_name": s["display_name"],
                            "section_title": s.get("section_title", ""),
                            "page_number": s.get("page_number"),
                            "score": s.get("similarity", 0),
                        }
                    )

                # Check for conflicts
                has_conflicts = "⚠ CONFLICT:" in answer or "⚠ تعارض:" in answer

                logger.info(
                    "direct_generation",
                    extra={
                        "documents": len(chunks_by_doc),
                        "max_score": max_score,
                    },
                )

                _total_elapsed = time.perf_counter() - _total_start
                return {
                    "answer": answer,
                    "grounded": True,
                    "sources": response_sources,
                    "confidence": confidence,
                    "score": max_score,
                    "source_type": "document",
                    "model": provider_display_name,
                    "provider_display_name": provider_display_name,
                    "duration_seconds": round(_total_elapsed, 1),
                    "is_verified": False,
                    "verified_source": None,
                    "manuals_consulted": docs_consulted,
                    "has_conflicts": has_conflicts,
                    "retrieval_info": retrieval_info,
                    "provider_used": provider_used,
                    "fallback_used": fallback_used,
                    "session_summary": None,
                    "latency_breakdown": breakdown,
                }
            else:
                logger.info(
                    "[document-search] not grounded (answer=%s), falling through to manual-chunks",
                    answer[:100] if answer else "",
                )
    except Exception as e:
        logger.warning(
            "Document chunk search failed, falling through to manual-chunks: %s", e
        )

    # --- End Layer 2 ---

    # No grounded answer from validated_qa or documents.
    # Layer 3 (old manual-chunks pipeline) has been retired (spec 072 Phase 7).
    # If the question seems like it could be about a specific system, ask for clarification
    # instead of the generic "not in manuals" fallback.
    fallback_answer = "This information is not in the available manuals."
    try:
        from services.ai_providers.resolver import generate as provider_generate

        clarify_prompt = (
            "You are a technical assistant for a civil aviation maintenance department.\n"
            "The department uses these systems: CADAS-ATS, CADAS-IMS, AIDA-NG, IRTOS.\n\n"
            "The user asked a question but the search returned no matching documentation.\n"
            "This might be because:\n"
            "1. The question is too vague and doesn't specify which system.\n"
            "2. The information genuinely doesn't exist in the uploaded documents.\n\n"
        )
        if history:
            history_block = "\n".join(
                f"User: {turn['question']}\nAssistant: {turn['answer']}"
                for turn in history[-3:]
            )
            clarify_prompt += f"CONVERSATION HISTORY:\n{history_block}\n\n"
        clarify_prompt += (
            f"USER QUESTION: {question}\n\n"
            "If the question could apply to multiple systems and the conversation history "
            "doesn't clarify which one, politely ask the user to specify the system.\n"
            "If the conversation history already establishes the system, say you don't have "
            "that specific information in the documentation for that system.\n"
            "Keep your response to 1-2 sentences. Reply in the same language as the question."
        )
        clarify_result, _, _ = await provider_generate(clarify_prompt)
        if clarify_result and clarify_result.strip():
            fallback_answer = clarify_result.strip()
    except Exception as e:
        logger.warning("Clarification generation failed: %s", e)

    breakdown["total_ms"] = round((time.perf_counter() - _total_start) * 1000)
    return {
        "answer": fallback_answer,
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
