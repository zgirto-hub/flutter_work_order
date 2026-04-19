import time
from datetime import datetime, timezone
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
from typing import Literal, Optional, List
from uuid import UUID
import os
import re
import uuid
import math
import json
from pydantic import BaseModel, Field
from db import supabase
from utils.activity import log_activity
import services.manual_rag_service as manual_rag_service
import services.agentic_tools as agentic_tools
import services.validated_qa_service as validated_qa_service
from services.ollama_embedder import embed_single, embed_many, EmbedderTimeoutError
from services.ai_providers.resolver import generate as provider_generate
from services.contextual_prefix import apply_contextual_prefix
from prompts.paraphrase_prompt import (
    PARAPHRASE_PROMPT_TEMPLATE,
    parse_paraphrase_output,
)
from sse_starlette.sse import EventSourceResponse
import logging

router = APIRouter(tags=["manuals"])

logger = logging.getLogger(__name__)


def _get_manual_title(manual_id: str) -> str:
    """Fetch title for contextual embedding prefix."""
    resp = (
        supabase.table("manuals")
        .select("title")
        .eq("id", manual_id)
        .maybe_single()
        .execute()
    )
    return resp.data.get("title", "") if resp.data else ""


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
    "I can help you with manuals, work orders, and verified Q&A. "
    "What would you like to know?"
)

_ALLOWED_VERIFIED_SORTS = {"recent", "most_used", "most_problematic"}


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


