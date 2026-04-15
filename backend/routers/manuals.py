from fastapi import (
    APIRouter,
    HTTPException,
    UploadFile,
    File,
    Form,
    Response,
    Query,
    BackgroundTasks,
)
from typing import Optional, List
from uuid import UUID
import os
import re
import uuid
import math
from pydantic import BaseModel
from db import supabase
from utils.activity import log_activity
import services.manual_rag_service as manual_rag_service
import services.agentic_tools as agentic_tools
import services.validated_qa_service as validated_qa_service
from services.ollama_embedder import embed_single, embed_many, EmbedderTimeoutError

router = APIRouter(tags=["manuals"])

ALLOWED_MIME_TYPES = {
    "application/pdf": "pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "text/plain": "txt",
    "text/markdown": "md",
}

MAX_FILE_SIZE = 20 * 1024 * 1024  # 20 MB

# Trivial inputs (greetings, acknowledgements) bypass the RAG pipeline — answering
# them via retrieval produces nonsense ("Manual X greets you...") and burns ~60s of
# Ollama time for zero value.
TRIVIAL_INPUT_PATTERN = re.compile(
    r"^\s*("
    r"hi+|hello+|hey+|yo|howdy|"
    r"thanks?|thank\s*you|thx|ty|"
    r"ok(ay)?|k|cool|nice|great|"
    r"bye|goodbye|cya|see\s*you|"
    r"salam|salaam|"
    r"سلام|السلام\s*عليكم|مرحبا|مرحبًا|أهلا|أهلاً|"
    r"شكرا|شكراً|شكرًا|"
    r"مع\s*السلامة|وداعا|وداعاً"
    r")[\s!.?،]*$",
    re.IGNORECASE,
)

TRIVIAL_INPUT_REPLY = (
    "Hi! Ask me a technical question about the manuals — "
    'for example: "how do I reset the X400 after a fault?" or '
    '"what are the APU start procedures?"'
)


class HistoryTurn(BaseModel):
    question: str
    answer: str


class AskRequest(BaseModel):
    question: str
    manual_id: Optional[str] = None
    user_email: str
    model: Optional[str] = None
    history: List[HistoryTurn] = []
    session_summary: Optional[str] = None


@router.get("/manuals/models")
async def get_models():
    from services.ollama_generator import list_models, get_default_model

    models = await list_models()
    return {"models": models, "default": get_default_model()}


@router.get("/manuals/settings")
async def get_ai_settings():
    from services.ollama_generator import get_default_model

    # Read system instructions from DB
    si_response = (
        supabase.table("manual_assistant_settings")
        .select("system_instructions")
        .eq("id", 1)
        .execute()
    )
    system_instructions = (
        si_response.data[0]["system_instructions"] if si_response.data else ""
    )
    return {
        "default_model": get_default_model(),
        "system_instructions": system_instructions,
    }


@router.post("/manuals/settings")
async def update_ai_settings(body: dict):
    from services.ollama_generator import set_default_model, get_default_model

    # Update default model if provided
    model = body.get("default_model")
    if model:
        set_default_model(model)
    # Update system instructions if provided
    if "system_instructions" in body:
        supabase.table("manual_assistant_settings").update(
            {
                "system_instructions": body["system_instructions"],
                "updated_at": "now()",
            }
        ).eq("id", 1).execute()
        try:
            log_activity(
                body.get("user_email", ""),
                "file",
                "updated_manual_assistant_settings",
                target_label="system_instructions",
                detail=str(len(body["system_instructions"])) + " chars",
            )
        except Exception:
            pass
    # Read back current state
    si_response = (
        supabase.table("manual_assistant_settings")
        .select("system_instructions")
        .eq("id", 1)
        .execute()
    )
    system_instructions = (
        si_response.data[0]["system_instructions"] if si_response.data else ""
    )
    return {
        "default_model": get_default_model(),
        "system_instructions": system_instructions,
    }


