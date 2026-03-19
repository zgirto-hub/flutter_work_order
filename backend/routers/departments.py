from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from db import supabase

router = APIRouter()


class CreateDepartmentBody(BaseModel):
    name: str


class RenameDepartmentBody(BaseModel):
    new_name: str


@router.get("/departments")
async def list_departments():
    """Get all departments"""
    result = supabase.table("departments").select("name").order("name").execute()
    return {"departments": [r.get("name") for r in (result.data or [])]}


@router.get("/departments/all")
async def list_all_departments():
    """Get all departments"""
    result = supabase.table("departments").select("name").order("name").execute()
    return {"departments": [r.get("name") for r in (result.data or [])]}


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
    """Create a new department"""
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Department name is required")
    
    existing = supabase.table("departments").select("name").eq("name", name).execute()
    if existing.data:
        raise HTTPException(status_code=400, detail=f"Department '{name}' already exists")
    
    supabase.table("departments").insert({"name": name}).execute()
    
    return {"department": name, "created": True}


@router.patch("/departments/{department_name}")
async def rename_department(department_name: str, body: RenameDepartmentBody):
    """Rename a department"""
    old_name = department_name.strip()
    new_name = body.new_name.strip()
    
    if not new_name:
        raise HTTPException(status_code=400, detail="New department name is required")
    
    existing = supabase.table("departments").select("name").eq("name", old_name).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail=f"Department '{old_name}' not found")
    
    new_existing = supabase.table("departments").select("name").eq("name", new_name).execute()
    if new_existing.data:
        raise HTTPException(status_code=400, detail=f"Department '{new_name}' already exists")
    
    supabase.table("departments").update({"name": new_name}).eq("name", old_name).execute()
    
    users_result = supabase.table("users") \
        .update({"department": new_name}) \
        .eq("department", old_name) \
        .execute()
    
    fixers_result = supabase.table("fixer_reporters").select("*").execute()
    for fixer in (fixers_result.data or []):
        reporter_depts = fixer.get("reporter_departments") or []
        fixer_dept = fixer.get("fixer_department") or ""
        
        if fixer_dept == old_name:
            supabase.table("fixer_reporters") \
                .update({"fixer_department": new_name}) \
                .eq("fixer_department", old_name) \
                .execute()
        
        if old_name in reporter_depts:
            new_reporter_depts = [d if d != old_name else new_name for d in reporter_depts]
            supabase.table("fixer_reporters") \
                .update({"reporter_departments": new_reporter_depts}) \
                .eq("fixer_department", fixer_dept) \
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
    
    users_result = supabase.table("users").select("id").eq("department", name).execute()
    if users_result.data:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot delete department '{name}' - {len(users_result.data)} user(s) are assigned"
        )
    
    supabase.table("departments").delete().eq("name", name).execute()
    
    return {"deleted": True, "department": name}


@router.get("/departments/{department_name}/user-count")
async def get_department_user_count(department_name: str):
    """Get the number of users in a department"""
    result = supabase.table("users").select("id").eq("department", department_name).execute()
    return {"department": department_name, "user_count": len(result.data or [])}
