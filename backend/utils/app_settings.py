import logging
from typing import Optional
from db import supabase

logger = logging.getLogger(__name__)


async def get_setting(key: str) -> Optional[str]:
    try:
        result = supabase.table("app_settings").select("value").eq("key", key).execute()
        if result.data and len(result.data) > 0:
            return result.data[0]["value"]
        return None
    except Exception as e:
        logger.error(f"Failed to get setting {key}: {e}")
        return None


async def set_setting(key: str, value: str, updated_by: Optional[str] = None) -> None:
    try:
        user_id = None
        if updated_by:
            user_result = (
                supabase.table("users").select("id").eq("email", updated_by).execute()
            )
            if user_result.data and len(user_result.data) > 0:
                user_id = user_result.data[0]["id"]

        supabase.table("app_settings").upsert(
            {"key": key, "value": value, "updated_at": "now()", "updated_by": user_id},
            on_conflict="key",
        ).execute()
    except Exception as e:
        logger.error(f"Failed to set setting {key}: {e}")
        raise
