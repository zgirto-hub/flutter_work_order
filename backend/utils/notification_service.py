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


def _get_preferences(emails: List[str]) -> Dict[str, dict]:
    clean = sorted({_norm(e) for e in emails if _is_valid(_norm(e))})
    if not clean:
        return {}
    res = (
        supabase.table("notification_preferences")
        .select("*")
        .in_("user_email", clean)
        .execute()
    )
    by_email = {_norm(r.get("user_email", "")): r for r in (res.data or [])}
    return by_email


def _resolve_admin_opt_in_emails() -> Set[str]:
    admins_res = (
        supabase.table("users")
        .select("email")
        .eq("user_type", "admin")
        .eq("is_active", True)
        .execute()
    )
    admin_emails = {
        _norm(r.get("email", ""))
        for r in (admins_res.data or [])
        if _is_valid(_norm(r.get("email", "")))
    }
    if not admin_emails:
        return set()

    prefs_res = (
        supabase.table("notification_preferences")
        .select("user_email")
        .eq("admin_all_workorder_comments", True)
        .in_("user_email", sorted(admin_emails))
        .execute()
    )
    return {
        _norm(r.get("user_email", ""))
        for r in (prefs_res.data or [])
        if _is_valid(_norm(r.get("user_email", "")))
    }


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

    assignments = (
        supabase.table("work_order_assignments")
        .select("technician_id")
        .eq("work_order_id", work_order_id)
        .execute()
    )
    user_ids = [
        r.get("technician_id")
        for r in (assignments.data or [])
        if r.get("technician_id")
    ]
    if not user_ids:
        return out

    users = supabase.table("users").select("email").in_("id", user_ids).execute()

    for r in users.data or []:
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

    user_res = supabase.table("users").select("email").eq("id", uid).single().execute()
    if user_res.data:
        return _norm(user_res.data.get("email") or "")

    return ""


def _resolve_watcher_emails(work_order_id: str) -> Set[str]:
    res = (
        supabase.table("work_order_watchers")
        .select("user_email")
        .eq("work_order_id", work_order_id)
        .execute()
    )
    return {
        _norm(r.get("user_email", ""))
        for r in (res.data or [])
        if _is_valid(_norm(r.get("user_email", "")))
    }


def resolve_comment_recipients(work_order_id: str, commenter_email: str) -> dict:
    try:
        commenter = _norm(commenter_email)

        wo_res = (
            supabase.table("work_orders")
            .select("id, job_no, title, created_by")
            .eq("id", work_order_id)
            .limit(1)
            .execute()
        )
        if not wo_res.data:
            return {
                "job_no": "",
                "title": "",
                "recipients": set(),
                "debug": {"error": "work_order_not_found"},
            }

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
    rows = [
        {
            "user_email": _norm(email),
            "kind": kind,
            "title": title,
            "body": body,
            "data": data or {},
            "source_type": source_type,
            "source_id": source_id,
        }
        for email in recipients
    ]
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
        next_retry = (datetime.utcnow() + timedelta(minutes=2**attempt)).isoformat()

    supabase.table("notification_delivery_logs").insert(
        {
            "notification_id": notification_id,
            "channel": channel,
            "provider": provider,
            "recipient": _norm(recipient),
            "status": status,
            "provider_message_id": provider_message_id,
            "error": error,
            "attempt": attempt,
            "next_retry_at": next_retry,
        }
    ).execute()


