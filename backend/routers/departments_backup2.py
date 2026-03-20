from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, List
from db import supabase

router = APIRouter()


class CreateDepartmentBody(BaseModel):
    name: str


class RenameDepartmentBody(BaseModel):
    new_name: str


def _get_all_department_names() -> List[str]:
    """Get all department names from departments table"""
    result = supabase.table("departments").select("name").eq("is_active", True).order("name").execute()
    return [r.get("name") for r in (result.data or [])]


@router.get("/departments")
async def list_departments(is_active: Optional[bool] = Query(None)):
    """Get all departments with full details (id, name, is_active, created_at)"""
    query = supabase.table("departments").select("id, name, is_active, created_at").order("name")
    
    if is_active is not None:
        query = query.eq("is_active", is_active)
    
    result = query.execute()
    return {"departments": result.data or []}


@router.get("/departments/all")
async def list_all_departments():
    """Get all departments"""
    return {"departments": _get_all_department_names()}


@router.get("/departments/{department_id}")
async def get_department(department_id: str):
    """Get a single department by ID"""
    result = supabase.table("departments") \
        .select("*") \
        .eq("id", department_id) \
        .execute()
    
    if not result.data:
        raise HTTPException(status_code=404, detail="Department not found")
    
    return {"department": result.data[0]}


@router.get("/departments/by-name/{department_name}")
async def get_department_info(department_name: str):
    """Get department info and user count by name (legacy endpoint)"""
    dept_result = supabase.table("departments").select("id").eq("name", department_name).execute()
    if not dept_result.data:
        raise HTTPException(status_code=404, detail=f"Department '{department_name}' not found")
    dept_id = dept_result.data[0].get("id")
    
    # Count fixers assigned to this department
    fixers_result = supabase.table("fixer_departments").select("fixer_id").eq("department_id", dept_id).execute()
    fixer_ids = [r.get("fixer_id") for r in (fixers_result.data or [])]
    
    return {
        "department": department_name,
        "department_id": dept_id,
        "user_count": len(fixer_ids),
        "fixer_count": len(fixer_ids),
        "reporter_count": 0
    }


@router.post("/departments")
async def create_department(body: CreateDepartmentBody):
    """Create a new department"""
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Department name is required")
    
    existing = supabase.table("departments").select("id").eq("name", name).execute()
    if existing.data:
        raise HTTPException(status_code=400, detail=f"Department '{name}' already exists")
    
    result = supabase.table("departments").insert({"name": name, "is_active": True}).execute()
    
    return {"department": name, "department_id": result.data[0].get("id") if result.data else None, "created": True}


@router.patch("/departments/by-name/{department_name}")
async def rename_department(department_name: str, body: RenameDepartmentBody):
    """Rename a department"""
    old_name = department_name.strip()
    new_name = body.new_name.strip()
    
    if not new_name:
        raise HTTPException(status_code=400, detail="New department name is required")
    
    dept_result = supabase.table("departments").select("id").eq("name", old_name).execute()
    if not dept_result.data:
        raise HTTPException(status_code=404, detail=f"Department '{old_name}' not found")
    
    new_existing = supabase.table("departments").select("id").eq("name", new_name).execute()
    if new_existing.data:
        raise HTTPException(status_code=400, detail=f"Department '{new_name}' already exists")
    
    # Just update the department name - fixer_departments uses department_id FK
    supabase.table("departments").update({"name": new_name}).eq("name", old_name).execute()
    
    return {
        "old_name": old_name,
        "new_name": new_name,
        "updated": True
    }


@router.delete("/departments/by-name/{department_name}")
async def delete_department(department_name: str):
    """Delete a department (soft delete by setting is_active=false)"""
    name = department_name.strip()
    
    # Get department ID
    dept_result = supabase.table("departments").select("id").eq("name", name).single().execute()
    if not dept_result.data:
        raise HTTPException(status_code=404, detail=f"Department '{name}' not found")
    
    dept_id = dept_result.data["id"]
    
    # Check if any users are assigned to this department via fixer_departments
    fixers_result = supabase.table("fixer_departments").select("id").eq("department_id", dept_id).execute()
    if fixers_result.data:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot delete department '{name}' - {len(fixers_result.data)} fixer(s) are assigned"
        )
    
    # Check if any work orders use this department
    wo_result = supabase.table("work_orders").select("id").eq("department_id", dept_id).execute()
    if wo_result.data:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot delete department '{name}' - {len(wo_result.data)} work order(s) use it"
        )
    
    supabase.table("departments").update({"is_active": False}).eq("id", dept_id).execute()
    
    return {"deleted": True, "department": name}


@router.get("/departments/by-name/{department_name}/user-count")
async def get_department_user_count(department_name: str):
    """Get the number of users in a department"""
    # Get department ID
    dept_result = supabase.table("departments").select("id").eq("name", department_name).execute()
    if not dept_result.data:
        return {"department": department_name, "user_count": 0}
    
    dept_id = dept_result.data[0]["id"]
    
    # Count fixers assigned to this department
    result = supabase.table("fixer_departments").select("fixer_id").eq("department_id", dept_id).execute()
    return {"department": department_name, "user_count": len(result.data or [])}
