from fastapi import APIRouter, HTTPException, UploadFile, File, Form, Response, Query
from typing import Optional
from uuid import UUID
import os
import uuid
from pydantic import BaseModel
from db import supabase
from utils.activity import log_activity
import services.manual_rag_service as manual_rag_service

router = APIRouter(tags=["manuals"])

ALLOWED_MIME_TYPES = {
    "application/pdf": "pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "text/plain": "txt",
    "text/markdown": "md",
}

MAX_FILE_SIZE = 20 * 1024 * 1024  # 20 MB


class AskRequest(BaseModel):
    question: str
    manual_id: Optional[str] = None
    user_email: str
    model: Optional[str] = None


@router.get("/manuals/models")
async def get_models():
    from services.ollama_generator import list_models, get_default_model
    models = await list_models()
    return {"models": models, "default": get_default_model()}


@router.get("/manuals/settings")
async def get_ai_settings():
    from services.ollama_generator import get_default_model
    return {"default_model": get_default_model()}


@router.post("/manuals/settings")
async def update_ai_settings(body: dict):
    from services.ollama_generator import set_default_model, get_default_model
    model = body.get("default_model")
    if model:
        set_default_model(model)
    return {"default_model": get_default_model()}


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
        result = await manual_rag_service.ask(question, manual_id_filter, model=request.model)
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
    except Exception:
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
            detail=f"grounded={result.get('grounded', False)}, sources={len(result.get('sources', []))}",
        )
    except Exception:
        pass

    return result
