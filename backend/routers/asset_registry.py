from collections import Counter
import json
from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException, Query
from typing import Optional, List
from pydantic import BaseModel
from db import supabase
from utils.activity import log_activity

router = APIRouter(tags=["asset-registry"])

VALID_TYPES = [
    "workstation",
    "server",
    "camera",
    "router",
    "switch",
    "media_converter",
    "power_adapter",
]
VALID_ROLES = ["primary", "standby", "client"]


def _admin_check(user_email: str):
    """Admin check pattern."""
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


class CreateAssetBody(BaseModel):
    name: str
    type: str
    location: str
    notes: Optional[str] = ""


class UpdateAssetBody(BaseModel):
    name: Optional[str] = None
    type: Optional[str] = None
    location: Optional[str] = None
    notes: Optional[str] = None


class CreateLinkBody(BaseModel):
    system: str
    role: str


class DismissSuggestionBody(BaseModel):
    equipment_id: str


def _fetch_asset_with_links(asset_id: str) -> Optional[dict]:
    """Fetch asset with its system links."""
    asset_resp = (
        supabase.table("assets").select("*").eq("id", asset_id).execute()
    )
    if not asset_resp.data:
        return None

    links_resp = (
        supabase.table("asset_system_links")
        .select("id, system, role, created_at")
        .eq("asset_id", asset_id)
        .execute()
    )

    asset = asset_resp.data[0]
    asset["system_links"] = links_resp.data or []
    return asset


def get_domain_knowledge_block() -> str:
    """Get formatted domain knowledge from asset registry for extraction prompt."""
    assets_resp = (
        supabase.table("assets")
        .select("id, name, type, location")
        .order("name")
        .execute()
    )

    if not assets_resp.data:
        return "No assets registered in the asset registry."

    all_links_resp = (
        supabase.table("asset_system_links")
        .select("asset_id, system, role")
        .execute()
    )
    links_by_asset = {}
    for link in (all_links_resp.data or []):
        links_by_asset.setdefault(link["asset_id"], []).append(link)

    lines = []
    for asset in assets_resp.data:
        links = links_by_asset.get(asset["id"], [])
        if links:
            roles_str = ", ".join([f"{l['system']} [{l['role']}]" for l in links])
            lines.append(
                f"- {asset['name']} ({asset['type']}, {asset['location']}): {roles_str}"
            )
        else:
            lines.append(
                f"- {asset['name']} ({asset['type']}, {asset['location']}): (no system links)"
            )

    return "DOMAIN KNOWLEDGE — Known assets and systems (from registry):\n" + "\n".join(
        lines
    )


@router.get("/asset-registry/assets")
async def list_assets(user_email: str = Query(...)):
    """List all assets with system links."""
    _admin_check(user_email)

    assets_resp = supabase.table("assets").select("*").order("name").execute()
    assets = assets_resp.data or []

    all_links_resp = (
        supabase.table("asset_system_links")
        .select("id, asset_id, system, role, created_at")
        .execute()
    )
    links_by_asset = {}
    for link in (all_links_resp.data or []):
        links_by_asset.setdefault(link["asset_id"], []).append(link)

    for asset in assets:
        asset["system_links"] = links_by_asset.get(asset["id"], [])

    return {"assets": assets}


@router.get("/asset-registry/asset-names")
async def list_asset_names():
    """List all asset names (alphabetically) - no admin required."""
    assets_resp = supabase.table("assets").select("name").order("name").execute()
    names = [a["name"] for a in (assets_resp.data or [])]
    return {"names": names}


@router.post("/asset-registry/assets")
async def create_asset(body: CreateAssetBody, user_email: str = Query(...)):
    """Create a new asset."""
    _admin_check(user_email)

    if body.type not in VALID_TYPES:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "invalid_type",
                "detail": f"Type must be one of: {', '.join(VALID_TYPES)}",
            },
        )

    existing = (
        supabase.table("assets")
        .select("id")
        .eq("name", body.name)
        .execute()
    )
    if existing.data:
        raise HTTPException(
            status_code=409,
            detail={
                "error": "duplicate_name",
                "detail": f"An asset with name '{body.name}' already exists",
            },
        )

    result = (
        supabase.table("assets")
        .insert(
            {
                "name": body.name,
                "type": body.type,
                "location": body.location,
                "notes": body.notes or "",
            }
        )
        .execute()
    )

    asset = result.data[0]
    asset["system_links"] = []

    log_activity(user_email, "asset", "created_asset", body.name)

    return {"asset": asset}


