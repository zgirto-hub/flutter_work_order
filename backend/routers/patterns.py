from fastapi import APIRouter, HTTPException, Query
from typing import Optional
from pydantic import BaseModel
from datetime import datetime
from db import supabase
from utils.activity import log_activity

router = APIRouter(tags=["patterns"])


def _admin_check(user_email: str):
    """Shared admin check pattern."""
    try:
        user_resp = (
            supabase.table("users")
            .select("user_type")
            .eq("email", user_email)
            .maybe_single()
            .execute()
        )
    except Exception:
        raise HTTPException(status_code=403, detail={"error": "admin_required"})
    if not user_resp.data or user_resp.data.get("user_type") != "admin":
        raise HTTPException(status_code=403, detail={"error": "admin_required"})


class RuleCreate(BaseModel):
    name: str
    description: Optional[str] = None
    severity: str
    detection_type: str
    threshold_count: Optional[int] = None
    threshold_days: Optional[int] = None
    target_field: Optional[str] = None
    group_by_field: Optional[str] = None
    enabled: bool = True


class RuleUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    severity: Optional[str] = None
    detection_type: Optional[str] = None
    threshold_count: Optional[int] = None
    threshold_days: Optional[int] = None
    target_field: Optional[str] = None
    group_by_field: Optional[str] = None
    enabled: Optional[bool] = None


class AlertStatusUpdate(BaseModel):
    status: str


VALID_SEVERITIES = {"low", "medium", "high"}
VALID_DETECTION_TYPES = {
    "recurring_fault",
    "technician_recurring",
    "procedure_deviation",
    "seasonal_pattern",
    "long_resolution",
    "parts_replaced_recurrence",
}
VALID_ALERT_STATUSES = {"new", "acknowledged", "resolved"}


@router.get("/patterns/rules")
async def list_rules():
    """List all pattern rules."""
    result = supabase.table("pattern_rules").select("*").order("created_at").execute()
    return {"rules": result.data or []}


@router.post("/patterns/rules")
async def create_rule(body: RuleCreate, user_email: str = Query(...)):
    """Create a new pattern rule. Admin only."""
    _admin_check(user_email)

    if not body.name or not body.name.strip():
        raise HTTPException(
            status_code=400,
            detail={"error": "validation_error", "detail": "name is required"},
        )
    if body.severity not in VALID_SEVERITIES:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "validation_error",
                "detail": "severity must be low/medium/high",
            },
        )
    if body.detection_type not in VALID_DETECTION_TYPES:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "validation_error",
                "detail": "detection_type must be one of: "
                + ", ".join(VALID_DETECTION_TYPES),
            },
        )
    if body.threshold_count is not None and body.threshold_count < 1:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "validation_error",
                "detail": "threshold_count must be >= 1",
            },
        )
    if body.threshold_days is not None and body.threshold_days < 1:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "validation_error",
                "detail": "threshold_days must be >= 1",
            },
        )

    now = datetime.utcnow().isoformat()
    rule_data = {
        "name": body.name.strip(),
        "description": body.description,
        "severity": body.severity,
        "detection_type": body.detection_type,
        "threshold_count": body.threshold_count,
        "threshold_days": body.threshold_days,
        "target_field": body.target_field,
        "group_by_field": body.group_by_field,
        "enabled": body.enabled,
        "is_built_in": False,
        "created_at": now,
        "updated_at": now,
    }

    result = supabase.table("pattern_rules").insert(rule_data).execute()
    rule = result.data[0] if result.data else None

    log_activity(user_email, "pattern", "created_rule", target_label=body.name)
    return rule


@router.put("/patterns/rules/{rule_id}")
async def update_rule(rule_id: str, body: RuleUpdate, user_email: str = Query(...)):
    """Update an existing rule. Admin only."""
    _admin_check(user_email)

    existing = (
        supabase.table("pattern_rules")
        .select("*")
        .eq("id", rule_id)
        .maybe_single()
        .execute()
    )
    if not existing.data:
        raise HTTPException(
            status_code=404, detail={"error": "not_found", "detail": "Rule not found"}
        )

    update_data = {"updated_at": datetime.utcnow().isoformat()}
    for field in [
        "name",
        "description",
        "severity",
        "detection_type",
        "threshold_count",
        "threshold_days",
        "target_field",
        "group_by_field",
        "enabled",
    ]:
        value = getattr(body, field, None)
        if value is not None:
            if field == "name" and value:
                value = value.strip()
            update_data[field] = value

    if body.severity is not None and body.severity not in VALID_SEVERITIES:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "validation_error",
                "detail": "severity must be low/medium/high",
            },
        )
    if (
        body.detection_type is not None
        and body.detection_type not in VALID_DETECTION_TYPES
    ):
        raise HTTPException(
            status_code=400,
            detail={
                "error": "validation_error",
                "detail": "detection_type must be one of: "
                + ", ".join(VALID_DETECTION_TYPES),
            },
        )
    if body.threshold_count is not None and body.threshold_count < 1:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "validation_error",
                "detail": "threshold_count must be >= 1",
            },
        )
    if body.threshold_days is not None and body.threshold_days < 1:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "validation_error",
                "detail": "threshold_days must be >= 1",
            },
        )

    result = (
        supabase.table("pattern_rules").update(update_data).eq("id", rule_id).execute()
    )
    rule = result.data[0] if result.data else None

    log_activity(
        user_email,
        "pattern",
        "updated_rule",
        target_label=rule.get("name") if rule else "",
    )
    return rule