@router.get("/manuals/")
async def list_manuals():
    response = (
        supabase.table("manuals")
        .select("*, users(full_name)")
        .order("created_at", desc=True)
        .execute()
    )
    manuals = []
    for row in response.data:
        manuals.append(
            {
                "id": row["id"],
                "title": row["title"],
                "file_name": row["file_name"],
                "file_extension": row["file_extension"],
                "file_size_bytes": row["file_size_bytes"],
                "uploaded_by": row["uploaded_by"],
                "uploaded_by_name": (row.get("users") or {}).get("full_name")
                if row.get("users")
                else None,
                "chunk_count": row["chunk_count"],
                "created_at": row["created_at"],
            }
        )

    stats_response = (
        supabase.table("manual_corpus_stats")
        .select("total_bytes, manual_count")
        .eq("id", 1)
        .execute()
    )
    stats = (
        stats_response.data[0]
        if stats_response.data
        else {"total_bytes": 0, "manual_count": 0}
    )
    ceiling_bytes = int(os.getenv("MANUAL_CORPUS_CEILING_MB", "400")) * 1024 * 1024

    return {
        "manuals": manuals,
        "corpus_stats": {
            "total_bytes": stats["total_bytes"],
            "manual_count": stats["manual_count"],
            "ceiling_bytes": ceiling_bytes,
        },
    }


@router.post("/manuals/upload")
async def upload_manual(
    file: UploadFile = File(...),
    title: str = Form(...),
    uploaded_by: str = Form(...),
):
    content_type = file.content_type
    file_extension = ALLOWED_MIME_TYPES.get(content_type)
    if not file_extension:
        raise HTTPException(
            status_code=415,
            detail={
                "error": "unsupported_media_type",
                "message": "Only PDF, DOCX, TXT, and MD files are supported.",
            },
        )

    file_bytes = await file.read()
    file_size = len(file_bytes)
    file_name = file.filename or f"untitled.{file_extension}"

    if file_size > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=413, detail={"error": "file_too_large", "limit_mb": 20}
        )

    if not title.strip():
        raise HTTPException(status_code=400, detail={"error": "title_required"})

    if len(title.strip()) > 200:
        raise HTTPException(
            status_code=400, detail={"error": "title_too_long", "limit": 200}
        )

    try:
        result = await manual_rag_service.upload_manual(
            title=title.strip(),
            file_bytes=file_bytes,
            file_name=file_name,
            file_extension=file_extension,
            file_size_bytes=file_size,
            uploaded_by=uploaded_by,
        )
    except manual_rag_service.NoExtractableTextError:
        raise HTTPException(status_code=422, detail={"error": "no_extractable_text"})
    except manual_rag_service.NoContentAfterChunkingError:
        raise HTTPException(
            status_code=422, detail={"error": "no_content_after_chunking"}
        )
    except manual_rag_service.CorpusFullError as e:
        ceiling_mb = int(os.getenv("MANUAL_CORPUS_CEILING_MB", "400"))
        raise HTTPException(
            status_code=413,
            detail={
                "error": "corpus_full",
                "message": "The manual library is full. Delete an existing manual to make room and try again.",
                "ceiling_mb": ceiling_mb,
            },
        )
    except manual_rag_service.EmbedderUnavailableError:
        raise HTTPException(
            status_code=504,
            detail={
                "error": "embedder_unavailable",
                "message": "The embedding service is temporarily unavailable. Please try again.",
            },
        )
    except Exception:
        raise HTTPException(
            status_code=500,
            detail={
                "error": "upload_failed",
                "message": "Something went wrong while saving the manual.",
            },
        )

    try:
        log_activity(
            uploaded_by,
            "file",
            "uploaded_manual",
            target_label=title.strip(),
            target_id=result["manual_id"],
            detail=f"{result['chunk_count']} chunks, {file_size} bytes",
        )
    except Exception:
        pass

    return result


@router.delete("/manuals/{manual_id}", status_code=204)
async def delete_manual(
    manual_id: str,
    user_email: str = Query(...),
):
    try:
        manual_uuid = UUID(manual_id)
    except ValueError:
        raise HTTPException(status_code=404, detail={"error": "manual_not_found"})

    try:
        deleted = await manual_rag_service.delete_manual(manual_uuid)
    except manual_rag_service.ManualNotFoundError:
        raise HTTPException(status_code=404, detail={"error": "manual_not_found"})
    except Exception:
        raise HTTPException(
            status_code=500,
            detail={
                "error": "delete_failed",
                "message": "Unable to delete the manual.",
            },
        )

    deleted_title = deleted.get("title", "")

    try:
        log_activity(
            user_email,
            "file",
            "deleted_manual",
            target_label=deleted_title,
            target_id=str(manual_uuid),
            detail="",
        )
    except Exception:
        pass

    return Response(status_code=204)