@router.put("/asset-registry/assets/{asset_id}")
async def update_asset(
    asset_id: str, body: UpdateAssetBody, user_email: str = Query(...)
):
    """Update an asset."""
    _admin_check(user_email)

    existing = (
        supabase.table("assets")
        .select("id")
        .eq("id", asset_id)
        .execute()
    )
    if not existing.data:
        raise HTTPException(
            status_code=404, detail={"error": "not_found", "detail": "Asset not found"}
        )

    update_data = {}
    if body.name is not None:
        dup_check = (
            supabase.table("assets")
            .select("id")
            .eq("name", body.name)
            .neq("id", asset_id)
            .execute()
        )
        if dup_check.data:
            raise HTTPException(
                status_code=409,
                detail={
                    "error": "duplicate_name",
                    "detail": f"An asset with name '{body.name}' already exists",
                },
            )
        update_data["name"] = body.name

    if body.type is not None:
        if body.type not in VALID_TYPES:
            raise HTTPException(
                status_code=400,
                detail={
                    "error": "invalid_type",
                    "detail": f"Type must be one of: {', '.join(VALID_TYPES)}",
                },
            )
        update_data["type"] = body.type

    if body.location is not None:
        update_data["location"] = body.location

    if body.notes is not None:
        update_data["notes"] = body.notes

    if update_data:
        update_data["updated_at"] = datetime.now(timezone.utc).isoformat()
        supabase.table("assets").update(update_data).eq("id", asset_id).execute()

    asset = _fetch_asset_with_links(asset_id)
    log_activity(user_email, "asset", "updated_asset", asset["name"])

    return {"asset": asset}


@router.delete("/asset-registry/assets/{asset_id}")
async def delete_asset(asset_id: str, user_email: str = Query(...)):
    """Delete an asset."""
    _admin_check(user_email)

    asset_resp = (
        supabase.table("assets")
        .select("name")
        .eq("id", asset_id)
        .execute()
    )
    if not asset_resp.data:
        raise HTTPException(
            status_code=404, detail={"error": "not_found", "detail": "Asset not found"}
        )

    asset_name = asset_resp.data[0]["name"]
    supabase.table("assets").delete().eq("id", asset_id).execute()

    log_activity(user_email, "asset", "deleted_asset", asset_name)

    return {"deleted": True}


@router.post("/asset-registry/assets/{asset_id}/links")
async def add_system_link(
    asset_id: str, body: CreateLinkBody, user_email: str = Query(...)
):
    """Add a system link to an asset."""
    _admin_check(user_email)

    asset_resp = (
        supabase.table("assets")
        .select("id")
        .eq("id", asset_id)
        .execute()
    )
    if not asset_resp.data:
        raise HTTPException(
            status_code=404, detail={"error": "not_found", "detail": "Asset not found"}
        )

    if not body.system.strip():
        raise HTTPException(
            status_code=400,
            detail={
                "error": "invalid_system",
                "detail": "System name is required",
            },
        )

    if body.role not in VALID_ROLES:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "invalid_role",
                "detail": f"Role must be one of: {', '.join(VALID_ROLES)}",
            },
        )

    dup_check = (
        supabase.table("asset_system_links")
        .select("id")
        .eq("asset_id", asset_id)
        .eq("system", body.system)
        .eq("role", body.role)
        .execute()
    )
    if dup_check.data:
        raise HTTPException(
            status_code=409,
            detail={
                "error": "duplicate_link",
                "detail": f"This asset is already linked to {body.system} as {body.role}",
            },
        )

    if body.role in ["primary", "standby"]:
        role_check = (
            supabase.table("asset_system_links")
            .select("asset_id")
            .eq("system", body.system)
            .eq("role", body.role)
            .execute()
        )
        if role_check.data:
            holder_id = role_check.data[0]["asset_id"]
            holder_resp = (
                supabase.table("assets")
                .select("name")
                .eq("id", holder_id)
                .execute()
            )
            holder_name = holder_resp.data[0]["name"] if holder_resp.data else "another asset"
            raise HTTPException(
                status_code=409,
                detail={
                    "error": "role_taken",
                    "detail": f"{body.system} already has a {body.role} server: {holder_name}",
                },
            )

    result = (
        supabase.table("asset_system_links")
        .insert({"asset_id": asset_id, "system": body.system, "role": body.role})
        .execute()
    )

    link = result.data[0]
    log_activity(user_email, "asset", "added_system_link", f"{body.system}/{body.role}")

    return {"link": link}


@router.delete("/asset-registry/links/{link_id}")
async def delete_system_link(link_id: str, user_email: str = Query(...)):
    """Delete a system link."""
    _admin_check(user_email)

    link_resp = (
        supabase.table("asset_system_links")
        .select("system, role")
        .eq("id", link_id)
        .execute()
    )
    if not link_resp.data:
        raise HTTPException(
            status_code=404, detail={"error": "not_found", "detail": "Link not found"}
        )

    supabase.table("asset_system_links").delete().eq("id", link_id).execute()

    log_activity(
        user_email,
        "asset",
        "removed_system_link",
        f"{link_resp.data[0]['system']}/{link_resp.data[0]['role']}",
    )

    return {"deleted": True}


