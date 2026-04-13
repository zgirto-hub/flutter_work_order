import logging
import time
from datetime import datetime, timedelta
from typing import Any, Optional

from db import supabase

logger = logging.getLogger(__name__)

BUILT_IN_RULES = [
    {
        "name": "Recurring fault threshold",
        "description": "Same fault_type on same equipment_id 3+ times within 6 months. Replacement may be mandatory per manual rule.",
        "severity": "high",
        "detection_type": "recurring_fault",
        "threshold_count": 3,
        "threshold_days": 180,
        "target_field": "equipment_id",
        "group_by_field": None,
    },
    {
        "name": "Same technician recurring fault",
        "description": "Same technician handles same fault_type 3+ times. Training or procedure review needed.",
        "severity": "medium",
        "detection_type": "technician_recurring",
        "threshold_count": 3,
        "threshold_days": None,
        "target_field": "technician_id",
        "group_by_field": "fault_type",
    },
    {
        "name": "Procedure deviation",
        "description": "action_taken does not match procedure_followed. Flag for senior engineer review.",
        "severity": "high",
        "detection_type": "procedure_deviation",
        "threshold_count": None,
        "threshold_days": None,
        "target_field": None,
        "group_by_field": None,
    },
    {
        "name": "Seasonal pattern",
        "description": "Same equipment_type and fault_type recurs in the same calendar month across 2+ years. Recommend preventive check.",
        "severity": "low",
        "detection_type": "seasonal_pattern",
        "threshold_count": 2,
        "threshold_days": None,
        "target_field": "equipment_type",
        "group_by_field": "fault_type",
    },
    {
        "name": "Long resolution time",
        "description": "Work order resolution exceeds 14 days for this fault_type. Escalation needed.",
        "severity": "medium",
        "detection_type": "long_resolution",
        "threshold_count": None,
        "threshold_days": 14,
        "target_field": None,
        "group_by_field": None,
    },
    {
        "name": "Parts replaced but fault recurs",
        "description": "Parts replaced but same fault_type recurs on same equipment within 30 days. Part quality or installation issue.",
        "severity": "high",
        "detection_type": "parts_replaced_recurrence",
        "threshold_count": None,
        "threshold_days": 30,
        "target_field": "equipment_id",
        "group_by_field": None,
    },
]


async def seed_built_in_rules() -> None:
    """Seed the 6 built-in rules if the table is empty."""
    try:
        count_result = supabase.table("pattern_rules").select("id").execute()
        if count_result.data:
            logger.info("[pattern_engine] Rules already exist, skipping seed")
            return

        rules_to_insert = [
            {**rule, "is_built_in": True, "enabled": True} for rule in BUILT_IN_RULES
        ]

        supabase.table("pattern_rules").insert(rules_to_insert).execute()
        logger.info(f"[pattern_engine] Seeded {len(rules_to_insert)} built-in rules")
    except Exception as e:
        logger.error(f"[pattern_engine] Failed to seed rules: {e}")


async def evaluate_patterns(work_order_id: str) -> None:
    """Evaluate all active rules against a single work order's entities."""
    try:
        entity_result = (
            supabase.table("work_order_entities")
            .select("*")
            .eq("work_order_id", work_order_id)
            .execute()
        )
        if not entity_result.data:
            logger.warning(f"[pattern_engine] No entity found for {work_order_id}")
            return

        entity = entity_result.data[0]
        rules_result = (
            supabase.table("pattern_rules").select("*").eq("enabled", True).execute()
        )
        rules = rules_result.data or []

        for rule in rules:
            detection_type = rule["detection_type"]
            if detection_type == "recurring_fault":
                match = await _check_recurring_fault(entity, rule)
            elif detection_type == "technician_recurring":
                match = await _check_technician_recurring(entity, rule)
            elif detection_type == "procedure_deviation":
                match = await _check_procedure_deviation(entity, rule)
            elif detection_type == "seasonal_pattern":
                match = await _check_seasonal_pattern(entity, rule)
            elif detection_type == "long_resolution":
                match = await _check_long_resolution(entity, rule)
            elif detection_type == "parts_replaced_recurrence":
                match = await _check_parts_replaced_recurrence(entity, rule)
            else:
                continue

            if match["matched"]:
                await _create_alert(
                    rule_id=rule["id"],
                    work_order_ids=[work_order_id],
                    system=entity.get("system"),
                    equipment_id=entity.get("equipment_id"),
                    fault_type=entity.get("fault_type"),
                    technician_id=entity.get("technician_id"),
                    severity=rule["severity"],
                    message=match["message"],
                    dedup_key=None,
                )
    except Exception as e:
        logger.warning(f"[pattern_engine] Evaluation failed for {work_order_id}: {e}")