@router.post("/manuals/ask")
async def ask_question(request: AskRequest):
    question = request.question.strip()
    if not question:
        raise HTTPException(status_code=400, detail={"error": "question_required"})
    if len(question) > 2000:
        raise HTTPException(
            status_code=400, detail={"error": "question_too_long", "limit": 2000}
        )

    if TRIVIAL_INPUT_PATTERN.match(question):
        try:
            log_activity(
                request.user_email,
                "file",
                "asked_manual",
                target_label=question[:200],
                target_id=request.manual_id or "all",
                detail="bypass=greeting",
            )
        except Exception:
            pass
        return {
            "answer": TRIVIAL_INPUT_REPLY,
            "sources": [],
            "grounded": False,
            "agentic": False,
            "tools_used": [],
            "bypass": "greeting",
        }

    manual_id_filter = None
    if request.manual_id:
        manual_id_filter = UUID(request.manual_id)
        check = (
            supabase.table("manuals")
            .select("id")
            .eq("id", str(manual_id_filter))
            .execute()
        )
        if not check.data:
            raise HTTPException(status_code=404, detail={"error": "manual_not_found"})

    try:
        history = [
            {"question": h.question, "answer": h.answer} for h in request.history
        ]
        result = await agentic_tools.run_agentic_loop(
            question,
            manual_id_filter,
            model=request.model,
            history=history,
            session_summary=request.session_summary,
        )
    except manual_rag_service.EmbedderUnavailableError:
        raise HTTPException(
            status_code=504,
            detail={
                "error": "embedder_unavailable",
                "message": "The embedding service is temporarily unavailable. Please try again.",
            },
        )
    except manual_rag_service.GeneratorUnavailableError:
        raise HTTPException(
            status_code=504,
            detail={
                "error": "assistant_unavailable",
                "message": "The assistant is taking longer than usual to respond. Please try again.",
            },
        )
    except Exception as e:
        from services.ollama_generator import GeneratorModelError

        if isinstance(e, GeneratorModelError):
            raise HTTPException(
                status_code=503,
                detail={
                    "error": "model_unavailable",
                    "message": f"Model '{e.model}' could not be loaded (not enough memory or not installed). Try a smaller model.",
                },
            )
        import traceback

        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail={
                "error": "ask_failed",
                "message": "Something went wrong while answering.",
            },
        )

    try:
        log_activity(
            request.user_email,
            "file",
            "asked_manual",
            target_label=question[:200],
            target_id=str(manual_id_filter) if manual_id_filter else "all",
            detail=f"grounded={result.get('grounded', False)}, sources={len(result.get('sources', []))}, agentic={result.get('agentic', False)}, tools={[t['tool_name'] for t in result.get('tools_used', [])]}",
        )
    except Exception:
        pass

    try:
        from services.ai_providers.resolver import get_last_provider_result

        provider_used, fallback_used = get_last_provider_result()
        result["provider_used"] = provider_used
        result["fallback_used"] = fallback_used
    except Exception:
        result["provider_used"] = "local"
        result["fallback_used"] = False

    return result


class RateAnswerRequest(BaseModel):
    question_text: str
    answer_text: str
    source_chunks: List[dict] = []
    rating: str
    rater_email: str
    manual_id: Optional[str] = None
    model_used: Optional[str] = None
    session_summary: Optional[str] = None
    validated_qa_id: Optional[str] = None


class ReviewAnswerRequest(BaseModel):
    rating_id: str
    action: str
    corrected_answer: Optional[str] = None
    reviewer_email: str


