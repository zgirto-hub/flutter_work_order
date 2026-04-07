from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List
import os
import httpx
import json
from datetime import date
from db import supabase
from utils.activity import log_activity

router = APIRouter(tags=["search"])

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434/api/generate")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "gemma4:e2b")
OLLAMA_TIMEOUT = float(os.getenv("OLLAMA_TIMEOUT", "60.0"))

VALID_STATUSES = ["Pending", "In Progress", "Resolved", "Closed"]
VALID_TYPES = ["Technical", "Inspection", "Other"]


class NLSearchRequest(BaseModel):
    query: str = ""
    email: str
    user_role: str
    limit: Optional[int] = 30
    offset: int = 0
    filters: Optional[dict] = None


def _build_nl_prompt(query: str, departments: List[str], today: str) -> str:
    prompt = "You are a work order search filter parser.\n"
    prompt += f"Today's date: {today}\n"
    prompt += (
        "Extract structured filters from the user's natural language search query.\n"
    )
    prompt += "Valid statuses: " + ", ".join(VALID_STATUSES) + "\n"
    prompt += "Valid types: " + ", ".join(VALID_TYPES) + "\n"
    if departments:
        prompt += "Valid departments: " + ", ".join(departments) + "\n"
    prompt += "The user may write in English or Arabic. Extract filters regardless of language.\n"
    prompt += "Output ONLY a JSON object with these nullable fields: status, type, department, location, date_from (ISO date), date_to (ISO date), min_resolution_days (number).\n"
    prompt += "Only include fields the user explicitly mentioned. Use null for unmentioned fields.\n"
    prompt += "Resolve relative dates like 'last week', 'this month', 'from last month' to actual dates relative to today's date.\n"
    prompt += "Do not add any text before or after the JSON.\n"
    prompt += f"User query: {query}"
    return prompt


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


async def _parse_query_with_ai(query: str, departments: List[str]) -> Optional[dict]:
    today = date.today().isoformat()
    prompt = _build_nl_prompt(query, departments, today)

    try:
        async with httpx.AsyncClient(timeout=OLLAMA_TIMEOUT) as client:
            res = await client.post(
                OLLAMA_URL,
                json={"model": OLLAMA_MODEL, "prompt": prompt, "stream": False},
            )
        if res.status_code != 200:
            return None
        data = res.json()
        response_text = data.get("response", "")
    except Exception:
        return None

    stripped = _strip_preamble(response_text)
    try:
        parsed = json.loads(stripped)
        return parsed
    except Exception:
        return None


def _validate_filters(raw_filters: dict, departments_from_db: List[dict]) -> dict:
    validated = {}

    status = raw_filters.get("status")
    if status and status in VALID_STATUSES:
        validated["status"] = status
    else:
        validated["status"] = None

    type_val = raw_filters.get("type")
    if type_val and type_val in VALID_TYPES:
        validated["type"] = type_val
    else:
        validated["type"] = None

    dept_name = raw_filters.get("department")
    validated["department_id"] = None
    validated["department"] = None
    if dept_name and departments_from_db:
        dept_name_lower = dept_name.lower()
        for dept in departments_from_db:
            if dept_name_lower in dept.get("name", "").lower():
                validated["department_id"] = dept.get("id")
                validated["department"] = dept.get("name")
                break

    location = raw_filters.get("location")
    validated["location"] = location if location else None

    date_from = raw_filters.get("date_from")
    date_to = raw_filters.get("date_to")
    if date_from:
        try:
            from datetime import datetime

            datetime.fromisoformat(date_from.replace("Z", ""))
            validated["date_from"] = date_from
        except Exception:
            validated["date_from"] = None
    else:
        validated["date_from"] = None

    if date_to:
        try:
            from datetime import datetime

            datetime.fromisoformat(date_to.replace("Z", ""))
            validated["date_to"] = date_to
        except Exception:
            validated["date_to"] = None
    else:
        validated["date_to"] = None

    if validated.get("date_from") and validated.get("date_to"):
        if validated["date_from"] > validated["date_to"]:
            validated["date_from"] = None
            validated["date_to"] = None

    min_res = raw_filters.get("min_resolution_days")
    if min_res and isinstance(min_res, (int, float)) and min_res > 0:
        validated["min_resolution_days"] = float(min_res)
    else:
        validated["min_resolution_days"] = None

    return validated


def _get_user_by_email(email: str) -> Optional[dict]:
    try:
        result = (
            supabase.table("users")
            .select("id, email, user_type, department_id")
            .eq("email", email)
            .execute()
        )
        if result.data:
            return result.data[0]
    except Exception:
        pass
    return None


def _get_user_id_by_email(email: str) -> Optional[str]:
    user = _get_user_by_email(email)
    if user:
        return user.get("id")
    return None


def _apply_role_filter(query_db, email: str, user_role: str):
    """Apply role-based filtering at the Supabase query level where possible."""
    if user_role == "reporter" and email:
        reporter_user_id = _get_user_id_by_email(email)
        if reporter_user_id:
            query_db = query_db.eq("created_by", reporter_user_id)
        else:
            query_db = query_db.eq("created_by", "00000000-0000-0000-0000-000000000000")
    elif user_role == "technician" and email:
        tech_user = _get_user_by_email(email)
        if tech_user and tech_user.get("department_id"):
            query_db = query_db.eq("department_id", tech_user["department_id"])
        else:
            query_db = query_db.eq("department_id", "00000000-0000-0000-0000-000000000000")
    return query_db


