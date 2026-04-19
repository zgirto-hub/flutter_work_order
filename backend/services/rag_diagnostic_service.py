import asyncio
import sys
import uuid
from collections import deque
from datetime import datetime, timezone
from typing import Optional

from db import supabase

_WRITE_FAILURE_WINDOW_SECONDS = 3600
_write_failure_timestamps: deque = deque()
_last_successful_write_at: Optional[datetime] = None


_SENTINEL_PHRASES = (
    "i don't have that information in the knowledge base",
    "this information is not in the available manuals",
    "\u0627\u0644\u0645\u0639\u0644\u0648\u0645\u0627\u062a \u0627\u0644\u0645\u0637\u0644\u0648\u0628\u0629 \u063a\u064a\u0631 \u0645\u0648\u062c\u0648\u062f\u0629 \u0641\u064a \u0627\u0644\u0623\u062f\u0644\u0629 \u0627\u0644\u0645\u062a\u0627\u062d\u0629",
)


def classify_reason_code(
    diagnostic: dict,
    answer: Optional[str],
    grounded: bool,
) -> tuple[str, str, str]:
    if not grounded:
        if answer is None or (isinstance(answer, str) and answer.strip() == ""):
            return ("error", "pipeline_error", "Pipeline raised an exception or produced no answer")

        retrieval = diagnostic.get("retrieval", {})
        candidates = retrieval.get("candidates") if isinstance(retrieval, dict) else None

        if candidates is not None and len(candidates) == 0:
            return ("ungrounded", "no_chunks_retrieved", "Hybrid search returned zero candidates")

        rerank = diagnostic.get("rerank", {})
        top_score = rerank.get("top_score") if isinstance(rerank, dict) else None
        threshold = rerank.get("threshold_applied") if isinstance(rerank, dict) else None
        if top_score is not None and threshold is not None and top_score < threshold:
            return (
                "ungrounded",
                "rerank_below_threshold",
                f"Top rerank score {top_score:.2f} below threshold {threshold:.2f}",
            )

        answer_lower = answer.strip().lower()
        sentinel_detected = diagnostic.get("grounding", {}).get("sentinel_phrase_detected", False)
        if sentinel_detected or any(p in answer_lower for p in _SENTINEL_PHRASES):
            if candidates is not None and len(candidates) > 0:
                note = f"Generator refused despite {len(candidates)} candidate(s)"
                if top_score is not None:
                    note += f"; top rerank={top_score}"
                return ("ungrounded", "generator_refused_with_chunks", note)
            return ("ungrounded", "generator_refused_with_chunks", "Generator refused with no retrieved chunks")

        return ("ungrounded", "generator_refused_with_chunks", "Ungrounded but no single refusal trigger identified")

    if diagnostic.get("grounding", {}).get("verbatim_match"):
        return ("grounded", "verbatim_answer", "Validated-QA verbatim path matched")

    if diagnostic.get("rewrite") is None and diagnostic.get("hyde") is None and diagnostic.get("retrieval") is None:
        return ("grounded", "short_circuited_no_rag", "Trivial input or greeting bypass")

    return ("grounded", "grounded_answer", "Pipeline produced a grounded answer")


async def persist_entry(entry_payload: dict) -> None:
    global _last_successful_write_at, _write_failure_timestamps
    try:
        supabase.table("rag_diagnostic_log").insert(entry_payload).execute()
        _last_successful_write_at = datetime.now(timezone.utc)
    except Exception as e:
        now = time.time()
        cutoff = now - _WRITE_FAILURE_WINDOW_SECONDS
        while _write_failure_timestamps and _write_failure_timestamps[0] < cutoff:
            _write_failure_timestamps.popleft()
        _write_failure_timestamps.append(now)
        print(f"[rag_diagnostic] Failed to persist entry: {e}", file=sys.stderr)


def get_failure_stats() -> dict:
    global _write_failure_timestamps, _last_successful_write_at
    now = time.time()
    cutoff = now - _WRITE_FAILURE_WINDOW_SECONDS
    while _write_failure_timestamps and _write_failure_timestamps[0] < cutoff:
        _write_failure_timestamps.popleft()
    return {
        "in_process_write_failures_last_hour": len(_write_failure_timestamps),
        "last_successful_write_at": _last_successful_write_at.isoformat() if _last_successful_write_at else None,
    }


import time


def schedule_persist(
    diagnostic: dict,
    answer: Optional[str],
    grounded: bool,
    user_email: str,
    source: str,
    question_raw: str,
    latency_breakdown: dict,
    provider_used: Optional[str] = None,
) -> None:
    decision, reason_code, reason_note = classify_reason_code(diagnostic, answer, grounded)
    entry_id = str(uuid.uuid4())
    entry = {
        "id": entry_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "user_email": user_email,
        "source": source,
        "question_raw": question_raw,
        "decision": decision,
        "reason_code": reason_code,
        "reason_note": reason_note,
        "pipeline_stages": diagnostic,
        "thresholds": {
            "max_chunk_distance": 0.55,
            "verbatim_match_min": 0.85,
        },
        "latency_breakdown": latency_breakdown,
        "provider_used": provider_used,
    }
    asyncio.create_task(persist_entry(entry))

    from utils.activity import log_activity
    try:
        log_activity(
            user_email=user_email,
            category="manual",
            action="rag_diagnostic_logged",
            target_id=entry_id,
        )
    except Exception:
        pass