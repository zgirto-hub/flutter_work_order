#!/usr/bin/env python3
import sys
import time
from pathlib import Path
from datetime import datetime, timedelta, timezone

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "_lib"))

from wo_api import get_admin_email, api_get, iso_now, parse_iso
from envelope import write_reply, log_stderr


MAX_ITEMS = 20
OVERDUE_THRESHOLD_HOURS = 48


def filter_stale(wos: list, threshold_hours: int = 48) -> list:
    now = parse_iso(iso_now())
    stale = []

    for wo in wos:
        if "updated_at" in wo:
            updated = parse_iso(wo["updated_at"])
            if now - updated > timedelta(hours=threshold_hours):
                stale.append(wo)

    return stale


def compute_age(updated_at: str) -> str:
    try:
        updated = parse_iso(updated_at)
        now = parse_iso(iso_now())
        delta = now - updated

        hours = int(delta.total_seconds() / 3600)
        if hours >= 24:
            days = hours // 24
            return f"{days}d ago"
        else:
            return f"{hours}h ago"
    except Exception:
        return "unknown"


def build_digest(open_wos: list, pending_wos: list, now_iso: str) -> str:
    open_count = len(open_wos)
    pending_count = len(pending_wos)

    all_wos = open_wos + pending_wos
    overdue = filter_stale(all_wos, OVERDUE_THRESHOLD_HOURS)
    stale_open = filter_stale(open_wos, OVERDUE_THRESHOLD_HOURS)

    today = datetime.now().astimezone().strftime("%Y-%m-%d")

    lines = [
        f"🌅 *Daily Work Order Digest — {today}*",
        f"- Open: {open_count}",
        f"- Pending: {pending_count}",
        f"- Overdue (>48h, no change): {len(overdue)}",
        "",
    ]

    if stale_open:
        lines.append("⚠️ *Stale (open >48h):*")
        for wo in stale_open[:MAX_ITEMS]:
            job_no = wo.get("job_no", "N/A")
            title = wo.get("title", "Untitled")
            age = compute_age(wo.get("updated_at", ""))
            lines.append(f"- #{job_no} — {title} (last update {age})")

        if len(stale_open) > MAX_ITEMS:
            lines.append(f"\n…and {len(stale_open) - MAX_ITEMS} more")

    return "\n".join(lines)


def main() -> None:
    started_at = time.monotonic()

    try:
        admin_email = get_admin_email()

        open_wos = api_get(
            "/work-orders",
            {"email": admin_email, "user_role": "admin", "status": "Open"},
        )

        pending_wos = api_get(
            "/work-orders",
            {"email": admin_email, "user_role": "admin", "status": "Pending"},
        )

        now_iso = iso_now()
        message = build_digest(open_wos, pending_wos, now_iso)

        write_reply(
            status="ok",
            reply=message,
            action="daily_digest",
            args={},
            outcome="success",
            started_at=started_at,
        )

    except Exception as e:
        log_stderr(f"daily_digest failed: {e}")
        write_reply(
            status="error",
            reply=f"Daily digest failed: {str(e)}",
            action="daily_digest",
            args={},
            outcome="failure",
            started_at=started_at,
            error=str(e),
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