@router.post("/manuals/ask/stream")
async def ask_question_stream(request: AskRequest):
    question = request.question.strip()
    if not question:
        raise HTTPException(status_code=400, detail={"error": "question_required"})
    if len(question) > 2000:
        raise HTTPException(
            status_code=400, detail={"error": "question_too_long", "limit": 2000}
        )

    _req_start = time.perf_counter()

    if TRIVIAL_INPUT_PATTERN.match(question):
        total_ms = round((time.perf_counter() - _req_start) * 1000)
        return EventSourceResponse(
            _trivial_stream_response(question, request.user_email, total_ms),
            media_type="text/event-stream",
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

    from services.manual_rag_service import _empty_latency_breakdown

    breakdown = _empty_latency_breakdown()

    try:
        history = [
            {"question": h.question, "answer": h.answer} for h in request.history
        ]

        if agentic_tools._needs_tools(question):
            result = await agentic_tools.run_agentic_loop(
                question,
                manual_id_filter,
                model=request.model,
                history=history,
                session_summary=request.session_summary,
                user_email=request.user_email,
                latency_breakdown=breakdown,
            )
            breakdown["total_ms"] = round((time.perf_counter() - _req_start) * 1000)
            result["latency_breakdown"] = breakdown

            async def agentic_event_gen():
                yield {"data": result["answer"]}
                result["done"] = True
                result["total_ms"] = breakdown["total_ms"]
                yield {"event": "metadata", "data": json.dumps(result)}

            return EventSourceResponse(
                agentic_event_gen(), media_type="text/event-stream"
            )

        stream_meta: dict = {}
        token_count = 0

        async def event_gen():
            nonlocal token_count

            try:
                async for token in manual_rag_service.ask_stream(
                    question,
                    manual_id_filter,
                    model=request.model,
                    history=history,
                    session_summary=request.session_summary,
                    user_email=request.user_email,
                    latency_breakdown=breakdown,
                    stream_meta=stream_meta,
                ):
                    token_count += 1
                    yield {"data": token}

                # Handle empty model response (no tokens)
                if token_count == 0:
                    yield {"data": "No answer generated"}

                breakdown["total_ms"] = round((time.perf_counter() - _req_start) * 1000)

                # Activity logging (constitution VI: Audit Everything)
                try:
                    log_activity(
                        request.user_email,
                        "file",
                        "asked_manual",
                        target_label=question[:200],
                        target_id=str(manual_id_filter) if manual_id_filter else "all",
                        detail=f"stream=true, grounded={stream_meta.get('grounded', False)}, sources={len(stream_meta.get('sources', []))}",
                    )
                except Exception:
                    pass

                # Fallback audit logging (spec-065)
                fallback_info = stream_meta.get("fallback_info")
                if fallback_info:
                    try:
                        log_activity(
                            fallback_info.get("user_email", request.user_email),
                            category="admin",
                            action="ai_provider_fallback",
                            target_label=fallback_info.get(
                                "failed_provider", "unknown"
                            ),
                            target_id=fallback_info.get("fallback_provider", "unknown"),
                            detail=fallback_info.get("detail", "unknown"),
                        )
                    except Exception:
                        pass

                result = {
                    "sources": stream_meta.get("sources", []),
                    "grounded": stream_meta.get("grounded", False),
                    "confidence": stream_meta.get("confidence", "low"),
                    "total_tokens": token_count,
                    "done": True,
                    "provider_used": stream_meta.get("provider_key", "local"),
                    "provider_display_name": stream_meta.get(
                        "display_name", "Local (Ollama)"
                    ),
                    "fallback_used": stream_meta.get("fallback_used", False),
                    "is_verified": stream_meta.get("is_verified", False),
                    "verified_source": stream_meta.get("verified_source"),
                    "verification_mode": stream_meta.get("verification_mode"),
                    "verified_source_count": stream_meta.get("verified_source_count"),
                    "latency_breakdown": breakdown,
                    "session_summary": stream_meta.get("session_summary"),
                    "manuals_consulted": stream_meta.get("manuals_consulted", []),
                    "agentic": False,
                    "tools_used": [],
                    "retrieval_info": stream_meta.get("retrieval_info"),
                }

                yield {"event": "metadata", "data": json.dumps(result)}

            except Exception as e:
                logger.error(f"Streaming error: {e}")
                error_data = {
                    "error": "stream_failed",
                    "message": str(e),
                    "partial": token_count > 0,
                }
                yield {"event": "error", "data": json.dumps(error_data)}

        return EventSourceResponse(event_gen(), media_type="text/event-stream")

    except Exception as e:
        logger.error(f"SSE endpoint error: {e}")
        error_data = {
            "error": "stream_failed",
            "message": str(e),
            "partial": False,
        }

        async def error_event_gen():
            yield {"event": "error", "data": json.dumps(error_data)}

        return EventSourceResponse(error_event_gen(), media_type="text/event-stream")


async def _trivial_stream_response(question: str, user_email: str, total_ms: int):
    try:
        log_activity(
            user_email,
            "file",
            "asked_manual",
            target_label=question[:200],
            target_id="all",
            detail="bypass=greeting",
        )
    except Exception:
        pass

    yield {"data": TRIVIAL_INPUT_REPLY}
    yield {
        "event": "metadata",
        "data": json.dumps(
            {
                "sources": [],
                "grounded": False,
                "confidence": "low",
                "total_tokens": 0,
                "done": True,
                "bypass": "greeting",
                "provider_used": "local",
                "provider_display_name": "Local (Ollama)",
                "fallback_used": False,
                "is_verified": False,
                "verified_source": None,
                "latency_breakdown": {
                    "embed_ms": None,
                    "hyde_ms": None,
                    "rewrite_ms": None,
                    "retrieval_ms": None,
                    "rerank_ms": None,
                    "generator_ms": None,
                    "total_ms": total_ms,
                },
                "session_summary": None,
                "manuals_consulted": [],
                "agentic": False,
                "tools_used": [],
                "retrieval_info": {
                    "detected_system": None,
                    "filtered_manual_ids": [],
                    "filter_applied": False,
                    "fallback_reason": None,
                },
            }
        ),
    }


@router.post("/manuals/ask")
async def ask_question(request: AskRequest):
    question = request.question.strip()
    if not question:
        raise HTTPException(status_code=400, detail={"error": "question_required"})
    if len(question) > 2000:
        raise HTTPException(
            status_code=400, detail={"error": "question_too_long", "limit": 2000}
        )

    # F2.1: Add request start timer at very beginning
    _req_start = time.perf_counter()

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

        # F2.2: Fix total_ms to be elapsed, not raw counter
        total_ms = round((time.perf_counter() - _req_start) * 1000)
        return {
            "answer": TRIVIAL_INPUT_REPLY,
            "sources": [],
            "grounded": False,
            "agentic": False,
            "tools_used": [],
            "bypass": "greeting",
            "latency_breakdown": {
                "embed_ms": None,
                "hyde_ms": None,
                "rewrite_ms": None,
                "retrieval_ms": None,
                "rerank_ms": None,
                "generator_ms": None,
                "total_ms": total_ms,
            },
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

    # F3: Create breakdown dict BEFORE calling the service, pass it down
    from services.manual_rag_service import _empty_latency_breakdown

    breakdown = _empty_latency_breakdown()

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
            user_email=request.user_email,
            # F1.4: Pass the breakdown dict into run_agentic_loop
            latency_breakdown=breakdown,
        )

        # F3.1-3.3: Stop synthesizing - use the dict that was passed through
        breakdown["total_ms"] = round((time.perf_counter() - _req_start) * 1000)
        result["latency_breakdown"] = breakdown

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

    # Fix #2: If the LLM refused to answer despite retrieval scoring above threshold,
    # override grounded to False so the frontend doesn't show a "grounded" badge on
    # an empty answer.  Uses the same sentinel phrases from manual_rag_service.
    if result.get("grounded") and result.get("answer"):
        from services.manual_rag_service import (
            _NOT_FOUND_KNOWLEDGE_BASE,
            _NOT_FOUND_MANUALS,
            _NOT_FOUND_KNOWLEDGE_BASE_AR,
        )

        _sentinel_phrases = [
            _NOT_FOUND_KNOWLEDGE_BASE.lower(),
            _NOT_FOUND_MANUALS.lower(),
            _NOT_FOUND_KNOWLEDGE_BASE_AR,
        ]
        answer_lower = result["answer"].strip().lower()
        if any(phrase in answer_lower for phrase in _sentinel_phrases):
            result["grounded"] = False

    result.setdefault("provider_used", "local")
    result.setdefault("fallback_used", False)

    # spec-065: write exactly one audit row on fallback (FR-003)
    fallback_info = result.get("_fallback_info")
    if fallback_info:
        try:
            log_activity(
                fallback_info.get("user_email", request.user_email),
                category="admin",
                action="ai_provider_fallback",
                target_label=fallback_info.get("failed_provider", "unknown"),
                target_id=fallback_info.get("fallback_provider", "unknown"),
                detail=fallback_info.get("detail", "unknown"),
            )
        except Exception:
            pass

    result.pop("_fallback_info", None)

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


class RatingFeedbackRequest(BaseModel):
    feedback_reason: Literal[
        "inaccurate", "incomplete", "outdated", "wrong_source", "unclear"
    ]
    feedback_comment: Optional[str] = Field(None, max_length=2000)
    user_email: str


@router.patch("/manuals/ratings/{rating_id}/feedback")
async def patch_rating_feedback(rating_id: str, request: RatingFeedbackRequest):
    try:
        result = validated_qa_service.update_rating_feedback(
            rating_id=rating_id,
            reason=request.feedback_reason,
            comment=request.feedback_comment,
            user_email=request.user_email,
        )
        return {
            "status": "saved",
            "rating_id": rating_id,
            "feedback_reason": result["feedback_reason"],
            "feedback_comment": result["feedback_comment"],
        }
    except validated_qa_service.RatingNotFound:
        raise HTTPException(
            status_code=404, detail={"error": "rating_not_found"}
        )
    except validated_qa_service.NotOwner:
        raise HTTPException(
            status_code=403, detail={"error": "not_owner"}
        )
    except validated_qa_service.NotNegativeRating:
        raise HTTPException(
            status_code=400, detail={"error": "not_negative_rating"}
        )
    except Exception as e:
        raise HTTPException(
            status_code=500, detail={"error": "save_failed", "message": str(e)}
        )


@router.delete("/manuals/ratings/{rating_id}")
async def delete_rating(rating_id: str, user_email: str = Query(...)):
    try:
        row_resp = (
            supabase.table("answer_ratings")
            .select("rater_email, question_text, rating")
            .eq("id", rating_id)
            .maybe_single()
            .execute()
        )
        if not row_resp.data:
            return {"status": "deleted", "existed": False}

        row = row_resp.data
        if row["rater_email"] != user_email:
            _admin_check(user_email)

        result = validated_qa_service.delete_rating(rating_id)

        try:
            if user_email == row["rater_email"]:
                log_activity(
                    user_email,
                    "manual",
                    "unrated_answer",
                    target_label=row["question_text"][:80],
                    detail=row["rating"],
                )
            else:
                log_activity(
                    user_email,
                    "manual",
                    "admin_deleted_rating",
                    target_label=row["question_text"][:80],
                    detail=row["rater_email"],
                )
        except Exception:
            pass

        return {"status": "deleted", "existed": result["existed"]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500, detail={"error": "delete_failed", "message": str(e)}
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
    if user_resp is None or not user_resp.data or user_resp.data.get("user_type") != "admin":
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
    if user_resp is None or not user_resp.data or user_resp.data.get("user_type") != "admin":
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


class ParaphraseVariantsRequest(BaseModel):
    question_text: str
    rating_id: Optional[str] = None
    lang: str = "en"


ARABIC_PARAPHRASE_PROMPT = 'Translate this question to Arabic, then generate 3 natural Arabic paraphrase variants a maintenance technician might use. The variants must sound natural in Arabic, not like direct translations. Return JSON only — no preamble, no markdown: {{"variants": ["...", "...", "..."]}}\nQuestion: {q}'


@router.post("/manuals/paraphrase-variants")
async def generate_paraphrase_variants(
    request: ParaphraseVariantsRequest,
    user_email: str = Query(...),
):
    try:
        _admin_check(user_email)
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})

    stripped_question = request.question_text.strip() if request.question_text else ""
    if not stripped_question or len(stripped_question) > 500:
        raise HTTPException(
            status_code=400, detail={"error": "question_text must be 1-500 chars"}
        )

    if request.lang == "ar":
        prompt = ARABIC_PARAPHRASE_PROMPT.format(q=request.question_text)
    else:
        prompt = PARAPHRASE_PROMPT_TEMPLATE.format(q=request.question_text)

    import asyncio as _asyncio

    async def _try_once() -> tuple[list[str], str | None, str | None]:
        """Returns (variants, provider_used, error_message)."""
        try:
            (
                answer_text,
                provider_key,
                display_name,
                fallback_used,
                fallback_info,
            ) = await provider_generate(prompt, [])
            if request.lang == "ar":
                # Arabic prompt asks for JSON — parse that shape
                variants = _parse_json_variants(answer_text)
            else:
                variants = parse_paraphrase_output(answer_text, request.question_text)
            return variants, display_name, None
        except Exception as e:
            return [], None, str(e)

    # First attempt
    variants, provider, err = await _try_once()

    # Retry once on transient failure (empty result OR exception)
    if not variants:
        logging.warning(
            f"Paraphrase attempt 1 failed (lang={request.lang}, err={err}); retrying..."
        )
        await _asyncio.sleep(1.5)
        variants, provider, err = await _try_once()

    if variants:
        return {"variants": variants, "provider": provider}

    # Surface the real reason so the UI can tell admins why it failed
    reason = err or "Model returned no parseable variants"
    logging.warning(
        f"Paraphrase generation failed after retry (lang={request.lang}): {reason}"
    )
    return {"variants": [], "error": reason}


