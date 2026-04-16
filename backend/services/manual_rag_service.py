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
RAG_OFFTOPIC_THRESHOLD = 0.40  # Score below this → skip manual-chunks pipeline entirely

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
    "- Be concise and direct. Use bullet points for procedures.\n"
    '- Always cite the document source (e.g. "According to CADAS ATS Manual, Section 4.2...").\n'
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


async def _retrieve_chunks_per_manual(
    embedding_str: str, allowed_manual_ids: set[str] | None = None
) -> dict[str, list[dict]]:
    """Retrieve top qualifying chunks grouped by manual ID (spec 046)."""
    # Get all manual IDs
    manuals_resp = supabase.table("manuals").select("id, title").execute()
    if allowed_manual_ids is not None:
        manuals_resp.data = [
            manual
            for manual in (manuals_resp.data or [])
            if manual["id"] in allowed_manual_ids
        ]
    if not manuals_resp.data:
        return {}

    chunks_by_manual: dict[str, list[dict]] = {}
    for manual in manuals_resp.data:
        mid = manual["id"]
        try:
            rpc_response = supabase.rpc(
                "search_manual_chunks",
                {
                    "q_embedding": embedding_str,
                    "match_count": 10,
                    "manual_id_filter": str(mid),
                },
            ).execute()
            raw_chunks = rpc_response.data or []
        except Exception as e:
            logger.warning("Per-manual retrieval failed for %s: %s", mid, e)
            continue

        # Apply reranking: distance threshold + cap
        qualified = [
            c for c in raw_chunks if c.get("distance", 1.0) <= MAX_CHUNK_DISTANCE
        ][:MAX_CHUNKS_PER_MANUAL]

        if qualified:
            chunks_by_manual[str(mid)] = qualified

    # If more than MAX_MANUALS_FOR_SYNTHESIS manuals qualified, keep the most relevant
    if len(chunks_by_manual) > MAX_MANUALS_FOR_SYNTHESIS:
        ranked = sorted(
            chunks_by_manual.items(),
            key=lambda item: (
                sum(c.get("distance", 1.0) for c in item[1]) / len(item[1])
            ),
        )
        chunks_by_manual = dict(ranked[:MAX_MANUALS_FOR_SYNTHESIS])

    logger.info(
        "Per-manual retrieval: %d manuals with qualifying chunks",
        len(chunks_by_manual),
    )
    return chunks_by_manual


async def _generate_sub_answers(
    chunks_by_manual: dict[str, list[dict]],
    question: str,
    history: list[dict] | None,
    memory: str | None,
    model: str | None,
    user_email: str | None = None,
    validated_context: str | None = None,
    extra_prefix: str | None = None,
    latency_breakdown: dict | None = None,
) -> tuple[list[dict], str, bool, str, dict | None]:
    """Generate a sub-answer for each manual's chunks (spec 046)."""
    from services.ai_providers.resolver import generate as provider_generate

    sub_answers = []
    last_error = None
    provider_used = "local"
    fallback_used = False
    for manual_id, chunks in chunks_by_manual.items():
        manual_title = chunks[0].get("manual_title", "Unknown")

        # Build prompt from this manual's chunks only
        retrieved_text = ""
        manual_sources = []
        for i, chunk in enumerate(chunks):
            source_page = chunk.get("source_page")
            content = chunk.get("content", "")
            retrieved_text += f"[Source {i + 1}: {manual_title}, page {source_page or '—'}]\n{content}\n---\n"
            manual_sources.append(
                {
                    "manual_id": chunk.get("manual_id"),
                    "manual_title": manual_title,
                    "chunk_index": chunk.get("chunk_index", 0),
                    "source_page": source_page,
                    "content_preview": content[:500],
                }
            )

        prompt = _build_prompt(
            retrieved_text, question, history, memory, validated_context
        )
        if extra_prefix:
            prompt = f"{extra_prefix}\n\n{prompt}"

        try:
            (
                answer_text,
                provider_used,
                provider_display_name,
                fallback_used,
                _fallback_info,
            ) = await provider_generate(
                prompt, [], user_email, latency_breakdown=latency_breakdown
            )
        except Exception as e:
            logger.warning(
                "Sub-answer generation failed for manual '%s': %s", manual_title, e
            )
            last_error = e
            continue

        # Check if grounded
        grounded = not any(
            sentinel in answer_text.lower() for sentinel in _SENTINEL_PHRASES
        )

        sub_answers.append(
            {
                "manual_id": manual_id,
                "manual_title": manual_title,
                "answer": answer_text.strip(),
                "chunks": manual_sources,
                "grounded": grounded,
                "provider_display_name": provider_display_name,
                "provider_used": provider_used,
                "fallback_used": fallback_used,
                "_fallback_info": _fallback_info,
            }
        )

    if not sub_answers and last_error:
        raise last_error

    provider_display_name = sub_answers[-1].get(
        "provider_display_name", "Local (Ollama)"
    )
    fallback_used = any(sa.get("fallback_used", False) for sa in sub_answers)
    fallback_info = next(
        (sa.get("_fallback_info") for sa in sub_answers if sa.get("_fallback_info")),
        None,
    )
    return (
        sub_answers,
        provider_used,
        fallback_used,
        provider_display_name,
        fallback_info,
    )


