from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from datetime import date, datetime, timedelta
from db import supabase

router = APIRouter()


def _get_active_systems():
    """Query systems table for active systems ordered by sort_order."""
    result = (
        supabase.table("systems")
        .select("id, name, category")
        .eq("is_active", True)
        .order("sort_order", desc=False)
        .execute()
    )
    return result.data or []


class ReportIssueBody(BaseModel):
    system_name: str
    report_date: str  # YYYY-MM-DD
    notes: Optional[str] = ""
    reported_by: str
    reported_by_name: Optional[str] = ""


class UpdateIssueBody(BaseModel):
    notes: Optional[str] = None
    report_date: Optional[str] = None
    resolved_at: Optional[str] = None


class ResolveIssueBody(BaseModel):
    resolved_by: str
    resolved_notes: Optional[str] = ""
    resolved_at: Optional[str] = None


@router.get("/system-status/today")
async def get_today_status(target_date: Optional[str] = Query(None)):
    """Get status of all systems for a given date (defaults to today)."""
    d = target_date or date.today().isoformat()

    systems_list = await _get_active_systems()

    if not systems_list:
        return {"date": d, "systems": []}

    system_ids = [s["id"] for s in systems_list]
    system_names = {s["id"]: s["name"] for s in systems_list}

    result = (
        supabase.table("system_status_reports")
        .select("*")
        .in_("system_id", system_ids)
        .is_("resolved_at", "null")
        .execute()
    )
    active_reports = {r["system_id"]: r for r in (result.data or [])}

    systems = []
    for sys in systems_list:
        report = active_reports.get(sys["id"])
        systems.append(
            {
                "system_name": sys["name"],
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
        .select("*, systems(name)")
        .order("created_at", desc=True)
        .limit(limit)
    )

    if system_name:
        sys_lookup = (
            supabase.table("systems").select("id").ilike("name", system_name).execute()
        )
        if not sys_lookup.data:
            raise HTTPException(
                status_code=400, detail=f"Unknown system: {system_name}"
            )
        system_id = sys_lookup.data[0]["id"]
        query = query.eq("system_id", system_id)

    result = query.execute()
    reports = result.data or []

    for r in reports:
        if "systems" in r and r["systems"]:
            r["system_name"] = r["systems"]["name"]
        if "systems" in r:
            del r["systems"]

    return {"reports": reports}


@router.post("/system-status/report")
async def report_issue(body: ReportIssueBody):
    """Report an issue for a system on a specific date."""
    sys_lookup = (
        supabase.table("systems").select("id").ilike("name", body.system_name).execute()
    )
    if not sys_lookup.data:
        raise HTTPException(
            status_code=400, detail=f"Unknown system: {body.system_name}"
        )
    system_id = sys_lookup.data[0]["id"]

    existing = (
        supabase.table("system_status_reports")
        .select("id")
        .eq("system_id", system_id)
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
                "system_id": system_id,
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

    result.data[0]["system_name"] = body.system_name
    return {"report": result.data[0]}


@router.patch("/system-status/{report_id}/resolve")
async def resolve_issue(report_id: str, body: ResolveIssueBody):
    """Mark an issue as resolved."""
    existing = (
        supabase.table("system_status_reports")
        .select("id, resolved_at, report_date")
        .eq("id", report_id)
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Report not found")
    existing_report = existing.data[0]
    if existing_report.get("resolved_at"):
        raise HTTPException(status_code=400, detail="Issue is already resolved")

    if body.resolved_at:
        resolved_date = date.fromisoformat(body.resolved_at)
        report_date = date.fromisoformat(existing_report["report_date"])
        if resolved_date < report_date:
            raise HTTPException(
                status_code=400,
                detail=f"Resolve date cannot be before the issue report date ({report_date})",
            )
        if resolved_date > date.today():
            raise HTTPException(
                status_code=400, detail="Resolve date cannot be in the future"
            )
        resolved_at_value = f"{body.resolved_at}T23:59:59"
    else:
        resolved_at_value = datetime.utcnow().isoformat()

    result = (
        supabase.table("system_status_reports")
        .update(
            {
                "resolved_at": resolved_at_value,
                "resolved_by": body.resolved_by,
                "resolved_notes": body.resolved_notes or "",
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
        .select("*, systems(name)")
        .eq("id", report_id)
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Report not found")

    old_report = existing.data[0]
    system_name = (
        old_report.get("systems", {}).get("name", "")
        if old_report.get("systems")
        else ""
    )
    system_id = old_report.get("system_id")

    updates = {}
    if body.notes is not None:
        updates["notes"] = body.notes
    if body.report_date is not None:
        if body.report_date != old_report["report_date"]:
            dup = (
                supabase.table("system_status_reports")
                .select("id")
                .eq("system_id", system_id)
                .eq("report_date", body.report_date)
                .is_("resolved_at", "null")
                .neq("id", report_id)
                .execute()
            )
            if dup.data:
                raise HTTPException(
                    status_code=409,
                    detail=f"An unresolved issue already exists for {system_name} on {body.report_date}",
                )
        updates["report_date"] = body.report_date
    if body.resolved_at is not None:
        if old_report["resolved_at"] is None:
            raise HTTPException(
                status_code=400,
                detail="Cannot edit resolve date on an unresolved issue",
            )

        resolved_date = date.fromisoformat(body.resolved_at)
        effective_report_date = body.report_date or old_report["report_date"]
        if resolved_date < date.fromisoformat(effective_report_date):
            raise HTTPException(
                status_code=400,
                detail=f"Resolve date cannot be before the issue report date ({effective_report_date})",
            )
        if resolved_date > date.today():
            raise HTTPException(
                status_code=400, detail="Resolve date cannot be in the future"
            )

        updates["resolved_at"] = f"{body.resolved_at}T23:59:59"

    if not updates:
        return {"report": old_report}

    result = (
        supabase.table("system_status_reports")
        .update(updates)
        .eq("id", report_id)
        .execute()
    )

    updated = result.data[0] if result.data else None
    if updated and system_name:
        updated["system_name"] = system_name
    return {"report": updated}


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
        raise HTTPException(
            status_code=400, detail="Invalid date format. Use YYYY-MM-DD"
        )

    if sd > ed:
        raise HTTPException(status_code=400, detail="start_date must be <= end_date")

    total_days = (ed - sd).days + 1

    systems_list = await _get_active_systems()
    systems_to_check = [s["name"] for s in systems_list]
    system_ids = {s["name"]: s["id"] for s in systems_list}

    if system_name:
        sys_lookup = (
            supabase.table("systems").select("id").ilike("name", system_name).execute()
        )
        if not sys_lookup.data:
            raise HTTPException(
                status_code=400, detail=f"Unknown system: {system_name}"
            )
        systems_to_check = [system_name]
        system_ids = {system_name: sys_lookup.data[0]["id"]}

    query = (
        supabase.table("system_status_reports")
        .select("system_id, report_date, resolved_at")
        .lte("report_date", end_date)
        .or_(f"resolved_at.gte.{start_date},resolved_at.is.null")
    )
    if system_name and system_name in system_ids:
        query = query.eq("system_id", system_ids[system_name])

    result = query.execute()
    reports = result.data or []

    issues_by_system: dict[str, set[date]] = {}
    for r in reports:
        sn = None
        for name, sid in system_ids.items():
            if sid == r["system_id"]:
                sn = name
                break
        if not sn:
            continue
        if sn not in issues_by_system:
            issues_by_system[sn] = set()

        issue_start = max(date.fromisoformat(r["report_date"]), sd)
        if r.get("resolved_at"):
            resolved_date = date.fromisoformat(r["resolved_at"][:10])
            issue_end = min(resolved_date, ed)
        else:
            issue_end = min(date.today(), ed)

        d = issue_start
        while d <= issue_end:
            issues_by_system[sn].add(d)
            d += timedelta(days=1)

    report_data = []
    for sn in systems_to_check:
        days_with_issues = len(issues_by_system.get(sn, set()))
        downtime_pct = (
            round((days_with_issues / total_days) * 100, 1) if total_days > 0 else 0
        )
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