@router.get("/asset-registry/suggestions")
async def get_suggestions(user_email: str = Query(...)):
    """Get unregistered equipment from pattern alerts with 2+ alerts."""
    _admin_check(user_email)

    alerts_resp = (
        supabase.table("pattern_alerts").select("equipment_id, fault_type").execute()
    )
    if not alerts_resp.data:
        return {"suggestions": []}

    equipment_alerts = {}
    for alert in alerts_resp.data:
        eq_id = alert.get("equipment_id")
        if not eq_id:
            continue
        if eq_id not in equipment_alerts:
            equipment_alerts[eq_id] = {"count": 0, "fault_types": set()}
        equipment_alerts[eq_id]["count"] += 1
        if alert.get("fault_type"):
            equipment_alerts[eq_id]["fault_types"].add(alert["fault_type"])

    equipment_alerts = {k: v for k, v in equipment_alerts.items() if v["count"] >= 2}

    assets_resp = supabase.table("assets").select("name").execute()
    asset_names = {a["name"].lower() for a in (assets_resp.data or [])}

    settings_resp = (
        supabase.table("system_settings")
        .select("value")
        .eq("key", "dismissed_asset_suggestions")
        .execute()
    )
    dismissed = []
    if settings_resp.data and settings_resp.data[0].get("value"):
        try:
            dismissed = settings_resp.data[0]["value"]
            if isinstance(dismissed, str):
                dismissed = json.loads(dismissed)
        except (json.JSONDecodeError, TypeError):
            dismissed = []

    dismissed_lower = {d.lower() for d in dismissed}

    # Filter to candidate equipment_ids
    candidate_ids = []
    for equipment_id in equipment_alerts:
        eq_lower = equipment_id.lower()
        if eq_lower in asset_names or eq_lower in dismissed_lower:
            continue
        candidate_ids.append(equipment_id)

    # Batch query for type inference (avoid N+1)
    types_by_equipment = {}
    if candidate_ids:
        all_entities = (
            supabase.table("work_order_entities")
            .select("equipment_id, equipment_type")
            .execute()
        )
        for e in all_entities.data or []:
            eq_id = e.get("equipment_id")
            eq_type = e.get("equipment_type")
            if eq_id and eq_type and eq_id in equipment_alerts:
                types_by_equipment.setdefault(eq_id, []).append(eq_type)

    suggestions = []
    for equipment_id in candidate_ids:
        data = equipment_alerts[equipment_id]
        inferred_type = None
        types = types_by_equipment.get(equipment_id, [])
        if types:
            inferred_type = Counter(types).most_common(1)[0][0]

        suggestions.append(
            {
                "equipment_id": equipment_id,
                "alert_count": data["count"],
                "fault_types": sorted(list(data["fault_types"])),
                "inferred_type": inferred_type,
            }
        )

    suggestions.sort(key=lambda x: x["alert_count"], reverse=True)
    return {"suggestions": suggestions}


@router.post("/asset-registry/suggestions/dismiss")
async def dismiss_suggestion(body: DismissSuggestionBody, user_email: str = Query(...)):
    """Dismiss a suggestion."""
    _admin_check(user_email)

    equipment_id = body.equipment_id
    if not equipment_id or not equipment_id.strip():
        raise HTTPException(
            status_code=400,
            detail={
                "error": "missing_equipment_id",
                "detail": "equipment_id is required",
            },
        )

    settings_resp = (
        supabase.table("system_settings")
        .select("value")
        .eq("key", "dismissed_asset_suggestions")
        .execute()
    )
    dismissed = []
    if settings_resp.data and settings_resp.data[0].get("value"):
        try:
            dismissed = settings_resp.data[0]["value"]
            if isinstance(dismissed, str):
                dismissed = json.loads(dismissed)
        except (json.JSONDecodeError, TypeError):
            dismissed = []

    if isinstance(dismissed, list):
        dismissed_set = {d.lower() for d in dismissed}
        if equipment_id.lower() not in dismissed_set:
            dismissed.append(equipment_id)
    else:
        dismissed = [equipment_id]

    supabase.table("system_settings").upsert(
        {"key": "dismissed_asset_suggestions", "value": json.dumps(dismissed)},
        on_conflict="key",
    ).execute()

    log_activity(user_email, "asset", "dismissed_suggestion", equipment_id)

    return {"dismissed": True}