@router.post("/manuals/rate-answer")
async def rate_answer(request: RateAnswerRequest):
    if request.rating not in ("positive", "negative"):
        raise HTTPException(status_code=400, detail={"error": "invalid_rating"})
    if not request.rater_email:
        raise HTTPException(status_code=400, detail={"error": "rater_email_required"})
    if not request.question_text or not request.answer_text:
        raise HTTPException(
            status_code=400, detail={"error": "question_and_answer_required"}
        )

    try:
        rating_id = validated_qa_service.save_rating(
            question_text=request.question_text,
            answer_text=request.answer_text,
            source_chunks=request.source_chunks,
            rating=request.rating,
            rater_email=request.rater_email,
            manual_id=request.manual_id,
            model_used=request.model_used,
            session_summary=request.session_summary,
        )

        if request.validated_qa_id:
            validated_qa_service.update_validated_rating(
                request.validated_qa_id, request.rating
            )

        try:
            log_activity(
                request.rater_email,
                "manual",
                "rated_answer",
                target_label=request.question_text[:80],
                detail=request.rating,
            )
        except Exception:
            pass

        return {"id": rating_id, "status": "saved"}
    except Exception as e:
        raise HTTPException(
            status_code=500, detail={"error": "save_failed", "message": str(e)}
        )


@router.get("/manuals/flagged-answers")
async def get_flagged_answers(user_email: str = Query(...)):
    try:
        user_resp = (
            supabase.table("users")
            .select("user_type")
            .eq("email", user_email)
            .maybe_single()
            .execute()
        )
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})
    if not user_resp.data or user_resp.data.get("user_type") != "admin":
        raise HTTPException(status_code=403, detail={"error": "admin_required"})

    try:
        items = validated_qa_service.get_flagged_answers()
        return {"items": items, "count": len(items)}
    except Exception as e:
        raise HTTPException(
            status_code=500, detail={"error": "fetch_failed", "message": str(e)}
        )


@router.post("/manuals/review-answer")
async def review_answer(request: ReviewAnswerRequest):
    try:
        user_resp = (
            supabase.table("users")
            .select("user_type")
            .eq("email", request.reviewer_email)
            .maybe_single()
            .execute()
        )
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})
    if not user_resp.data or user_resp.data.get("user_type") != "admin":
        raise HTTPException(status_code=403, detail={"error": "admin_required"})

    if request.action not in ("approve", "correct"):
        raise HTTPException(status_code=400, detail={"error": "invalid_action"})
    if request.action == "correct" and not request.corrected_answer:
        raise HTTPException(
            status_code=400, detail={"error": "corrected_answer_required"}
        )

    try:
        validated_qa_id = await validated_qa_service.review_answer(
            rating_id=request.rating_id,
            action=request.action,
            corrected_answer=request.corrected_answer,
            reviewer_email=request.reviewer_email,
        )
        return {
            "validated_qa_id": validated_qa_id,
            "action": request.action,
            "status": "saved",
        }
    except ValueError as e:
        raise HTTPException(status_code=404, detail={"error": str(e)})
    except Exception as e:
        raise HTTPException(
            status_code=500, detail={"error": "review_failed", "message": str(e)}
        )


class UpdateVerifiedAnswerRequest(BaseModel):
    question_text: Optional[str] = None
    validated_answer: Optional[str] = None
    editor_email: str


@router.get("/manuals/verified-answers")
async def get_verified_answers(
    user_email: str = Query(...),
    search: Optional[str] = Query(None),
    limit: int = Query(50),
    offset: int = Query(0),
):
    _admin_check(user_email)

    try:
        result = validated_qa_service.get_all_verified_answers(
            search=search, limit=limit, offset=offset
        )
        return result
    except Exception:
        raise HTTPException(status_code=500, detail={"error": "fetch_failed"})


@router.put("/manuals/verified-answers/{qa_id}")
async def update_verified_answer(
    qa_id: str,
    request: UpdateVerifiedAnswerRequest,
):
    try:
        _admin_check(request.editor_email)
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})

    try:
        result = await validated_qa_service.update_verified_answer(
            qa_id=qa_id,
            question_text=request.question_text,
            validated_answer=request.validated_answer,
            editor_email=request.editor_email,
        )
        try:
            log_activity(
                request.editor_email,
                "manual",
                "edited_verified_answer",
                target_id=qa_id,
            )
        except Exception:
            pass
        return result
    except ValueError:
        raise HTTPException(status_code=404, detail={"error": "not found"})
    except EmbedderTimeoutError:
        raise HTTPException(status_code=504, detail={"error": "embedding_timeout"})
    except Exception:
        raise HTTPException(status_code=500, detail={"error": "update_failed"})


