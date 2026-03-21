from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import List, Optional
from db import supabase

router = APIRouter()


class TechnicianDepartmentCreate(BaseModel):
    technician_id: str
    department: str


class TechnicianDepartmentsUpdate(BaseModel):
    departments: List[str]


def _get_department_id(department_name: str) -> Optional[str]:
    """Get department UUID by name"""
    result = supabase.table("departments").select("id").eq("name", department_name).eq("is_active", True).execute()
    return result.data[0].get("id") if result.data else None


def _get_department_name(department_id: str) -> Optional[str]:
    """Get department name by UUID"""
    result = supabase.table("departments").select("name").eq("id", department_id).execute()
    return result.data[0].get("name") if result.data else None


# --------------------
# Technician Department Endpoints
# --------------------

@router.get("/technician-departments")
async def list_technician_departments():
    """Get all technician-department mappings with user info"""
    result = supabase.table("technician_departments").select("*, users(id, email, full_name)").execute()

    mappings = []
    for r in (result.data or []):
        dept_id = r.get("department_id")
        dept_name = _get_department_name(dept_id) if dept_id else None
        user = r.get("users") or {}
        mappings.append({
            **r,
            "department": dept_name,
            "users": user
        })

    return {"technician_departments": mappings}


@router.get("/technician-departments/user/{user_id}")
async def get_user_technician_departments(user_id: str):
    """Get departments handled by a specific technician"""
    result = supabase.table("technician_departments") \
        .select("department_id") \
        .eq("technician_id", user_id) \
        .execute()

    departments = []
    for r in (result.data or []):
        dept_id = r.get("department_id")
        if dept_id:
            dept_name = _get_department_name(dept_id)
            if dept_name:
                departments.append(dept_name)

    return {"departments": departments}


@router.get("/technician-departments/department/{department}")
async def get_technicians_by_department(department: str):
    """Get all technicians who handle a specific department"""
    dept_id = _get_department_id(department)
    if not dept_id:
        return {"technicians": [], "department": department}

    result = supabase.table("technician_departments") \
        .select("*, users(id, email, full_name, is_active)") \
        .eq("department_id", dept_id) \
        .execute()

    active_technicians = [
        r for r in (result.data or [])
        if r.get("users") and r["users"].get("is_active") is True
    ]
    return {"technicians": active_technicians, "department": department}


@router.post("/technician-departments")
async def create_technician_department(body: TechnicianDepartmentCreate):
    """Add a department to a technician's scope"""
    technician_id = body.technician_id.strip()
    department = body.department.strip()

    if not technician_id:
        raise HTTPException(status_code=400, detail="technician_id is required")
    if not department:
        raise HTTPException(status_code=400, detail="department is required")

    technician = supabase.table("users").select("id").eq("id", technician_id).execute()
    if not technician.data:
        raise HTTPException(status_code=404, detail="Technician user not found")

    dept_id = _get_department_id(department)
    if not dept_id:
        raise HTTPException(status_code=404, detail=f"Department '{department}' not found")

    existing = supabase.table("technician_departments") \
        .select("id") \
        .eq("technician_id", technician_id) \
        .eq("department_id", dept_id) \
        .execute()
    if existing.data:
        raise HTTPException(status_code=400, detail=f"Technician already handles department '{department}'")

    result = supabase.table("technician_departments").insert({
        "technician_id": technician_id,
        "department_id": dept_id,
    }).execute()

    return {"technician_department": result.data[0] if result.data else None}


@router.post("/technician-departments/bulk/{user_id}")
async def set_technician_departments(user_id: str, body: TechnicianDepartmentsUpdate):
    """Set all departments for a technician (replaces existing)"""
    user_id_clean = user_id.strip()

    if not user_id_clean:
        raise HTTPException(status_code=400, detail="user_id is required")

    user = supabase.table("users").select("id").eq("id", user_id_clean).execute()
    if not user.data:
        raise HTTPException(status_code=404, detail="User not found")

    supabase.table("technician_departments") \
        .delete() \
        .eq("technician_id", user_id_clean) \
        .execute()

    if body.departments:
        new_mappings = []
        for dept_name in body.departments:
            dept_name = dept_name.strip()
            if dept_name:
                dept_id = _get_department_id(dept_name)
                if dept_id:
                    new_mappings.append({"technician_id": user_id_clean, "department_id": dept_id})
        if new_mappings:
            supabase.table("technician_departments").insert(new_mappings).execute()

    return {"status": "updated", "departments": body.departments}


@router.delete("/technician-departments/{technician_id}/{department}")
async def delete_technician_department(technician_id: str, department: str):
    """Remove a department from a technician's scope"""
    technician_id_clean = technician_id.strip()
    department_clean = department.strip()

    dept_id = _get_department_id(department_clean)
    if not dept_id:
        raise HTTPException(status_code=404, detail=f"Department '{department_clean}' not found")

    existing = supabase.table("technician_departments") \
        .select("id") \
        .eq("technician_id", technician_id_clean) \
        .eq("department_id", dept_id) \
        .execute()

    if not existing.data:
        raise HTTPException(status_code=404, detail="Technician-department mapping not found")

    supabase.table("technician_departments") \
        .delete() \
        .eq("id", existing.data[0]["id"]) \
        .execute()

    return {"deleted": True, "technician_id": technician_id_clean, "department": department_clean}
