from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from datetime import date, datetime, timedelta

from db import supabase
from utils.activity import log_activity

router = APIRouter()

ALLOWED_FREQUENCIES = {"daily", "weekly", "monthly", "yearly"}


# --------------------
# Pydantic Models
# --------------------

class CreateRecurringInspection(BaseModel):
    title: str
    description: Optional[str] = ""
    location: Optional[str] = ""
    department_id: str
    frequency: str  # daily, weekly, monthly, yearly
    day_of_week: Optional[int] = None  # 0=Mon..6=Sun
    day_of_month: Optional[int] = None  # 1-31
    interval: Optional[int] = 1  # repeat every N units
    start_date: str  # YYYY-MM-DD
    end_date: Optional[str] = None
    assigned_fixer_ids: Optional[List[str]] = []
    created_by: str


class UpdateRecurringInspection(BaseModel):
    title: str
    description: Optional[str] = ""
    location: Optional[str] = ""
    department_id: str
    frequency: str
    day_of_week: Optional[int] = None
    day_of_month: Optional[int] = None
    interval: Optional[int] = 1
    start_date: str
    end_date: Optional[str] = None
    is_active: Optional[bool] = True
    assigned_fixer_ids: Optional[List[str]] = []


# --------------------
# Helpers
# --------------------

def _validate_frequency(frequency: str):
    if frequency not in ALLOWED_FREQUENCIES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid frequency. Must be one of: {', '.join(ALLOWED_FREQUENCIES)}"
        )


def _compute_next_due(frequency: str, start_date: str, day_of_week: Optional[int], day_of_month: Optional[int], interval: int = 1) -> str:
    """Compute the next due date based on frequency starting from start_date."""
    today = date.today()
    start = date.fromisoformat(start_date)

    if start > today:
        return start.isoformat()

    n = max(1, interval or 1)

    if frequency == "daily":
        return today.isoformat()

    if frequency == "weekly":
        dow = day_of_week if day_of_week is not None else 0
        days_ahead = dow - today.weekday()
        if days_ahead <= 0:
            days_ahead += 7 * n
        return (today + timedelta(days=days_ahead)).isoformat()

    if frequency == "monthly":
        dom = day_of_month if day_of_month is not None else 1
        year, month = today.year, today.month
        if today.day >= dom:
            month += n
            while month > 12:
                month -= 12
                year += 1
        try:
            return date(year, month, min(dom, 28)).isoformat()
        except ValueError:
            return date(year, month, 28).isoformat()

    if frequency == "yearly":
        year = today.year
        if today.month > 1 or today.day > 1:
            year += n
        return date(year, 1, 1).isoformat()

    return today.isoformat()


def _advance_next_due(frequency: str, current_due: str, day_of_week: Optional[int], day_of_month: Optional[int], interval: int = 1) -> str:
    """Advance the next_due_date by one period."""
    current = date.fromisoformat(current_due)
    n = max(1, interval or 1)

    if frequency == "daily":
        return (current + timedelta(days=n)).isoformat()

    if frequency == "weekly":
        return (current + timedelta(weeks=n)).isoformat()

    if frequency == "monthly":
        month = current.month + n
        year = current.year
        while month > 12:
            month -= 12
            year += 1
        dom = day_of_month if day_of_month is not None else current.day
        try:
            return date(year, month, min(dom, 28)).isoformat()
        except ValueError:
            return date(year, month, 28).isoformat()

    if frequency == "yearly":
        return date(current.year + n, current.month, current.day).isoformat()

    return current.isoformat()


def _sync_assignees(recurring_inspection_id: str, fixer_ids: List[str]):
    supabase.table("recurring_inspection_assignees") \
        .delete() \
        .eq("recurring_inspection_id", recurring_inspection_id) \
        .execute()
    if fixer_ids:
        rows = [
            {"recurring_inspection_id": recurring_inspection_id, "fixer_id": fid}
            for fid in fixer_ids
        ]
        supabase.table("recurring_inspection_assignees").insert(rows).execute()


def _fetch_full(ri_id: str):
    result = supabase.table("recurring_inspections").select("""
        *,
        departments!recurring_inspections_department_id_fkey (id, name),
        recurring_inspection_assignees (
            fixer_id,
            users!recurring_inspection_assignees_fixer_id_fkey (id, full_name, email)
        )
    """).eq("id", ri_id).execute()
    return result.data[0] if result.data else None