class CreateVerifiedAnswerRequest(BaseModel):
    question_text: str
    validated_answer: str
    editor_email: str


@router.post("/manuals/verified-answers")
async def create_verified_answer(
    request: CreateVerifiedAnswerRequest,
    background_tasks: BackgroundTasks,
):
    try:
        _admin_check(request.editor_email)
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})

    if not request.question_text.strip() or not request.validated_answer.strip():
        raise HTTPException(
            status_code=422, detail={"error": "question and answer required"}
        )

    try:
        result = await validated_qa_service.create_verified_answer(
            question_text=request.question_text.strip(),
            validated_answer=request.validated_answer.strip(),
            editor_email=request.editor_email,
        )
        background_tasks.add_task(
            log_activity,
            user_email=request.editor_email,
            category="manual_assistant",
            action="created_verified_answer",
            details={
                "qa_id": result.get("id"),
                "question_preview": request.question_text[:100],
            },
        )
        return result
    except ValueError:
        raise HTTPException(
            status_code=422, detail={"error": "question and answer required"}
        )
    except EmbedderTimeoutError:
        raise HTTPException(status_code=504, detail={"error": "embedding_timeout"})
    except Exception:
        raise HTTPException(status_code=500, detail={"error": "create_failed"})


@router.delete("/manuals/verified-answers/{qa_id}")
async def delete_verified_answer(
    qa_id: str,
    editor_email: str = Query(...),
):
    try:
        _admin_check(editor_email)
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})

    try:
        validated_qa_service.delete_verified_answer(qa_id)
        try:
            log_activity(
                editor_email,
                "manual",
                "deleted_verified_answer",
                target_id=qa_id,
            )
        except Exception:
            pass
        return {"status": "deleted", "id": qa_id}
    except ValueError:
        raise HTTPException(status_code=404, detail={"error": "not found"})
    except Exception:
        raise HTTPException(status_code=500, detail={"error": "delete_failed"})


def _admin_check(user_email: str):
    """Shared admin check pattern."""
    try:
        user_resp = (
            supabase.table("users")
            .select("user_type")
            .eq("email", user_email)
            .maybe_single()
            .execute()
        )
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})
    if not user_resp.data or user_resp.data.get("user_type") != "admin":
        raise HTTPException(status_code=403, detail={"error": "admin_required"})


def _reindex_chunks(manual_id: str):
    """Re-number chunk_index values sequentially (0-based) and update chunk_count."""
    chunks = (
        supabase.table("manual_chunks")
        .select("id")
        .eq("manual_id", manual_id)
        .order("chunk_index")
        .execute()
    )
    for i, chunk in enumerate(chunks.data):
        supabase.table("manual_chunks").update({"chunk_index": i}).eq(
            "id", chunk["id"]
        ).execute()

    supabase.table("manuals").update({"chunk_count": len(chunks.data)}).eq(
        "id", manual_id
    ).execute()


class UpdateChunkRequest(BaseModel):
    content: str
    user_email: str


class AddChunkRequest(BaseModel):
    content: str
    insert_after: int = -1
    user_email: str


class SplitChunkRequest(BaseModel):
    split_position: int
    user_email: str


class MergeChunkRequest(BaseModel):
    user_email: str


class BulkDeleteRequest(BaseModel):
    chunk_ids: List[str]
    user_email: str


@router.post("/manuals/{manual_id}/chunks/re-embed")
async def re_embed_all(
    manual_id: str,
    user_email: str = Query(...),
    background_tasks: BackgroundTasks = None,
):
    _admin_check(user_email)

    count_resp = (
        supabase.table("manual_chunks")
        .select("id", count="exact")
        .eq("manual_id", manual_id)
        .execute()
    )
    count = count_resp.count or 0

    async def re_embed_worker(mid: str):
        chunks = (
            supabase.table("manual_chunks")
            .select("id, content")
            .eq("manual_id", mid)
            .order("chunk_index")
            .execute()
        )
        for chunk in chunks.data:
            try:
                embedding = await embed_single(chunk["content"])
                embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"
                supabase.table("manual_chunks").update({"embedding": embedding_str}).eq(
                    "id", chunk["id"]
                ).execute()
            except EmbedderTimeoutError:
                pass

    if background_tasks:
        background_tasks.add_task(re_embed_worker, manual_id)
    else:
        await re_embed_worker(manual_id)

    return {"status": "started", "chunk_count": count}


