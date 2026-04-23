from db import supabase


def is_global_viewer(user: dict) -> bool:
    return (
        user.get("user_type") == "admin"
        or bool(user.get("is_supervisor"))
        or bool(user.get("is_superintendent"))
    )


def get_user_department_ids(user_id: str) -> list[str]:
    result = supabase.table("technician_departments") \
        .select("department_id") \
        .eq("technician_id", user_id) \
        .execute()
    return [row["department_id"] for row in (result.data or [])]


def get_user_by_email(user_email: str) -> dict | None:
    result = supabase.table("users") \
        .select("id, email, user_type, is_supervisor, is_superintendent") \
        .eq("email", user_email) \
        .single() \
        .execute()
    return result.data