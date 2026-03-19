from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from db import supabase

router = APIRouter()


class FixerReporterCreate(BaseModel):
    fixer_department: str
    reporter_departments: List[str]


class FixerReporterUpdate(BaseModel):
    reporter_departments: Optional[List[str]] = None


@router.get("/fixer-reporters")
async def list_fixer_reporters():
    """Get all fixer-reporter mappings"""
    result = supabase.table("fixer_reporters").select("*").execute()
    return {"fixer_reporters": result.data or []}


@router.post("/fixer-reporters")
async def create_fixer_reporter(body: FixerReporterCreate):
    """Create a new fixer-reporter mapping"""
    fixer_dept = body.fixer_department.strip()
    if not fixer_dept:
        raise HTTPException(status_code=400, detail="Fixer department is required")
    
    # Check if already exists
    existing = supabase.table("fixer_reporters") \
        .select("fixer_department") \
        .eq("fixer_department", fixer_dept) \
        .execute()
    if existing.data:
        raise HTTPException(status_code=400, detail=f"Fixer department '{fixer_dept}' already exists")
    
    result = supabase.table("fixer_reporters").insert({
        "fixer_department": fixer_dept,
        "reporter_departments": body.reporter_departments
    }).execute()
    
    return {"fixer_reporter": result.data[0] if result.data else None}


@router.get("/fixer-reporters/{fixer_department}")
async def get_fixer_reporter(fixer_department: str):
    """Get fixer-reporter mapping by fixer department"""
    result = supabase.table("fixer_reporters") \
        .select("*") \
        .eq("fixer_department", fixer_department) \
        .execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Fixer department not found")
    return {"fixer_reporter": result.data[0]}


@router.patch("/fixer-reporters/{fixer_department}")
async def update_fixer_reporter(fixer_department: str, body: FixerReporterUpdate):
    """Update reporter departments for a fixer"""
    update_data = {}
    
    if body.reporter_departments is not None:
        update_data["reporter_departments"] = body.reporter_departments
    
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update")
    
    result = supabase.table("fixer_reporters") \
        .update(update_data) \
        .eq("fixer_department", fixer_department) \
        .execute()
    
    if not result.data:
        raise HTTPException(status_code=404, detail="Fixer department not found")
    
    return {"fixer_reporter": result.data[0]}


@router.delete("/fixer-reporters/{fixer_department}")
async def delete_fixer_reporter(fixer_department: str):
    """Delete a fixer-reporter mapping"""
    # Check if exists
    existing = supabase.table("fixer_reporters") \
        .select("fixer_department") \
        .eq("fixer_department", fixer_department) \
        .execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Fixer department not found")
    
    supabase.table("fixer_reporters") \
        .delete() \
        .eq("fixer_department", fixer_department) \
        .execute()
    
    return {"deleted": True, "fixer_department": fixer_department}


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


@router.get("/fixer-departments")
async def list_fixer_departments():
    """Get all fixer departments (departments with at least one fixer user)"""
    result = supabase.table("users").select("department").eq("user_type", "fixer").eq("is_active", True).execute()
    departments = set()
    for row in (result.data or []):
        dept = row.get("department")
        if dept:
            departments.add(dept)
    return {"fixer_departments": sorted(list(departments))}
