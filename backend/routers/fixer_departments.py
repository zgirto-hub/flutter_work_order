from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import List, Optional
from db import supabase

router = APIRouter()


class FixerDepartmentCreate(BaseModel):
    fixer_id: str
    department: str


class FixerDepartmentsUpdate(BaseModel):
    departments: List[str]


# --------------------
# Fixer Department Endpoints
# --------------------

@router.get("/fixer-departments")
async def list_fixer_departments():
    """Get all fixer-department mappings"""
    result = supabase.table("fixer_departments").select("*, users(email, full_name)").execute()
    return {"fixer_departments": result.data or []}


@router.get("/fixer-departments/user/{user_id}")
async def get_user_fixer_departments(user_id: str):
    """Get departments handled by a specific fixer"""
    result = supabase.table("fixer_departments") \
        .select("department") \
        .eq("fixer_id", user_id) \
        .execute()
    return {"departments": [r.get("department") for r in (result.data or [])]}


@router.get("/fixer-departments/department/{department}")
async def get_fixers_by_department(department: str):
    """Get all fixers who handle a specific department"""
    result = supabase.table("fixer_departments") \
        .select("*, users(id, email, full_name, is_active)") \
        .eq("department", department) \
        .execute()
    
    active_fixers = [
        r for r in (result.data or [])
        if r.get("users") and r["users"].get("is_active") is True
    ]
    return {"fixers": active_fixers, "department": department}


@router.post("/fixer-departments")
async def create_fixer_department(body: FixerDepartmentCreate):
    """Add a department to a fixer's scope"""
    fixer_id = body.fixer_id.strip()
    department = body.department.strip()
    
    if not fixer_id:
        raise HTTPException(status_code=400, detail="fixer_id is required")
    if not department:
        raise HTTPException(status_code=400, detail="department is required")
    
    # Verify fixer exists
    fixer = supabase.table("users").select("id").eq("id", fixer_id).execute()
    if not fixer.data:
        raise HTTPException(status_code=404, detail="Fixer user not found")
    
    # Check if already exists
    existing = supabase.table("fixer_departments") \
        .select("id") \
        .eq("fixer_id", fixer_id) \
        .eq("department", department) \
        .execute()
    if existing.data:
        raise HTTPException(status_code=400, detail=f"Fixer already handles department '{department}'")
    
    result = supabase.table("fixer_departments").insert({
        "fixer_id": fixer_id,
        "department": department,
    }).execute()
    
    return {"fixer_department": result.data[0] if result.data else None}


@router.post("/fixer-departments/bulk/{user_id}")
async def set_fixer_departments(user_id: str, body: FixerDepartmentsUpdate):
    """Set all departments for a fixer (replaces existing)"""
    user_id_clean = user_id.strip()
    
    if not user_id_clean:
        raise HTTPException(status_code=400, detail="user_id is required")
    
    # Verify user exists
    user = supabase.table("users").select("id").eq("id", user_id_clean).execute()
    if not user.data:
        raise HTTPException(status_code=404, detail="User not found")
    
    # Delete existing mappings
    supabase.table("fixer_departments") \
        .delete() \
        .eq("fixer_id", user_id_clean) \
        .execute()
    
    # Insert new mappings
    if body.departments:
        new_mappings = [
            {"fixer_id": user_id_clean, "department": dept.strip()}
            for dept in body.departments
            if dept.strip()
        ]
        if new_mappings:
            supabase.table("fixer_departments").insert(new_mappings).execute()
    
    return {"status": "updated", "departments": body.departments}


@router.delete("/fixer-departments/{fixer_id}/{department}")
async def delete_fixer_department(fixer_id: str, department: str):
    """Remove a department from a fixer's scope"""
    fixer_id_clean = fixer_id.strip()
    department_clean = department.strip()
    
    existing = supabase.table("fixer_departments") \
        .select("id") \
        .eq("fixer_id", fixer_id_clean) \
        .eq("department", department_clean) \
        .execute()
    
    if not existing.data:
        raise HTTPException(status_code=404, detail="Fixer-department mapping not found")
    
    supabase.table("fixer_departments") \
        .delete() \
        .eq("id", existing.data[0]["id"]) \
        .execute()
    
    return {"deleted": True, "fixer_id": fixer_id_clean, "department": department_clean}


# --------------------
# Department List Endpoints
# --------------------

@router.get("/departments")
async def list_departments():
    """Get all unique departments from fixer_departments"""
    result = supabase.table("fixer_departments").select("department").execute()
    departments = sorted(set(r.get("department") for r in (result.data or []) if r.get("department")))
    return {"departments": departments}


@router.get("/departments/all")
async def list_all_departments():
    """Get all possible departments (for work order creation)"""
    # These are the standard departments in the system
    departments = [
        "Operations",
        "ATC",
        "Finance",
        "NOTAM",
        "MET",
        "IT-Support",
        "Helpdesk",
        "General",
    ]
    return {"departments": departments}
