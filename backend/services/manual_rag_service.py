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

PROMPT_TEMPLATE = """You are a technical assistant for a civil aviation maintenance department.
Answer the technician's question using ONLY the manual sections provided below.
If the answer is not found in the sections, say: "This information is not in the available manuals."
Reply in the same language as the question (Arabic or English).

MANUAL SECTIONS:
{retrieved_chunks}

QUESTION: {user_question}

ANSWER:
"""

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
    user_row = supabase.table("users").select("id").eq("email", uploaded_by).limit(1).execute()
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


async def ask(question: str, manual_id_filter: Optional[UUID] = None, model: Optional[str] = None) -> dict:
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
        }

    # Embed the question
    try:
        question_embedding = await embed_single(question)
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
        return {
            "answer": "This information is not in the available manuals.",
            "grounded": False,
            "sources": [],
        }

    # Build prompt
    # All 5 chunks go into the prompt (more context = better answer),
    # but only relevant ones (distance < 0.45) are shown as sources to the user.
    MAX_SOURCE_DISTANCE = 0.45
    retrieved_chunks = ""
    sources = []
    for i, chunk in enumerate(chunks_data):
        manual_title = chunk.get("manual_title", "Unknown")
        source_page = chunk.get("source_page")
        content = chunk.get("content", "")
        distance = chunk.get("distance", 1.0)
        retrieved_chunks += f"[Source {i + 1}: {manual_title}, page {source_page or '—'}]\n{content}\n---\n"
        if distance <= MAX_SOURCE_DISTANCE:
            sources.append(
                {
                    "manual_id": chunk.get("manual_id"),
                    "manual_title": manual_title,
                    "chunk_index": chunk.get("chunk_index", 0),
                    "source_page": source_page,
                    "content_preview": content[:500],
                }
            )

    prompt = PROMPT_TEMPLATE.format(
        retrieved_chunks=retrieved_chunks,
        user_question=question,
    )
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
        }

    # Format sources for response with highlighting
    final_sources = []
    for src in sources:
        preview = src["content_preview"]  # already truncated to 500 chars during assembly
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