async def full_scan() -> dict[str, Any]:
    """Run all active rules against all entities, with deduplication."""
    start_time = time.time()
    rules_result = (
        supabase.table("pattern_rules").select("*").eq("enabled", True).execute()
    )
    rules = rules_result.data or []

    entities_result = supabase.table("work_order_entities").select("*").execute()
    entities = entities_result.data or []

    alerts_created = 0
    alerts_skipped_duplicate = 0

    for rule in rules:
        detection_type = rule["detection_type"]
        rule_id = rule["id"]

        for entity in entities:
            entity_date = entity.get("date", "")
            if detection_type in (
                "recurring_fault",
                "seasonal_pattern",
                "parts_replaced_recurrence",
            ):
                if not entity_date:
                    continue

            if detection_type == "recurring_fault":
                match = await _check_recurring_fault(entity, rule)
            elif detection_type == "technician_recurring":
                match = await _check_technician_recurring(entity, rule)
            elif detection_type == "procedure_deviation":
                match = await _check_procedure_deviation(entity, rule)
            elif detection_type == "seasonal_pattern":
                match = await _check_seasonal_pattern(entity, rule)
            elif detection_type == "long_resolution":
                match = await _check_long_resolution(entity, rule)
            elif detection_type == "parts_replaced_recurrence":
                match = await _check_parts_replaced_recurrence(entity, rule)
            else:
                continue

            if match["matched"]:
                dedup_key = f"{rule_id}:{entity.get('system')}:{entity.get('equipment_id')}:{entity.get('fault_type')}:{_get_year_month(entity_date)}"
                existing = (
                    supabase.table("pattern_alerts")
                    .select("id")
                    .eq("dedup_key", dedup_key)
                    .execute()
                )
                if existing.data:
                    alerts_skipped_duplicate += 1
                    continue

                await _create_alert(
                    rule_id=rule_id,
                    work_order_ids=[entity["work_order_id"]],
                    system=entity.get("system"),
                    equipment_id=entity.get("equipment_id"),
                    fault_type=entity.get("fault_type"),
                    technician_id=entity.get("technician_id"),
                    severity=rule["severity"],
                    message=match["message"],
                    dedup_key=dedup_key,
                )
                alerts_created += 1

    duration = time.time() - start_time
    return {
        "rules_evaluated": len(rules),
        "alerts_created": alerts_created,
        "alerts_skipped_duplicate": alerts_skipped_duplicate,
        "duration_seconds": round(duration, 2),
    }


def _get_year_month(date_str: str) -> str:
    """Parse YYYY-MM from date string."""
    try:
        dt = datetime.strptime(date_str, "%Y-%m-%d")
        return dt.strftime("%Y-%m")
    except (ValueError, TypeError):
        return ""


def _parse_date(date_str: str) -> Optional[datetime]:
    """Parse date string to datetime object. Returns None if invalid."""
    if not date_str:
        return None
    try:
        return datetime.strptime(date_str, "%Y-%m-%d")
    except (ValueError, TypeError):
        return None


