from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from db import supabase

router = APIRouter()

STANDARD_DEPARTMENTS = [
    "Operations",
    "ATC",
    "Finance",
    "NOTAM",
    "MET",
    "IT-Support",
    "Helpdesk",
    "General",
]


class CreateDepartmentBody(BaseModel):
    name: str


class RenameDepartmentBody(BaseModel):
    new_name: str


def _get_all_departments() -> List[str]:
    """Get all departments from fixer_departments + standard list"""
    result = supabase.table("fixer_departments").select("department").execute()
    fd_depts = set(r.get("department") for r in (result.data or []) if r.get("department"))
    all_depts = set(STANDARD_DEPARTMENTS) | fd_depts
    return sorted(all_depts)


@router.get("/departments")
async def list_departments():
    """Get all departments"""
    return {"departments": _get_all_departments()}


@router.get("/departments/all")
async def list_all_departments():
    """Get all departments"""
    return {"departments": _get_all_departments()}


@router.get("/departments/{department_name}")
async def get_department_info(department_name: str):
    """Get department info and user count"""
    users_result = supabase.table("users").select("id").eq("department", department_name).execute()
    user_count = len(users_result.data or [])
    
    fixers_result = supabase.table("users").select("id").eq("department", department_name).eq("user_type", "fixer").execute()
    fixer_count = len(fixers_result.data or [])
    
    reporters_result = supabase.table("users").select("id").eq("department", department_name).eq("user_type", "reporter").execute()
    reporter_count = len(reporters_result.data or [])
    
    return {
        "department": department_name,
        "user_count": user_count,
        "fixer_count": fixer_count,
        "reporter_count": reporter_count
    }


@router.post("/departments")
async def create_department(body: CreateDepartmentBody):
    """Create a new department (adds to fixer_departments if new)"""
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Department name is required")
    
    all_depts = _get_all_departments()
    if name in all_depts:
        raise HTTPException(status_code=400, detail=f"Department '{name}' already exists")
    
    return {"department": name, "created": True}


@router.patch("/departments/{department_name}")
async def rename_department(department_name: str, body: RenameDepartmentBody):
    """Rename a department"""
    old_name = department_name.strip()
    new_name = body.new_name.strip()
    
    if not new_name:
        raise HTTPException(status_code=400, detail="New department name is required")
    
    all_depts = _get_all_departments()
    if old_name not in all_depts:
        raise HTTPException(status_code=404, detail=f"Department '{old_name}' not found")
    
    if new_name in all_depts:
        raise HTTPException(status_code=400, detail=f"Department '{new_name}' already exists")
    
    users_result = supabase.table("users") \
        .update({"department": new_name}) \
        .eq("department", old_name) \
        .execute()
    
    supabase.table("fixer_departments") \
        .update({"department": new_name}) \
        .eq("department", old_name) \
        .execute()
    
    return {
        "old_name": old_name,
        "new_name": new_name,
        "updated_users": len(users_result.data or [])
    }


@router.delete("/departments/{department_name}")
async def delete_department(department_name: str):
    """Delete a department (blocked if users exist with this department)"""
    name = department_name.strip()
    
    if name in STANDARD_DEPARTMENTS:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot delete standard department '{name}'"
        )
    
    users_result = supabase.table("users").select("id").eq("department", name).execute()
    if users_result.data:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot delete department '{name}' - {len(users_result.data)} user(s) are assigned"
        )
    
    supabase.table("fixer_departments") \
        .delete() \
        .eq("department", name) \
        .execute()
    
    return {"deleted": True, "department": name}


@router.get("/departments/{department_name}/user-count")
async def get_department_user_count(department_name: str):
    """Get the number of users in a department"""
    result = supabase.table("users").select("id").eq("department", department_name).execute()
    return {"department": department_name, "user_count": len(result.data or [])}