@router.delete("/manuals/{manual_id}/chunks/bulk-delete")
async def bulk_delete_chunks(manual_id: str, request: BulkDeleteRequest):
    _admin_check(request.user_email)

    for chunk_id in request.chunk_ids:
        supabase.table("manual_chunks").delete().eq("id", chunk_id).eq(
            "manual_id", manual_id
        ).execute()

    _reindex_chunks(manual_id)

    try:
        log_activity(
            request.user_email,
            "file",
            "bulk_deleted_chunks",
            target_id=manual_id,
            detail=f"Deleted {len(request.chunk_ids)} chunks",
        )
    except Exception:
        pass

    return {"deleted": len(request.chunk_ids)}


@router.get("/manuals/{manual_id}/chunks")
async def list_chunks(
    manual_id: str,
    user_email: str = Query(""),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
):

    manual_check = (
        supabase.table("manuals")
        .select("id")
        .eq("id", manual_id)
        .maybe_single()
        .execute()
    )
    if not manual_check.data:
        raise HTTPException(status_code=404, detail={"error": "manual_not_found"})

    count_resp = (
        supabase.table("manual_chunks")
        .select("id", count="exact")
        .eq("manual_id", manual_id)
        .execute()
    )
    total = count_resp.count or 0

    chunks_resp = (
        supabase.table("manual_chunks")
        .select("id, chunk_index, source_page, content, created_at")
        .eq("manual_id", manual_id)
        .order("chunk_index")
        .range((page - 1) * page_size, page * page_size - 1)
        .execute()
    )

    chunks = []
    for row in chunks_resp.data:
        chunks.append(
            {
                "id": row["id"],
                "chunk_index": row["chunk_index"],
                "source_page": row["source_page"],
                "content": row["content"],
                "created_at": row["created_at"],
            }
        )

    return {
        "chunks": chunks,
        "total": total,
        "page": page,
        "page_size": page_size,
        "total_pages": math.ceil(total / page_size) if total > 0 else 1,
    }


@router.post("/manuals/{manual_id}/chunks")
async def add_chunk(manual_id: str, request: AddChunkRequest):
    _admin_check(request.user_email)

    if not request.content.strip():
        raise HTTPException(status_code=400, detail={"error": "content_required"})

    try:
        embedding = await embed_single(request.content)
        embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"
    except EmbedderTimeoutError:
        raise HTTPException(
            status_code=504,
            detail={
                "error": "embedder_unavailable",
                "message": "Embedding service timed out",
            },
        )

    if request.insert_after == -1:
        count_resp = (
            supabase.table("manual_chunks")
            .select("id", count="exact")
            .eq("manual_id", manual_id)
            .execute()
        )
        new_index = count_resp.count or 0
    else:
        new_index = request.insert_after + 1

    existing = (
        supabase.table("manual_chunks")
        .select("id, chunk_index")
        .eq("manual_id", manual_id)
        .gte("chunk_index", new_index)
        .order("chunk_index", desc=True)
        .execute()
    )
    for chunk in existing.data:
        supabase.table("manual_chunks").update(
            {"chunk_index": chunk["chunk_index"] + 1}
        ).eq("id", chunk["id"]).execute()

    new_chunk = (
        supabase.table("manual_chunks")
        .insert(
            {
                "manual_id": manual_id,
                "chunk_index": new_index,
                "source_page": None,
                "content": request.content,
                "embedding": embedding_str,
            }
        )
        .execute()
    )

    supabase.table("manuals").update(
        {
            "chunk_count": supabase.table("manual_chunks")
            .select("id", count="exact")
            .eq("manual_id", manual_id)
            .execute()
            .count
            or 0
        }
    ).eq("id", manual_id).execute()

    try:
        log_activity(
            request.user_email,
            "file",
            "added_chunk",
            target_id=manual_id,
            detail=f"Added chunk at index {new_index}",
        )
    except Exception:
        pass

    row = new_chunk.data[0]
    return {
        "id": row["id"],
        "chunk_index": row["chunk_index"],
        "source_page": row["source_page"],
        "content": row["content"],
        "created_at": row["created_at"],
    }


