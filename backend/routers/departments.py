from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from db import supabase

router = APIRouter()


@router.get("/departments")
async def list_departments():
    """Get all unique departments from users table"""
    result = supabase.table("users").select("department").eq("is_active", True).execute()
    departments = set()
    for row in (result.data or []):
        dept = row.get("department")
        if dept:
            departments.add(dept)
    return {"departments": sorted(list(departments))}


@router.get("/departments/all")
async def list_all_departments():
    """Get all unique departments from users table (including inactive)"""
    result = supabase.table("users").select("department").execute()
    departments = set()
    for row in (result.data or []):
        dept = row.get("department")
        if dept:
            departments.add(dept)
    return {"departments": sorted(list(departments))}


@router.get("/departments/{department_name}")
async def get_department_info(department_name: str):
    """Get department info and user count"""
    # Count users in this department
    users_result = supabase.table("users").select("id").eq("department", department_name).execute()
    user_count = len(users_result.data or [])
    
    # Count fixers
    fixers_result = supabase.table("users").select("id").eq("department", department_name).eq("user_type", "fixer").execute()
    fixer_count = len(fixers_result.data or [])
    
    # Count reporters
    reporters_result = supabase.table("users").select("id").eq("department", department_name).eq("user_type", "reporter").execute()
    reporter_count = len(reporters_result.data or [])
    
    return {
        "department": department_name,
        "user_count": user_count,
        "fixer_count": fixer_count,
        "reporter_count": reporter_count
    }