def _base_wo_query():
    return supabase.table("work_orders").select("""
        *,
        creator:users!work_orders_created_by_fkey!left (
            full_name,
            email
        ),
        departments!work_orders_department_id_fkey!left (
            id,
            name,
            is_active
        ),
        work_order_assignments!left (
            technician_id,
            assigned_at,
            assigned_by,
            users!work_order_assignments_technician_id_fkey!left (
                id,
                email,
                full_name
            )
        )
    """).order("created_at", desc=True)


def _keyword_search(
    query: str, email: str, user_role: str, limit: int, offset: int
) -> dict:
    query_db = _base_wo_query()
    query_db = _apply_role_filter(query_db, email, user_role)
    query_db = query_db.or_(
        f"job_no.ilike.%{query}%,title.ilike.%{query}%,description.ilike.%{query}%"
    )

    try:
        result = query_db.execute()
    except Exception:
        return {"work_orders": [], "total": 0, "filters": None, "fallback": True}

    work_orders = result.data or []
    total = len(work_orders)
    work_orders = work_orders[offset:]
    if limit:
        work_orders = work_orders[:limit]

    return {
        "work_orders": work_orders,
        "total": total,
        "filters": None,
        "fallback": True,
    }


def _filtered_search(
    filters: dict, email: str, user_role: str, limit: int, offset: int
) -> dict:
    query_db = _base_wo_query()
    query_db = _apply_role_filter(query_db, email, user_role)

    status = filters.get("status")
    if status:
        query_db = query_db.eq("status", status)

    type_val = filters.get("type")
    if type_val:
        query_db = query_db.eq("type", type_val)

    dept_id = filters.get("department_id")
    if dept_id:
        query_db = query_db.eq("department_id", dept_id)

    location = filters.get("location")
    if location:
        query_db = query_db.ilike("location", f"%{location}%")

    date_from = filters.get("date_from")
    if date_from:
        query_db = query_db.gte("created_at", date_from)

    date_to = filters.get("date_to")
    if date_to:
        query_db = query_db.lte("created_at", date_to)

    try:
        result = query_db.execute()
    except Exception:
        return {"work_orders": [], "total": 0, "filters": None, "fallback": True}

    work_orders = result.data or []

    # min_resolution_days must be filtered in Python (computed from two columns)
    if filters.get("min_resolution_days"):
        min_days = filters["min_resolution_days"]
        from datetime import datetime

        filtered = []
        for wo in work_orders:
            if wo.get("closed_at") and wo.get("created_at"):
                try:
                    closed = datetime.fromisoformat(wo["closed_at"].replace("Z", "+00:00"))
                    created = datetime.fromisoformat(wo["created_at"].replace("Z", "+00:00"))
                    if (closed - created).days >= min_days:
                        filtered.append(wo)
                except Exception:
                    pass
        work_orders = filtered

    total = len(work_orders)
    work_orders = work_orders[offset:]
    if limit:
        work_orders = work_orders[:limit]

    response_filters = {
        "status": filters.get("status"),
        "type": filters.get("type"),
        "department": filters.get("department"),
        "location": filters.get("location"),
        "date_from": filters.get("date_from"),
        "date_to": filters.get("date_to"),
        "min_resolution_days": filters.get("min_resolution_days"),
    }

    return {
        "work_orders": work_orders,
        "total": total,
        "filters": response_filters,
        "fallback": False,
    }


@router.post("/search/nl")
async def nl_search(request: NLSearchRequest):
    query = request.query.strip() if request.query else ""
    user_role = request.user_role
    email = request.email

    if user_role not in ["admin", "supervisor", "technician", "reporter"]:
        raise HTTPException(status_code=422, detail="Invalid user role")

    try:
        dept_result = supabase.table("departments").select("id, name").execute()
        departments = dept_result.data or []
    except Exception:
        departments = []

    # Direct filter re-query (chip removal path) — no query text needed
    if request.filters:
        validated = _validate_filters(request.filters, departments)
        result = _filtered_search(
            validated, email, user_role, request.limit, request.offset
        )
        log_activity(
            email, "search", "nl_search", target_label="filters", detail="direct"
        )
        return result

    # NL query path — query text is required
    if not query:
        raise HTTPException(status_code=422, detail="Query must not be empty")

    ai_result = await _parse_query_with_ai(query, [d["name"] for d in departments])

    if not ai_result:
        result = _keyword_search(query, email, user_role, request.limit, request.offset)
        log_activity(
            email, "search", "nl_search", target_label=query, detail="keyword_fallback"
        )
        return result

    has_filters = any(v is not None for v in ai_result.values())
    if not has_filters:
        result = _keyword_search(query, email, user_role, request.limit, request.offset)
        log_activity(
            email, "search", "nl_search", target_label=query, detail="no_filters"
        )
        return result

    validated = _validate_filters(ai_result, departments)
    result = _filtered_search(
        validated, email, user_role, request.limit, request.offset
    )
    log_activity(email, "search", "nl_search", target_label=query, detail="ai")
    return result
