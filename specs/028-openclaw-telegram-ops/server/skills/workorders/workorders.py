#!/usr/bin/env python3
import sys
import time
from pathlib import Path
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Tuple, Optional, Union

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "_lib"))

from wo_api import (
    get_admin_email,
    get_api_base,
    api_get,
    api_post,
    api_put,
    iso_now,
    parse_iso,
)
from envelope import read_envelope, write_reply
from authz import assert_authorized


MAX_ITEMS = 20
OVERDUE_THRESHOLD_HOURS = 48


def handle_list(status: str) -> Tuple[str, str, str, Optional[str]]:
    admin_email = get_admin_email()
    try:
        params = {"email": admin_email, "user_role": "admin", "status": status}
        items = api_get("/work-orders", params)

        if not items:
            return ("ok", f"No {status.lower()} work orders.", "success", None)

        header = f"{status} work orders:"
        reply = format_wo_list(items, header)
        return ("ok", reply, "success", None)
    except Exception as e:
        return ("error", f"Failed to fetch {status} work orders", "failure", str(e))


def handle_list_overdue() -> Tuple[str, str, str, Optional[str]]:
    admin_email = get_admin_email()
    try:
        open_items = api_get(
            "/work-orders",
            {"email": admin_email, "user_role": "admin", "status": "Open"},
        )
        pending_items = api_get(
            "/work-orders",
            {"email": admin_email, "user_role": "admin", "status": "Pending"},
        )

        all_items = open_items + pending_items
        now = parse_iso(iso_now())

        overdue_items = []
        for wo in all_items:
            if "updated_at" in wo:
                updated = parse_iso(wo["updated_at"])
                if now - updated > timedelta(hours=OVERDUE_THRESHOLD_HOURS):
                    overdue_items.append(wo)

        if not overdue_items:
            return ("ok", "No overdue work orders.", "success", None)

        header = "*Overdue work orders (>48h, no status change)*"
        reply = format_wo_list(overdue_items, header)
        return ("ok", reply, "success", None)
    except Exception as e:
        return ("error", "Failed to fetch overdue work orders", "failure", str(e))


def handle_count(args: Dict) -> Tuple[str, str, str, Optional[str]]:
    status = args.get("status", "Open")
    admin_email = get_admin_email()

    try:
        params = {"email": admin_email, "user_role": "admin", "status": status}
        items = api_get("/work-orders", params)
        count = len(items) if isinstance(items, list) else 0

        reply = f"There are {count} {status} work orders."
        return ("ok", reply, "success", None)
    except Exception as e:
        return ("error", f"Failed to count {status} work orders", "failure", str(e))


def handle_get(args: Dict) -> Tuple[str, str, str, Optional[str]]:
    job_no = args.get("job_no")
    wo_id = args.get("id")
    admin_email = get_admin_email()

    try:
        if wo_id is not None:
            work_order = api_get(f"/work-orders/{wo_id}", None)
        elif job_no is not None:
            items = api_get(
                "/work-orders", {"email": admin_email, "user_role": "admin"}
            )
            work_order = None
            for wo in items:
                if str(wo.get("job_no")) == str(job_no):
                    work_order = wo
                    break

            if work_order is None:
                return ("error", f"Work order #{job_no} not found.", "failure", None)
        else:
            return ("error", "Either job_no or id required", "failure", None)

        title = work_order.get("title", "Untitled")
        status = work_order.get("status", "Unknown")
        assigned_to = work_order.get("assigned_to") or "unassigned"
        created = work_order.get("created_at", "Unknown")
        updated = work_order.get("updated_at", "Unknown")

        reply = f"""*Work Order #{job_no or wo_id}*
- **Title**: {title}
- **Status**: {status}
- **Assigned to**: {assigned_to}
- **Created**: {created}
- **Last updated**: {updated}"""

        return ("ok", reply, "success", None)
    except Exception as e:
        if "404" in str(e):
            return (
                "error",
                f"Work order #{job_no or wo_id} not found.",
                "failure",
                None,
            )
        return ("error", "Failed to get work order", "failure", str(e))


def resolve_id(job_no_or_id: Union[str, int]) -> Optional[int]:
    admin_email = get_admin_email()

    try:
        wo_id = int(job_no_or_id)
        return wo_id
    except (ValueError, TypeError):
        pass

    try:
        items = api_get("/work-orders", {"email": admin_email, "user_role": "admin"})
        for wo in items:
            if str(wo.get("job_no")) == str(job_no_or_id):
                return wo.get("id")
        return None
    except Exception:
        return None


