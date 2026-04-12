import logging
import os
import re
import uuid
from datetime import datetime, timezone
from uuid import UUID
from typing import List, Optional
from db import supabase
from services.manual_parser import parse, NoExtractableTextError
from services.manual_chunker import chunk_paragraphs, Chunk
from services.ollama_embedder import embed_many, EmbedderTimeoutError
from services.manual_storage_service import save, delete as delete_file

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

import time as _time

# System instructions cache (avoids DB round-trip on every question)
_si_cache: dict = {"value": "", "ts": 0.0}
_SI_CACHE_TTL = 60.0  # seconds

# Chunk reranking thresholds (spec 044)
# MAX_CHUNK_DISTANCE: cosine distance ceiling; 0.45 was too strict for technical
# manuals with part-number queries — loosened to 0.55 (= 0.45 similarity minimum)
MAX_CHUNK_DISTANCE = 0.55
# MAX_PROMPT_CHUNKS: max chunks sent to LLM after filtering
MAX_PROMPT_CHUNKS = 3


def _get_system_instructions() -> str:
    """Read system instructions from DB, cached for 60 seconds."""
    now = _time.monotonic()
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
) -> str:
    """Assemble the 3-layer prompt: system instructions → chunks → memory → history → question."""
    parts = []

    si = _get_system_instructions()
    if si.strip():
        parts.append(si.strip())

    parts.append(
        "You are a technical assistant for a civil aviation maintenance department.\n"
        "Answer the technician's question using ONLY the manual sections provided below.\n"
        'If the answer is not found in the sections, say: "This information is not in the available manuals."\n'
        "Reply in the same language as the question (Arabic or English)."
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
        embeddings = await embed_many(texts, concurrency=4)
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


async def ask(
    question: str,
    manual_id_filter: Optional[UUID] = None,
    model: Optional[str] = None,
    history: list[dict] | None = None,
    session_summary: str | None = None,
) -> dict:
    from services.ollama_embedder import embed_single, EmbedderTimeoutError
    from services.ollama_generator import generate, GeneratorTimeoutError

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
        }

    # --- Compression logic (spec 045) ---
    # Determine compression early so it can run in parallel with search pipeline.
    # Compression only needs history + session_summary, not search results.
    import asyncio

    memory: str | None = None
    effective_history = history
    needs_compression = history and len(history) > 8
    compression_task: asyncio.Task | None = None
    turns_to_preserve = 4

    if needs_compression:
        turns_already_compressed = len(history) - turns_to_preserve

        if session_summary and turns_already_compressed <= 5:
            # Reuse: threshold triggers at >8 turns (9+), preserving 4 → first
            # compression covers 5 turns. Reuse while that count hasn't grown.
            logger.info("[COMPRESS] Reusing existing summary")
            memory = session_summary
            effective_history = history[-turns_to_preserve:]
        else:
            # Launch compression in parallel with the search pipeline below
            old_turns = (
                history[:-turns_to_preserve]
                if len(history) > turns_to_preserve
                else history
            )
            compression_task = asyncio.create_task(
                _compress_history(old_turns, session_summary, model)
            )

    # --- Search pipeline (runs in parallel with compression) ---
    # Skip query rewrite and HyDE to minimize Ollama calls. On a single-GPU server
    # Ollama serializes generate requests, so each extra call adds ~15s. Direct
    # embedding produces good enough retrieval (distances 0.32-0.43 observed).
    # Both _rewrite_query() and _generate_hypothetical_answer() are preserved if needed.
    embed_input = question

    # Embed the question
    try:
        question_embedding = await embed_single(embed_input)
    except EmbedderTimeoutError:
        raise EmbedderUnavailableError()

    # Retrieve top-5 nearest chunks via the pgvector RPC.
    # Convert embedding list to string format for PostgREST → pgvector cast.
    embedding_str = "[" + ",".join(str(x) for x in question_embedding) + "]"
    rpc_params = {
        "q_embedding": embedding_str,
        "match_count": 5,
    }
    # Only include manual_id_filter if set — omitting it lets the SQL DEFAULT NULL
    # pass all manuals. Sending None via PostgREST can cause casting issues.
    if manual_id_filter:
        rpc_params["manual_id_filter"] = str(manual_id_filter)
    try:
        rpc_response = supabase.rpc(
            "search_manual_chunks",
            rpc_params,
        ).execute()
        chunks_data = rpc_response.data or []
    except Exception:
        raise

    if not chunks_data:
        # Cancel pending compression — we won't need it
        if compression_task:
            compression_task.cancel()
        return {
            "answer": "This information is not in the available manuals.",
            "grounded": False,
            "sources": [],
            "session_summary": None,
        }

    # --- Chunk reranking (spec 044) ---
    # Filter: keep only chunks within the distance threshold
    qualified_chunks = [
        c for c in chunks_data if c.get("distance", 1.0) <= MAX_CHUNK_DISTANCE
    ]
    passed_count = len(qualified_chunks)
    # Slice: take at most MAX_PROMPT_CHUNKS (already sorted by distance ascending from RPC)
    qualified_chunks = qualified_chunks[:MAX_PROMPT_CHUNKS]

    logger.info(
        "Chunk reranking: %d retrieved → %d passed threshold (≤%.2f) → %d sent to LLM",
        len(chunks_data),
        passed_count,
        MAX_CHUNK_DISTANCE,
        len(qualified_chunks),
    )
    if not qualified_chunks:
        if compression_task:
            compression_task.cancel()
        return {
            "answer": "This information is not in the available manuals.",
            "grounded": False,
            "sources": [],
            "model": None,
            "duration_seconds": 0,
            "session_summary": None,
        }

    # --- Await compression result (should already be done or nearly done) ---
    if compression_task:
        new_summary = await compression_task
        if new_summary:
            memory = new_summary
            effective_history = history[-turns_to_preserve:]
            old_count = len(history) - turns_to_preserve
            logger.info(
                "[COMPRESS] Created new summary from %d turns", old_count
            )
        else:
            # Compression failed, fall back to last 10 turns
            logger.warning(
                "[COMPRESS] Compression failed, falling back to last 10 turns"
            )
            effective_history = history[-10:] if history else None
            memory = None

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

    prompt = _build_prompt(retrieved_chunks, question, effective_history, memory)
    # Generate answer
    import time

    gen_start = time.monotonic()
    try:
        answer = await generate(prompt, model=model)
    except GeneratorTimeoutError:
        raise GeneratorUnavailableError()
    gen_elapsed = time.monotonic() - gen_start

    # Check groundedness
    sentinel_phrases = [
        "This information is not in the available manuals.",
        "المعلومات المطلوبة غير موجودة في الأدلة المتاحة",
    ]

    grounded = not any(phrase.lower() in answer.lower() for phrase in sentinel_phrases)

    from services.ollama_generator import get_default_model

    used_model = model or get_default_model()
    if not grounded:
        return {
            "answer": "This information is not in the available manuals.",
            "grounded": False,
            "sources": [],
            "model": used_model,
            "duration_seconds": round(gen_elapsed, 1),
            "session_summary": memory,
        }

    # Format sources for response with highlighting
    final_sources = []
    for src in sources:
        preview = src[
            "content_preview"
        ]  # already truncated to 500 chars during assembly
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
        "model": used_model,
        "duration_seconds": round(gen_elapsed, 1),
        "session_summary": memory,
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