async def _check_recurring_fault(entity: dict, rule: dict) -> dict:
    """Check if same fault_type on same equipment_id occurs threshold_count+ times within threshold_days."""
    equipment_id = entity.get("equipment_id")
    fault_type = entity.get("fault_type")
    entity_date = entity.get("date")

    if not equipment_id or not fault_type or not entity_date:
        return {"matched": False, "message": ""}

    dt = _parse_date(entity_date)
    if not dt:
        return {"matched": False, "message": ""}

    threshold_count = rule.get("threshold_count", 3)
    threshold_days = rule.get("threshold_days", 180)
    target_date = dt - timedelta(days=threshold_days)

    result = (
        supabase.table("work_order_entities")
        .select("work_order_id, date")
        .eq("equipment_id", equipment_id)
        .eq("fault_type", fault_type)
        .execute()
    )
    matching = []
    for e in result.data or []:
        if e.get("date"):
            ed = _parse_date(e["date"])
            if ed and target_date <= ed <= dt:
                matching.append(e["work_order_id"])

    if len(matching) >= threshold_count:
        msg = f"Equipment {equipment_id} has had {len(matching)} '{fault_type}' faults in the last {threshold_days} days — replacement may be mandatory per manual rule."
        return {"matched": True, "message": msg, "work_order_ids": matching}

    return {"matched": False, "message": ""}


async def _check_technician_recurring(entity: dict, rule: dict) -> dict:
    """Check if same technician handles same fault_type threshold_count+ times."""
    technician_id = entity.get("technician_id")
    fault_type = entity.get("fault_type")

    if not technician_id or not fault_type:
        return {"matched": False, "message": ""}

    threshold_count = rule.get("threshold_count", 3)

    result = (
        supabase.table("work_order_entities")
        .select("work_order_id")
        .eq("technician_id", technician_id)
        .eq("fault_type", fault_type)
        .execute()
    )
    matching = [e["work_order_id"] for e in (result.data or [])]

    if len(matching) >= threshold_count:
        msg = f"Technician {technician_id} has handled '{fault_type}' {len(matching)} times. Training or procedure review needed."
        return {"matched": True, "message": msg, "work_order_ids": matching}

    return {"matched": False, "message": ""}


async def _check_procedure_deviation(entity: dict, rule: dict) -> dict:
    """Check if action_taken differs from procedure_followed (case-insensitive, stripped)."""
    action_taken = entity.get("action_taken", "")
    procedure_followed = entity.get("procedure_followed", "")

    if not action_taken or not procedure_followed:
        return {"matched": False, "message": ""}

    action_normalized = action_taken.strip().lower()
    procedure_normalized = procedure_followed.strip().lower()

    if action_normalized != procedure_normalized:
        equipment_id = entity.get("equipment_id", "unknown")
        msg = f"action_taken does not match procedure_followed for equipment {equipment_id}. Flag for senior engineer review."
        return {"matched": True, "message": msg}

    return {"matched": False, "message": ""}


async def _check_seasonal_pattern(entity: dict, rule: dict) -> dict:
    """Check if same equipment_type + fault_type recurs in the same calendar month across threshold_count+ years."""
    equipment_type = entity.get("equipment_type")
    fault_type = entity.get("fault_type")
    entity_date = entity.get("date")

    if not equipment_type or not fault_type or not entity_date:
        return {"matched": False, "message": ""}

    dt = _parse_date(entity_date)
    if not dt:
        return {"matched": False, "message": ""}

    calendar_month = dt.month
    threshold_count = rule.get("threshold_count", 2)

    result = (
        supabase.table("work_order_entities")
        .select("work_order_id, date")
        .eq("equipment_type", equipment_type)
        .eq("fault_type", fault_type)
        .execute()
    )

    years = set()
    for e in result.data or []:
        if e.get("date"):
            ed = _parse_date(e["date"])
            if ed and ed.month == calendar_month:
                years.add(ed.year)

    if len(years) >= threshold_count:
        equipment_id = entity.get("equipment_id", "unknown")
        msg = f"Equipment {equipment_id} ({equipment_type}) has had '{fault_type}' in month {calendar_month} across {len(years)} years. Recommend preventive check."
        return {"matched": True, "message": msg}

    return {"matched": False, "message": ""}


