#!/usr/bin/env python3
import sys
import time
import re
from pathlib import Path
from datetime import datetime, timezone, timedelta
from typing import Dict, Tuple, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "_lib"))

from wo_api import get_admin_email, get_api_base, api_get, api_post
from envelope import read_envelope, write_reply
from authz import assert_authorized


EMAIL_REGEX = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def validate_email(addr: str) -> bool:
    return bool(EMAIL_REGEX.match(addr))


def resolve_id(job_no: str) -> Optional[int]:
    admin_email = get_admin_email()

    try:
        items = api_get("/work-orders", {"email": admin_email, "user_role": "admin"})
        for wo in items:
            if str(wo.get("job_no")) == str(job_no):
                return wo.get("id")
        return None
    except Exception:
        return None


def handle_send_work_order_pdf(args: Dict) -> Tuple[str, str, str, Optional[str]]:
    job_no = args.get("job_no")
    to = args.get("to")
    cc = args.get("cc", [])
    subject = args.get("subject")

    if not job_no:
        return ("error", "job_no is required", "failure", None)

    if not to:
        return ("error", "to email is required", "failure", None)

    if not validate_email(to):
        return ("error", f"Invalid email address: {to}", "failure", None)

    wo_id = resolve_id(job_no)
    if wo_id is None:
        return ("error", f"Work order #{job_no} not found.", "failure", None)

    admin_email = get_admin_email()

    try:
        body = {"to": [to], "cc": cc, "from_email": admin_email}
        if subject:
            body["subject"] = subject

        try:
            api_post(f"/work-orders/{wo_id}/email", body)
        except Exception as e:
            if hasattr(e, "code") and e.code in (404, 501):
                return ("error", "Email backend not available yet.", "failure", None)
            raise

        reply = f"📧 Sent work order #{job_no} PDF to {to}."
        return ("ok", reply, "success", None)

    except Exception as e:
        if hasattr(e, "code") and e.code in (404, 501):
            return ("error", "Email backend not available yet.", "failure", None)
        return ("error", f"Failed to send email: {str(e)}", "failure", str(e))


def handle_send_weekly_summary(args: Dict) -> Tuple[str, str, str, Optional[str]]:
    to = args.get("to")
    admin_email = get_admin_email()

    if not to:
        to = admin_email

    if not validate_email(to):
        return ("error", f"Invalid email address: {to}", "failure", None)

    today = datetime.now().astimezone()
    end_date = today.strftime("%Y-%m-%d")
    start_date = (today - timedelta(days=7)).strftime("%Y-%m-%d")

    try:
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

        summary_lines = [
            f"📅 *Weekly Summary — {start_date} → {end_date}*",
            f"- Closed this week: {len(closed)}",
            f"- Currently open: {open_count}",
            f"- Currently pending: {pending_count}",
            "",
        ]

        if closed:
            summary_lines.append("*Top closed:*")
            for wo in closed[:10]:
                job_no = wo.get("job_no", "N/A")
                title = wo.get("title", "Untitled")
                summary_lines.append(f"- #{job_no} — {title}")

        summary_body = "\n".join(summary_lines)

        try:
            api_post(
                "/email/send",
                {
                    "to": [to],
                    "from_email": admin_email,
                    "subject": f"Weekly Work Order Summary — {start_date} → {end_date}",
                    "body": summary_body,
                },
            )
        except Exception as e:
            if hasattr(e, "code") and e.code in (404, 501):
                return ("error", "Email backend not available yet.", "failure", None)
            raise

        reply = f"📧 Weekly summary emailed to {to}."
        return ("ok", reply, "success", None)

    except Exception as e:
        if hasattr(e, "code") and e.code in (404, 501):
            return ("error", "Email backend not available yet.", "failure", None)
        return ("error", f"Failed to send weekly summary: {str(e)}", "failure", str(e))


def main() -> None:
    started_at = time.monotonic()

    try:
        caller_id = assert_authorized()
    except PermissionError as e:
        write_reply(
            status="error",
            reply="Unauthorized caller",
            action="unknown",
            args={},
            outcome="unauthorized",
            started_at=started_at,
            error=str(e),
        )
        sys.exit(0)

    envelope = read_envelope()

    action = envelope.get("action", "")
    args = envelope.get("args", {})

    status, reply, outcome, error = "error", "", "failure", None

    try:
        if action == "send_work_order_pdf":
            status, reply, outcome, error = handle_send_work_order_pdf(args)
        elif action == "send_weekly_summary":
            status, reply, outcome, error = handle_send_weekly_summary(args)
        else:
            status = "error"
            reply = f"Unknown action: {action}"
            outcome = "failure"
            error = f"Action '{action}' not recognized"
    except Exception as e:
        status = "error"
        reply = f"An error occurred: {str(e)}"
        outcome = "failure"
        error = str(e)

    write_reply(
        status=status,
        reply=reply,
        action=action,
        args=args,
        outcome=outcome,
        started_at=started_at,
        error=error,
    )

    sys.exit(0)


if __name__ == "__main__":
    main()
