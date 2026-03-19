from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from db import supabase

router = APIRouter()


class DepartmentCreate(BaseModel):
    name: str
    sort_order: Optional[int] = 0


class DepartmentUpdate(BaseModel):
    name: Optional[str] = None
    sort_order: Optional[int] = None


@router.get("/departments")
async def list_departments():
    """Get all departments sorted by sort_order"""
    result = supabase.table("departments") \
        .select("*") \
        .order("sort_order") \
        .execute()
    return {"departments": result.data or []}


@router.post("/departments")
async def create_department(body: DepartmentCreate):
    """Create a new department"""
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Department name is required")
    
    # Check if already exists
    existing = supabase.table("departments") \
        .select("id") \
        .eq("name", name) \
        .execute()
    if existing.data:
        raise HTTPException(status_code=400, detail=f"Department '{name}' already exists")
    
    # Get max sort_order if not provided
    if body.sort_order is None:
        max_order = supabase.table("departments") \
            .select("sort_order") \
            .order("sort_order", desc=True) \
            .limit(1) \
            .execute()
        next_order = (max_order.data[0]["sort_order"] + 1) if max_order.data else 1
    else:
        next_order = body.sort_order
    
    result = supabase.table("departments").insert({
        "name": name,
        "sort_order": next_order
    }).execute()
    
    return {"department": result.data[0] if result.data else None}


@router.patch("/departments/{department_id}")
async def update_department(department_id: str, body: DepartmentUpdate):
    """Update a department"""
    update_data = {}
    
    if body.name is not None:
        name = body.name.strip()
        if not name:
            raise HTTPException(status_code=400, detail="Department name cannot be empty")
        
        # Check if name already exists for different department
        existing = supabase.table("departments") \
            .select("id") \
            .eq("name", name) \
            .neq("id", department_id) \
            .execute()
        if existing.data:
            raise HTTPException(status_code=400, detail=f"Department '{name}' already exists")
        
        update_data["name"] = name
    
    if body.sort_order is not None:
        update_data["sort_order"] = body.sort_order
    
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update")
    
    result = supabase.table("departments") \
        .update(update_data) \
        .eq("id", department_id) \
        .execute()
    
    if not result.data:
        raise HTTPException(status_code=404, detail="Department not found")
    
    return {"department": result.data[0]}


@router.delete("/departments/{department_id}")
async def delete_department(department_id: str):
    """Delete a department"""
    # Check if department exists
    existing = supabase.table("departments") \
        .select("name") \
        .eq("id", department_id) \
        .execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Department not found")
    
    department_name = existing.data[0]["name"]
    
    # Check if department is used in work_orders
    wo_check = supabase.table("work_orders") \
        .select("id") \
        .eq("department", department_name) \
        .limit(1) \
        .execute()
    if wo_check.data:
        raise HTTPException(
            status_code=400,
            detail="Cannot delete: department is used in work orders"
        )
    
    # Delete the department
    supabase.table("departments") \
        .delete() \
        .eq("id", department_id) \
        .execute()
    
    return {"deleted": True, "name": department_name}
