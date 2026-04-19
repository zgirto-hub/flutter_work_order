import logging
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from db import supabase

logger = logging.getLogger(__name__)

router = APIRouter()

REASON_CODES = [
    "grounded_answer",
    "verbatim_answer",
    "short_circuited_no_rag",
    "no_chunks_retrieved",
    "rerank_below_threshold",
    "generator_refused_with_chunks",
    "pipeline_error",
]

DECISIONS = ["grounded", "ungrounded", "error"]
SOURCES = ["user", "test_suite", "internal"]


def _admin_check(user_email: str):
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


@router.get("/admin/rag-diagnostics")
async def list_diagnostics(
    user_email: str = Query(...),
    source: Optional[str] = Query(None),
    decision: Optional[str] = Query(None),
    reason_code: Optional[str] = Query(None),
    from_ts: Optional[str] = Query(None, alias="from"),
    to_ts: Optional[str] = Query(None, alias="to"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    _admin_check(user_email)

    query = supabase.table("rag_diagnostic_log").select(
        "id,created_at,user_email,source,question_raw,decision,reason_code,reason_note,provider_used,latency_breakdown",
        count="exact",
    )

    if source:
        query = query.eq("source", source)
    if decision:
        query = query.eq("decision", decision)
    if reason_code:
        query = query.eq("reason_code", reason_code)

    if from_ts:
        query = query.gte("created_at", from_ts)
    else:
        default_from = datetime.now(timezone.utc).isoformat()
        query = query.gte("created_at", "2020-01-01T00:00:00Z")

    if to_ts:
        query = query.lte("created_at", to_ts)

    query = query.order("created_at", desc=True).range(offset, offset + limit - 1)

    try:
        response = query.execute()
    except Exception as e:
        logger.error("rag-diagnostics list query failed: %s", e)
        raise HTTPException(status_code=500, detail={"error": "query_failed"})

    entries = []
    for row in (response.data or []):
        entries.append({
            "id": row["id"],
            "created_at": row["created_at"],
            "user_email": row["user_email"],
            "source": row["source"],
            "question_raw": row["question_raw"],
            "decision": row["decision"],
            "reason_code": row["reason_code"],
            "reason_note": row.get("reason_note"),
            "provider_used": row.get("provider_used"),
            "latency_breakdown": row.get("latency_breakdown", {}),
        })

    total = response.count if response.count is not None else len(entries)

    return {
        "entries": entries,
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@router.get("/admin/rag-diagnostics/{entry_id}")
async def get_diagnostic(entry_id: str, user_email: str = Query(...)):
    _admin_check(user_email)

    try:
        response = (
            supabase.table("rag_diagnostic_log")
            .select("*")
            .eq("id", entry_id)
            .maybe_single()
            .execute()
        )
    except Exception as e:
        logger.error("rag-diagnostics detail query failed: %s", e)
        raise HTTPException(status_code=500, detail={"error": "query_failed"})

    if not response.data:
        raise HTTPException(status_code=404, detail={"error": "not_found"})

    return response.data