def _parse_json_variants(raw: str) -> list[str]:
    """Extract variants from JSON-shaped model output (Arabic prompt)."""
    import re as _re
    try:
        cleaned = raw.strip()
        # Strip markdown fences if the model added them despite "no markdown"
        if cleaned.startswith("```"):
            cleaned = _re.sub(r"^```[a-zA-Z]*\n?", "", cleaned)
            cleaned = _re.sub(r"\n?```$", "", cleaned).strip()
        data = json.loads(cleaned)
        variants = data.get("variants", [])
        return [v.strip() for v in variants if isinstance(v, str) and v.strip()][:5]
    except Exception:
        # Fallback: try line-split parsing if JSON failed
        return parse_paraphrase_output(raw, "")


class ReviewAnswerWithVariantsRequest(BaseModel):
    rating_id: str
    action: str
    corrected_answer: Optional[str] = None
    existing_validated_qa_id: Optional[str] = None
    variants: List[str]


@router.post("/manuals/review-answer-with-variants")
async def review_answer_with_variants(
    request: ReviewAnswerWithVariantsRequest,
    user_email: str = Query(...),
):
    try:
        _admin_check(user_email)
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})

    if request.action not in ("approve", "correct", "retro_expand"):
        raise HTTPException(status_code=400, detail={"error": "invalid_action"})

    if request.action == "correct" and not request.corrected_answer:
        raise HTTPException(
            status_code=400, detail={"error": "corrected_answer_required"}
        )

    if request.action == "retro_expand" and not request.existing_validated_qa_id:
        raise HTTPException(
            status_code=400, detail={"error": "existing_validated_qa_id_required"}
        )

    # Validate variants: trim, drop whitespace-only
    cleaned_variants = [v.strip() for v in request.variants if v.strip()]
    if not cleaned_variants:
        raise HTTPException(status_code=400, detail={"error": "no_valid_variants"})

    if len(cleaned_variants) > 10:
        raise HTTPException(status_code=400, detail={"error": "max_10_variants"})

    # Validate each variant length
    for v in cleaned_variants:
        if len(v) > 500:
            raise HTTPException(
                status_code=400, detail={"error": "variant_exceeds_500_chars"}
            )

    try:
        result = await validated_qa_service.review_answer_multi(
            rating_id=request.rating_id,
            action=request.action,
            corrected_answer=request.corrected_answer,
            reviewer_email=user_email,
            variant_texts=cleaned_variants,
            existing_validated_qa_id=request.existing_validated_qa_id,
        )
        return result
    except ValueError as e:
        raise HTTPException(status_code=404, detail={"error": str(e)})
    except EmbedderTimeoutError:
        raise HTTPException(status_code=500, detail={"error": "embedding_timeout"})
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
    sort: str = Query("recent"),
):
    _admin_check(user_email)

    if sort not in _ALLOWED_VERIFIED_SORTS:
        raise HTTPException(
            status_code=400,
            detail={"error": "invalid_sort", "allowed": sorted(_ALLOWED_VERIFIED_SORTS)},
        )

    try:
        result = validated_qa_service.get_all_verified_answers(
            search=search, limit=limit, offset=offset, sort=sort
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
    source_manual_id: Optional[str] = None


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
            source_manual_id=request.source_manual_id,
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
    _admin_check(editor_email)

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


@router.get("/manuals/verified-answers/{qa_id}/variants")
async def get_verified_answer_variants(
    qa_id: str,
    user_email: str = Query(...),
):
    _admin_check(user_email)

    try:
        result = await validated_qa_service.get_variants_group(qa_id)
        return result
    except ValueError as e:
        raise HTTPException(status_code=404, detail={"error": str(e)})
    except Exception:
        raise HTTPException(status_code=500, detail={"error": "fetch_failed"})


class UpdateVerifiedAnswerVariantsRequest(BaseModel):
    user_email: str
    variants: List[str]


@router.put("/manuals/verified-answers/{qa_id}/variants")
async def update_verified_answer_variants(
    qa_id: str,
    request: UpdateVerifiedAnswerVariantsRequest,
):
    _admin_check(request.user_email)

    try:
        result = await validated_qa_service.reconcile_variants(
            qa_id=qa_id,
            submitted_variants=request.variants,
            editor_email=request.user_email,
        )
        return result
    except ValueError as e:
        msg = str(e)
        if msg == "not found":
            raise HTTPException(status_code=404, detail={"error": "not found"})
        if msg in ("at least one variant required", "variant exceeds 500 characters"):
            raise HTTPException(status_code=400, detail={"error": msg})
        raise HTTPException(status_code=400, detail={"error": msg})
    except validated_qa_service.EmbeddingUnavailable as e:
        raise HTTPException(
            status_code=503,
            detail={"error": "embedding service unavailable; please retry"},
        )
    except Exception:
        raise HTTPException(status_code=500, detail={"error": "update_failed"})


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
    if user_resp is None or not user_resp.data or user_resp.data.get("user_type") != "admin":
        raise HTTPException(status_code=403, detail={"error": "admin_required"})


class GenerateQACandidatesRequest(BaseModel):
    manual_id: str
    max_candidates: int = 20


@router.post("/manuals/generate-qa-candidates")
async def generate_qa_candidates(
    request: GenerateQACandidatesRequest,
    user_email: str = Query(...),
    background_tasks: BackgroundTasks = None,
):
    try:
        return await _generate_qa_candidates_impl(
            request, user_email, background_tasks
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"generate-qa-candidates failed: {e}")
        raise HTTPException(
            status_code=500,
            detail={"error": "generation_failed", "message": str(e)},
        )


async def _generate_qa_candidates_impl(
    request: GenerateQACandidatesRequest,
    user_email: str,
    background_tasks: BackgroundTasks,
):
    try:
        _admin_check(user_email)
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})

    # Cap max_candidates to prevent excessive API calls
    max_candidates = min(request.max_candidates, 50)

    # Read from knowledge_documents (live table) — the legacy `manuals` table
    # was retired in spec 072 when the Knowledge tab replaced the Manual uploader
    manual_resp = (
        supabase.table("knowledge_documents")
        .select("id, display_name")
        .eq("id", request.manual_id)
        .maybe_single()
        .execute()
    )
    if not manual_resp.data:
        raise HTTPException(
            status_code=404,
            detail={"error": "not_found", "message": "Document not found."},
        )

    manual_title = manual_resp.data["display_name"]

    # Only child chunks have embeddings (parent chunks hold synthesis context)
    chunks_resp = (
        supabase.table("document_chunks")
        .select("id, content, page_number, embedding")
        .eq("document_id", request.manual_id)
        .eq("chunk_type", "child")
        .execute()
    )
    if not chunks_resp.data:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "no_chunks",
                "message": "This document has no content chunks. Please process it first.",
            },
        )

    chunks = chunks_resp.data
    skipped_cached = 0
    candidates = []
    generated_embeddings = []

    def cosine_similarity(a: List[float], b: List[float]) -> float:
        dot = sum(x * y for x, y in zip(a, b))
        norm_a = sum(x * x for x in a) ** 0.5
        norm_b = sum(x * x for x in b) ** 0.5
        if norm_a == 0 or norm_b == 0:
            return 0.0
        return dot / (norm_a * norm_b)

    # Cap dedup pre-filter to avoid timing out on large docs — we only need
    # enough non-cached chunks to fill max_candidates batches of 3
    dedup_cap = min(len(chunks), max_candidates * 6)

    # Filter out chunks already cached (cosine >= 0.85 → distance < 0.15)
    skipped_ids = set()
    for chunk in chunks[:dedup_cap]:
        chunk_embedding = chunk.get("embedding")
        if not chunk_embedding:
            skipped_ids.add(chunk["id"])
            continue

        if isinstance(chunk_embedding, str):
            try:
                chunk_embedding = json.loads(chunk_embedding)
            except Exception:
                skipped_ids.add(chunk["id"])
                continue

        try:
            embedding_arg = chunk_embedding
            if isinstance(embedding_arg, list):
                embedding_arg = "[" + ",".join(str(x) for x in embedding_arg) + "]"
            rpc_resp = supabase.rpc(
                "search_validated_qa",
                {"q_embedding": embedding_arg, "match_count": 1},
            ).execute()
            if rpc_resp.data and rpc_resp.data[0].get("distance", 1.0) < 0.15:
                skipped_cached += 1
                skipped_ids.add(chunk["id"])
        except Exception as e:
            logger.warning(f"Cache dedup check failed for chunk {chunk.get('id')}: {e}")

    remaining_chunks = [c for c in chunks[:dedup_cap] if c["id"] not in skipped_ids]
    batches = [remaining_chunks[i : i + 3] for i in range(0, len(remaining_chunks), 3)]

    for batch in batches:
        if len(candidates) >= max_candidates:
            break

        batch_content = "\n\n---\n\n".join([c.get("content", "") for c in batch])
        batch_chunk_ids = [c["id"] for c in batch]
        source_pages = [c.get("page_number") for c in batch]
        source_page = source_pages[0] if source_pages and source_pages[0] else 1

        prompt = (
            "Given these manual excerpts, generate ONE practical question a "
            "maintenance technician would realistically ask, and a clear "
            "step-by-step answer grounded ONLY in the provided text. Never "
            "add information not present in the excerpts. Return JSON only — "
            'no preamble, no markdown:\n'
            '{"question": "...", "answer": "..."}\n\n'
            f"Manual excerpts:\n{batch_content[:2000]}"
        )

        try:
            (
                answer_text,
                provider_key,
                display_name,
                fallback_used,
                fallback_info,
            ) = await provider_generate(prompt, [])

            try:
                qa_data = json.loads(answer_text.strip())
                question = qa_data.get("question", "").strip()
                answer = qa_data.get("answer", "").strip()
            except json.JSONDecodeError:
                continue

            if not question or not answer:
                continue

            # Embed once, then check dedup against all previously generated
            question_embedding = await embed_single(question)
            is_dup = any(
                cosine_similarity(gen_emb, question_embedding) >= 0.85
                for gen_emb in generated_embeddings
            )
            if is_dup:
                continue

            generated_embeddings.append(question_embedding)
            candidates.append(
                {
                    "question": question,
                    "answer": answer,
                    "source_title": f"{manual_title} — Page {source_page}",
                    "source_chunk_ids": batch_chunk_ids,
                }
            )

        except Exception as e:
            logger.warning(f"Q&A generation failed for batch: {e}")
            continue

    if background_tasks:
        background_tasks.add_task(
            log_activity,
            user_email=user_email,
            category="manual_assistant",
            action="generated_qa_candidates",
            details={
                "manual_id": request.manual_id,
                "manual_title": manual_title,
                "total": len(candidates),
                "skipped_cached": skipped_cached,
            },
        )

    return {
        "candidates": candidates,
        "total": len(candidates),
        "skipped_cached": skipped_cached,
    }