@router.delete("/patterns/rules/{rule_id}")
async def delete_rule(rule_id: str, user_email: str = Query(...)):
    """Delete a rule. Admin only."""
    _admin_check(user_email)

    existing = (
        supabase.table("pattern_rules")
        .select("name")
        .eq("id", rule_id)
        .maybe_single()
        .execute()
    )
    if not existing.data:
        raise HTTPException(
            status_code=404, detail={"error": "not_found", "detail": "Rule not found"}
        )

    rule_name = existing.data.get("name", "")
    supabase.table("pattern_rules").delete().eq("id", rule_id).execute()

    log_activity(user_email, "pattern", "deleted_rule", target_label=rule_name)
    return {"deleted": True}


@router.patch("/patterns/rules/{rule_id}/toggle")
async def toggle_rule(rule_id: str, user_email: str = Query(...)):
    """Toggle rule enabled/disabled. Admin only."""
    _admin_check(user_email)

    existing = (
        supabase.table("pattern_rules")
        .select("*")
        .eq("id", rule_id)
        .maybe_single()
        .execute()
    )
    if not existing.data:
        raise HTTPException(
            status_code=404, detail={"error": "not_found", "detail": "Rule not found"}
        )

    current_enabled = existing.data.get("enabled", True)
    new_enabled = not current_enabled

    result = (
        supabase.table("pattern_rules")
        .update({"enabled": new_enabled, "updated_at": datetime.utcnow().isoformat()})
        .eq("id", rule_id)
        .execute()
    )
    rule = result.data[0] if result.data else None

    action = "enabled_rule" if new_enabled else "disabled_rule"
    log_activity(
        user_email, "pattern", action, target_label=rule.get("name") if rule else ""
    )
    return rule


@router.get("/patterns/alerts")
async def list_alerts(
    status: Optional[str] = Query(None),
    severity: Optional[str] = Query(None),
    page: int = Query(1),
    page_size: int = Query(20),
    user_email: str = Query(...),
):
    """List pattern alerts with optional filters. Admin only."""
    _admin_check(user_email)

    query = supabase.table("pattern_alerts").select("*", count="exact")

    if status:
        query = query.eq("status", status)
    if severity:
        query = query.eq("severity", severity)

    query = query.order("detected_at", desc=True)

    offset = (page - 1) * page_size
    query = query.range(offset, offset + page_size - 1)

    result = query.execute()
    alerts = result.data or []
    total = result.count or 0

    rules_result = supabase.table("pattern_rules").select("id, name").execute()
    rule_names = {r["id"]: r["name"] for r in (rules_result.data or [])}

    enriched_alerts = []
    for alert in alerts:
        alert["rule_name"] = rule_names.get(alert.get("rule_id"))
        enriched_alerts.append(alert)

    return {
        "alerts": enriched_alerts,
        "total": total,
        "page": page,
        "page_size": page_size,
    }


@router.patch("/patterns/alerts/{alert_id}/status")
async def update_alert_status(
    alert_id: str, body: AlertStatusUpdate, user_email: str = Query(...)
):
    """Update alert status. Admin only."""
    _admin_check(user_email)

    if body.status not in VALID_ALERT_STATUSES:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "validation_error",
                "detail": "status must be new/acknowledged/resolved",
            },
        )

    existing_resp = (
        supabase.table("pattern_alerts")
        .select("*")
        .eq("id", alert_id)
        .execute()
    )
    if not existing_resp.data:
        raise HTTPException(
            status_code=404, detail={"error": "not_found", "detail": "Alert not found"}
        )
    existing_alert = existing_resp.data[0]

    current_status = existing_alert.get("status", "new")

    if current_status == "new" and body.status != "acknowledged":
        raise HTTPException(
            status_code=400,
            detail={
                "error": "invalid_transition",
                "detail": f"Invalid status transition: {current_status} → {body.status}",
            },
        )
    if current_status == "acknowledged" and body.status != "resolved":
        raise HTTPException(
            status_code=400,
            detail={
                "error": "invalid_transition",
                "detail": f"Invalid status transition: {current_status} → {body.status}",
            },
        )
    if current_status == "resolved":
        raise HTTPException(
            status_code=400,
            detail={
                "error": "invalid_transition",
                "detail": f"Invalid status transition: {current_status} → {body.status}",
            },
        )

    result = (
        supabase.table("pattern_alerts")
        .update({"status": body.status, "updated_at": datetime.utcnow().isoformat()})
        .eq("id", alert_id)
        .execute()
    )
    alert = result.data[0] if result.data else None

    if alert:
        rules_result = (
            supabase.table("pattern_rules")
            .select("name")
            .eq("id", alert.get("rule_id"))
            .maybe_single()
            .execute()
        )
        alert["rule_name"] = (
            rules_result.data.get("name") if rules_result.data else None
        )

    log_activity(
        user_email, "pattern", "updated_alert_status", target_label=body.status
    )
    return alert


@router.post("/patterns/scan")
async def trigger_scan(user_email: str = Query(...)):
    """Trigger full scan. Admin only."""
    _admin_check(user_email)

    from services.pattern_engine import full_scan

    summary = await full_scan()

    log_activity(
        user_email,
        "pattern",
        "triggered_scan",
        detail=f"{summary.get('alerts_created')} alerts created",
    )
    return summary
