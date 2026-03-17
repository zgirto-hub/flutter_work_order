from db import supabase


def log_activity(
    user_email: str,
    category: str,
    action: str,
    target_label: str = "",
    target_id: str = "",
    detail: str = "",
):
    """
    Fire-and-forget activity log write.
    Silently ignores errors so it never breaks the main operation.
    """
    try:
        user_name = user_email.split("@")[0]
        supabase.table("user_activity_log").insert({
            "user_email": user_email,
            "user_name": user_name,
            "category": category,
            "action": action,
            "target_label": target_label,
            "target_id": str(target_id),
            "detail": detail,
        }).execute()
    except Exception as e:
        print(f"[activity_log] Failed to log: {e}")
