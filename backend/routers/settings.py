from datetime import datetime, timezone

from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from db import supabase
from utils.activity import log_activity

router = APIRouter(prefix="/settings", tags=["settings"])


class SettingUpdateBody(BaseModel):
    value: str


def _require_admin(email: str):
    """Verify the caller is an admin, raise 403 otherwise"""
    if not email:
        raise HTTPException(status_code=403, detail="Admin access required")
    user = (
        supabase.table("users")
        .select("*")
        .eq("email", email.strip().lower())
        .maybe_single()
        .execute()
    )
    if not user.data or user.data.get("user_type") != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")


@router.get("/{key}")
async def get_setting(key: str, admin_email: str = Query(...)):
    """Get a system setting by key (admin only)"""
    _require_admin(admin_email)
    result = (
        supabase.table("system_settings")
        .select("*")
        .eq("key", key)
        .maybe_single()
        .execute()
    )
    if not result or not result.data:
        raise HTTPException(status_code=404, detail="Setting not found")
    return result.data


@router.put("/{key}")
async def update_setting(
    key: str, body: SettingUpdateBody, admin_email: str = Query(...)
):
    """Update a system setting (admin only)"""
    _require_admin(admin_email)
    result = (
        supabase.table("system_settings")
        .upsert(
            {
                "key": key,
                "value": body.value,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        .execute()
    )
    log_activity(admin_email, "admin", "updated_setting", target_label=key)
    return result.data[0] if result.data else {"key": key, "value": body.value}
