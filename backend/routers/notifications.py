from fastapi import APIRouter, Query
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

from db import supabase
from utils.notification_service import resolve_comment_recipients

router = APIRouter()


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


def _get_user_id_by_email(email: str) -> Optional[str]:
    """Get user UUID by email"""
    normalized = _norm(email)
    res = supabase.table("users").select("id").eq("email", normalized).limit(1).execute()
    return res.data[0].get("id") if res.data else None


def _get_user_email_by_id(user_id: str) -> Optional[str]:
    """Get user email by UUID"""
    res = supabase.table("users").select("email").eq("id", user_id).limit(1).execute()
    return res.data[0].get("email") if res.data else None


class NotificationPreferencesPatchBody(BaseModel):
    email: str
    push_enabled: Optional[bool] = None
    in_app_enabled: Optional[bool] = None
    mute_all: Optional[bool] = None
    comment_notifications: Optional[bool] = None
    status_notifications: Optional[bool] = None
    system_notifications: Optional[bool] = None
    admin_all_workorder_comments: Optional[bool] = None


class WatcherBody(BaseModel):
    email: str


@router.get("/notification-preferences")
async def get_notification_preferences(email: str = Query(...)):
    normalized = _norm(email)
    user_id = _get_user_id_by_email(normalized)
    
    if not user_id:
        prefs = DEFAULT_PREFS.copy()
        prefs["user_email"] = normalized
        return {"preferences": prefs}
    
    res = supabase.table("notification_preferences") \
        .select("*") \
        .eq("user_id", user_id) \
        .limit(1) \
        .execute()

    prefs: dict = DEFAULT_PREFS.copy()
    if res.data:
        prefs.update(res.data[0])
    prefs["user_email"] = normalized
    prefs["user_id"] = user_id
    return {"preferences": prefs}


@router.patch("/notification-preferences")
async def patch_notification_preferences(body: NotificationPreferencesPatchBody):
    normalized = _norm(body.email)
    user_id = _get_user_id_by_email(normalized)
    
    if not user_id:
        return {"status": "error", "detail": "User not found"}
    
    update_data = {"user_id": user_id, "user_email": normalized}
    for key in (
        "push_enabled",
        "in_app_enabled",
        "mute_all",
        "comment_notifications",
        "status_notifications",
        "system_notifications",
        "admin_all_workorder_comments",
    ):
        value = getattr(body, key)
        if value is not None:
            update_data[key] = value

    supabase.table("notification_preferences") \
        .upsert(update_data, on_conflict="user_id") \
        .execute()

    return {"status": "updated"}


@router.get("/work-orders/{work_order_id}/watchers")
async def get_work_order_watchers(work_order_id: str):
    res = supabase.table("work_order_watchers") \
        .select("user_id, user_email") \
        .eq("work_order_id", work_order_id) \
        .order("created_at", desc=False) \
        .execute()
    return {
        "watchers": [r.get("user_email") for r in (res.data or []) if r.get("user_email")],
        "watchers_id": [r.get("user_id") for r in (res.data or []) if r.get("user_id")]
    }


@router.post("/work-orders/{work_order_id}/watchers")
async def add_work_order_watcher(work_order_id: str, body: WatcherBody):
    normalized = _norm(body.email)
    user_id = _get_user_id_by_email(normalized)
    
    if not user_id:
        return {"status": "error", "detail": "User not found"}
    
    supabase.table("work_order_watchers") \
        .upsert({
            "work_order_id": work_order_id,
            "user_id": user_id,
            "user_email": normalized
        }, on_conflict="work_order_id,user_id") \
        .execute()
    return {"status": "watching"}


@router.delete("/work-orders/{work_order_id}/watchers")
async def remove_work_order_watcher(work_order_id: str, email: str = Query(...)):
    normalized = _norm(email)
    user_id = _get_user_id_by_email(normalized)
    
    if not user_id:
        return {"status": "error", "detail": "User not found"}
    
    supabase.table("work_order_watchers") \
        .delete() \
        .eq("work_order_id", work_order_id) \
        .eq("user_id", user_id) \
        .execute()
    return {"status": "unwatched"}


