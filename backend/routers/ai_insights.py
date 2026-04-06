from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from datetime import datetime, timedelta
import httpx

from db import supabase
from utils.activity import log_activity

router = APIRouter()

OLLAMA_MODEL = "gemma4:e2b"
OLLAMA_URL = "http://localhost:11434/api/generate"
OLLAMA_TIMEOUT = 60

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
    "International Circuits - Bahrain",
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


class AiInsightRequest(BaseModel):
    insight_type: str
    date_range_days: int = 30
    language: str = "en"


def _strip_preamble(text: str) -> str:
    lines = text.split("\n")
    preamble_phrases = [
        "here",
        "sure",
        "of course",
        "certainly",
        "below",
        "i'd",
        "i would",
        "بالتأكيد",
        "إليك",
        "بالطبع",
        "حسناً",
    ]
    start_idx = 0
    for i, line in enumerate(lines):
        stripped = line.strip().lower()
        if not stripped:
            start_idx = i + 1
            continue
        is_preamble = False
        for phrase in preamble_phrases:
            if stripped.startswith(phrase):
                is_preamble = True
                break
        if is_preamble:
            start_idx = i + 1
        else:
            break
    result = "\n".join(lines[start_idx:]).strip()
    if not result:
        return text.strip()
    return result


def _aggregate_work_order_stats(days: int) -> dict:
    cutoff_date = datetime.now() - timedelta(days=days)

    wo_result = (
        supabase.table("work_orders")
        .select("status, type, department_id, location, created_at, closed_at")
        .gte("created_at", cutoff_date.isoformat())
        .execute()
    )
    data = wo_result.data or []

    dept_result = supabase.table("departments").select("id, name").execute()
    dept_map = {d["id"]: d["name"] for d in (dept_result.data or [])}

    total = len(data)

    # Count by status
    by_status = {}
    for status in ["Pending", "In Progress", "Resolved", "Closed"]:
        by_status[status] = 0
    for wo in data:
        s = wo.get("status", "")
        if s in by_status:
            by_status[s] += 1

    # Count by type
    by_type = {}
    for t in ["Technical", "Inspection", "Other"]:
        by_type[t] = 0
    for wo in data:
        t = wo.get("type", "")
        if t in by_type:
            by_type[t] += 1

    # Count by department
    dept_counts = {}
    for wo in data:
        did = wo.get("department_id")
        if did:
            name = dept_map.get(did, f"Unknown ({did})")
            dept_counts[name] = dept_counts.get(name, 0) + 1
    by_department = sorted(
        [{"name": k, "count": v} for k, v in dept_counts.items()],
        key=lambda x: x["count"],
        reverse=True,
    )

    # Average resolution hours
    resolution_hours = []
    for wo in data:
        if wo.get("created_at") and wo.get("closed_at"):
            try:
                created = datetime.fromisoformat(wo["created_at"].replace("Z", "+00:00"))
                closed = datetime.fromisoformat(wo["closed_at"].replace("Z", "+00:00"))
                hours = (closed - created).total_seconds() / 3600
                if hours >= 0:
                    resolution_hours.append(hours)
            except (ValueError, TypeError):
                continue
    avg_resolution_hours = (
        round(sum(resolution_hours) / len(resolution_hours), 1)
        if resolution_hours
        else None
    )

    # Weekly volumes
    week_counts = {}
    for wo in data:
        if wo.get("created_at"):
            try:
                dt = datetime.fromisoformat(wo["created_at"].replace("Z", "+00:00"))
                iso_cal = dt.isocalendar()
                week_key = f"{iso_cal[0]}-W{iso_cal[1]:02d}"
                week_counts[week_key] = week_counts.get(week_key, 0) + 1
            except (ValueError, TypeError):
                continue
    weekly_volumes = sorted(
        [{"week": k, "count": v} for k, v in week_counts.items()],
        key=lambda x: x["week"],
    )

    # Top locations
    loc_counts = {}
    for wo in data:
        loc = wo.get("location")
        if loc and loc.strip():
            loc_counts[loc.strip()] = loc_counts.get(loc.strip(), 0) + 1
    top_locations = sorted(
        [{"location": k, "count": v} for k, v in loc_counts.items()],
        key=lambda x: x["count"],
        reverse=True,
    )[:5]

    return {
        "total": total,
        "by_status": by_status,
        "by_type": by_type,
        "by_department": by_department,
        "avg_resolution_hours": avg_resolution_hours,
        "weekly_volumes": weekly_volumes,
        "top_locations": top_locations,
    }


