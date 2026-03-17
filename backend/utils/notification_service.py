from datetime import datetime, timedelta
from typing import Dict, List, Optional, Set

from db import supabase
from utils.notifications import send_push_to_external_ids


DEFAULT_PREFS = {
    "push_enabled": True,
    "in_app_enabled": True,
    "mute_all": False,
    "comment_notifications": True,
    "status_notifications": True,
    "system_notifications": True,
}


def _norm(email: str) -> str:
    return (email or "").strip().lower()


def _is_valid(email: str) -> bool:
    return "@" in email and "." in email


def _get_preferences(emails: List[str]) -> Dict[str, dict]:
    clean = sorted({_norm(e) for e in emails if _is_valid(_norm(e))})
    if not clean:
        return {}
    res = supabase.table("notification_preferences") \
        .select("*") \
        .in_("user_email", clean) \
        .execute()
    by_email = {_norm(r.get("user_email", "")): r for r in (res.data or [])}
    return by_email


def _prefs_allow(row: dict, event_type: str) -> bool:
    if row.get("mute_all"):
        return False
    if event_type == "comment":
        return row.get("comment_notifications", True)
    if event_type == "status_change":
        return row.get("status_notifications", True)
    return row.get("system_notifications", True)


def _resolve_assigned_emails(work_order_id: str) -> Set[str]:
    out: Set[str] = set()

    assignments = supabase.table("work_order_assignments") \
        .select("employee_id") \
        .eq("work_order_id", work_order_id) \
        .execute()
    emp_ids = [r.get("employee_id") for r in (assignments.data or []) if r.get("employee_id")]
    if not emp_ids:
        return out

    employees = supabase.table("employees") \
        .select("id, profile_id") \
        .in_("id", emp_ids) \
        .execute()

    profile_ids = [r.get("profile_id") for r in (employees.data or []) if r.get("profile_id")]
    if not profile_ids:
        return out

    # profile_id maps to auth user id in this project
    for pid in profile_ids:
        try:
            user_resp = supabase.auth.admin.get_user_by_id(str(pid))
            user_obj = getattr(user_resp, "user", None)
            if user_obj is None and isinstance(user_resp, dict):
                user_obj = user_resp.get("user")
            email = None
            if isinstance(user_obj, dict):
                email = user_obj.get("email")
            else:
                email = getattr(user_obj, "email", None)
            n = _norm(email or "")
            if _is_valid(n):
                out.add(n)
        except Exception:
            continue

    return out


def _resolve_watcher_emails(work_order_id: str) -> Set[str]:
    res = supabase.table("work_order_watchers") \
        .select("user_email") \
        .eq("work_order_id", work_order_id) \
        .execute()
    return {_norm(r.get("user_email", "")) for r in (res.data or []) if _is_valid(_norm(r.get("user_email", "")))}


def resolve_comment_recipients(work_order_id: str, commenter_email: str) -> dict:
    try:
        commenter = _norm(commenter_email)

        wo_res = supabase.table("work_orders") \
            .select("id, job_no, title, request_id, created_by_email") \
            .eq("id", work_order_id) \
            .limit(1) \
            .execute()
        if not wo_res.data:
            return {"job_no": "", "title": "", "recipients": set(), "debug": {"error": "work_order_not_found"}}

        wo = wo_res.data[0]
        recipients: Set[str] = set()
        sources = {
            "creator": [],
            "requester": [],
            "assignees": [],
            "watchers": [],
        }

        creator_email = _norm(wo.get("created_by_email") or "")
        if _is_valid(creator_email):
            recipients.add(creator_email)
            sources["creator"].append(creator_email)

        request_id = wo.get("request_id")
        if request_id:
            try:
                req_res = supabase.table("requests") \
                    .select("created_by") \
                    .eq("id", request_id) \
                    .limit(1) \
                    .execute()
                if req_res.data:
                    requester = _norm(req_res.data[0].get("created_by") or "")
                    if _is_valid(requester):
                        recipients.add(requester)
                        sources["requester"].append(requester)
            except Exception as e:
                print(f"Notification recipient resolve (requester) failed: {e}")

        try:
            assignees = _resolve_assigned_emails(work_order_id)
            recipients |= assignees
            sources["assignees"] = sorted(assignees)
        except Exception as e:
            print(f"Notification recipient resolve (assignees) failed: {e}")

        try:
            watchers = _resolve_watcher_emails(work_order_id)
            recipients |= watchers
            sources["watchers"] = sorted(watchers)
        except Exception as e:
            print(f"Notification recipient resolve (watchers) failed: {e}")

        before_exclusion = sorted(recipients)
        if _is_valid(commenter):
            recipients.discard(commenter)

        return {
            "job_no": wo.get("job_no") or "",
            "title": wo.get("title") or "",
            "recipients": recipients,
            "debug": {
                "sources": sources,
                "before_exclusion": before_exclusion,
                "commenter": commenter,
                "after_exclusion": sorted(recipients),
            },
        }
    except Exception as e:
        print(f"Notification recipient resolve (fatal) failed: {e}")
        return {
            "job_no": "",
            "title": "",
            "recipients": set(),
            "debug": {"error": str(e)},
        }


