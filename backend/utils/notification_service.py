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
    "admin_all_workorder_comments": False,
}


def _norm(email: str) -> str:
    return (email or "").strip().lower()


def _is_valid(email: str) -> bool:
    return "@" in email and "." in email


def _get_user_id_by_email(email: str) -> Optional[str]:
    """Get user UUID by email"""
    normalized = _norm(email)
    res = supabase.table("users").select("id").eq("email", normalized).limit(1).execute()
    return res.data[0].get("id") if res.data else None


def _get_user_id_and_email(email: str) -> tuple:
    """Get user UUID and email by email"""
    normalized = _norm(email)
    res = supabase.table("users").select("id, email").eq("email", normalized).limit(1).execute()
    if res.data:
        return res.data[0].get("id"), normalized
    return None, normalized


def _get_preferences(user_ids: List[str]) -> Dict[str, dict]:
    """Get preferences by user_id list"""
    if not user_ids:
        return {}
    res = supabase.table("notification_preferences") \
        .select("*") \
        .in_("user_id", user_ids) \
        .execute()
    by_user_id = {r.get("user_id", ""): r for r in (res.data or [])}
    return by_user_id


def _get_prefs_by_emails(emails: List[str]) -> Dict[str, dict]:
    """Get preferences by email list (resolves to user_id internally)"""
    clean = sorted({_norm(e) for e in emails if _is_valid(_norm(e))})
    if not clean:
        return {}
    
    users_res = supabase.table("users").select("id, email").in_("email", clean).execute()
    users_by_email = {_norm(u.get("email", "")): u.get("id") for u in (users_res.data or [])}
    
    user_ids = [uid for uid in users_by_email.values() if uid]
    if not user_ids:
        return {}
    
    prefs_res = supabase.table("notification_preferences") \
        .select("*") \
        .in_("user_id", user_ids) \
        .execute()
    
    by_email = {}
    for pref in (prefs_res.data or []):
        pref_user_id = pref.get("user_id", "")
        for email, uid in users_by_email.items():
            if uid == pref_user_id:
                by_email[email] = pref
                break
    return by_email


def _resolve_admin_opt_in_emails() -> Set[str]:
    """Get emails of admins who have opted into all work order comments"""
    admins_res = supabase.table("users") \
        .select("id, email") \
        .eq("user_type", "admin") \
        .eq("is_active", True) \
        .execute()
    
    admin_ids = [r.get("id") for r in (admins_res.data or []) if r.get("id")]
    admin_emails = {_norm(r.get("email", "")): r.get("id") for r in (admins_res.data or []) if _is_valid(_norm(r.get("email", "")))}
    
    if not admin_ids:
        return set()

    prefs_res = supabase.table("notification_preferences") \
        .select("user_id") \
        .eq("admin_all_workorder_comments", True) \
        .in_("user_id", admin_ids) \
        .execute()
    
    opted_in_ids = {r.get("user_id") for r in (prefs_res.data or [])}
    
    return {
        email for email, uid in admin_emails.items()
        if uid in opted_in_ids and _is_valid(email)
    }


def _prefs_allow(row: dict, event_type: str) -> bool:
    if row.get("mute_all"):
        return False
    if event_type == "comment":
        return row.get("comment_notifications", True)
    if event_type == "status_change":
        return row.get("status_notifications", True)
    return row.get("system_notifications", True)


def _resolve_assigned_fixers(work_order_id: str) -> Set[str]:
    """Get emails of assigned fixers for a work order"""
    out: Set[str] = set()

    assignments = supabase.table("work_order_assignments") \
        .select("fixer_id") \
        .eq("work_order_id", work_order_id) \
        .execute()
    fixer_ids = [r.get("fixer_id") for r in (assignments.data or []) if r.get("fixer_id")]
    if not fixer_ids:
        return out

    users = supabase.table("users") \
        .select("email") \
        .in_("id", fixer_ids) \
        .execute()

    for r in (users.data or []):
        email = _norm(r.get("email") or "")
        if _is_valid(email):
            out.add(email)

    return out


