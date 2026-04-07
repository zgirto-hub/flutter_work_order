#!/usr/bin/env python3
import sys
import time
from pathlib import Path
from datetime import datetime, timezone, timedelta
from typing import List, Dict

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "_lib"))

from wo_api import api_get, iso_now
from envelope import write_reply, log_stderr


def build_failure_message(failures: List[Dict]) -> str:
    lines = [
        "🔔 *Push delivery failure alert*",
        f"{len(failures)} notification(s) failed to deliver in the last hour.",
        "",
        "Affected:",
    ]

    for failure in failures:
        notif_id = failure.get("notification_id", "unknown")
        error_msg = failure.get("error_message", "Unknown error")
        lines.append(f"- {notif_id}: {error_msg}")

    return "\n".join(lines)


def main() -> None:
    started_at = time.monotonic()

    try:
        one_hour_ago = datetime.now().astimezone() - timedelta(hours=1)
        since_iso = one_hour_ago.isoformat()

        try:
            failures = api_get("/notifications/delivery-failures", {"since": since_iso})

            if isinstance(failures, dict) and "failures" in failures:
                failures_list = failures["failures"]
            elif isinstance(failures, list):
                failures_list = failures
            else:
                failures_list = []

            if not failures_list:
                write_reply(
                    status="ok",
                    reply="",
                    action="push_failure_check",
                    args={"since": since_iso},
                    outcome="success",
                    started_at=started_at,
                )
            else:
                message = build_failure_message(failures_list)
                write_reply(
                    status="ok",
                    reply=message,
                    action="push_failure_check",
                    args={"since": since_iso, "failure_count": len(failures_list)},
                    outcome="success",
                    started_at=started_at,
                )

        except Exception as e:
            error_str = str(e)
            if hasattr(e, "code") and e.code in (404, 501):
                log_stderr(
                    f"push_failure_check: endpoint not available (HTTP {e.code}), exiting gracefully"
                )
                write_reply(
                    status="ok",
                    reply="",
                    action="push_failure_check",
                    args={},
                    outcome="success",
                    started_at=started_at,
                )
            else:
                raise

    except Exception as e:
        log_stderr(f"push_failure_check failed: {e}")
        write_reply(
            status="error",
            reply=f"Push failure check failed: {str(e)}",
            action="push_failure_check",
            args={},
            outcome="failure",
            started_at=started_at,
            error=str(e),
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