@router.get("/manuals/real-usage-suggestions")
async def real_usage_suggestions(
    user_email: str = Query(...),
):
    try:
        _admin_check(user_email)
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})

    try:
        # Get positive ratings grouped by question+answer with count >= 2
        ratings_resp = (
            supabase.table("answer_ratings")
            .select("question_text, answer_text, created_at")
            .eq("rating", "positive")
            .execute()
        )

        if not ratings_resp.data:
            return {"suggestions": []}

        # Group by question+answer
        groups: dict = {}
        for r in ratings_resp.data:
            key = (r["question_text"], r["answer_text"])
            if key not in groups:
                groups[key] = {"count": 0, "last_asked_at": r["created_at"]}
            groups[key]["count"] += 1
            if r["created_at"] > groups[key]["last_asked_at"]:
                groups[key]["last_asked_at"] = r["created_at"]

        # Filter count >= 2
        filtered = [
            (q, a, g["count"], g["last_asked_at"])
            for (q, a), g in groups.items()
            if g["count"] >= 2
        ]

        # Sort by count descending, limit 50
        filtered.sort(key=lambda x: x[2], reverse=True)
        filtered = filtered[:50]

        # Exclude questions already in validated_qa (similarity >= 0.80)
        # Batch embed all questions for parallel processing
        questions_to_check = [(q, a, c, la) for q, a, c, la in filtered]
        
        async def check_not_cached(question: str, answer: str, count: int, last_asked: str):
            try:
                q_embedding = await embed_single(question)
                embedding_str = "[" + ",".join(str(x) for x in q_embedding) + "]"
                rpc_resp = supabase.rpc(
                    "search_validated_qa",
                    {"q_embedding": embedding_str, "match_count": 1},
                ).execute()
                if rpc_resp.data and rpc_resp.data[0].get("distance", 1.0) < 0.20:
                    return None  # Already cached
                return {"question": question, "answer": answer, "rating_count": count, "last_asked_at": last_asked}
            except Exception:
                return {"question": question, "answer": answer, "rating_count": count, "last_asked_at": last_asked}

        import asyncio
        results = await asyncio.gather(*[
            check_not_cached(q, a, c, la) for q, a, c, la in questions_to_check
        ])
        suggestions = [r for r in results if r is not None]

        return {"suggestions": suggestions}

    except HTTPException:
        raise
    except Exception as e:
        logger.warning(f"Failed to fetch usage suggestions: {e}")
        raise HTTPException(
            status_code=500, detail={"error": "fetch_failed"}
        )