def _insert_notifications(
    *,
    recipients: List[str],
    kind: str,
    title: str,
    body: str,
    source_type: str,
    source_id: str,
    data: Optional[dict] = None,
) -> List[dict]:
    if not recipients:
        return []
    rows = [{
        "user_email": _norm(email),
        "kind": kind,
        "title": title,
        "body": body,
        "data": data or {},
        "source_type": source_type,
        "source_id": source_id,
    } for email in recipients]
    res = supabase.table("notifications").insert(rows).execute()
    return res.data or []


def _log_delivery(
    *,
    notification_id: Optional[str],
    recipient: str,
    status: str,
    provider: str = "onesignal",
    channel: str = "push",
    provider_message_id: Optional[str] = None,
    error: Optional[str] = None,
    attempt: int = 1,
):
    next_retry = None
    if status == "failed" and attempt < 5:
        next_retry = (datetime.utcnow() + timedelta(minutes=2 ** attempt)).isoformat()

    supabase.table("notification_delivery_logs").insert({
        "notification_id": notification_id,
        "channel": channel,
        "provider": provider,
        "recipient": _norm(recipient),
        "status": status,
        "provider_message_id": provider_message_id,
        "error": error,
        "attempt": attempt,
        "next_retry_at": next_retry,
    }).execute()


def dispatch_work_order_comment_notification(
    *,
    work_order_id: str,
    comment_id: str,
    comment_text: str,
    author_email: str,
    author_name: str,
):
    resolved = resolve_comment_recipients(work_order_id, author_email)
    recipients = sorted(resolved["recipients"])
    if not recipients:
        return

    prefs_map = _get_preferences(recipients)

    in_app_recipients: List[str] = []
    push_recipients: List[str] = []

    for email in recipients:
        pref = DEFAULT_PREFS.copy()
        pref.update(prefs_map.get(email, {}))
        if not _prefs_allow(pref, "comment"):
            continue
        if pref.get("in_app_enabled", True):
            in_app_recipients.append(email)
        if pref.get("push_enabled", True):
            push_recipients.append(email)

    snippet = (comment_text or "").strip()
    if len(snippet) > 90:
        snippet = f"{snippet[:87]}..."

    title = "Work Order Update"
    body = f"{author_name} commented on {resolved['job_no'] or 'work order'}: {snippet}"
    payload = {
        "type": "work_order_comment",
        "work_order_id": work_order_id,
        "comment_id": comment_id,
        "job_no": resolved.get("job_no") or "",
    }

    notification_id_by_email = {}
    if in_app_recipients:
        try:
            inserted = _insert_notifications(
                recipients=in_app_recipients,
                kind="work_order_comment",
                title=title,
                body=body,
                source_type="work_order_comment",
                source_id=comment_id,
                data=payload,
            )
            notification_id_by_email = {
                _norm(r.get("user_email") or ""): r.get("id") for r in inserted
            }
        except Exception as e:
            print(f"Notification insert failed: {e}")

    if push_recipients:
        push_result = send_push_to_external_ids(
            title=title,
            body=body,
            external_ids=push_recipients,
            data=payload,
        )
        message_id = None
        status = "sent"
        error = None

        if isinstance(push_result, dict):
            message_id = push_result.get("id")
            if push_result.get("error"):
                status = "failed"
                error = str(push_result.get("error"))

        for email in push_recipients:
            _log_delivery(
                notification_id=notification_id_by_email.get(_norm(email)),
                recipient=email,
                status=status,
                provider_message_id=message_id,
                error=error,
            )