def _aggregate_system_status_stats(days: int) -> dict:
    cutoff_date = datetime.now() - timedelta(days=days)

    reports_result = (
        supabase.table("system_status_reports")
        .select("system_name, report_date, notes, resolved_at, resolved_notes")
        .gte("report_date", cutoff_date.isoformat())
        .execute()
    )
    reports = reports_result.data or []

    unresolved_result = (
        supabase.table("system_status_reports")
        .select("system_name, report_date, notes")
        .is_("resolved_at", "null")
        .execute()
    )
    unresolved = unresolved_result.data or []

    currently_unresolved = [
        {
            "system_name": r["system_name"],
            "report_date": r["report_date"],
            "notes": r.get("notes", ""),
        }
        for r in unresolved
    ]

    # Issues per system
    system_counts = {}
    for r in reports:
        sn = r["system_name"]
        system_counts[sn] = system_counts.get(sn, 0) + 1
    issues_per_system = sorted(
        [{"system_name": k, "count": v} for k, v in system_counts.items()],
        key=lambda x: x["count"],
        reverse=True,
    )

    # Average resolution hours per system
    resolution_by_system: dict[str, list[float]] = {}
    for r in reports:
        if r.get("resolved_at") and r.get("report_date"):
            try:
                report_dt = datetime.fromisoformat(r["report_date"])
                resolved_dt = datetime.fromisoformat(
                    r["resolved_at"].replace("Z", "+00:00")
                )
                # report_date may be date-only (YYYY-MM-DD), make it timezone-naive
                if report_dt.tzinfo is None and resolved_dt.tzinfo is not None:
                    resolved_dt = resolved_dt.replace(tzinfo=None)
                hours = (resolved_dt - report_dt).total_seconds() / 3600
                if hours >= 0:
                    sn = r["system_name"]
                    if sn not in resolution_by_system:
                        resolution_by_system[sn] = []
                    resolution_by_system[sn].append(hours)
            except (ValueError, TypeError):
                continue
    avg_resolution_hours_per_system = {
        sn: round(sum(hrs) / len(hrs), 1)
        for sn, hrs in resolution_by_system.items()
        if hrs
    }

    # Clean systems (zero issues in the period)
    systems_with_issues = set(system_counts.keys())
    clean_systems = [s for s in ALLOWED_SYSTEMS if s not in systems_with_issues]

    # Worst systems (top 5 by issue count)
    worst_systems = issues_per_system[:5]

    return {
        "currently_unresolved": currently_unresolved,
        "issues_per_system": issues_per_system,
        "avg_resolution_hours_per_system": avg_resolution_hours_per_system,
        "clean_systems": clean_systems,
        "worst_systems": worst_systems,
    }


def _build_overview_prompt(wo_stats: dict, sys_stats: dict, language: str) -> str:
    busiest_dept = (
        wo_stats["by_department"][0]["name"] if wo_stats["by_department"] else "N/A"
    )
    top_locs = ", ".join(
        loc["location"] for loc in wo_stats["top_locations"]
    ) or "N/A"
    down_systems = [
        item["system_name"] for item in sys_stats["currently_unresolved"]
    ]
    down_names = ", ".join(down_systems) if down_systems else "None"
    worst_system = (
        sys_stats["worst_systems"][0]["system_name"]
        if sys_stats["worst_systems"]
        else "N/A"
    )
    total_issues = sum(
        item["count"] for item in sys_stats["issues_per_system"]
    )

    prompt = (
        "You are an operations analyst for a civil aviation technical department.\n\n"
        "### Work Order Data\n"
        f"- Total work orders: {wo_stats['total']}\n"
        f"- By status: {wo_stats['by_status']}\n"
        f"- By type: {wo_stats['by_type']}\n"
        f"- Average resolution time: {wo_stats['avg_resolution_hours']} hours\n"
        f"- Busiest department: {busiest_dept}\n"
        f"- Top locations: {top_locs}\n\n"
        "### System Status\n"
        f"- Currently unresolved issues: {len(sys_stats['currently_unresolved'])}\n"
        f"- Systems currently down: {down_names}\n"
        f"- Total issues in period: {total_issues}\n"
        f"- Worst system: {worst_system}\n\n"
        "Provide 3-5 concise bullet points summarizing operational health. "
        "No preamble, greeting, or commentary."
    )

    if language == "ar":
        prompt += "\nRespond entirely in Arabic."

    return prompt


def _build_system_status_prompt(sys_stats: dict, language: str) -> str:
    lines = [
        "You are a systems reliability analyst for civil aviation infrastructure.\n",
        "SYSTEMS WITH ISSUES:",
    ]
    for item in sys_stats["issues_per_system"]:
        avg_hrs = sys_stats["avg_resolution_hours_per_system"].get(item["system_name"], "N/A")
        lines.append(f"- {item['system_name']}: {item['count']} issues, avg resolution {avg_hrs}h")

    lines.append("\nCURRENTLY UNRESOLVED:")
    for item in sys_stats["currently_unresolved"]:
        lines.append(f"- {item['system_name']} (reported {item['report_date']}): {item.get('notes', '')}")

    clean_joined = ", ".join(sys_stats["clean_systems"]) if sys_stats["clean_systems"] else "None"
    lines.append(f"\nSYSTEMS WITH ZERO ISSUES: {clean_joined}")

    lines.append(
        "\nWrite 3-5 concise bullet points identifying which systems need attention, "
        "any patterns in failures, and which systems are performing well. "
        "Be specific with system names and numbers. No preamble."
    )

    prompt = "\n".join(lines)
    if language == "ar":
        prompt += "\nRespond entirely in Arabic."
    return prompt


