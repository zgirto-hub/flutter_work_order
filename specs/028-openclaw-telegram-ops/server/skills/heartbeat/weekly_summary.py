#!/usr/bin/env python3
import sys
import time
from pathlib import Path
from datetime import datetime, timedelta, timezone

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "_lib"))

from wo_api import get_admin_email, api_get, iso_now
from envelope import write_reply, log_stderr


MAX_ITEMS = 20


def build_weekly(
    closed: list, open_count: int, pending_count: int, start_date: str, end_date: str
) -> str:
    lines = [
        f"📅 *Weekly Summary — {start_date} → {end_date}*",
        f"- Closed this week: {len(closed)}",
        f"- Currently open: {open_count}",
        f"- Currently pending: {pending_count}",
        "",
    ]

    if closed:
        lines.append("*Top closed:*")
        for wo in closed[:MAX_ITEMS]:
            job_no = wo.get("job_no", "N/A")
            title = wo.get("title", "Untitled")
            lines.append(f"- #{job_no} — {title}")

        if len(closed) > MAX_ITEMS:
            lines.append(f"\n…and {len(closed) - MAX_ITEMS} more")
    else:
        lines.append("*No work orders closed this week.*")

    return "\n".join(lines)


def main() -> None:
    started_at = time.monotonic()

    try:
        admin_email = get_admin_email()

        today = datetime.now().astimezone()
        end_date = today.strftime("%Y-%m-%d")
        start_date = (today - timedelta(days=7)).strftime("%Y-%m-%d")

        closed_data = api_get(
            "/reports/closed-work-orders",
            {
                "email": admin_email,
                "user_role": "admin",
                "start_date": start_date,
                "end_date": end_date,
            },
        )

        if isinstance(closed_data, dict) and "work_orders" in closed_data:
            closed = closed_data["work_orders"]
        elif isinstance(closed_data, list):
            closed = closed_data
        else:
            closed = []

        open_wos = api_get(
            "/work-orders",
            {"email": admin_email, "user_role": "admin", "status": "Open"},
        )
        open_count = len(open_wos) if isinstance(open_wos, list) else 0

        pending_wos = api_get(
            "/work-orders",
            {"email": admin_email, "user_role": "admin", "status": "Pending"},
        )
        pending_count = len(pending_wos) if isinstance(pending_wos, list) else 0

        message = build_weekly(closed, open_count, pending_count, start_date, end_date)

        write_reply(
            status="ok",
            reply=message,
            action="weekly_summary",
            args={},
            outcome="success",
            started_at=started_at,
        )

    except Exception as e:
        log_stderr(f"weekly_summary failed: {e}")
        write_reply(
            status="error",
            reply=f"Weekly summary failed: {str(e)}",
            action="weekly_summary",
            args={},
            outcome="failure",
            started_at=started_at,
            error=str(e),
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