def _resolve_user_id_to_email(user_id: str) -> str:
    uid = (user_id or "").strip()
    if not uid:
        return ""
    if "@" in uid:
        return _norm(uid)
    
    user_res = supabase.table("users") \
        .select("email") \
        .eq("id", uid) \
        .single() \
        .execute()
    if user_res.data:
        return _norm(user_res.data.get("email") or "")
    
    return ""


def _resolve_watchers(work_order_id: str) -> List[tuple]:
    """Get list of (user_id, user_email) for watchers"""
    res = supabase.table("work_order_watchers") \
        .select("user_id, user_email") \
        .eq("work_order_id", work_order_id) \
        .execute()
    return [(r.get("user_id"), _norm(r.get("user_email", ""))) for r in (res.data or []) if r.get("user_id")]


def resolve_comment_recipients(work_order_id: str, commenter_email: str) -> dict:
    try:
        commenter = _norm(commenter_email)

        wo_res = supabase.table("work_orders") \
            .select("id, job_no, title, created_by") \
            .eq("id", work_order_id) \
            .limit(1) \
            .execute()
        if not wo_res.data:
            return {"job_no": "", "title": "", "recipients": set(), "debug": {"error": "work_order_not_found"}}

        wo = wo_res.data[0]
        recipients: Set[str] = set()
        sources = {
            "creator": [],
            "assignees": [],
            "watchers": [],
        }

        creator_email = _resolve_user_id_to_email(wo.get("created_by") or "")
        if _is_valid(creator_email):
            recipients.add(creator_email)
            sources["creator"].append(creator_email)

        try:
            assignees = _resolve_assigned_fixers(work_order_id)
            recipients |= assignees
            sources["assignees"] = sorted(assignees)
        except Exception as e:
            print(f"Notification recipient resolve (assignees) failed: {e}")

        try:
            watchers = _resolve_watchers(work_order_id)
            watcher_emails = [email for _, email in watchers if _is_valid(email)]
            recipients |= set(watcher_emails)
            sources["watchers"] = sorted(watcher_emails)
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
    recipients: List[tuple],
    kind: str,
    title: str,
    body: str,
    source_type: str,
    source_id: str,
    data: Optional[dict] = None,
) -> List[dict]:
    """Insert notifications. recipients is list of (user_id, user_email) tuples"""
    if not recipients:
        return []
    rows = [{
        "user_id": user_id,
        "user_email": _norm(email),
        "kind": kind,
        "title": title,
        "body": body,
        "data": data or {},
        "source_type": source_type,
        "source_id": source_id,
    } for user_id, email in recipients if user_id]
    if not rows:
        return []
    res = supabase.table("notifications").insert(rows).execute()
    return res.data or []


def _log_delivery(
    *,
    notification_id: Optional[str],
    user_id: Optional[str],
    user_email: str,
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
        "user_id": user_id,
        "user_email": _norm(user_email),
        "channel": channel,
        "provider": provider,
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
    recipients_set = set(resolved["recipients"])
    try:
        recipients_set |= _resolve_admin_opt_in_emails()
    except Exception as e:
        print(f"Notification recipient resolve (admin-opt-in) failed: {e}")

    commenter = _norm(author_email)
    if _is_valid(commenter):
        recipients_set.discard(commenter)

    recipients = sorted(recipients_set)
    if not recipients:
        return

    prefs_map = _get_prefs_by_emails(recipients)

    in_app_recipients: List[tuple] = []
    push_recipients: List[tuple] = []

    for email in recipients:
        pref = DEFAULT_PREFS.copy()
        pref.update(prefs_map.get(email, {}))
        if not _prefs_allow(pref, "comment"):
            continue
        
        user_id = _get_user_id_by_email(email)
        if user_id:
            user_tuple = (user_id, email)
        else:
            user_tuple = (None, email)
        
        if pref.get("in_app_enabled", True):
            in_app_recipients.append(user_tuple)
        if pref.get("push_enabled", True):
            push_recipients.append(user_tuple)

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
        push_emails = [email for _, email in push_recipients]
        push_result = send_push_to_external_ids(
            title=title,
            body=body,
            external_ids=push_emails,
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

        for user_id, email in push_recipients:
            _log_delivery(
                notification_id=notification_id_by_email.get(_norm(email)),
                user_id=user_id,
                user_email=email,
                status=status,
                provider_message_id=message_id,
                error=error,
            )