@router.get("/notifications")
async def list_notifications(
    email: str = Query(...),
    unread_only: bool = Query(False),
    limit: int = Query(50),
    offset: int = Query(0),
):
    normalized = _norm(email)
    user_id = _get_user_id_by_email(normalized)
    
    if not user_id:
        return {"notifications": [], "total": 0}

    query = supabase.table("notifications") \
        .select("*") \
        .eq("user_id", user_id) \
        .order("created_at", desc=True) \
        .limit(limit) \
        .offset(offset)
    if unread_only:
        query = query.is_("read_at", "null")

    data_res = query.execute()

    count_query = supabase.table("notifications") \
        .select("id") \
        .eq("user_id", user_id)
    if unread_only:
        count_query = count_query.is_("read_at", "null")
    count_res = count_query.execute()

    return {
        "notifications": data_res.data or [],
        "total": len(count_res.data or []),
    }


@router.get("/notifications/unread-count")
async def unread_count(email: str = Query(...)):
    normalized = _norm(email)
    user_id = _get_user_id_by_email(normalized)
    
    if not user_id:
        return {"count": 0}
    
    res = supabase.table("notifications") \
        .select("id") \
        .eq("user_id", user_id) \
        .is_("read_at", "null") \
        .execute()
    return {"count": len(res.data or [])}


@router.patch("/notifications/{notification_id}/read")
async def mark_notification_read(notification_id: str, email: str = Query(...)):
    normalized = _norm(email)
    user_id = _get_user_id_by_email(normalized)
    
    if not user_id:
        return {"status": "error", "detail": "User not found"}
    
    supabase.table("notifications") \
        .update({"read_at": datetime.utcnow().isoformat()}) \
        .eq("id", notification_id) \
        .eq("user_id", user_id) \
        .execute()
    return {"status": "read"}


@router.patch("/notifications/read-all")
async def mark_all_notifications_read(email: str = Query(...)):
    normalized = _norm(email)
    user_id = _get_user_id_by_email(normalized)
    
    if not user_id:
        return {"status": "error", "detail": "User not found"}
    
    supabase.table("notifications") \
        .update({"read_at": datetime.utcnow().isoformat()}) \
        .eq("user_id", user_id) \
        .is_("read_at", "null") \
        .execute()
    return {"status": "read_all"}


@router.delete("/notifications")
async def clear_all_notifications(email: str = Query(...)):
    normalized = _norm(email)
    user_id = _get_user_id_by_email(normalized)
    
    if not user_id:
        return {"status": "cleared", "count": 0}
    
    existing = supabase.table("notifications") \
        .select("id") \
        .eq("user_id", user_id) \
        .execute()
    count = len(existing.data or [])
    if count == 0:
        return {"status": "cleared", "count": 0}

    supabase.table("notifications") \
        .delete() \
        .eq("user_id", user_id) \
        .execute()
    return {"status": "cleared", "count": count}


@router.get("/work-orders/{work_order_id}/notification-debug")
async def debug_work_order_notification_recipients(
    work_order_id: str,
    commenter_email: str = Query(""),
):
    try:
        resolved = resolve_comment_recipients(work_order_id, commenter_email)
        recipients_raw = resolved.get("recipients", set())
        recipients = sorted(list(recipients_raw)) if recipients_raw else []
    except Exception as e:
        return {
            "work_order_id": work_order_id,
            "job_no": "",
            "title": "",
            "recipients": [],
            "debug": {"error": str(e)},
        }
    return {
        "work_order_id": work_order_id,
        "job_no": resolved.get("job_no", ""),
        "title": resolved.get("title", ""),
        "recipients": recipients,
        "debug": resolved.get("debug", {}),
    }