def _get_technicians_by_department(department_id: str) -> List[str]:
    result = supabase.table("technician_departments").select("technician_id").eq("department_id", department_id).execute()
    return [r.get("technician_id") for r in (result.data or [])]


# --------------------
# CRUD Endpoints
# --------------------

@router.get("/recurring-inspections")
async def list_recurring_inspections(
    department_id: Optional[str] = Query(None),
    is_active: Optional[bool] = Query(None),
):
    query = supabase.table("recurring_inspections").select("""
        *,
        departments!recurring_inspections_department_id_fkey (id, name),
        recurring_inspection_assignees (
            fixer_id,
            users!recurring_inspection_assignees_fixer_id_fkey (id, full_name, email)
        )
    """).order("next_due_date", desc=False)

    if department_id:
        query = query.eq("department_id", department_id)
    if is_active is not None:
        query = query.eq("is_active", is_active)

    result = query.execute()
    data = result.data or []

    # Annotate each inspection with whether a WO was generated today
    today_str = date.today().isoformat()
    logs_res = supabase.table("recurring_inspection_logs") \
        .select("recurring_inspection_id") \
        .eq("generated_date", today_str) \
        .execute()
    generated_today_ids = {log["recurring_inspection_id"] for log in (logs_res.data or [])}
    for ri in data:
        ri["generated_today"] = ri["id"] in generated_today_ids

    return {"recurring_inspections": data}


@router.get("/recurring-inspections/{ri_id}")
async def get_recurring_inspection(ri_id: str):
    data = _fetch_full(ri_id)
    if not data:
        raise HTTPException(status_code=404, detail="Recurring inspection not found")
    return {"recurring_inspection": data}


@router.post("/recurring-inspections")
async def create_recurring_inspection(body: CreateRecurringInspection):
    _validate_frequency(body.frequency)

    interval = max(1, body.interval or 1)
    next_due = _compute_next_due(body.frequency, body.start_date, body.day_of_week, body.day_of_month, interval)

    payload = {
        "title": body.title,
        "description": body.description or "",
        "location": body.location or "",
        "department_id": body.department_id,
        "frequency": body.frequency,
        "day_of_week": body.day_of_week,
        "day_of_month": body.day_of_month,
        "interval": interval,
        "start_date": body.start_date,
        "end_date": body.end_date,
        "next_due_date": next_due,
        "created_by": body.created_by,
    }

    result = supabase.table("recurring_inspections").insert(payload).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create recurring inspection")

    ri_id = result.data[0]["id"]
    fixer_ids = body.assigned_fixer_ids or []
    if not fixer_ids:
        fixer_ids = _get_technicians_by_department(body.department_id)
    _sync_assignees(ri_id, fixer_ids)

    return {"recurring_inspection": _fetch_full(ri_id)}


