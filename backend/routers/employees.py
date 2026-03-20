from fastapi import APIRouter, Query
from db import supabase

router = APIRouter()


@router.get("/employees")
async def list_employees(tech: bool = Query(False)):
    """Get all active employees, optionally filtered to tech/admin only."""
    if tech:
        result = supabase.table("employees").select("*").eq("active", True).in_("user_type", ["tech", "admin"]).order("full_name").execute()
    else:
        result = supabase.table("employees").select("*").eq("active", True).order("full_name").execute()
    return {"employees": result.data or []}


@router.get("/employee-profile")
async def get_employee_profile(email: str = Query(...)):
    """Get employee profile including user_type from auth."""
    normalized = email.strip().lower()
    result = supabase.table("employees").select("*").eq("email", normalized).execute()
    emp = (result.data or [{}])[0] if result.data else {}

    user_result = supabase.table("users").select("user_type").eq("email", normalized).execute()
    user_type = (user_result.data or [{}])[0].get("user_type") if user_result.data else None

    profile = dict(emp)
    profile["user_type"] = user_type
    return {"employee": profile}