def dispatch_signature_notification(
    *,
    work_order_id: str,
    signature_id: str,
    signer_email: str,
    kind: str,
    job_no: str = "",
    actor_email: str = "",
    wo_department_id: str = "",
):
    """Dispatch notifications for signature events.

    kind values:
    - 'signature_pending_supervisor' - technician signed, notify supervisors
    - 'signature_pending_superintendent' - no supervisors, notify superintendents
    - 'signature_approved_supervisor' - supervisor approved
    - 'signature_approved_superintendent' - superintendent approved (chain complete)
    - 'signature_rejected' - signature rejected
    """
    signer = _norm(signer_email)

    # T010(6): NEVER include admin users in signature notification recipients
    recipients = []
    title = ""
    body = ""

    if kind == "signature_pending_supervisor":
        # T010(2): Query supervisors for the department
        if wo_department_id:
            supervisors_res = (
                supabase.table("users")
                .select("id, email")
                .eq("is_supervisor", True)
                .execute()
            )
            supervisor_ids = [u.get("id") for u in (supervisors_res.data or [])]
            if supervisor_ids:
                td_res = (
                    supabase.table("technician_departments")
                    .select("technician_id")
                    .eq("department_id", wo_department_id)
                    .in_("technician_id", supervisor_ids)
                    .execute()
                )
                authorized_supervisor_ids = [
                    t.get("technician_id") for t in (td_res.data or [])
                ]
                if authorized_supervisor_ids:
                    user_res = (
                        supabase.table("users")
                        .select("email")
                        .in_("id", authorized_supervisor_ids)
                        .execute()
                    )
                    recipients = [
                        _norm(r.get("email", ""))
                        for r in (user_res.data or [])
                        if _is_valid(_norm(r.get("email", "")))
                    ]

        # If no supervisors found for this department, fall back to superintendents
        if not recipients:
            # T010(2): Fall back to superintendents
            supers_res = (
                supabase.table("users")
                .select("email")
                .eq("is_superintendent", True)
                .execute()
            )
            recipients = [
                _norm(r.get("email", ""))
                for r in (supers_res.data or [])
                if _is_valid(_norm(r.get("email", "")))
            ]
            if recipients:
                kind = "signature_pending_superintendent"

        if recipients:
            title = "Approval Required"
            body = f"Technician {signer} has signed {job_no or 'a work order'}. Your approval is needed."

    elif kind == "signature_pending_superintendent":
        # T010(3): Query superintendents
        supers_res = (
            supabase.table("users")
            .select("email")
            .eq("is_superintendent", True)
            .execute()
        )
        recipients = [
            _norm(r.get("email", ""))
            for r in (supers_res.data or [])
            if _is_valid(_norm(r.get("email", "")))
        ]
        if recipients:
            title = "Final Approval Required"
            body = f"Technician signature on {job_no or 'work order'} approved by supervisor. Final approval needed."

    elif kind == "signature_approved_superintendent":
        # T010(4): Notify technician who signed and WO creator
        recipients = [signer]
        # Also get WO creator
        wo_res = (
            supabase.table("work_orders")
            .select("created_by")
            .eq("id", work_order_id)
            .execute()
        )
        if wo_res.data:
            creator_id = wo_res.data[0].get("created_by")
            if creator_id:
                creator_res = (
                    supabase.table("users")
                    .select("email")
                    .eq("id", creator_id)
                    .execute()
                )
                if creator_res.data:
                    creator_email = _norm(creator_res.data[0].get("email", ""))
                    if creator_email and creator_email not in recipients:
                        recipients.append(creator_email)

        if recipients:
            title = "Signature Chain Completed"
            body = f"Work order {job_no or ''} has completed all approval steps."

    elif kind == "signature_rejected":
        # T010(5): Notify assigned technician and WO creator
        recipients = [signer]
        wo_res = (
            supabase.table("work_orders")
            .select("created_by")
            .eq("id", work_order_id)
            .execute()
        )
        if wo_res.data:
            creator_id = wo_res.data[0].get("created_by")
            if creator_id:
                creator_res = (
                    supabase.table("users")
                    .select("email")
                    .eq("id", creator_id)
                    .execute()
                )
                if creator_res.data:
                    creator_email = _norm(creator_res.data[0].get("email", ""))
                    if creator_email and creator_email not in recipients:
                        recipients.append(creator_email)

        if recipients:
            title = "Signature Rejected"
            body = f"Your signature on {job_no or 'work order'} was rejected. Please re-sign."

    elif kind == "signature_approved_supervisor":
        # Notify technician that supervisor approved
        recipients = [signer]
        if recipients:
            title = "Signature Approved by Supervisor"
            body = f"Your signature on {job_no or 'work order'} has been approved by supervisor. Waiting for final approval."

    elif kind == "signature_approved":
        # Legacy fallback
        recipients = [signer]
        title = "Signature Approved"
        body = f"Your signature on {job_no or 'work order'} has been approved."

    elif kind == "signature_pending":
        # Legacy fallback - don't notify admins anymore
        return

    else:
        return

    if not recipients:
        return

    # Remove duplicates and filter out admin emails (T010(6))
    recipients = list(set(recipients))
    admin_res = (
        supabase.table("users").select("email").eq("user_type", "admin").execute()
    )
    admin_emails = {_norm(a.get("email", "")) for a in (admin_res.data or [])}
    recipients = [r for r in recipients if r not in admin_emails]

    if not recipients:
        return

    # T010(8): Add 'approval_notifications' to preference check
    def _prefs_allow_approval(row: dict, event_type: str) -> bool:
        if row.get("mute_all"):
            return False
        if event_type in (
            "signature_pending",
            "signature_approved",
            "signature_rejected",
        ):
            return row.get("approval_notifications", True) or row.get(
                "status_notifications", True
            )
        return row.get("system_notifications", True)

    if not recipients:
        return

    prefs_map = _get_preferences(recipients)
    in_app_recipients: List[str] = []
    push_recipients: List[str] = []

    for email in recipients:
        pref = DEFAULT_PREFS.copy()
        pref.update(prefs_map.get(email, {}))
        if pref.get("mute_all"):
            continue
        if _prefs_allow_approval(pref, kind):
            if pref.get("in_app_enabled", True):
                in_app_recipients.append(email)
            if pref.get("push_enabled", True):
                push_recipients.append(email)

    payload = {
        "type": kind,
        "work_order_id": work_order_id,
        "signature_id": signature_id,
        "job_no": job_no,
    }

    notification_id_by_email = {}
    if in_app_recipients:
        try:
            inserted = _insert_notifications(
                recipients=in_app_recipients,
                kind=kind,
                title=title,
                body=body,
                source_type="work_order_signature",
                source_id=signature_id,
                data=payload,
            )
            notification_id_by_email = {
                _norm(r.get("user_email") or ""): r.get("id") for r in inserted
            }
        except Exception as e:
            print(f"Signature notification insert failed: {e}")

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
