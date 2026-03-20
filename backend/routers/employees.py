from fastapi import APIRouter, Query
from db import supabase

router = APIRouter()


@router.get("/employees")
async def list_employees(tech: bool = Query(False)):
    """Get all active fixers/admins for employee selection."""
    if tech:
        result = supabase.table("users").select("*").eq("is_active", True).in_("user_type", ["fixer", "admin"]).order("full_name").execute()
    else:
        result = supabase.table("users").select("*").eq("is_active", True).order("full_name").execute()
    return {"employees": result.data or []}


@router.get("/employee-profile")
async def get_employee_profile(email: str = Query(...)):
    """Get employee profile including user_type."""
    normalized = email.strip().lower()
    result = supabase.table("users").select("*").eq("email", normalized).execute()
    user = (result.data or [{}])[0] if result.data else {}
    return {"employee": user}