@router.get("/manuals/{manual_id}/chunks/{chunk_id}")
async def get_chunk(manual_id: str, chunk_id: str, user_email: str = Query("")):

    chunk_resp = (
        supabase.table("manual_chunks")
        .select("id, chunk_index, source_page, content, created_at")
        .eq("id", chunk_id)
        .eq("manual_id", manual_id)
        .maybe_single()
        .execute()
    )

    if not chunk_resp.data:
        raise HTTPException(status_code=404, detail={"error": "chunk_not_found"})

    row = chunk_resp.data
    return {
        "id": row["id"],
        "chunk_index": row["chunk_index"],
        "source_page": row["source_page"],
        "content": row["content"],
        "created_at": row["created_at"],
    }


@router.put("/manuals/{manual_id}/chunks/{chunk_id}")
async def update_chunk(manual_id: str, chunk_id: str, request: UpdateChunkRequest):
    _admin_check(request.user_email)

    if not request.content.strip():
        raise HTTPException(status_code=400, detail={"error": "content_required"})

    try:
        embedding = await embed_single(request.content)
        embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"
    except EmbedderTimeoutError:
        embedding_str = None

    update_data = {"content": request.content}
    if embedding_str:
        update_data["embedding"] = embedding_str

    updated = (
        supabase.table("manual_chunks")
        .update(update_data)
        .eq("id", chunk_id)
        .eq("manual_id", manual_id)
        .execute()
    )

    if not updated.data:
        raise HTTPException(status_code=404, detail={"error": "chunk_not_found"})

    try:
        log_activity(
            request.user_email,
            "file",
            "updated_chunk",
            target_id=manual_id,
            detail=f"Updated chunk {chunk_id}",
        )
    except Exception:
        pass

    row = updated.data[0]
    return {
        "id": row["id"],
        "chunk_index": row["chunk_index"],
        "source_page": row["source_page"],
        "content": row["content"],
        "created_at": row["created_at"],
    }


@router.delete("/manuals/{manual_id}/chunks/{chunk_id}", status_code=204)
async def delete_chunk(manual_id: str, chunk_id: str, user_email: str = Query(...)):
    _admin_check(user_email)

    supabase.table("manual_chunks").delete().eq("id", chunk_id).eq(
        "manual_id", manual_id
    ).execute()

    _reindex_chunks(manual_id)

    try:
        log_activity(
            user_email,
            "file",
            "deleted_chunk",
            target_id=manual_id,
            detail=f"Deleted chunk {chunk_id}",
        )
    except Exception:
        pass

    return Response(status_code=204)


