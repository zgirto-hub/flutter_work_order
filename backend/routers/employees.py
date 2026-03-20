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