class BulkDeleteRatingsRequest(BaseModel):
    question_text: str
    answer_text: str


@router.post("/manuals/ratings/bulk-delete")
async def bulk_delete_ratings(
    request: BulkDeleteRatingsRequest,
    user_email: str = Query(...),
):
    _admin_check(user_email)

    try:
        deleted = validated_qa_service.bulk_delete_ratings_by_qa(
            request.question_text, request.answer_text
        )

        try:
            log_activity(
                user_email,
                "manual",
                "admin_bulk_deleted_ratings",
                target_label=request.question_text[:80],
                detail=f"count={deleted}",
            )
        except Exception:
            pass

        return {"deleted_count": deleted}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500, detail={"error": "bulk_delete_failed", "message": str(e)}
        )


@router.get("/manuals/stale-cache-entries")
async def stale_cache_entries(
    user_email: str = Query(...),
):
    try:
        _admin_check(user_email)
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})

    try:
        # Query validated_qa with source_manual_id joined to manuals
        qa_resp = (
            supabase.table("validated_qa")
            .select("id, question_text, validated_answer, verified_at, source_manual_id")
            .not_.is_("source_manual_id", "null")
            .execute()
        )

        if not qa_resp.data:
            return {"stale_entries": [], "total": 0}

        # Get all referenced documents from knowledge_documents (live table)
        manual_ids = list(set(r["source_manual_id"] for r in qa_resp.data))
        manuals_resp = (
            supabase.table("knowledge_documents")
            .select("id, display_name, updated_at")
            .in_("id", manual_ids)
            .execute()
        )
        manuals_map = {m["id"]: m for m in (manuals_resp.data or [])}

        stale_entries = []


        for qa in qa_resp.data:
            manual = manuals_map.get(qa["source_manual_id"])
            if not manual or not manual.get("updated_at"):
                continue

            manual_updated = datetime.fromisoformat(
                manual["updated_at"].replace("Z", "+00:00")
            )
            verified = datetime.fromisoformat(
                qa["verified_at"].replace("Z", "+00:00")
            ) if qa.get("verified_at") else datetime.min.replace(tzinfo=timezone.utc)

            if manual_updated > verified:
                days = (datetime.now(timezone.utc) - manual_updated).days
                stale_entries.append(
                    {
                        "qa_id": qa["id"],
                        "question": qa["question_text"],
                        "answer": qa["validated_answer"],
                        "manual_title": manual.get("display_name", "Unknown"),
                        "manual_updated_at": manual["updated_at"],
                        "days_since_update": max(days, 0),
                    }
                )

        return {"stale_entries": stale_entries, "total": len(stale_entries)}

    except HTTPException:
        raise
    except Exception as e:
        logger.warning(f"Failed to fetch stale entries: {e}")
        raise HTTPException(
            status_code=500, detail={"error": "fetch_failed"}
        )