async def _synthesize_answers(
    sub_answers: list[dict],
    question: str,
    model: str | None,
    user_email: str | None = None,
    latency_breakdown: dict | None = None,
) -> dict:
    """Combine grounded sub-answers into one synthesized answer (spec 046)."""
    from services.ollama_generator import generate

    grounded = [s for s in sub_answers if s["grounded"]]

    # No grounded answers
    if not grounded:
        return {
            "answer": "This information is not in the available manuals.",
            "synthesized": False,
            "manuals_consulted": [],
            "has_conflicts": False,
            "grounded": False,
        }

    # Single grounded answer — skip synthesis, no extra LLM call
    if len(grounded) == 1:
        sa = grounded[0]
        return {
            "answer": sa["answer"],
            "synthesized": False,
            "manuals_consulted": [{"id": sa["manual_id"], "title": sa["manual_title"]}],
            "has_conflicts": False,
            "grounded": True,
        }

    # Multiple grounded answers — synthesize
    manual_answers_block = "\n\n".join(
        f"[Manual: {sa['manual_title']}]\n{sa['answer']}" for sa in grounded
    )

    synthesis_prompt = (
        "You are a technical synthesis expert for civil aviation maintenance.\n"
        "You have answers from multiple manuals to the same question.\n\n"
        "Rules:\n"
        "1. LEAD with the direct answer in 1-2 sentences. No preamble, no headers before the answer.\n"
        "2. Only add section headers if the answer spans 3+ genuinely distinct topics. "
        "For simple lookups (credentials, values, single procedures), write prose, not sections.\n"
        '3. Attribute inline when useful (e.g., "per [Manual X], ..."), not as bullet lists of sources.\n'
        "4. If manuals AGREE, state once and cite agreeing manuals.\n"
        "5. Only flag a CONFLICT if manuals directly contradict each other on the same fact. "
        "Complementary info (one says 'ask IT', another gives a procedure) is NOT a conflict — "
        "just present the concrete procedure.\n"
        "6. If one manual has the concrete answer and another says 'info not available' or "
        "'verify with supervisor', IGNORE the latter — do not mention it.\n"
        "7. Reply in the same language as the question (Arabic or English).\n\n"
        f"QUESTION: {question}\n\n"
        f"MANUAL ANSWERS:\n{manual_answers_block}\n\n"
        "ANSWER:"
    )

    try:
        from services.ai_providers.resolver import generate as provider_generate

        (
            synthesized,
            provider_used,
            provider_display_name,
            fallback_used,
            fallback_info,
        ) = await provider_generate(
            synthesis_prompt, [], user_email, latency_breakdown=latency_breakdown
        )
    except Exception as e:
        logger.warning("Synthesis failed, returning first sub-answer: %s", e)
        first = grounded[0]
        provider_display_name = first.get("provider_display_name", "Local (Ollama)")
        provider_used = first.get("provider_used", "local")
        fallback_used = first.get("fallback_used", False)
        return {
            "answer": first["answer"],
            "synthesized": False,
            "manuals_consulted": [
                {"id": first["manual_id"], "title": first["manual_title"]}
            ],
            "has_conflicts": False,
            "grounded": True,
            "provider_used": provider_used,
            "fallback_used": fallback_used,
            "provider_display_name": provider_display_name,
            "_fallback_info": first.get("_fallback_info"),
        }

    answer_text = synthesized.strip()
    has_conflicts = "⚠ CONFLICT:" in answer_text or "⚠ تعارض:" in answer_text

    return {
        "answer": answer_text,
        "synthesized": True,
        "manuals_consulted": [
            {"id": sa["manual_id"], "title": sa["manual_title"]} for sa in grounded
        ],
        "has_conflicts": has_conflicts,
        "grounded": True,
        "provider_used": provider_used,
        "fallback_used": fallback_used,
        "provider_display_name": provider_display_name,
        "_fallback_info": fallback_info,
    }


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

    # Track best VQA similarity across both pre- and post-rewrite checks.
    # If the best score stays below RAG_OFFTOPIC_THRESHOLD, the question is
    # clearly off-topic and we skip the expensive manual-chunks pipeline entirely.
    _best_vqa_score = 0.0

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
            _best_vqa_score = max(_best_vqa_score, max_score)
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
            _best_vqa_score = max(_best_vqa_score, max_score)
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

    # --- Layer 2: Document chunk search (spec 070) ---
    # Search uploaded document chunks BEFORE falling through to the manual-chunks pipeline.
    # Embed the search_query directly (no HyDE — that's for manual-chunks).
    import time as _time

    try:
        _doc_embed_start = _time.perf_counter()
        doc_query_embedding = await embed_single(search_query)
        _doc_embed_elapsed = _time.perf_counter() - _doc_embed_start

        doc_matches = await search_document_chunks(doc_query_embedding, limit=3)

        if doc_matches:
            doc_max_score = max(m["similarity"] for m in doc_matches)
            logger.info(
                "[document-search] max_similarity=%.2f threshold=%.2f",
                doc_max_score,
                RAG_CONFIDENCE_THRESHOLD,
            )

            if doc_max_score >= RAG_CONFIDENCE_THRESHOLD:
                # Fetch full parent section content for each matched child
                enriched_matches = await fetch_parent_context(doc_matches)

                # Build document context for LLM
                context_parts = []
                for i, m in enumerate(enriched_matches):
                    part = f"[Document Source {i + 1}]\n"
                    part += f"Document: {m['display_name']}\n"
                    if m.get("section_title"):
                        part += f"Section: {m['section_title']}\n"
                    if m.get("page_number"):
                        part += f"Page: {m['page_number']}\n"
                    part += f"\n{m.get('parent_content', m['content'])}"
                    context_parts.append(part)
                combined_context = "\n\n".join(context_parts)

                # Build prompt with document system prompt
                prompt = (
                    f"{DOCUMENT_QA_SYSTEM_PROMPT}\n\n"
                    f"CONTEXT:\n{combined_context}\n\n"
                    f"QUESTION: {search_query}\n\nANSWER:"
                )

                # Call LLM
                from services.ai_providers.resolver import generate as provider_generate

                gen_start = _time.perf_counter()
                (
                    answer,
                    doc_provider_used,
                    doc_provider_display_name,
                    doc_fallback_used,
                    doc_fallback_info,
                ) = await provider_generate(
                    prompt, [], user_email, latency_breakdown=breakdown
                )
                gen_elapsed = _time.perf_counter() - gen_start

                doc_provider_display_name = (
                    doc_provider_display_name or "Local (Ollama)"
                )

                # Build confidence band
                if doc_max_score >= RAG_HIGH_CONFIDENCE:
                    confidence = "high"
                elif doc_max_score >= RAG_CONFIDENCE_THRESHOLD:
                    confidence = "medium"
                else:
                    confidence = "low"

                # Build document sources array
                sources = [
                    {
                        "type": "document",
                        "document_id": m["document_id"],
                        "display_name": m["display_name"],
                        "section_title": m.get("section_title", ""),
                        "page_number": m.get("page_number"),
                        "score": m["similarity"],
                    }
                    for m in enriched_matches
                ]

                logger.info(
                    "document_chunk hit",
                    extra={
                        "document_id": enriched_matches[0]["document_id"],
                        "section": enriched_matches[0].get("section_title"),
                        "max_similarity": doc_max_score,
                    },
                )

                return {
                    "answer": answer,
                    "grounded": True,
                    "sources": sources,
                    "confidence": confidence,
                    "score": doc_max_score,
                    "source_type": "document",
                    "model": doc_provider_display_name,
                    "provider_display_name": doc_provider_display_name,
                    "duration_seconds": round(gen_elapsed, 1),
                    "is_verified": False,
                    "verified_source": None,
                    "retrieval_info": retrieval_info,
                    "provider_used": doc_provider_used,
                    "fallback_used": doc_fallback_used,
                    "session_summary": None,
                    "latency_breakdown": breakdown,
                }
            else:
                logger.info(
                    "[document-search] below threshold (%.2f < %.2f), falling through to manual-chunks",
                    doc_max_score,
                    RAG_CONFIDENCE_THRESHOLD,
                )
        else:
            logger.info("[document-search] no matches found")
    except Exception as e:
        logger.warning(
            "Document chunk search failed, falling through to manual-chunks: %s", e
        )

    # --- End Layer 2 ---

    # Early exit: if the best VQA score across both checks is below the
    # off-topic threshold, the question is clearly unrelated to the knowledge
    # base. Skip the entire manual-chunks pipeline (HyDE + embed + retrieval)
    # to save ~15-20s of wasted compute.
    if _best_vqa_score < RAG_OFFTOPIC_THRESHOLD:
        logger.info(
            "[off-topic] best VQA score %.2f < %.2f — skipping manual-chunks pipeline",
            _best_vqa_score,
            RAG_OFFTOPIC_THRESHOLD,
        )
        breakdown["total_ms"] = round((time.perf_counter() - _total_start) * 1000)
        return {
            "answer": "This information is not in the available manuals.",
            "grounded": False,
            "sources": [],
            "confidence": "low",
            "score": round(_best_vqa_score, 2),
            "session_summary": None,
            "retrieval_info": retrieval_info,
            "latency_breakdown": breakdown,
        }

    # HyDE: generate hypothetical answer for better embedding
    with _StageTimer(breakdown, "hyde_ms"):
        hyde_text = await _generate_hypothetical_answer(search_query)
    embed_input = hyde_text if hyde_text else search_query

    # Embed the question
    with _StageTimer(breakdown, "embed_ms"):
        try:
            question_embedding = await embed_single(embed_input)
        except EmbedderTimeoutError:
            raise EmbedderUnavailableError()

    # Convert embedding list to string format for PostgREST → pgvector cast.
    embedding_str = "[" + ",".join(str(x) for x in question_embedding) + "]"

    # --- Compression logic (spec 045) — shared by both paths ---
    memory: str | None = None
    effective_history = history
    needs_compression = history and len(history) > 8

    if needs_compression:
        turns_to_preserve = 4
        turns_already_compressed = len(history) - turns_to_preserve

        if session_summary and turns_already_compressed <= 5:
            logger.info("[COMPRESS] Reusing existing summary")
            memory = session_summary
            effective_history = history[-turns_to_preserve:]
        else:
            old_turns = (
                history[:-turns_to_preserve]
                if len(history) > turns_to_preserve
                else history
            )
            new_summary = await _compress_history(old_turns, session_summary, model)
            if new_summary:
                memory = new_summary
                effective_history = history[-turns_to_preserve:]
                logger.info(
                    "[COMPRESS] Created new summary from %d turns", len(old_turns)
                )
            else:
                logger.warning(
                    "[COMPRESS] Compression failed, falling back to last 10 turns"
                )
                effective_history = history[-10:] if history else None
                memory = None

    from services.ollama_generator import get_default_model

    used_model = model or get_default_model()
    provider_used = "local"
    fallback_used = False

    if detected_system and manual_id_filter is None:
        system_manual_ids = await get_manual_ids_for_system(detected_system, supabase)
        if system_manual_ids:
            retrieval_info["filtered_manual_ids"] = system_manual_ids
            retrieval_info["filter_applied"] = True
            logger.info(
                "[hybrid-retrieval] detected_system=%s filter_applied=true matched_manuals=%d",
                detected_system,
                len(system_manual_ids),
            )
        else:
            retrieval_info["fallback_reason"] = "no_manuals_for_system"
            no_manuals_directive = (
                f"IMPORTANT: The user asked specifically about {detected_system}. "
                f"No manuals for {detected_system} are currently uploaded to the system. "
                "Do NOT substitute content from other similar-sounding systems. "
                f"Respond that specific information about {detected_system} is not available in the uploaded manuals."
            )
            logger.warning(
                "[hybrid-retrieval] System '%s' detected but no manuals found, falling back to all",
                detected_system,
            )
    elif manual_id_filter is not None and detected_system:
        logger.info(
            "[hybrid-retrieval] User selected manual - skipping filter (detected=%s)",
            detected_system,
        )

    # ================================================================
    # BRANCH: single-manual vs cross-manual synthesis (spec 046)
    # ================================================================
    if manual_id_filter:
        # === EXISTING SINGLE-MANUAL PATH (unchanged) ===
        rpc_params = {
            "q_embedding": embedding_str,
            "match_count": 5,
            "manual_id_filter": str(manual_id_filter),
        }
        with _StageTimer(breakdown, "retrieval_ms"):
            try:
                rpc_response = supabase.rpc(
                    "search_manual_chunks", rpc_params
                ).execute()
                chunks_data = rpc_response.data or []
            except Exception:
                raise

        if not chunks_data:
            return {
                "answer": "This information is not in the available manuals.",
                "grounded": False,
                "sources": [],
                "session_summary": memory,
                "retrieval_info": retrieval_info,
            }

        # Chunk reranking (spec 044) — only time when there are enough candidates
        # to be meaningfully reranked. Fewer than 2 → skip (leave rerank_ms=None).
        if len(chunks_data) >= 2:
            with _StageTimer(breakdown, "rerank_ms"):
                qualified_chunks = [
                    c
                    for c in chunks_data
                    if c.get("distance", 1.0) <= MAX_CHUNK_DISTANCE
                ]
                passed_count = len(qualified_chunks)
                qualified_chunks = qualified_chunks[:MAX_PROMPT_CHUNKS]
        else:
            qualified_chunks = [
                c for c in chunks_data if c.get("distance", 1.0) <= MAX_CHUNK_DISTANCE
            ]
            passed_count = len(qualified_chunks)
            qualified_chunks = qualified_chunks[:MAX_PROMPT_CHUNKS]

        logger.info(
            "Chunk reranking: %d retrieved → %d passed threshold (≤%.2f) → %d sent to LLM",
            len(chunks_data),
            passed_count,
            MAX_CHUNK_DISTANCE,
            len(qualified_chunks),
        )

        if not qualified_chunks:
            return {
                "answer": "This information is not in the available manuals.",
                "grounded": False,
                "sources": [],
                "model": used_model,
                "duration_seconds": 0,
                "session_summary": memory,
                "retrieval_info": retrieval_info,
            }

        # Build prompt from qualified chunks
        retrieved_chunks = ""
        sources = []
        for i, chunk in enumerate(qualified_chunks):
            manual_title = chunk.get("manual_title", "Unknown")
            source_page = chunk.get("source_page")
            content = chunk.get("content", "")
            retrieved_chunks += f"[Source {i + 1}: {manual_title}, page {source_page or '—'}]\n{content}\n---\n"
            sources.append(
                {
                    "manual_id": chunk.get("manual_id"),
                    "manual_title": manual_title,
                    "chunk_index": chunk.get("chunk_index", 0),
                    "source_page": source_page,
                    "content_preview": content[:500],
                }
            )

        prompt = _build_prompt(
            retrieved_chunks, question, effective_history, memory, validated_context
        )

        gen_start = time.monotonic()
        try:
            from services.ai_providers.resolver import generate as provider_generate

            (
                answer,
                provider_used,
                provider_display_name,
                fallback_used,
                fallback_info,
            ) = await provider_generate(
                prompt, [], user_email, latency_breakdown=breakdown
            )
        except GeneratorTimeoutError:
            raise GeneratorUnavailableError()
        gen_elapsed = time.monotonic() - gen_start

        # Check groundedness
        grounded = not any(phrase in answer.lower() for phrase in _SENTINEL_PHRASES)

        if not grounded:
            provider_display_name = provider_display_name or "Local (Ollama)"
            return {
                "answer": "This information is not in the available manuals.",
                "grounded": False,
                "sources": [],
                "model": provider_display_name,  # spec-065: deprecated alias
                "provider_display_name": provider_display_name,
                "duration_seconds": round(gen_elapsed, 1),
                "session_summary": memory,
                "retrieval_info": retrieval_info,
                "provider_used": provider_used,
                "fallback_used": fallback_used,
                "_fallback_info": fallback_info,
            }

        # Highlight sources
        final_sources = []
        for src in sources:
            preview = src["content_preview"]
            highlight_start, highlight_end = compute_highlight(preview, answer)
            final_sources.append(
                {
                    "manual_id": src["manual_id"],
                    "manual_title": src["manual_title"],
                    "chunk_index": src["chunk_index"],
                    "source_page": src["source_page"],
                    "content_preview": preview,
                    "highlight_start": highlight_start,
                    "highlight_end": highlight_end,
                }
            )

        return {
            "answer": answer,
            "grounded": True,
            "sources": final_sources,
            "model": provider_display_name,  # spec-065: deprecated alias
            "provider_display_name": provider_display_name,
            "duration_seconds": round(gen_elapsed, 1),
            "session_summary": memory,
            "retrieval_info": retrieval_info,
            "provider_used": provider_used,
            "fallback_used": fallback_used,
            "_fallback_info": fallback_info,
        }

    else:
        # === CROSS-MANUAL SYNTHESIS PATH (spec 046) ===
        gen_start = time.monotonic()

        # Step 1: Per-manual chunk retrieval
        retrieval_start = time.monotonic()
        with _StageTimer(breakdown, "retrieval_ms"):
            chunks_by_manual = await _retrieve_chunks_per_manual(
                embedding_str,
                allowed_manual_ids=set(system_manual_ids)
                if retrieval_info["filter_applied"]
                else None,
            )
        retrieval_elapsed = time.monotonic() - retrieval_start

        if not chunks_by_manual:
            logger.info("Cross-manual synthesis: no qualifying chunks found")
            return {
                "answer": "This information is not in the available manuals.",
                "grounded": False,
                "sources": [],
                "model": used_model,
                "duration_seconds": 0,
                "session_summary": memory,
                "retrieval_info": retrieval_info,
                "provider_used": provider_used,
                "fallback_used": fallback_used,
            }

        logger.info(
            "Cross-manual retrieval took %.1fs for %d manuals",
            retrieval_elapsed,
            len(chunks_by_manual),
        )

        # Step 2: Generate sub-answers per manual
        sub_answer_start = time.monotonic()
        (
            sub_answers,
            provider_used,
            fallback_used,
            provider_display_name,
            sub_fallback_info,
        ) = await _generate_sub_answers(
            chunks_by_manual,
            question,
            effective_history,
            memory,
            model,
            user_email,
            validated_context,
            no_manuals_directive,
            latency_breakdown=breakdown,
        )
        sub_answer_elapsed = time.monotonic() - sub_answer_start

        grounded_count = sum(1 for s in sub_answers if s["grounded"])
        logger.info(
            "Sub-answer generation took %.1fs for %d manuals, %d grounded",
            sub_answer_elapsed,
            len(chunks_by_manual),
            grounded_count,
        )

        # Step 3: Synthesize — pass breakdown so generator_ms captures the
        # final synthesis call (the customer-facing LLM invocation).
        synthesis_start = time.monotonic()
        synthesis_result = await _synthesize_answers(
            sub_answers, question, model, user_email, latency_breakdown=breakdown
        )
        synthesis_elapsed = time.monotonic() - synthesis_start

        logger.info("Synthesis took %.1fs", synthesis_elapsed)

        gen_elapsed = time.monotonic() - gen_start

        if not synthesis_result["grounded"]:
            provider_display_name = provider_display_name or "Local (Ollama)"
            return {
                "answer": "This information is not in the available manuals.",
                "grounded": False,
                "sources": [],
                "model": provider_display_name,  # spec-065: deprecated alias
                "provider_display_name": provider_display_name,
                "duration_seconds": round(gen_elapsed, 1),
                "session_summary": memory,
                "retrieval_info": retrieval_info,
                "fallback_used": fallback_used,
                "_fallback_info": sub_fallback_info,
            }

        # Collect all sources from contributing manuals and compute highlights
        all_sources = []
        for sa in sub_answers:
            if sa["grounded"]:
                for src in sa["chunks"]:
                    preview = src["content_preview"]
                    highlight_start, highlight_end = compute_highlight(
                        preview, synthesis_result["answer"]
                    )
                    all_sources.append(
                        {
                            "manual_id": src["manual_id"],
                            "manual_title": src["manual_title"],
                            "chunk_index": src["chunk_index"],
                            "source_page": src["source_page"],
                            "content_preview": preview,
                            "highlight_start": highlight_start,
                            "highlight_end": highlight_end,
                        }
                    )

        return {
            "answer": synthesis_result["answer"],
            "grounded": True,
            "sources": all_sources,
            "model": provider_display_name,  # spec-065: deprecated alias
            "provider_display_name": provider_display_name,
            "duration_seconds": round(gen_elapsed, 1),
            "session_summary": memory,
            "manuals_consulted": synthesis_result["manuals_consulted"],
            "has_conflicts": synthesis_result["has_conflicts"],
            "retrieval_info": retrieval_info,
            "provider_used": provider_used,
            "fallback_used": fallback_used,
            "_fallback_info": sub_fallback_info
            or synthesis_result.get("_fallback_info"),
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
