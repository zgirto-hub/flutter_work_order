from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime, timezone
from db import supabase
from utils.activity import log_activity


def _admin_check(user_email: str):
    """Verify the user has admin role."""
    if not user_email:
        raise HTTPException(status_code=401, detail="Authentication required")
    try:
        user_resp = (
            supabase.table("users")
            .select("user_type")
            .eq("email", user_email)
            .execute()
        )
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})
    if not user_resp.data or user_resp.data[0].get("user_type") != "admin":
        raise HTTPException(status_code=403, detail={"error": "admin_required"})

router = APIRouter()


class SystemCreate(BaseModel):
    name: str
    category: Optional[str] = None
    sort_order: Optional[int] = None


class SystemUpdate(BaseModel):
    name: Optional[str] = None
    category: Optional[str] = None
    sort_order: Optional[int] = None


class SystemResponse(BaseModel):
    id: str
    name: str
    category: Optional[str]
    sort_order: int
    is_active: bool
    needs_review: bool
    created_at: str
    updated_at: str


@router.get("/systems")
async def list_systems(
    active_only: bool = Query(True),
    needs_review: bool = Query(False),
):
    query = supabase.table("systems").select("*")

    if active_only:
        query = query.eq("is_active", True)

    if needs_review:
        query = query.eq("needs_review", True)

    result = query.order("sort_order", desc=False).execute()

    return {"systems": result.data}


@router.post("/systems", status_code=201)
async def create_system(body: SystemCreate, user_email: Optional[str] = None):
    _admin_check(user_email)

    all_systems = supabase.table("systems").select("id, name").execute()
    if any(s["name"].lower() == body.name.lower() for s in (all_systems.data or [])):
        raise HTTPException(status_code=409, detail="System name already exists")

    if body.sort_order is None:
        max_order = (
            supabase.table("systems")
            .select("sort_order")
            .order("sort_order", desc=True)
            .limit(1)
            .execute()
        )
        body.sort_order = (max_order.data[0]["sort_order"] + 1) if max_order.data else 1

    insert_data = {
        "name": body.name,
        "category": body.category,
        "sort_order": body.sort_order,
        "is_active": True,
        "needs_review": False,
    }

    result = supabase.table("systems").insert(insert_data).execute()

    if result.data:
        log_activity(user_email, "admin", "created_system", target_label=body.name)

    return result.data[0]


@router.patch("/systems/{system_id}")
async def update_system(
    system_id: str, body: SystemUpdate, user_email: Optional[str] = None
):
    _admin_check(user_email)

    existing = supabase.table("systems").select("*").eq("id", system_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="System not found")

    current = existing.data[0]
    update_data = {}

    if body.name is not None and body.name != current["name"]:
        all_systems = supabase.table("systems").select("id, name").neq("id", system_id).execute()
        if any(s["name"].lower() == body.name.lower() for s in (all_systems.data or [])):
            raise HTTPException(status_code=409, detail="System name already exists")
        update_data["name"] = body.name

    if body.category is not None:
        update_data["category"] = body.category

    if body.sort_order is not None:
        update_data["sort_order"] = body.sort_order

    if update_data:
        update_data["updated_at"] = "now()"
        result = (
            supabase.table("systems").update(update_data).eq("id", system_id).execute()
        )

        if result.data:
            log_activity(
                user_email, "admin", "updated_system", target_label=current["name"]
            )

        return result.data[0]

    return current


@router.patch("/systems/{system_id}/retire")
async def retire_system(system_id: str, user_email: Optional[str] = None):
    _admin_check(user_email)

    existing = supabase.table("systems").select("*").eq("id", system_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="System not found")

    current = existing.data[0]

    unresolved_count = (
        supabase.table("system_status_reports")
        .select("id", count="exact")
        .eq("system_id", system_id)
        .is_("resolved_at", "null")
        .execute()
    )

    warning = None
    if unresolved_count.count and unresolved_count.count > 0:
        warning = f"System has {unresolved_count.count} unresolved status reports"

    result = (
        supabase.table("systems")
        .update(
            {
                "is_active": False,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        .eq("id", system_id)
        .execute()
    )

    if result.data:
        log_activity(
            user_email, "admin", "retired_system", target_label=current["name"]
        )

    response = {"system": result.data[0]}
    if warning:
        response["warning"] = warning

    return response


@router.patch("/systems/{system_id}/activate")
async def activate_system(system_id: str, user_email: Optional[str] = None):
    _admin_check(user_email)

    existing = supabase.table("systems").select("*").eq("id", system_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="System not found")

    result = (
        supabase.table("systems")
        .update(
            {
                "is_active": True,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        .eq("id", system_id)
        .execute()
    )

    if result.data:
        log_activity(
            user_email, "admin", "activated_system", target_label=result.data[0]["name"]
        )

    return result.data[0]
