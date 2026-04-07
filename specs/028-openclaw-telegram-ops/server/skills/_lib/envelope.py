import sys
import json
import time
from typing import Dict, Optional


def read_envelope() -> Dict:
    try:
        content = sys.stdin.read().strip()
        if not content:
            return {}
        return json.loads(content)
    except json.JSONDecodeError as e:
        write_reply(
            status="error",
            reply="Failed to parse input envelope",
            action="unknown",
            args={},
            outcome="failure",
            started_at=time.monotonic(),
            error=str(e),
        )
        sys.exit(0)


def write_reply(
    status: str,
    reply: str,
    action: str,
    args: Dict,
    outcome: str,
    started_at: float,
    error: Optional[str] = None,
) -> None:
    valid_statuses = {"ok", "error", "needs_confirmation"}
    if status not in valid_statuses:
        raise ValueError(f"Invalid status: {status}. Must be one of {valid_statuses}")

    valid_outcomes = {
        "success",
        "failure",
        "confirmation_required",
        "confirmation_expired",
        "unauthorized",
    }
    if outcome not in valid_outcomes:
        raise ValueError(f"Invalid outcome: {outcome}. Must be one of {valid_outcomes}")

    duration_ms = int((time.monotonic() - started_at) * 1000)

    result = {
        "status": status,
        "reply": reply,
        "audit": {
            "action": action,
            "args": args,
            "outcome": outcome,
            "duration_ms": duration_ms,
        },
    }

    if error is not None:
        result["audit"]["error"] = error

    print(json.dumps(result, separators=(",", ":")))
    sys.stdout.flush()


def log_stderr(msg: str) -> None:
    print(msg, file=sys.stderr)