@router.put("/recurring-inspections/{ri_id}")
async def update_recurring_inspection(ri_id: str, body: UpdateRecurringInspection, user_email: str = Query(...)):
    _validate_frequency(body.frequency)

    existing = supabase.table("recurring_inspections").select("id").eq("id", ri_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Recurring inspection not found")

    interval = max(1, body.interval or 1)
    next_due = _compute_next_due(body.frequency, body.start_date, body.day_of_week, body.day_of_month, interval)

    payload = {
        "title": body.title,
        "description": body.description or "",
        "location": body.location or "",
        "department_id": body.department_id,
        "frequency": body.frequency,
        "day_of_week": body.day_of_week,
        "day_of_month": body.day_of_month,
        "interval": interval,
        "start_date": body.start_date,
        "end_date": body.end_date,
        "next_due_date": next_due,
        "is_active": body.is_active,
        "updated_at": datetime.utcnow().isoformat(),
    }

    supabase.table("recurring_inspections").update(payload).eq("id", ri_id).execute()
    _sync_assignees(ri_id, body.assigned_fixer_ids or [])

    log_activity(user_email, "recurring_inspection", "updated", target_label=body.title, target_id=ri_id)

    return {"recurring_inspection": _fetch_full(ri_id)}


@router.delete("/recurring-inspections/{ri_id}")
async def delete_recurring_inspection(ri_id: str, user_email: str = Query(...)):
    existing = supabase.table("recurring_inspections").select("id, title").eq("id", ri_id).execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Recurring inspection not found")

    supabase.table("recurring_inspections").delete().eq("id", ri_id).execute()
    log_activity(user_email, "recurring_inspection", "deleted",
                 target_label=existing.data[0].get("title", ""), target_id=ri_id)
    return {"status": "deleted"}


# --------------------
# Generate Work Orders
# --------------------

@router.post("/recurring-inspections/generate")
async def generate_due_inspections():
    """Generate work orders for all active recurring inspections that are due today or overdue."""
    today = date.today().isoformat()

    result = supabase.table("recurring_inspections").select("""
        *,
        recurring_inspection_assignees (fixer_id)
    """).eq("is_active", True).lte("next_due_date", today).execute()

    inspections = result.data or []
    generated = []
    skipped_today = 0

    for ri in inspections:
        # Check end_date
        if ri.get("end_date") and ri["end_date"] < today:
            supabase.table("recurring_inspections").update({"is_active": False}).eq("id", ri["id"]).execute()
            continue

        # Generate job number
        job_no = f"RI-{ri['id'][:8]}-{today.replace('-', '')}"

        # Check if already generated today
        existing_log = supabase.table("recurring_inspection_logs") \
            .select("id") \
            .eq("recurring_inspection_id", ri["id"]) \
            .gte("generated_at", f"{today}T00:00:00") \
            .execute()
        if existing_log.data:
            skipped_today += 1
            continue

        # Create work order
        wo_payload = {
            "job_no": job_no,
            "title": ri["title"],
            "description": ri.get("description", ""),
            "location": ri.get("location", ""),
            "department_id": ri["department_id"],
            "type": "Inspection",
            "status": "Pending",
            "created_by": ri.get("created_by"),
        }

        wo_result = supabase.table("work_orders").insert(wo_payload).execute()

        new_next = _advance_next_due(
            ri["frequency"], ri["next_due_date"],
            ri.get("day_of_week"), ri.get("day_of_month"),
            ri.get("interval", 1) or 1,
        )

        if not wo_result.data:
            # WO already exists (job_no unique violation) — advance next_due_date to
            # prevent this inspection from being picked up again on the next generate call.
            supabase.table("recurring_inspections").update({
                "next_due_date": new_next,
                "updated_at": datetime.utcnow().isoformat(),
            }).eq("id", ri["id"]).execute()
            continue

        wo_id = wo_result.data[0]["id"]

        # Assign technicians
        fixer_ids = [a["fixer_id"] for a in (ri.get("recurring_inspection_assignees") or [])]
        if not fixer_ids:
            fixer_ids = _get_technicians_by_department(ri["department_id"])
        if fixer_ids:
            assignments = [
                {"work_order_id": wo_id, "technician_id": fid, "assigned_by": ri.get("created_by")}
                for fid in fixer_ids
            ]
            supabase.table("work_order_assignments").insert(assignments).execute()

        # Log generation (generated_date enables DB-level unique constraint per day)
        supabase.table("recurring_inspection_logs").insert({
            "recurring_inspection_id": ri["id"],
            "work_order_id": wo_id,
            "generated_date": today,
        }).execute()

        # Advance next_due_date
        supabase.table("recurring_inspections").update({
            "next_due_date": new_next,
            "updated_at": datetime.utcnow().isoformat(),
        }).eq("id", ri["id"]).execute()

        generated.append({"recurring_inspection_id": ri["id"], "work_order_id": wo_id})

    return {"generated": generated, "count": len(generated), "skipped_today": skipped_today}


# --------------------
# Calendar View
# --------------------

@router.get("/recurring-inspections/calendar")
async def calendar_view(
    start_date: str = Query(..., description="YYYY-MM-DD"),
    end_date: str = Query(..., description="YYYY-MM-DD"),
):
    """Get recurring inspections and generated work orders for a date range."""
    # Active recurring inspections
    ri_result = supabase.table("recurring_inspections").select("""
        *,
        departments!recurring_inspections_department_id_fkey (id, name),
        recurring_inspection_assignees (
            fixer_id,
            users!recurring_inspection_assignees_fixer_id_fkey (id, full_name, email)
        )
    """).eq("is_active", True).execute()

    # Generated work orders in range
    logs_result = supabase.table("recurring_inspection_logs").select("""
        *,
        work_orders!recurring_inspection_logs_work_order_id_fkey (
            id, job_no, title, status, type, created_at, location,
            departments!work_orders_department_id_fkey (id, name)
        )
    """).gte("generated_at", f"{start_date}T00:00:00").lte("generated_at", f"{end_date}T23:59:59").execute()

    return {
        "recurring_inspections": ri_result.data or [],
        "generated_work_orders": logs_result.data or [],
    }