@router.post("/manuals/{manual_id}/chunks/{chunk_id}/split")
async def split_chunk(manual_id: str, chunk_id: str, request: SplitChunkRequest):
    _admin_check(request.user_email)

    chunk_resp = (
        supabase.table("manual_chunks")
        .select("id, chunk_index, source_page, content, created_at")
        .eq("id", chunk_id)
        .eq("manual_id", manual_id)
        .maybe_single()
        .execute()
    )

    if not chunk_resp.data:
        raise HTTPException(status_code=404, detail={"error": "chunk_not_found"})

    chunk = chunk_resp.data
    content = chunk["content"]
    original_index = chunk["chunk_index"]

    split_pos = request.split_position
    if split_pos <= 0 or split_pos >= len(content):
        raise HTTPException(status_code=400, detail={"error": "invalid_split_position"})

    part_a = content[:split_pos].strip()
    part_b = content[split_pos:].strip()

    if not part_a or not part_b:
        raise HTTPException(
            status_code=400, detail={"error": "split_would_create_empty"}
        )

    try:
        embeddings = await embed_many([part_a, part_b])
        emb_a = "[" + ",".join(str(x) for x in embeddings[0]) + "]"
        emb_b = "[" + ",".join(str(x) for x in embeddings[1]) + "]"
    except EmbedderTimeoutError:
        raise HTTPException(
            status_code=504,
            detail={
                "error": "embedder_unavailable",
                "message": "Embedding service timed out",
            },
        )

    existing = (
        supabase.table("manual_chunks")
        .select("id, chunk_index")
        .eq("manual_id", manual_id)
        .gt("chunk_index", original_index)
        .order("chunk_index", desc=True)
        .execute()
    )
    for c in existing.data:
        supabase.table("manual_chunks").update(
            {"chunk_index": c["chunk_index"] + 1}
        ).eq("id", c["id"]).execute()

    supabase.table("manual_chunks").update({"content": part_a, "embedding": emb_a}).eq(
        "id", chunk_id
    ).execute()

    new_chunk = (
        supabase.table("manual_chunks")
        .insert(
            {
                "manual_id": manual_id,
                "chunk_index": original_index + 1,
                "source_page": None,
                "content": part_b,
                "embedding": emb_b,
            }
        )
        .execute()
    )

    supabase.table("manuals").update(
        {
            "chunk_count": supabase.table("manual_chunks")
            .select("id", count="exact")
            .eq("manual_id", manual_id)
            .execute()
            .count
            or 0
        }
    ).eq("id", manual_id).execute()

    try:
        log_activity(
            request.user_email,
            "file",
            "split_chunk",
            target_id=manual_id,
            detail=f"Split chunk {chunk_id} at position {split_pos}",
        )
    except Exception:
        pass

    updated_a = (
        supabase.table("manual_chunks")
        .select("id, chunk_index, source_page, content, created_at")
        .eq("id", chunk_id)
        .execute()
    )
    row_a = updated_a.data[0]
    row_b = new_chunk.data[0]
    return {
        "chunks": [
            {
                "id": row_a["id"],
                "chunk_index": row_a["chunk_index"],
                "source_page": row_a["source_page"],
                "content": row_a["content"],
                "created_at": row_a["created_at"],
            },
            {
                "id": row_b["id"],
                "chunk_index": row_b["chunk_index"],
                "source_page": row_b["source_page"],
                "content": part_b,
                "created_at": row_b["created_at"],
            },
        ]
    }


@router.post("/manuals/{manual_id}/chunks/{chunk_id}/merge")
async def merge_chunk(manual_id: str, chunk_id: str, request: MergeChunkRequest):
    _admin_check(request.user_email)

    chunk_resp = (
        supabase.table("manual_chunks")
        .select("id, chunk_index, content")
        .eq("id", chunk_id)
        .eq("manual_id", manual_id)
        .maybe_single()
        .execute()
    )

    if not chunk_resp.data:
        raise HTTPException(status_code=404, detail={"error": "chunk_not_found"})

    chunk = chunk_resp.data
    original_index = chunk["chunk_index"]

    next_chunk_resp = (
        supabase.table("manual_chunks")
        .select("id, chunk_index, content")
        .eq("manual_id", manual_id)
        .eq("chunk_index", original_index + 1)
        .maybe_single()
        .execute()
    )

    if not next_chunk_resp.data:
        raise HTTPException(status_code=400, detail={"error": "no_next_chunk"})

    next_chunk = next_chunk_resp.data
    combined = chunk["content"] + "\n\n" + next_chunk["content"]

    try:
        embedding = await embed_single(combined)
        embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"
    except EmbedderTimeoutError:
        embedding_str = None

    update_data = {"content": combined}
    if embedding_str:
        update_data["embedding"] = embedding_str

    supabase.table("manual_chunks").update(update_data).eq("id", chunk_id).execute()

    supabase.table("manual_chunks").delete().eq("id", next_chunk["id"]).execute()

    _reindex_chunks(manual_id)

    try:
        log_activity(
            request.user_email,
            "file",
            "merged_chunks",
            target_id=manual_id,
            detail=f"Merged chunk {chunk_id} with {next_chunk['id']}",
        )
    except Exception:
        pass

    updated = (
        supabase.table("manual_chunks")
        .select("id, chunk_index, source_page, content, created_at")
        .eq("id", chunk_id)
        .execute()
    )

    row = updated.data[0]
    return {
        "id": row["id"],
        "chunk_index": row["chunk_index"],
        "source_page": row["source_page"],
        "content": row["content"],
        "created_at": row["created_at"],
    }