def handle_close(args: Dict, confirmed: bool) -> Tuple[str, str, str, Optional[str]]:
    job_no = args.get("job_no")
    reason = args.get("reason", "")

    if not job_no:
        return ("error", "job_no is required", "failure", None)

    wo_id = resolve_id(job_no)
    if wo_id is None:
        return ("error", f"Work order #{job_no} not found.", "failure", None)

    if not confirmed:
        try:
            work_order = api_get(f"/work-orders/{wo_id}", None)
            title = work_order.get("title", "Untitled")
        except Exception:
            title = "Untitled"

        reply = (
            f'Close work order #{job_no} ({title})? Reply "yes" within 60s to confirm.'
        )
        return ("needs_confirmation", reply, "confirmation_required", None)

    admin_email = get_admin_email()

    try:
        api_post(
            f"/work-orders/{wo_id}/close",
            {"closed_by_email": admin_email, "reason": reason},
        )
        reply = f"✅ Work order #{job_no} closed."
        return ("ok", reply, "success", None)
    except Exception as e:
        return ("error", f"Failed to close work order #{job_no}", "failure", str(e))


def handle_update_status(
    args: Dict, confirmed: bool
) -> Tuple[str, str, str, Optional[str]]:
    job_no = args.get("job_no")
    new_status = args.get("new_status")

    if not job_no or not new_status:
        return ("error", "job_no and new_status are required", "failure", None)

    if new_status == "Closed":
        return ("error", "Use 'close' action to close a work order", "failure", None)

    valid_statuses = ["Open", "Pending", "In Progress"]
    if new_status not in valid_statuses:
        return (
            "error",
            f"Invalid status. Must be one of: {', '.join(valid_statuses)}",
            "failure",
            None,
        )

    wo_id = resolve_id(job_no)
    if wo_id is None:
        return ("error", f"Work order #{job_no} not found.", "failure", None)

    if not confirmed:
        try:
            work_order = api_get(f"/work-orders/{wo_id}", None)
            title = work_order.get("title", "Untitled")
        except Exception:
            title = "Untitled"

        reply = f'Update status of work order #{job_no} ({title}) to {new_status}? Reply "yes" within 60s to confirm.'
        return ("needs_confirmation", reply, "confirmation_required", None)

    admin_email = get_admin_email()

    try:
        api_put(
            f"/work-orders/{wo_id}",
            {"status": new_status, "updated_by_email": admin_email},
        )
        reply = f"Work order #{job_no} status updated to {new_status}."
        return ("ok", reply, "success", None)
    except Exception as e:
        return ("error", f"Failed to update work order #{job_no}", "failure", str(e))


def handle_summary(args: Dict) -> Tuple[str, str, str, Optional[str]]:
    start_date = args.get("start_date")
    end_date = args.get("end_date")

    if not start_date or not end_date:
        return ("error", "start_date and end_date are required", "failure", None)

    admin_email = get_admin_email()

    try:
        params = {
            "email": admin_email,
            "user_role": "admin",
            "start_date": start_date,
            "end_date": end_date,
        }
        closed_items = api_get("/reports/closed-work-orders", params)

        if isinstance(closed_items, dict) and "work_orders" in closed_items:
            closed_list = closed_items["work_orders"]
        elif isinstance(closed_items, list):
            closed_list = closed_items
        else:
            closed_list = []

        count = len(closed_list)

        if count == 0:
            reply = f"No work orders closed between {start_date} and {end_date}."
        else:
            header = f"Work orders closed ({start_date} → {end_date}): {count}"
            reply = format_wo_list(closed_list[:MAX_ITEMS], header)

            if count > MAX_ITEMS:
                reply += f"\n…and {count - MAX_ITEMS} more"

        return ("ok", reply, "success", None)
    except Exception as e:
        return ("error", "Failed to get closed work orders summary", "failure", str(e))


def format_wo_list(items: List[Dict], header: str) -> str:
    display_items = items[:MAX_ITEMS]
    lines = [header, ""]

    for wo in display_items:
        job_no = wo.get("job_no", "N/A")
        title = wo.get("title", "Untitled")
        assigned = wo.get("assigned_to") or "unassigned"
        lines.append(f"- #{job_no} — {title} ({assigned})")

    if len(items) > MAX_ITEMS:
        lines.append(f"\n…and {len(items) - MAX_ITEMS} more")

    return "\n".join(lines)


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
    confirmed = envelope.get("confirmed", False)

    status, reply, outcome, error = "error", "", "failure", None

    try:
        if action == "list_open":
            status, reply, outcome, error = handle_list("Open")
        elif action == "list_pending":
            status, reply, outcome, error = handle_list("Pending")
        elif action == "list_overdue":
            status, reply, outcome, error = handle_list_overdue()
        elif action == "count":
            status, reply, outcome, error = handle_count(args)
        elif action == "get":
            status, reply, outcome, error = handle_get(args)
        elif action == "close":
            status, reply, outcome, error = handle_close(args, confirmed)
        elif action == "update_status":
            status, reply, outcome, error = handle_update_status(args, confirmed)
        elif action == "summary_closed_in_range":
            status, reply, outcome, error = handle_summary(args)
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
