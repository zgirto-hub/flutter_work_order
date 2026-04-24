from db import supabase


def is_global_viewer(user: dict) -> bool:
    return (
        user.get("user_type") == "admin"
        or bool(user.get("is_supervisor"))
        or bool(user.get("is_superintendent"))
    )


def get_user_department_ids(user_id: str) -> list[str]:
    # Union of both membership sources:
    #  - users.department_id: primary single-department assignment (most users)
    #  - technician_departments: multi-department assignments (newer / optional)
    dept_ids: set[str] = set()

    user_row = supabase.table("users") \
        .select("department_id") \
        .eq("id", user_id) \
        .single() \
        .execute()
    if user_row.data and user_row.data.get("department_id"):
        dept_ids.add(user_row.data["department_id"])

    td = supabase.table("technician_departments") \
        .select("department_id") \
        .eq("technician_id", user_id) \
        .execute()
    for row in (td.data or []):
        if row.get("department_id"):
            dept_ids.add(row["department_id"])

    return list(dept_ids)


def get_user_by_email(user_email: str) -> dict | None:
    result = supabase.table("users") \
        .select("id, email, user_type, is_supervisor, is_superintendent, department_id") \
        .eq("email", user_email) \
        .single() \
        .execute()
    return result.data