def _build_trends_prompt(wo_stats: dict, sys_stats: dict, language: str) -> str:
    lines = [
        "You are an operations trend analyst for a civil aviation maintenance department.\n",
        "WEEKLY WORK ORDER VOLUME:",
    ]
    for item in wo_stats["weekly_volumes"]:
        lines.append(f"- {item['week']}: {item['count']}")

    lines.append("\nRECURRING SYSTEM ISSUES (2+ in period):")
    recurring = [s for s in sys_stats["issues_per_system"] if s["count"] >= 2]
    for item in recurring:
        lines.append(f"- {item['system_name']}: {item['count']} issues")

    lines.append("\nDEPARTMENT WORKLOAD:")
    for item in wo_stats["by_department"]:
        lines.append(f"- {item['name']}: {item['count']}")

    avg_res = wo_stats["avg_resolution_hours"] if wo_stats["avg_resolution_hours"] is not None else "N/A"
    lines.append(f"\nRESOLUTION TIMES: Average: {avg_res}h")

    lines.append(
        "\nWrite 3-5 concise bullet points about trends, patterns, or concerns. "
        "Flag anything getting worse. No preamble."
    )

    prompt = "\n".join(lines)
    if language == "ar":
        prompt += "\nRespond entirely in Arabic."
    return prompt


@router.post("/ai/insights")
async def get_insights(
    request: AiInsightRequest,
    email: str = Query(...),
    user_role: str = Query(...),
):
    if user_role not in ("admin", "supervisor"):
        raise HTTPException(status_code=403, detail="Admin or supervisor access required")

    if request.insight_type not in ("overview", "system_status", "trends"):
        raise HTTPException(
            status_code=422,
            detail=f"Invalid insight_type '{request.insight_type}'. Must be one of: overview, system_status, trends",
        )

    wo_stats = _aggregate_work_order_stats(request.date_range_days)

    if wo_stats["total"] < 5:
        raise HTTPException(
            status_code=422,
            detail="Not enough data for meaningful analysis. Try a wider date range.",
        )

    sys_stats = _aggregate_system_status_stats(request.date_range_days)

    if request.insight_type == "overview":
        prompt = _build_overview_prompt(wo_stats, sys_stats, request.language)
    elif request.insight_type == "system_status":
        prompt = _build_system_status_prompt(sys_stats, request.language)
    elif request.insight_type == "trends":
        prompt = _build_trends_prompt(wo_stats, sys_stats, request.language)

    try:
        async with httpx.AsyncClient(timeout=OLLAMA_TIMEOUT) as client:
            res = await client.post(
                OLLAMA_URL,
                json={"model": OLLAMA_MODEL, "prompt": prompt, "stream": False},
            )
    except (httpx.ConnectError, httpx.ConnectTimeout):
        raise HTTPException(
            status_code=503, detail="AI service is currently unavailable"
        )
    except httpx.ReadTimeout:
        raise HTTPException(status_code=503, detail="AI service timed out")

    if res.status_code != 200:
        raise HTTPException(status_code=502, detail="AI model error")

    try:
        data = res.json()
        response_text = data.get("response", "")
    except Exception:
        raise HTTPException(status_code=502, detail="AI model error")

    stripped = _strip_preamble(response_text)
    if not stripped:
        raise HTTPException(
            status_code=502, detail="AI model returned an empty response"
        )

    log_activity(email, "ai", "generated_insight", target_label=request.insight_type)

    down_count = len(sys_stats["currently_unresolved"])

    data_summary = {
        "total_work_orders": wo_stats["total"],
        "pending": wo_stats["by_status"].get("Pending", 0),
        "in_progress": wo_stats["by_status"].get("In Progress", 0),
        "closed": wo_stats["by_status"].get("Closed", 0),
        "systems_down": down_count,
        "date_range_days": request.date_range_days,
    }

    if request.insight_type == "system_status":
        data_summary["systems_with_issues"] = len(sys_stats["issues_per_system"])
        data_summary["currently_unresolved"] = len(sys_stats["currently_unresolved"])
    elif request.insight_type == "trends":
        data_summary["recurring_systems"] = len(
            [s for s in sys_stats["issues_per_system"] if s["count"] >= 2]
        )
        data_summary["weeks_analyzed"] = len(wo_stats["weekly_volumes"])

    return {
        "insight": stripped,
        "generated_at": datetime.utcnow().isoformat() + "Z",
        "data_summary": data_summary,
    }