class MarkCacheReviewedRequest(BaseModel):
    qa_id: str
    action: str
    updated_question: Optional[str] = None
    updated_answer: Optional[str] = None


@router.post("/manuals/mark-cache-reviewed")
async def mark_cache_reviewed(
    request: MarkCacheReviewedRequest,
    user_email: str = Query(...),
    background_tasks: BackgroundTasks = None,
):
    try:
        _admin_check(user_email)
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})

    if request.action not in ("confirm", "delete"):
        raise HTTPException(
            status_code=400, detail={"error": "invalid_action"}
        )

    # Fetch the target entry
    qa_resp = (
        supabase.table("validated_qa")
        .select("id, rating_id")
        .eq("id", request.qa_id)
        .maybe_single()
        .execute()
    )
    if not qa_resp.data:
        raise HTTPException(
            status_code=404,
            detail={"error": "not_found", "message": "QA entry not found."},
        )

    target = qa_resp.data
    target_rating_id = target.get("rating_id")

    try:
        if request.action == "confirm":
            now_iso = datetime.now(timezone.utc).isoformat()
            update_data = {"verified_at": now_iso}

            # If question or answer updated, re-embed
            if request.updated_question:
                new_embedding = await embed_single(request.updated_question.strip())
                embedding_str = "[" + ",".join(str(x) for x in new_embedding) + "]"
                update_data["question_text"] = request.updated_question.strip()
                update_data["question_embedding"] = embedding_str
            if request.updated_answer:
                update_data["validated_answer"] = request.updated_answer.strip()

            supabase.table("validated_qa").update(update_data).eq(
                "id", request.qa_id
            ).execute()

            # Also update variants sharing same rating_id
            updated_count = 1
            if target_rating_id:
                variant_resp = (
                    supabase.table("validated_qa")
                    .update({"verified_at": now_iso})
                    .eq("rating_id", target_rating_id)
                    .neq("id", request.qa_id)
                    .execute()
                )
                updated_count += len(variant_resp.data or [])

            if background_tasks:
                background_tasks.add_task(
                    log_activity,
                    user_email=user_email,
                    category="manual_assistant",
                    action="reviewed_stale_entry",
                    details={"qa_id": request.qa_id, "action": "confirm"},
                )

            return {
                "status": "confirmed",
                "qa_id": request.qa_id,
                "verified_at": now_iso,
                "updated_count": updated_count,
            }

        else:  # delete
            # Delete primary + all variants sharing same rating_id
            deleted_count = 0

            supabase.table("validated_qa").delete().eq(
                "id", request.qa_id
            ).execute()
            deleted_count += 1

            if target_rating_id:
                variant_del = (
                    supabase.table("validated_qa")
                    .delete()
                    .eq("rating_id", target_rating_id)
                    .execute()
                )
                deleted_count += len(variant_del.data or [])

            if background_tasks:
                background_tasks.add_task(
                    log_activity,
                    user_email=user_email,
                    category="manual_assistant",
                    action="reviewed_stale_entry",
                    details={"qa_id": request.qa_id, "action": "delete"},
                )

            return {"status": "deleted", "deleted_count": deleted_count}

    except HTTPException:
        raise
    except EmbedderTimeoutError:
        raise HTTPException(
            status_code=504, detail={"error": "embedding_timeout"}
        )
    except Exception as e:
        logger.warning(f"Mark cache reviewed failed: {e}")
        raise HTTPException(
            status_code=500, detail={"error": "review_failed"}
        )


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

    manual_resp = (
        supabase.table("manuals")
        .select("title")
        .eq("id", manual_id)
        .maybe_single()
        .execute()
    )
    if not manual_resp.data:
        raise HTTPException(status_code=404, detail="Manual not found")

    title = manual_resp.data["title"]

    count_resp = (
        supabase.table("manual_chunks")
        .select("id", count="exact")
        .eq("manual_id", manual_id)
        .execute()
    )
    count = count_resp.count or 0

    async def re_embed_worker(mid: str, manual_title: str):
        chunks = (
            supabase.table("manual_chunks")
            .select("id, content")
            .eq("manual_id", mid)
            .order("chunk_index")
            .execute()
        )
        for chunk in chunks.data:
            try:
                prefixed = apply_contextual_prefix(
                    content=chunk["content"], doc_title=manual_title
                )
                embedding = await embed_single(prefixed)
                embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"
                supabase.table("manual_chunks").update({"embedding": embedding_str}).eq(
                    "id", chunk["id"]
                ).execute()
            except Exception as e:
                logger.warning(
                    "Re-embed failed for manual chunk %s: %s", chunk["id"], e
                )

    if background_tasks:
        background_tasks.add_task(re_embed_worker, manual_id, title)
    else:
        await re_embed_worker(manual_id, title)

    # Update manuals.updated_at for staleness detection (spec 080)
    supabase.table("manuals").update(
        {"updated_at": datetime.now(timezone.utc).isoformat()}
    ).eq("id", manual_id).execute()

    log_activity(
        user_email,
        "admin",
        "manual_re_embedded",
        target_label=title,
        target_id=manual_id,
    )

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
        title = _get_manual_title(manual_id)
        prefixed = apply_contextual_prefix(request.content, title)
        embedding = await embed_single(prefixed)
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
        title = _get_manual_title(manual_id)
        prefixed = apply_contextual_prefix(request.content, title)
        embedding = await embed_single(prefixed)
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
        title = _get_manual_title(manual_id)
        prefixed_a = apply_contextual_prefix(part_a, title)
        prefixed_b = apply_contextual_prefix(part_b, title)
        embeddings = await embed_many([prefixed_a, prefixed_b])
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
        title = _get_manual_title(manual_id)
        prefixed = apply_contextual_prefix(combined, title)
        embedding = await embed_single(prefixed)
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
