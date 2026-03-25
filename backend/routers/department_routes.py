from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from db import supabase

router = APIRouter()


class DepartmentRouteCreate(BaseModel):
    source_department_id: str
    target_department_id: str


class DepartmentRouteBulkUpdate(BaseModel):
    target_department_ids: List[str]


def _get_department_name(department_id: str) -> Optional[str]:
    result = supabase.table("departments").select("name").eq("id", department_id).execute()
    return result.data[0].get("name") if result.data else None


# --------------------
# Department Route Endpoints
# --------------------

@router.get("/department-routes")
async def list_department_routes():
    """Get all department routing rules with department names"""
    result = supabase.table("department_routes").select("*").execute()

    routes = []
    for r in (result.data or []):
        source_name = _get_department_name(r.get("source_department_id", ""))
        target_name = _get_department_name(r.get("target_department_id", ""))
        routes.append({
            **r,
            "source_department_name": source_name,
            "target_department_name": target_name,
        })

    return {"department_routes": routes}


@router.get("/department-routes/source/{source_department_id}")
async def get_target_departments(source_department_id: str):
    """Get allowed target departments for a given source department"""
    result = supabase.table("department_routes") \
        .select("target_department_id") \
        .eq("source_department_id", source_department_id) \
        .execute()

    targets = []
    for r in (result.data or []):
        dept_id = r.get("target_department_id")
        if dept_id:
            dept_name = _get_department_name(dept_id)
            if dept_name:
                targets.append({"id": dept_id, "name": dept_name})

    return {"target_departments": targets}


@router.post("/department-routes")
async def create_department_route(body: DepartmentRouteCreate):
    """Add a single routing rule"""
    source_id = body.source_department_id.strip()
    target_id = body.target_department_id.strip()

    if not source_id or not target_id:
        raise HTTPException(status_code=400, detail="source and target department IDs are required")
    if source_id == target_id:
        raise HTTPException(status_code=400, detail="Source and target departments must be different")

    # Validate both departments exist
    for dept_id, label in [(source_id, "Source"), (target_id, "Target")]:
        check = supabase.table("departments").select("id").eq("id", dept_id).execute()
        if not check.data:
            raise HTTPException(status_code=404, detail=f"{label} department not found")

    # Check for duplicate
    existing = supabase.table("department_routes") \
        .select("id") \
        .eq("source_department_id", source_id) \
        .eq("target_department_id", target_id) \
        .execute()
    if existing.data:
        raise HTTPException(status_code=400, detail="This routing rule already exists")

    result = supabase.table("department_routes").insert({
        "source_department_id": source_id,
        "target_department_id": target_id,
    }).execute()

    return {"department_route": result.data[0] if result.data else None}


@router.post("/department-routes/bulk/{source_department_id}")
async def set_department_routes(source_department_id: str, body: DepartmentRouteBulkUpdate):
    """Set all target departments for a source department (replaces existing)"""
    source_id = source_department_id.strip()
    if not source_id:
        raise HTTPException(status_code=400, detail="source_department_id is required")

    # Validate source department exists
    check = supabase.table("departments").select("id").eq("id", source_id).execute()
    if not check.data:
        raise HTTPException(status_code=404, detail="Source department not found")

    # Delete existing routes for this source
    supabase.table("department_routes") \
        .delete() \
        .eq("source_department_id", source_id) \
        .execute()

    # Insert new routes
    if body.target_department_ids:
        new_routes = []
        for target_id in body.target_department_ids:
            target_id = target_id.strip()
            if target_id and target_id != source_id:
                new_routes.append({
                    "source_department_id": source_id,
                    "target_department_id": target_id,
                })
        if new_routes:
            supabase.table("department_routes").insert(new_routes).execute()

    return {"status": "updated", "source_department_id": source_id, "target_department_ids": body.target_department_ids}


@router.delete("/department-routes/{source_department_id}/{target_department_id}")
async def delete_department_route(source_department_id: str, target_department_id: str):
    """Remove a single routing rule"""
    source_id = source_department_id.strip()
    target_id = target_department_id.strip()

    existing = supabase.table("department_routes") \
        .select("id") \
        .eq("source_department_id", source_id) \
        .eq("target_department_id", target_id) \
        .execute()

    if not existing.data:
        raise HTTPException(status_code=404, detail="Routing rule not found")

    supabase.table("department_routes") \
        .delete() \
        .eq("id", existing.data[0]["id"]) \
        .execute()

    return {"deleted": True, "source_department_id": source_id, "target_department_id": target_id}