async def _check_long_resolution(entity: dict, rule: dict) -> dict:
    """Check if work order created_at to closed_at exceeds threshold_days."""
    work_order_id = entity.get("work_order_id")
    if not work_order_id:
        return {"matched": False, "message": ""}

    threshold_days = rule.get("threshold_days", 14)

    try:
        wo_result = (
            supabase.table("work_orders")
            .select("created_at, closed_at")
            .eq("id", work_order_id)
            .maybe_single()
            .execute()
        )
    except Exception:
        return {"matched": False, "message": ""}

    if not wo_result.data:
        return {"matched": False, "message": ""}

    created_at_str = wo_result.data.get("created_at")
    closed_at_str = wo_result.data.get("closed_at")

    if not created_at_str or not closed_at_str:
        return {"matched": False, "message": ""}

    try:
        created_at = datetime.fromisoformat(created_at_str.replace("Z", "+00:00"))
        closed_at = datetime.fromisoformat(closed_at_str.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return {"matched": False, "message": ""}

    days_to_resolve = (closed_at - created_at).days

    if days_to_resolve > threshold_days:
        equipment_id = entity.get("equipment_id", "unknown")
        fault_type = entity.get("fault_type", "unknown")
        msg = f"Work order for {equipment_id} ({fault_type}) took {days_to_resolve} days to resolve — exceeds {threshold_days} day threshold. Escalation needed."
        return {"matched": True, "message": msg}

    return {"matched": False, "message": ""}


async def _check_parts_replaced_recurrence(entity: dict, rule: dict) -> dict:
    """Check if parts replaced but same fault recurs within threshold_days."""
    parts_replaced = entity.get("parts_replaced")
    equipment_id = entity.get("equipment_id")
    fault_type = entity.get("fault_type")
    entity_date = entity.get("date")

    if not parts_replaced or not equipment_id or not fault_type or not entity_date:
        return {"matched": False, "message": ""}

    dt = _parse_date(entity_date)
    if not dt:
        return {"matched": False, "message": ""}

    threshold_days = rule.get("threshold_days", 30)
    target_date = dt + timedelta(days=threshold_days)

    result = (
        supabase.table("work_order_entities")
        .select("work_order_id, date")
        .eq("equipment_id", equipment_id)
        .eq("fault_type", fault_type)
        .execute()
    )
    matching = []
    for e in result.data or []:
        if e.get("date"):
            ed = _parse_date(e["date"])
            if ed and dt < ed <= target_date:
                matching.append(e["work_order_id"])

    if matching:
        msg = f"Parts replaced on {equipment_id} but '{fault_type}' recurred within {threshold_days} days. Part quality or installation issue."
        return {"matched": True, "message": msg, "work_order_ids": matching}

    return {"matched": False, "message": ""}


async def _create_alert(
    rule_id: str,
    work_order_ids: list[str],
    system: Optional[str],
    equipment_id: Optional[str],
    fault_type: Optional[str],
    technician_id: Optional[str],
    severity: str,
    message: str,
    dedup_key: Optional[str],
) -> None:
    """Create a new pattern alert with optional asset context enrichment."""
    asset_context = None

    if equipment_id:
        try:
            asset_resp = (
                supabase.table("assets")
                .select("id, name, type, location")
                .eq("name", equipment_id)
                .execute()
            )
            if asset_resp.data:
                asset = asset_resp.data[0]
                links_resp = (
                    supabase.table("asset_system_links")
                    .select("system, role")
                    .eq("asset_id", asset["id"])
                    .execute()
                )
                systems = [
                    {"system": l["system"], "role": l["role"]}
                    for l in (links_resp.data or [])
                ]
                asset_context = {
                    "name": asset["name"],
                    "type": asset["type"],
                    "location": asset["location"],
                    "systems": systems,
                }
        except Exception as e:
            logger.warning(f"[pattern_engine] Failed to enrich asset context: {e}")

    try:
        supabase.table("pattern_alerts").insert(
            {
                "rule_id": rule_id,
                "work_order_ids": work_order_ids,
                "system": system,
                "equipment_id": equipment_id,
                "fault_type": fault_type,
                "technician_id": technician_id,
                "severity": severity,
                "status": "new",
                "message": message,
                "dedup_key": dedup_key,
                "asset_context": asset_context,
            }
        ).execute()
    except Exception as e:
        logger.warning(f"[pattern_engine] Failed to create alert: {e}")
