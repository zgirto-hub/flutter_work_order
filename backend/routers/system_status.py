from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from datetime import date, datetime
from db import supabase

router = APIRouter()

ALLOWED_SYSTEMS = [
    "AIDA-NG",
    "CADAS-ATS",
    "CADAS-IMS",
    "Billing System",
    "UPS",
    "Permissions",
    "IRTOS",
    "International Circuits - Beirut",
    "International Circuits - Damascus",
    "International Circuits - Karachi",
    "International Circuits - Tehran",
    "International Circuits - Baghdad",
    "INDRA CCTV - Camera 1",
    "INDRA CCTV - Camera 2",
    "INDRA CCTV - Camera 3",
    "INDRA CCTV - Camera 4",
    "INDRA CCTV - Camera 5",
    "INDRA CCTV - Camera 6",
    "INDRA CCTV - Camera 7",
    "INDRA CCTV - Camera 8",
    "INDRA CCTV - Camera 9",
    "INDRA CCTV - Camera 10",
]


class ReportIssueBody(BaseModel):
    system_name: str
    report_date: str  # YYYY-MM-DD
    notes: Optional[str] = ""
    reported_by: str
    reported_by_name: Optional[str] = ""


class UpdateIssueBody(BaseModel):
    notes: Optional[str] = None
    report_date: Optional[str] = None


class ResolveIssueBody(BaseModel):
    resolved_by: str


@router.get("/system-status/today")
async def get_today_status(target_date: Optional[str] = Query(None)):
    """Get status of all systems for a given date (defaults to today)."""
    d = target_date or date.today().isoformat()

    result = (
        supabase.table("system_status_reports")
        .select("*")
        .eq("report_date", d)
        .is_("resolved_at", "null")
        .execute()
    )
    active_reports = {r["system_name"]: r for r in (result.data or [])}

    systems = []
    for name in ALLOWED_SYSTEMS:
        report = active_reports.get(name)
        systems.append(
            {
                "system_name": name,
                "status": "issue" if report else "operational",
                "active_report": report,
            }
        )

    return {"date": d, "systems": systems}


@router.get("/system-status/history")
async def get_history(
    system_name: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=200),
):
    """Get issue history, optionally filtered by system."""
    query = (
        supabase.table("system_status_reports")
        .select("*")
        .order("created_at", desc=True)
        .limit(limit)
    )
    if system_name:
        if system_name not in ALLOWED_SYSTEMS:
            raise HTTPException(status_code=400, detail=f"Unknown system: {system_name}")
        query = query.eq("system_name", system_name)

    result = query.execute()
    return {"reports": result.data or []}


@router.post("/system-status/report")
async def report_issue(body: ReportIssueBody):
    """Report an issue for a system on a specific date."""
    if body.system_name not in ALLOWED_SYSTEMS:
        raise HTTPException(status_code=400, detail=f"Unknown system: {body.system_name}")

    # Check for duplicate unresolved report on same system + date
    existing = (
        supabase.table("system_status_reports")
        .select("id")
        .eq("system_name", body.system_name)
        .eq("report_date", body.report_date)
        .is_("resolved_at", "null")
        .execute()
    )
    if existing.data:
        raise HTTPException(
            status_code=409,
            detail=f"An unresolved issue already exists for {body.system_name} on {body.report_date}",
        )

    result = (
        supabase.table("system_status_reports")
        .insert(
            {
                "system_name": body.system_name,
                "report_date": body.report_date,
                "notes": body.notes or "",
                "reported_by": body.reported_by,
                "reported_by_name": body.reported_by_name or "",
            }
        )
        .execute()
    )

    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create report")

    return {"report": result.data[0]}


@router.patch("/system-status/{report_id}/resolve")
async def resolve_issue(report_id: str, body: ResolveIssueBody):
    """Mark an issue as resolved."""
    # Verify it exists and is not already resolved
    existing = (
        supabase.table("system_status_reports")
        .select("id, resolved_at")
        .eq("id", report_id)
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Report not found")
    if existing.data[0].get("resolved_at"):
        raise HTTPException(status_code=400, detail="Issue is already resolved")

    result = (
        supabase.table("system_status_reports")
        .update(
            {
                "resolved_at": datetime.utcnow().isoformat(),
                "resolved_by": body.resolved_by,
            }
        )
        .eq("id", report_id)
        .execute()
    )

    return {"report": result.data[0] if result.data else None}


@router.put("/system-status/{report_id}")
async def update_issue(report_id: str, body: UpdateIssueBody):
    """Update an issue's notes and/or date."""
    existing = (
        supabase.table("system_status_reports")
        .select("*")
        .eq("id", report_id)
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Report not found")

    updates = {}
    if body.notes is not None:
        updates["notes"] = body.notes
    if body.report_date is not None:
        # Check for duplicate if date is changing
        old_report = existing.data[0]
        if body.report_date != old_report["report_date"]:
            dup = (
                supabase.table("system_status_reports")
                .select("id")
                .eq("system_name", old_report["system_name"])
                .eq("report_date", body.report_date)
                .is_("resolved_at", "null")
                .neq("id", report_id)
                .execute()
            )
            if dup.data:
                raise HTTPException(
                    status_code=409,
                    detail=f"An unresolved issue already exists for {old_report['system_name']} on {body.report_date}",
                )
        updates["report_date"] = body.report_date

    if not updates:
        return {"report": existing.data[0]}

    result = (
        supabase.table("system_status_reports")
        .update(updates)
        .eq("id", report_id)
        .execute()
    )
    return {"report": result.data[0] if result.data else None}


@router.delete("/system-status/{report_id}")
async def delete_issue(report_id: str):
    """Delete an issue report."""
    existing = (
        supabase.table("system_status_reports")
        .select("id")
        .eq("id", report_id)
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Report not found")

    supabase.table("system_status_reports").delete().eq("id", report_id).execute()
    return {"deleted": True}


@router.get("/system-status/report")
async def get_uptime_report(
    start_date: str = Query(...),
    end_date: str = Query(...),
    system_name: Optional[str] = Query(None),
):
    """Get uptime/downtime report for a date range."""
    try:
        sd = date.fromisoformat(start_date)
        ed = date.fromisoformat(end_date)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    if sd > ed:
        raise HTTPException(status_code=400, detail="start_date must be <= end_date")

    total_days = (ed - sd).days + 1

    systems_to_check = [system_name] if system_name and system_name in ALLOWED_SYSTEMS else ALLOWED_SYSTEMS

    # Fetch all reports in the date range
    query = (
        supabase.table("system_status_reports")
        .select("system_name, report_date")
        .gte("report_date", start_date)
        .lte("report_date", end_date)
    )
    if system_name and system_name in ALLOWED_SYSTEMS:
        query = query.eq("system_name", system_name)

    result = query.execute()
    reports = result.data or []

    # Count distinct days with issues per system
    issues_by_system: dict[str, set[str]] = {}
    for r in reports:
        sn = r["system_name"]
        if sn not in issues_by_system:
            issues_by_system[sn] = set()
        issues_by_system[sn].add(r["report_date"])

    report_data = []
    for sn in systems_to_check:
        days_with_issues = len(issues_by_system.get(sn, set()))
        downtime_pct = round((days_with_issues / total_days) * 100, 1) if total_days > 0 else 0
        uptime_pct = round(100 - downtime_pct, 1)
        report_data.append(
            {
                "system_name": sn,
                "total_days": total_days,
                "days_with_issues": days_with_issues,
                "uptime_pct": uptime_pct,
                "downtime_pct": downtime_pct,
            }
        )

    return {"start_date": start_date, "end_date": end_date, "systems": report_data}
