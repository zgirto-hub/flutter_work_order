from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
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
VALID_ROLES = ["primary", "standby", "client"]
VALID_SITES = ["production", "contingency"]


class SystemCreate(BaseModel):
    name: str
    category: Optional[str] = None
    sort_order: Optional[int] = None
    has_contingency: bool = False


class SystemUpdate(BaseModel):
    name: Optional[str] = None
    category: Optional[str] = None
    sort_order: Optional[int] = None
    has_contingency: Optional[bool] = None


class SystemResponse(BaseModel):
    id: str
    name: str
    category: Optional[str]
    sort_order: int
    is_active: bool
    needs_review: bool
    has_contingency: bool = False
    created_at: str
    updated_at: str


def _empty_grouped_links():
    return {role: [] for role in VALID_ROLES}


def _detail_asset_entry(link: dict) -> dict:
    asset = link.get("assets") or {}
    return {
        "link_id": link["id"],
        "asset": {
            "id": asset.get("id"),
            "name": asset.get("name"),
            "type": asset.get("type"),
            "location": asset.get("location"),
        },
    }


def _check_link_conflict(
    system_id: str,
    asset_id: str,
    role: str,
    site: str,
    *,
    exclude_link_id: Optional[str] = None,
):
    duplicate_link_query = (
        supabase.table("asset_system_links")
        .select("id")
        .eq("asset_id", asset_id)
        .eq("system_id", system_id)
        .eq("site", site)
    )
    if exclude_link_id:
        duplicate_link_query = duplicate_link_query.neq("id", exclude_link_id)
    duplicate_link = duplicate_link_query.execute()
    if duplicate_link.data:
        return {
            "error": "duplicate_link",
            "conflict_with_link_id": duplicate_link.data[0]["id"],
            "site": site,
        }

    if role in ["primary", "standby"]:
        role_query = (
            supabase.table("asset_system_links")
            .select("id")
            .eq("system_id", system_id)
            .eq("role", role)
            .eq("site", site)
        )
        if exclude_link_id:
            role_query = role_query.neq("id", exclude_link_id)
        role_conflict = role_query.execute()
        if role_conflict.data:
            return {
                "error": f"duplicate_{role}",
                "conflict_with_link_id": role_conflict.data[0]["id"],
                "site": site,
            }

    return None


@router.get("/systems")
async def list_systems(
    active_only: bool = Query(True),
    needs_review: bool = Query(False),
    user_email: Optional[str] = None,
):
    _admin_check(user_email)

    query = supabase.table("systems").select("*")

    if active_only:
        query = query.eq("is_active", True)

    if needs_review:
        query = query.eq("needs_review", True)

    result = query.order("sort_order", desc=False).execute()

    return {"systems": result.data}


@router.get("/systems/{system_id}/detail")
async def get_system_detail(system_id: str, user_email: Optional[str] = None):
    _admin_check(user_email)

    system_resp = supabase.table("systems").select("*").eq("id", system_id).execute()
    if not system_resp.data:
        raise HTTPException(status_code=404, detail="System not found")

    system = system_resp.data[0]
    links_resp = (
        supabase.table("asset_system_links")
        .select("id, role, site, assets(id, name, type, location)")
        .eq("system_id", system_id)
        .execute()
    )

    grouped = {"production": _empty_grouped_links()}
    if system.get("has_contingency"):
        grouped["contingency"] = _empty_grouped_links()

    for link in links_resp.data or []:
        site = link.get("site") or "production"
        role = link.get("role")
        if site not in grouped or role not in VALID_ROLES:
            continue
        grouped[site][role].append(_detail_asset_entry(link))

    response = {
        "system": system,
        "production": grouped["production"],
    }
    if system.get("has_contingency"):
        response["contingency"] = grouped["contingency"]

    return response


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
        "has_contingency": body.has_contingency,
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
        all_systems = (
            supabase.table("systems").select("id, name").neq("id", system_id).execute()
        )
        if any(
            s["name"].lower() == body.name.lower() for s in (all_systems.data or [])
        ):
            raise HTTPException(status_code=409, detail="System name already exists")
        update_data["name"] = body.name

    if body.category is not None:
        update_data["category"] = body.category

    if body.sort_order is not None:
        update_data["sort_order"] = body.sort_order

    if body.has_contingency is not None and body.has_contingency != current.get(
        "has_contingency", False
    ):
        if body.has_contingency is False:
            contingency_links = (
                supabase.table("asset_system_links")
                .select("id", count="exact")
                .eq("system_id", system_id)
                .eq("site", "contingency")
                .execute()
            )
            count = contingency_links.count or 0
            if count > 0:
                raise HTTPException(
                    status_code=409,
                    detail={"error": "contingency_assets_exist", "count": count},
                )
        update_data["has_contingency"] = body.has_contingency

    if update_data:
        update_data["updated_at"] = datetime.now(timezone.utc).isoformat()
        result = (
            supabase.table("systems").update(update_data).eq("id", system_id).execute()
        )

        if result.data:
            log_activity(
                user_email, "admin", "updated_system", target_label=current["name"]
            )

        return result.data[0]

    return current


@router.post("/systems/{system_id}/disable-contingency")
async def disable_contingency(system_id: str, user_email: Optional[str] = None):
    _admin_check(user_email)

    existing = supabase.table("systems").select("*").eq("id", system_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="System not found")

    current = existing.data[0]
    if not current.get("has_contingency", False):
        raise HTTPException(
            status_code=409,
            detail={"error": "contingency_already_disabled"},
        )

    links_resp = (
        supabase.table("asset_system_links")
        .select("id, asset_id, role, site")
        .eq("system_id", system_id)
        .eq("site", "contingency")
        .execute()
    )

    moved = 0
    demoted = 0
    now = datetime.now(timezone.utc).isoformat()
    for link in links_resp.data or []:
        target_role = link["role"]
        conflict = _check_link_conflict(
            system_id,
            link["asset_id"],
            target_role,
            "production",
            exclude_link_id=link["id"],
        )
        if conflict and conflict["error"] == "duplicate_link":
            (
                supabase.table("asset_system_links")
                .delete()
                .eq("id", link["id"])
                .execute()
            )
            continue

        if conflict and conflict["error"] != "duplicate_link":
            target_role = "client"
            conflict = _check_link_conflict(
                system_id,
                link["asset_id"],
                target_role,
                "production",
                exclude_link_id=link["id"],
            )

        if conflict:
            raise HTTPException(status_code=409, detail=conflict)

        (
            supabase.table("asset_system_links")
            .update({"site": "production", "role": target_role})
            .eq("id", link["id"])
            .execute()
        )
        moved += 1
        if target_role != link["role"]:
            demoted += 1

    result = (
        supabase.table("systems")
        .update({"has_contingency": False, "updated_at": now})
        .eq("id", system_id)
        .execute()
    )

    log_activity(
        user_email,
        "admin",
        "disabled_system_contingency",
        target_label=current["name"],
    )

    return {"system": result.data[0], "moved": moved, "demoted": demoted}


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
