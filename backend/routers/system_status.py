from collections import Counter
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from datetime import date, datetime, timedelta
from db import supabase

router = APIRouter()


async def _get_active_systems():
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
    asset_id: Optional[str] = None
    report_date: str  # YYYY-MM-DD
    notes: Optional[str] = ""
    reported_by: str
    reported_by_name: Optional[str] = ""


class UpdateIssueBody(BaseModel):
    notes: Optional[str] = None
    report_date: Optional[str] = None
    resolved_at: Optional[str] = None
    resolved_notes: Optional[str] = None


class ResolveIssueBody(BaseModel):
    resolved_by: str
    resolved_notes: Optional[str] = ""
    resolved_at: Optional[str] = None


async def _attach_asset_name(report: dict, assets_by_id: dict) -> dict:
    asset_id = report.get("asset_id")
    report["asset_name"] = assets_by_id.get(asset_id) if asset_id else None
    return report


async def _fetch_assets_by_id(asset_ids: list[str]) -> dict[str, str]:
    if not asset_ids:
        return {}
    result = (
        supabase.table("assets")
        .select("id, name")
        .in_("id", asset_ids)
        .execute()
    )
    return {r["id"]: r["name"] for r in (result.data or [])}


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
    rows = result.data or []

    system_level = {r["system_id"]: r for r in rows if r.get("asset_id") is None}
    asset_counts_by_system: dict[str, int] = {}
    for r in rows:
        if r.get("asset_id") is not None:
            sid = r["system_id"]
            asset_counts_by_system[sid] = asset_counts_by_system.get(sid, 0) + 1

    assets_by_id = await _fetch_assets_by_id(
        [r["asset_id"] for r in rows if r.get("asset_id")]
    )

    systems = []
    for sys in systems_list:
        report = system_level.get(sys["id"])
        enriched = await _attach_asset_name(report, assets_by_id) if report else None
        systems.append(
            {
                "system_id": sys["id"],
                "system_name": sys["name"],
                "status": "issue" if report else "operational",
                "active_report": enriched,
                "asset_issues_count": asset_counts_by_system.get(sys["id"], 0),
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
        .select("*, systems(name), assets(name)")
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

    asset_ids = [r["asset_id"] for r in reports if r.get("asset_id")]
    assets_by_id = await _fetch_assets_by_id(asset_ids)

    for r in reports:
        if "systems" in r and r["systems"]:
            r["system_name"] = r["systems"]["name"]
        if "systems" in r:
            del r["systems"]
        if "assets" in r:
            del r["assets"]
        await _attach_asset_name(r, assets_by_id)

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

    asset_name = None
    if body.asset_id:
        asset_lookup = (
            supabase.table("assets").select("id, name").eq("id", body.asset_id).execute()
        )
        if not asset_lookup.data:
            raise HTTPException(
                status_code=400, detail=f"Unknown asset: {body.asset_id}"
            )
        asset_name = asset_lookup.data[0]["name"]

        link_lookup = (
            supabase.table("asset_system_links")
            .select("id")
            .eq("system_id", system_id)
            .eq("asset_id", body.asset_id)
            .execute()
        )
        if not link_lookup.data:
            raise HTTPException(
                status_code=400,
                detail=f"Asset {asset_name} is not linked to system {body.system_name}",
            )

    existing = (
        supabase.table("system_status_reports")
        .select("id, asset_id")
        .eq("system_id", system_id)
        .eq("report_date", body.report_date)
        .is_("resolved_at", "null")
        .execute()
    )
    if body.asset_id:
        existing = [
            r for r in existing.data
            if r.get("asset_id") == body.asset_id
        ]
    else:
        existing = [r for r in existing.data if r.get("asset_id") is None]

    if existing:
        msg = (
            f"An unresolved issue already exists for {asset_name or body.system_name} on {body.report_date}"
            if body.asset_id
            else f"An unresolved issue already exists for {body.system_name} on {body.report_date}"
        )
        raise HTTPException(status_code=409, detail=msg)

    insert_payload = {
        "system_id": system_id,
        "report_date": body.report_date,
        "notes": body.notes or "",
        "reported_by": body.reported_by,
        "reported_by_name": body.reported_by_name or "",
    }
    if body.asset_id:
        insert_payload["asset_id"] = body.asset_id

    result = (
        supabase.table("system_status_reports")
        .insert(insert_payload)
        .execute()
    )

    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create report")

    result.data[0]["system_name"] = body.system_name
    await _attach_asset_name(result.data[0], {body.asset_id: asset_name} if asset_name else {})
    return {"report": result.data[0]}


@router.patch("/system-status/{report_id}/resolve")
async def resolve_issue(report_id: str, body: ResolveIssueBody):
    """Mark an issue as resolved."""
    existing = (
        supabase.table("system_status_reports")
        .select("id, resolved_at, report_date, asset_id")
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

    updated = result.data[0] if result.data else None
    if updated:
        asset_ids = [updated["asset_id"]] if updated.get("asset_id") else []
        assets_by_id = await _fetch_assets_by_id(asset_ids)
        await _attach_asset_name(updated, assets_by_id)
    return {"report": updated}


@router.patch("/system-status/{report_id}/unresolve")
async def unresolve_issue(report_id: str):
    """Reopen a resolved issue by clearing its resolution fields."""
    existing = (
        supabase.table("system_status_reports")
        .select("id, resolved_at, report_date, system_id, asset_id")
        .eq("id", report_id)
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Report not found")
    existing_report = existing.data[0]
    if not existing_report.get("resolved_at"):
        raise HTTPException(status_code=400, detail="Issue is not resolved")

    dup = (
        supabase.table("system_status_reports")
        .select("id, asset_id")
        .eq("system_id", existing_report["system_id"])
        .eq("report_date", existing_report["report_date"])
        .is_("resolved_at", "null")
        .neq("id", report_id)
        .execute()
    )
    asset_id = existing_report.get("asset_id")
    conflicts = [
        r for r in (dup.data or [])
        if (asset_id is None and r.get("asset_id") is None)
        or r.get("asset_id") == asset_id
    ]
    if conflicts:
        raise HTTPException(
            status_code=409,
            detail="Another unresolved issue already exists for this system on that date",
        )

    result = (
        supabase.table("system_status_reports")
        .update(
            {
                "resolved_at": None,
                "resolved_by": None,
                "resolved_notes": "",
            }
        )
        .eq("id", report_id)
        .execute()
    )

    updated = result.data[0] if result.data else None
    if updated:
        asset_ids = [updated["asset_id"]] if updated.get("asset_id") else []
        assets_by_id = await _fetch_assets_by_id(asset_ids)
        await _attach_asset_name(updated, assets_by_id)
    return {"report": updated}


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
    old_asset_id = old_report.get("asset_id")

    updates = {}
    if body.notes is not None:
        updates["notes"] = body.notes
    if body.report_date is not None:
        if body.report_date != old_report["report_date"]:
            dup = (
                supabase.table("system_status_reports")
                .select("id, asset_id")
                .eq("system_id", system_id)
                .eq("report_date", body.report_date)
                .is_("resolved_at", "null")
                .neq("id", report_id)
                .execute()
            )
            if old_asset_id:
                dup = [r for r in dup.data if r.get("asset_id") == old_asset_id]
            else:
                dup = [r for r in dup.data if r.get("asset_id") is None]
            if dup:
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
    if body.resolved_notes is not None:
        if old_report["resolved_at"] is None:
            raise HTTPException(
                status_code=400,
                detail="Cannot edit resolve notes on an unresolved issue",
            )
        updates["resolved_notes"] = body.resolved_notes

    if not updates:
        return {"report": old_report}

    result = (
        supabase.table("system_status_reports")
        .update(updates)
        .eq("id", report_id)
        .execute()
    )

    updated = result.data[0] if result.data else None
    if updated:
        if system_name:
            updated["system_name"] = system_name
        asset_ids = [updated["asset_id"]] if updated.get("asset_id") else []
        assets_by_id = await _fetch_assets_by_id(asset_ids)
        await _attach_asset_name(updated, assets_by_id)
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
        sid = system_ids[sn]
        days_with_issues = len(issues_by_system.get(sn, set()))
        downtime_pct = (
            round((days_with_issues / total_days) * 100, 1) if total_days > 0 else 0
        )
        uptime_pct = round(100 - downtime_pct, 1)

        asset_links_result = (
            supabase.table("asset_system_links")
            .select("asset_id, role, site")
            .eq("system_id", sid)
            .execute()
        )
        asset_links = asset_links_result.data or []
        asset_ids = [l["asset_id"] for l in asset_links]
        assets_by_id = await _fetch_assets_by_id(asset_ids)

        if not asset_ids:
            report_data.append(
                {
                    "system_name": sn,
                    "total_days": total_days,
                    "days_with_issues": days_with_issues,
                    "uptime_pct": uptime_pct,
                    "downtime_pct": downtime_pct,
                    "assets": [],
                }
            )
            continue

        asset_reports_result = (
            supabase.table("system_status_reports")
            .select("asset_id, report_date, resolved_at")
            .eq("system_id", sid)
            .in_("asset_id", asset_ids)
            .lte("report_date", end_date)
            .or_(f"resolved_at.gte.{start_date},resolved_at.is.null")
            .execute()
        )
        asset_reports = asset_reports_result.data or []

        issues_by_asset: dict[str, set[date]] = {}
        for r in asset_reports:
            aid = r.get("asset_id")
            if not aid:
                continue
            if aid not in issues_by_asset:
                issues_by_asset[aid] = set()
            issue_start = max(date.fromisoformat(r["report_date"]), sd)
            if r.get("resolved_at"):
                resolved_date = date.fromisoformat(r["resolved_at"][:10])
                issue_end = min(resolved_date, ed)
            else:
                issue_end = min(date.today(), ed)
            d = issue_start
            while d <= issue_end:
                issues_by_asset[aid].add(d)
                d += timedelta(days=1)

        asset_uptime_list = []
        for link in asset_links:
            aid = link["asset_id"]
            a_days_with_issues = len(issues_by_asset.get(aid, set()))
            a_downtime_pct = (
                round((a_days_with_issues / total_days) * 100, 1)
                if total_days > 0
                else 0
            )
            asset_uptime_list.append(
                {
                    "asset_id": aid,
                    "asset_name": assets_by_id.get(aid),
                    "role": link.get("role", ""),
                    "site": link.get("site", ""),
                    "total_days": total_days,
                    "days_with_issues": a_days_with_issues,
                    "uptime_pct": round(100 - a_downtime_pct, 1),
                    "downtime_pct": a_downtime_pct,
                }
            )

        report_data.append(
            {
                "system_name": sn,
                "total_days": total_days,
                "days_with_issues": days_with_issues,
                "uptime_pct": uptime_pct,
                "downtime_pct": downtime_pct,
                "assets": asset_uptime_list,
            }
        )

    return {"start_date": start_date, "end_date": end_date, "systems": report_data}


@router.get("/system-status/systems/{system_id}/assets")
async def get_system_assets(system_id: str):
    """Return assets linked to a system with their current status."""
    sys_lookup = (
        supabase.table("systems").select("id, name").eq("id", system_id).execute()
    )
    if not sys_lookup.data:
        raise HTTPException(status_code=404, detail="System not found")
    system_name = sys_lookup.data[0]["name"]

    links_result = (
        supabase.table("asset_system_links")
        .select("asset_id, role, site, assets(name)")
        .eq("system_id", system_id)
        .execute()
    )
    links = links_result.data or []

    asset_ids = [link["asset_id"] for link in links]
    assets_by_id = await _fetch_assets_by_id(asset_ids)

    if not asset_ids:
        return {"system_id": system_id, "system_name": system_name, "assets": []}

    open_reports_result = (
        supabase.table("system_status_reports")
        .select("*")
        .eq("system_id", system_id)
        .is_("resolved_at", "null")
        .in_("asset_id", asset_ids)
        .order("created_at", desc=False)
        .execute()
    )
    open_reports = open_reports_result.data or []
    oldest_open: dict[str, dict] = {}
    for r in open_reports:
        aid = r.get("asset_id")
        if aid and aid not in oldest_open:
            oldest_open[aid] = r

    for r in open_reports:
        await _attach_asset_name(r, assets_by_id)

    role_order = {"primary": 0, "standby": 1, "client": 2}
    assets = []
    for link in sorted(
        links,
        key=lambda l: (role_order.get(l.get("role", ""), 3), assets_by_id.get(l["asset_id"], "")),
    ):
        aid = link["asset_id"]
        active = oldest_open.get(aid)
        assets.append(
            {
                "asset_id": aid,
                "asset_name": assets_by_id.get(aid),
                "role": link.get("role", ""),
                "site": link.get("site", ""),
                "status": "issue" if active else "operational",
                "active_report": active,
            }
        )

    return {"system_id": system_id, "system_name": system_name, "assets": assets}
