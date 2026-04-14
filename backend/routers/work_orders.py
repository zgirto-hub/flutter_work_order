from fastapi import (
    APIRouter,
    Query,
    HTTPException,
    UploadFile,
    File,
    Form,
    BackgroundTasks,
)
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
import os
import uuid
import io
import traceback
import sys

from PIL import Image, ImageOps
from db import supabase
from utils.activity import log_activity
from utils.notification_service import dispatch_work_order_comment_notification
from services.entity_extractor import extract_entities
import asyncio

router = APIRouter()

UPLOAD_DIR = "uploaded_files"

MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
MAX_IMAGE_DIMENSION = 1920
ALLOWED_EXTENSIONS = {"pdf", "doc", "docx", "jpg", "jpeg", "png", "gif"}
IMAGE_EXTENSIONS = {"jpg", "jpeg", "png", "gif"}

ALLOWED_TYPES = {"Technical", "Inspection", "Other"}
ALLOWED_STATUSES = {"Pending", "In Progress", "Resolved", "Closed"}
VALID_OUTCOMES = ("Resolved", "Pending Parts", "Escalated", "Monitoring")

# --------------------
# Pydantic Models
# --------------------


class CreateWorkOrderBody(BaseModel):
    job_no: str
    title: str
    description: Optional[str] = ""
    location: Optional[str] = ""
    mobile_number: Optional[str] = ""
    department_id: str
    type: Optional[str] = "Technical"
    status: Optional[str] = "Pending"
    created_by: str
    created_by_email: Optional[str] = ""
    assigned_technician_id: Optional[str] = None
    asset_name: Optional[str] = None
    fault_description: Optional[str] = None
    action_taken: Optional[str] = None
    outcome: Optional[str] = None
    notes: Optional[str] = None


class UpdateWorkOrderBody(BaseModel):
    job_no: str
    title: str
    description: Optional[str] = ""
    location: str
    mobile_number: Optional[str] = ""
    department_id: str
    type: str
    status: str
    assigned_technician_id: Optional[str] = None
    created_by: Optional[str] = None
    created_at: Optional[str] = None
    closed_at: Optional[str] = None


class CloseWorkOrderBody(BaseModel):
    closed_by: str  # user UUID
    tech_notes: Optional[str] = None


class AddCommentBody(BaseModel):
    author_email: str
    author_name: str
    body: str
    type: str = "comment"
    meta: Optional[dict] = None


# --------------------
# Helpers
# --------------------


def _get_user_by_email(email: str) -> Optional[dict]:
    normalized = email.strip().lower()
    if not normalized:
        return None
    result = supabase.table("users").select("*").eq("email", normalized).execute()
    return result.data[0] if result.data else None


def _get_user_by_id(user_id: str) -> Optional[dict]:
    result = supabase.table("users").select("*").eq("id", user_id).execute()
    return result.data[0] if result.data else None


def _get_user_role(email: str) -> str:
    user = _get_user_by_email(email)
    if not user:
        raise HTTPException(status_code=403, detail="User not found")
    return (user.get("user_type") or "reporter").strip().lower()


def _get_user_id_by_email(email: str) -> Optional[str]:
    user = _get_user_by_email(email)
    if user:
        return user.get("id")
    return None


def _get_user_by_auth_id(auth_id: str) -> Optional[dict]:
    if not auth_id:
        return None
    result = supabase.table("users").select("*").eq("auth_id", auth_id).execute()
    return result.data[0] if result.data else None


def _get_technicians_by_department(department_id: str) -> List[str]:
    """Get list of technician user IDs that belong to a specific department"""
    result = (
        supabase.table("users")
        .select("id")
        .eq("department_id", department_id)
        .eq("user_type", "technician")
        .eq("is_active", True)
        .execute()
    )
    return [str(r.get("id")) for r in (result.data or []) if r.get("id")]


def _get_user_department_id(user_id: str) -> Optional[str]:
    """Get the department_id for a user"""
    if not user_id:
        return None
    result = supabase.table("users").select("department_id").eq("id", user_id).execute()
    return result.data[0].get("department_id") if result.data else None


def _ensure_not_reporter(email: str):
    if _get_user_role(email) == "reporter":
        raise HTTPException(
            status_code=403,
            detail="Reporter is not allowed to modify or delete work orders",
        )


def _validate_type(type: Optional[str]):
    if type is not None and type not in ALLOWED_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid type. Must be one of: {', '.join(ALLOWED_TYPES)}",
        )


def _validate_status(status: Optional[str]):
    if status is not None and status not in ALLOWED_STATUSES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid status. Must be one of: {', '.join(ALLOWED_STATUSES)}",
        )


def _fetch_full_work_order(work_order_id: str):
    # Updated query to include department details via JOIN
    result = (
        supabase.table("work_orders")
        .select("""
        *,
        creator:users!work_orders_created_by_fkey (
            full_name,
            email
        ),
        departments!work_orders_department_id_fkey (
            id,
            name,
            is_active
        ),
        work_order_assignments (
            technician_id,
            assigned_at,
            assigned_by,
            users!work_order_assignments_technician_id_fkey (
                id,
                email,
                full_name
            )
        )
    """)
        .eq("id", work_order_id)
        .execute()
    )
    if not result.data:
        return None
    data = result.data[0]
    # If the FK join didn't resolve creator (e.g. created_by stores auth UUID),
    # fall back to looking up the user by their auth_id
    if not data.get("creator") and data.get("created_by"):
        fallback_user = _get_user_by_auth_id(data["created_by"])
        if fallback_user:
            data["creator"] = {
                "full_name": fallback_user.get("full_name"),
                "email": fallback_user.get("email"),
            }
    return data


def _sync_single_technician(
    work_order_id: str, technician_id: Optional[str], assigned_by: str
):
    """Sync single technician assignment for a work order"""
    try:
        supabase.table("work_order_assignments").delete().eq(
            "work_order_id", work_order_id
        ).execute()
        if technician_id:
            supabase.table("work_order_assignments").insert(
                {
                    "work_order_id": work_order_id,
                    "technician_id": technician_id,
                    "assigned_by": assigned_by,
                }
            ).execute()
    except Exception as e:
        print(f"[_sync_single_technician] Failed for WO {work_order_id}: {e}")
        raise


def _log_assignment_changes(
    work_order_id: str,
    old_ids: List[str],
    new_ids: List[str],
    changed_by_email: str,
    changed_by_name: str,
):
    """Insert system comments for added/removed technician assignments."""
    old_set = set(old_ids)
    new_set = set(new_ids)
    added = new_set - old_set
    removed = old_set - new_set

    if not added and not removed:
        return

    # Fetch names for affected IDs in one query
    affected_ids = list(added | removed)
    users_result = (
        supabase.table("users")
        .select("id, full_name, email")
        .in_("id", affected_ids)
        .execute()
    )
    user_map = {
        u["id"]: (u.get("full_name") or u.get("email") or "Unknown")
        for u in (users_result.data or [])
    }

    comments = []
    for uid in added:
        name = user_map.get(uid, "Unknown")
        comments.append(
            {
                "work_order_id": work_order_id,
                "author_email": changed_by_email,
                "author_name": changed_by_name,
                "body": f"Assigned technician: {name}",
                "type": "system",
            }
        )
    for uid in removed:
        name = user_map.get(uid, "Unknown")
        comments.append(
            {
                "work_order_id": work_order_id,
                "author_email": changed_by_email,
                "author_name": changed_by_name,
                "body": f"Removed technician: {name}",
                "type": "system",
            }
        )

    if comments:
        try:
            supabase.table("work_order_comments").insert(comments).execute()
        except Exception as e:
            print(f"[_log_assignment_changes] Failed to insert comments: {e}")


def _log_status_change(
    work_order_id: str,
    old_status: str,
    new_status: str,
    changed_by: str,
    changed_by_email: str = "",
    changed_by_name: str = "",
    note: Optional[str] = None,
):
    """Log status change to audit trail and insert a status_change comment"""
    supabase.table("work_order_status_logs").insert(
        {
            "work_order_id": work_order_id,
            "changed_by": changed_by,
            "old_status": old_status,
            "new_status": new_status,
            "note": note,
        }
    ).execute()

    try:
        supabase.table("work_order_comments").insert(
            {
                "work_order_id": work_order_id,
                "author_email": changed_by_email,
                "author_name": changed_by_name,
                "body": f"Status changed from {old_status} to {new_status}",
                "type": "status_change",
                "meta": {"from": old_status, "to": new_status},
            }
        ).execute()
    except Exception as e:
        print(f"[_log_status_change] Failed to insert comment: {e}")


async def extract_entities_background(work_order_id: str) -> None:
    from db import supabase

    result = (
        supabase.table("system_settings")
        .select("value")
        .eq("key", "entity_extraction_enabled")
        .maybe_single()
        .execute()
    )
    if result.data is None or result.data.get("value") != "true":
        print(f"[entity_extraction] Skipping WO {work_order_id} — extraction disabled")
        return

    try:
        await extract_entities(work_order_id)
    except Exception as e:
        print(
            f"[extract_entities_background] WO {work_order_id} failed: {e}",
            file=sys.stderr,
        )


async def backfill_entities(pending_ids: list[str], user_email: str) -> None:
    try:
        success = 0
        failed = 0
        total = len(pending_ids)
        for i in range(0, len(pending_ids), 10):
            batch = pending_ids[i : i + 10]
            for wo_id in batch:
                try:
                    result = await extract_entities(wo_id)
                    if result is not None:
                        success += 1
                    else:
                        failed += 1
                except Exception:
                    failed += 1
            await asyncio.sleep(2)
        print(
            f"[backfill] Complete: {success} extracted, {failed} failed out of {total}",
            file=sys.stderr,
        )
        try:
            log_activity(
                user_email,
                "work_order",
                "entities_backfill_completed",
                detail=f"{success} extracted, {failed} failed",
            )
        except Exception:
            pass
    except Exception as e:
        print(f"[backfill_entities] Unexpected error: {e}", file=sys.stderr)


# --------------------
# Endpoints
# --------------------


@router.get("/work-orders/count")
async def count_work_orders(
    email: Optional[str] = Query(None),
    user_role: Optional[str] = Query(None),
):
    """Lightweight endpoint that returns only the count of non-closed work orders."""
    query = supabase.table("work_orders").select(
        "id, status, created_by, department_id"
    )
    result = query.execute()
    work_orders = [wo for wo in (result.data or []) if wo.get("status") != "Closed"]

    if user_role == "reporter" and email:
        reporter_user_id = _get_user_id_by_email(email)
        if reporter_user_id:
            work_orders = [
                wo for wo in work_orders if wo.get("created_by") == reporter_user_id
            ]
        else:
            work_orders = []
    elif user_role == "technician" and email:
        tech_user = _get_user_by_email(email)
        if tech_user:
            tech_dept_id = tech_user.get("department_id")
            if tech_dept_id:
                work_orders = [
                    wo for wo in work_orders if wo.get("department_id") == tech_dept_id
                ]
            else:
                work_orders = []
        else:
            work_orders = []

    return {"count": len(work_orders)}


@router.get("/work-orders")
async def list_work_orders(
    email: Optional[str] = Query(None),
    user_role: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    type: Optional[str] = Query(None),
    department_id: Optional[str] = Query(None),
    limit: Optional[int] = Query(None),
    offset: int = Query(0),
):
    # Updated query to include department details
    # Use left joins (via !left) so WOs still appear when FK doesn't match
    query = (
        supabase.table("work_orders")
        .select("""
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
    """)
        .order("created_at", desc=True)
    )

    if status:
        query = query.eq("status", status)
    if type:
        query = query.eq("type", type)
    if department_id:  # Changed from 'department' to 'department_id'
        query = query.eq("department_id", department_id)

    try:
        result = query.execute()
    except Exception as e:
        import traceback

        error_detail = f"{e}\n{traceback.format_exc()}"
        print(f"ERROR in list_work_orders: {error_detail}")
        return JSONResponse(status_code=500, content={"error": error_detail})
    work_orders = result.data or []

    if user_role == "reporter" and email:
        reporter_user_id = _get_user_id_by_email(email)
        if reporter_user_id:
            work_orders = [
                wo for wo in work_orders if wo.get("created_by") == reporter_user_id
            ]
        else:
            work_orders = []
    elif user_role == "technician" and email:
        tech_user = _get_user_by_email(email)
        if tech_user:
            tech_dept_id = tech_user.get("department_id")
            if tech_dept_id:
                work_orders = [
                    wo for wo in work_orders if wo.get("department_id") == tech_dept_id
                ]
            else:
                work_orders = []
        else:
            work_orders = []
    # Admin sees all (no filtering)

    total = len(work_orders)

    # Apply pagination
    if offset > 0:
        work_orders = work_orders[offset:]
    if limit is not None:
        work_orders = work_orders[:limit]

    # Enrich creator data for WOs where the FK join failed (created_by stores auth UUID)
    for wo in work_orders:
        if not wo.get("creator") and wo.get("created_by"):
            fallback_user = _get_user_by_auth_id(wo["created_by"])
            if fallback_user:
                wo["creator"] = {
                    "full_name": fallback_user.get("full_name"),
                    "email": fallback_user.get("email"),
                }

    return {"work_orders": work_orders, "total": total}


@router.get("/work-orders/pending-approvals")
async def list_pending_approvals(email: str = Query(...)):
    from .signatures import _get_user_approval_info

    caller_info = _get_user_approval_info(email)
    if not caller_info:
        return JSONResponse(status_code=403, content={"error": "User not found"})

    approval_level = caller_info.get("approval_level")
    if not approval_level or approval_level == 0:
        return JSONResponse(status_code=403, content={"error": "No approval role"})

    user_dept_ids = caller_info.get("department_ids", [])

    if approval_level == 1:
        query = (
            supabase.table("work_orders")
            .select("""
                id,
                job_no,
                title,
                status,
                department_id,
                created_at,
                signature_status,
                departments!left (
                    id,
                    name
                ),
                work_order_assignments!left (
                    technician_id,
                    users!work_order_assignments_technician_id_fkey (
                        id,
                        email,
                        full_name
                    )
                ),
                work_order_signatures!left (
                    id,
                    signer_role,
                    status,
                    signed_at
                )
            """)
            .eq("signature_status", "tech_signed")
            .in_("department_id", user_dept_ids)
            .order("created_at", desc=True)
        )
    elif approval_level == 2:
        query = (
            supabase.table("work_orders")
            .select("""
                id,
                job_no,
                title,
                status,
                department_id,
                created_at,
                signature_status,
                departments!left (
                    id,
                    name
                ),
                work_order_assignments!left (
                    technician_id,
                    users!work_order_assignments_technician_id_fkey (
                        id,
                        email,
                        full_name
                    )
                ),
                work_order_signatures!left (
                    id,
                    signer_role,
                    status,
                    signed_at
                )
            """)
            .eq("signature_status", "supervisor_approved")
            .order("created_at", desc=True)
        )
    else:
        return JSONResponse(
            status_code=403, content={"error": "Invalid approval level"}
        )

    result = query.execute()
    work_orders_data = result.data or []

    formatted = []
    for wo in work_orders_data:
        dept = wo.get("departments") or {}
        raw_assignments = wo.get("work_order_assignments")
        if isinstance(raw_assignments, dict):
            first_assignment = raw_assignments
        elif isinstance(raw_assignments, list) and raw_assignments:
            first_assignment = raw_assignments[0] or {}
        else:
            first_assignment = {}
        tech = first_assignment.get("users") or {}

        sigs = wo.get("work_order_signatures") or []
        pending_sig = None
        for sig in sigs:
            if sig.get("status") in (None, "pending"):
                pending_sig = sig
                break

        formatted.append(
            {
                "id": wo.get("id"),
                "job_no": wo.get("job_no"),
                "title": wo.get("title"),
                "status": wo.get("status"),
                "department_id": wo.get("department_id"),
                "department_name": dept.get("name"),
                "created_at": wo.get("created_at"),
                "signature_status": wo.get("signature_status"),
                "assigned_technician": {
                    "id": tech.get("id"),
                    "full_name": tech.get("full_name"),
                    "email": tech.get("email"),
                }
                if tech.get("id")
                else None,
                "pending_signature_id": pending_sig.get("id") if pending_sig else None,
            }
        )

    return {"work_orders": formatted}


@router.get("/work-orders/{work_order_id}")
async def get_work_order(
    work_order_id: str,
    email: Optional[str] = Query(None),
    user_role: Optional[str] = Query(None),
):
    data = _fetch_full_work_order(work_order_id)
    if not data:
        raise HTTPException(status_code=404, detail="Work order not found")

    if user_role == "reporter" and email:
        reporter_user_id = _get_user_id_by_email(email)
        if data.get("created_by") != reporter_user_id:
            raise HTTPException(status_code=403, detail="Access denied")
    elif user_role == "technician" and email:
        tech_user = _get_user_by_email(email)
        if tech_user:
            if data.get("department_id") != tech_user.get("department_id"):
                raise HTTPException(status_code=403, detail="Access denied")
        else:
            raise HTTPException(status_code=403, detail="Access denied")

    return {"work_order": data}


@router.post("/work-orders")
async def create_work_order(
    body: CreateWorkOrderBody, background_tasks: BackgroundTasks
):
    _validate_type(body.type)
    _validate_status(body.status)

    # Verify department exists and is active
    dept_result = (
        supabase.table("departments")
        .select("id, name, is_active")
        .eq("id", body.department_id)
        .execute()
    )
    if not dept_result.data:
        raise HTTPException(
            status_code=400, detail="Invalid department_id: department not found"
        )
    if not dept_result.data[0].get("is_active", True):
        raise HTTPException(
            status_code=400, detail="Cannot create work order for inactive department"
        )

    # Validate department routing for non-admin users
    if body.created_by_email:
        creator = _get_user_by_email(body.created_by_email)
        if creator and creator.get("user_type") != "admin":
            creator_dept_id = creator.get("department_id")
            if creator_dept_id and creator_dept_id != body.department_id:
                route_check = (
                    supabase.table("department_routes")
                    .select("id")
                    .eq("source_department_id", creator_dept_id)
                    .eq("target_department_id", body.department_id)
                    .execute()
                )
                if not route_check.data:
                    raise HTTPException(
                        status_code=403,
                        detail="Your department is not allowed to create work orders for this target department",
                    )

    # Resolve the public.users.id from email (frontend sends auth UUID which differs)
    resolved_created_by = None
    if body.created_by_email:
        resolved_created_by = _get_user_id_by_email(body.created_by_email)
    # Fallback: if email lookup failed, try matching via auth_id
    if not resolved_created_by and body.created_by:
        auth_user = _get_user_by_auth_id(body.created_by)
        if auth_user:
            resolved_created_by = auth_user.get("id")
    if not resolved_created_by:
        raise HTTPException(
            status_code=400,
            detail="Unable to resolve user identity. Work order could not be saved.",
        )

    # Structured field stitching
    final_description = body.description or ""
    if (
        body.asset_name
        and body.fault_description
        and body.action_taken
        and body.outcome
    ):
        if body.outcome not in VALID_OUTCOMES:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid outcome. Must be one of: {', '.join(VALID_OUTCOMES)}",
            )
        parts = [
            f"[Asset] {body.asset_name}",
            f"[Fault] {body.fault_description}",
            f"[Action] {body.action_taken}",
            f"[Outcome] {body.outcome}",
        ]
        if body.notes:
            parts.append(f"[Notes] {body.notes}")
        final_description = "\n".join(parts)

    now = datetime.utcnow().isoformat()
    payload = {
        "job_no": body.job_no,
        "title": body.title,
        "description": final_description,
        "location": body.location or "",
        "mobile_number": body.mobile_number or "",
        "department_id": body.department_id,
        "type": body.type or "Technical",
        "status": body.status or "Pending",
        "created_by": resolved_created_by,
    }
    if (body.status or "Pending") == "Closed":
        payload["closed_at"] = now
        payload["closed_by"] = resolved_created_by
    result = supabase.table("work_orders").insert(payload).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create work order")

    work_order_id = result.data[0].get("id")

    # Sync single technician assignment
    technician_id = body.assigned_technician_id
    if not technician_id and body.created_by_email:
        creator = _get_user_by_email(body.created_by_email)
        if creator and creator.get("user_type") == "technician":
            technician_id = creator.get("id")
    if technician_id:
        _sync_single_technician(work_order_id, technician_id, resolved_created_by)

    created_user_email = body.created_by_email or "unknown"
    log_activity(
        created_user_email,
        "work_order",
        "created",
        target_label=body.title,
        target_id=work_order_id,
    )

    background_tasks.add_task(extract_entities_background, work_order_id)

    # Insert system comment so Activity tab shows "Work order created"
    user_name = created_user_email.split("@")[0]
    try:
        supabase.table("work_order_comments").insert(
            {
                "work_order_id": work_order_id,
                "author_email": created_user_email,
                "author_name": user_name,
                "body": "Work order created",
                "type": "system",
            }
        ).execute()
    except Exception as e:
        print(f"[create_work_order] Failed to insert system comment: {e}")

    return {"work_order": _fetch_full_work_order(work_order_id)}


@router.put("/work-orders/{work_order_id}")
async def update_work_order(
    work_order_id: str,
    body: UpdateWorkOrderBody,
    user_email: str = Query(...),
):
    editor_user = _get_user_by_email(user_email)
    if not editor_user:
        raise HTTPException(status_code=401, detail="User not found")
    user_role = editor_user.get("user_type", "reporter")
    user_id = editor_user.get("id")
    if not user_id:
        raise HTTPException(status_code=401, detail="User has no id")
    editor_name = editor_user.get("full_name") or user_email.split("@")[0]

    existing = (
        supabase.table("work_orders")
        .select("id, status, type, created_by, created_at")
        .eq("id", work_order_id)
        .execute()
    )

    if not existing.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    if user_role == "reporter":
        if existing.data[0].get("created_by") != user_id:
            raise HTTPException(
                status_code=403, detail="Reporters can only edit their own work orders"
            )
    else:
        _validate_type(body.type)
        _validate_status(body.status)

    # Admin-only authorization for metadata fields
    if (
        body.created_by is not None
        or body.created_at is not None
        or body.closed_at is not None
    ):
        caller_info = _get_user_by_email(user_email)
        caller_role = (
            caller_info.get("user_type", "reporter") if caller_info else "reporter"
        )
        if caller_role != "admin":
            raise HTTPException(
                status_code=403,
                detail="Admin access required to modify metadata fields",
            )

    old_status = existing.data[0]["status"]

    # Validate metadata fields
    user_record = None
    if body.created_by is not None:
        user_result = (
            supabase.table("users")
            .select("id, email, full_name, is_active")
            .eq("id", body.created_by)
            .execute()
        )
        if not user_result.data or not user_result.data[0].get("is_active", False):
            raise HTTPException(
                status_code=400, detail="Selected user not found or inactive"
            )
        user_record = user_result.data[0]

    if body.created_at is not None:
        try:
            created_dt = datetime.fromisoformat(body.created_at.replace("Z", "+00:00"))
            if created_dt > datetime.utcnow():
                raise HTTPException(
                    status_code=400, detail="Created date cannot be in the future"
                )
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid created_at format")

    if body.closed_at is not None:
        effective_status = body.status if body.status else old_status
        if effective_status != "Closed":
            raise HTTPException(
                status_code=400,
                detail="Closed date can only be set on closed work orders",
            )
        try:
            closed_dt = datetime.fromisoformat(body.closed_at.replace("Z", "+00:00"))
            effective_created = (
                body.created_at
                if body.created_at
                else existing.data[0].get("created_at")
            )
            if effective_created:
                created_dt = datetime.fromisoformat(
                    effective_created.replace("Z", "+00:00")
                )
                if closed_dt < created_dt:
                    raise HTTPException(
                        status_code=400,
                        detail="Closed date cannot be before created date",
                    )
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid closed_at format")

    # Verify department exists and is active
    dept_result = (
        supabase.table("departments")
        .select("id, name, is_active")
        .eq("id", body.department_id)
        .execute()
    )
    if not dept_result.data:
        raise HTTPException(
            status_code=400, detail="Invalid department_id: department not found"
        )
    if not dept_result.data[0].get("is_active", True):
        raise HTTPException(
            status_code=400, detail="Cannot update work order to inactive department"
        )

    now = datetime.utcnow().isoformat()

    if user_role == "reporter":
        # Reporters can only update basic fields; status/type/assignments are preserved
        payload = {
            "job_no": body.job_no,
            "title": body.title,
            "description": body.description,
            "location": body.location,
            "mobile_number": body.mobile_number,
            "department_id": body.department_id,
            "updated_at": now,
        }
    else:
        payload = {
            "job_no": body.job_no,
            "title": body.title,
            "description": body.description,
            "location": body.location,
            "mobile_number": body.mobile_number,
            "department_id": body.department_id,
            "type": body.type,
            "status": body.status,
            "updated_at": now,
        }

        # Add metadata fields to payload
        if body.created_by is not None and user_record:
            payload["created_by"] = body.created_by
        if body.created_at is not None:
            payload["created_at"] = body.created_at
        if body.closed_at is not None:
            payload["closed_at"] = body.closed_at

        if body.status == "Closed" and old_status != "Closed":
            if body.closed_at is None:
                payload["closed_at"] = now
            payload["closed_by"] = user_id

    supabase.table("work_orders").update(payload).eq("id", work_order_id).execute()

    if user_role != "reporter":
        new_tech_id = body.assigned_technician_id
        old_assignments = (
            supabase.table("work_order_assignments")
            .select("technician_id")
            .eq("work_order_id", work_order_id)
            .execute()
        )
        old_id = (
            (old_assignments.data or [{}])[0].get("technician_id")
            if old_assignments.data
            else None
        )

        _sync_single_technician(work_order_id, new_tech_id, user_id)

        if old_id != new_tech_id:
            wo_check = (
                supabase.table("work_orders")
                .select("signature_status")
                .eq("id", work_order_id)
                .execute()
            )
            if wo_check.data and wo_check.data[0].get("signature_status") not in (
                None,
                "unsigned",
                "rejected",
            ):
                supabase.table("work_orders").update(
                    {"signature_status": "unsigned"}
                ).eq("id", work_order_id).execute()
                supabase.table("work_order_signatures").update(
                    {"status": "rejected"}
                ).eq("work_order_id", work_order_id).neq("status", "rejected").execute()
                log_activity(
                    user_email,
                    "work_order",
                    "signature_chain_reset",
                    target_id=work_order_id,
                    detail="Technician assignment changed, chain reset",
                )

        if old_id:
            _log_assignment_changes(
                work_order_id,
                [old_id] if old_id else [],
                [new_tech_id] if new_tech_id else [],
                changed_by_email=user_email,
                changed_by_name=editor_name,
            )
        if old_status != body.status:
            _log_status_change(
                work_order_id,
                old_status,
                body.status,
                user_id,
                changed_by_email=user_email,
                changed_by_name=editor_name,
            )

    # Log activity with metadata change detail
    changed_metadata = []
    if body.created_by is not None:
        changed_metadata.append("created_by")
    if body.created_at is not None:
        changed_metadata.append("created_at")
    if body.closed_at is not None:
        changed_metadata.append("closed_at")

    detail = (
        f"Admin modified: {', '.join(changed_metadata)}" if changed_metadata else None
    )

    log_activity(
        user_email,
        "work_order",
        "updated",
        target_label=body.title,
        target_id=work_order_id,
        detail=detail,
    )

    return {"work_order": _fetch_full_work_order(work_order_id)}


@router.post("/work-orders/{work_order_id}/close")
async def close_work_order(
    work_order_id: str,
    body: CloseWorkOrderBody,
    background_tasks: BackgroundTasks,
    user_email: str = Query(...),
):
    _ensure_not_reporter(user_email)
    existing = (
        supabase.table("work_orders")
        .select("id, status")
        .eq("id", work_order_id)
        .execute()
    )

    if not existing.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    if existing.data[0]["status"] == "Closed":
        raise HTTPException(status_code=400, detail="Work order already closed")

    old_status = existing.data[0]["status"]
    now = datetime.utcnow().isoformat()

    supabase.table("work_orders").update(
        {
            "status": "Closed",
            "closed_by": body.closed_by,
            "closed_at": now,
            "tech_notes": body.tech_notes,
            "updated_at": now,
        }
    ).eq("id", work_order_id).execute()

    closer_user = _get_user_by_email(user_email) if user_email else None
    closer_name = (
        (closer_user.get("full_name") or user_email.split("@")[0])
        if closer_user
        else user_email.split("@")[0]
    )
    _log_status_change(
        work_order_id,
        old_status,
        "Closed",
        body.closed_by,
        changed_by_email=user_email,
        changed_by_name=closer_name,
        note=body.tech_notes,
    )

    log_activity(
        user_email,
        "work_order",
        "closed",
        target_label=work_order_id,
        target_id=work_order_id,
    )

    background_tasks.add_task(extract_entities_background, work_order_id)

    return {"status": "closed"}


@router.delete("/work-orders/{work_order_id}")
async def delete_work_order(
    work_order_id: str,
    user_email: str = Query(...),
):
    user_role = _get_user_role(user_email)
    existing = (
        supabase.table("work_orders")
        .select("id, title, created_by")
        .eq("id", work_order_id)
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    wo_title = existing.data[0].get("title", work_order_id)

    if user_role == "reporter":
        reporter_id = _get_user_id_by_email(user_email)
        if existing.data[0].get("created_by") != reporter_id:
            raise HTTPException(
                status_code=403,
                detail="Reporters can only delete their own work orders",
            )

    supabase.table("work_orders").delete().eq("id", work_order_id).execute()
    log_activity(
        user_email,
        "work_order",
        "deleted",
        target_label=wo_title,
        target_id=work_order_id,
    )
    return {"status": "deleted"}


@router.delete("/work-orders")
async def delete_work_orders_bulk(
    ids: str = Query(..., description="Comma-separated work order IDs"),
    user_email: str = Query(...),
):
    id_list = [i.strip() for i in ids.split(",") if i.strip()]
    if not id_list:
        raise HTTPException(status_code=400, detail="No IDs provided")

    user_role = _get_user_role(user_email)
    wo_check = (
        supabase.table("work_orders")
        .select("id, title, created_by")
        .in_("id", id_list)
        .execute()
    )
    wo_data = wo_check.data or []

    if user_role == "reporter":
        reporter_id = _get_user_id_by_email(user_email)
        not_owned = [w["id"] for w in wo_data if w.get("created_by") != reporter_id]
        if not_owned:
            raise HTTPException(
                status_code=403,
                detail="Reporters can only delete their own work orders",
            )

    supabase.table("work_orders").delete().in_("id", id_list).execute()

    for wo in wo_data:
        log_activity(
            user_email,
            "work_order",
            "deleted",
            target_label=wo.get("title", wo["id"]),
            target_id=wo["id"],
        )

    return {"status": "deleted", "count": len(id_list)}


# --------------------
# Status History
# --------------------


@router.get("/work-orders/{work_order_id}/status-history")
async def get_status_history(work_order_id: str):
    """Get status change history for a work order"""
    result = (
        supabase.table("work_order_status_logs")
        .select("*, users(full_name, email)")
        .eq("work_order_id", work_order_id)
        .order("changed_at", desc=True)
        .execute()
    )
    return {"status_history": result.data or []}


# --------------------
# Comments
# --------------------


@router.get("/work-orders/{work_order_id}/comments")
async def get_comments(work_order_id: str):
    result = (
        supabase.table("work_order_comments")
        .select("*")
        .eq("work_order_id", work_order_id)
        .order("created_at", desc=False)
        .execute()
    )
    return {"comments": result.data or []}


@router.post("/work-orders/{work_order_id}/comments")
async def add_comment(work_order_id: str, body: AddCommentBody):
    existing = (
        supabase.table("work_orders").select("id").eq("id", work_order_id).execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    record = {
        "work_order_id": work_order_id,
        "author_email": body.author_email.strip().lower(),
        "author_name": body.author_name,
        "body": body.body,
        "type": body.type,
        "meta": body.meta,
    }
    try:
        result = supabase.table("work_order_comments").insert(record).execute()
    except Exception as e:
        print(f"[add_comment] Failed to insert comment for WO {work_order_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to save comment: {e}")
    comment = result.data[0] if result.data else {}

    if body.type == "comment" and comment.get("id"):
        try:
            dispatch_work_order_comment_notification(
                work_order_id=work_order_id,
                comment_id=str(comment.get("id")),
                comment_text=body.body,
                author_email=body.author_email,
                author_name=body.author_name,
            )
        except Exception as e:
            print(f"Notification dispatch failed: {e}")

    return {"comment": comment}


# --------------------
# Entity Extraction Endpoints
# --------------------


@router.post("/work-orders/extract-entities/backfill")
async def trigger_entity_backfill(
    background_tasks: BackgroundTasks,
    user_email: str = Query(...),
):
    caller = _get_user_by_email(user_email)
    if not caller or caller.get("user_type") != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")

    all_wo = supabase.table("work_orders").select("id").execute()
    existing = supabase.table("work_order_entities").select("work_order_id").execute()
    existing_ids = {r["work_order_id"] for r in (existing.data or [])}
    pending_ids = [r["id"] for r in (all_wo.data or []) if r["id"] not in existing_ids]

    if not pending_ids:
        return {
            "status": "no_pending",
            "total_pending": 0,
            "message": "All work orders already have entities",
        }

    background_tasks.add_task(backfill_entities, pending_ids, user_email)
    return {
        "status": "backfill_started",
        "total_pending": len(pending_ids),
        "batch_size": 10,
        "message": f"Processing {len(pending_ids)} work orders in batches of 10",
    }


@router.post("/work-orders/extract-entities/{work_order_id}")
async def trigger_entity_extraction(
    work_order_id: str,
    user_email: str = Query(...),
):
    caller = _get_user_by_email(user_email)
    if not caller or caller.get("user_type") != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")

    wo_check = (
        supabase.table("work_orders").select("id").eq("id", work_order_id).execute()
    )
    if not wo_check.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    result = await extract_entities(work_order_id)
    if result is None:
        raise HTTPException(
            status_code=400,
            detail="Extraction failed — check extraction_failures table",
        )

    log_activity(
        user_email,
        "work_order",
        "entities_extracted",
        target_label=work_order_id,
        target_id=work_order_id,
    )
    return {"status": "extracted", "work_order_id": work_order_id, "entities": result}


# --------------------
# Attachment Endpoints
# --------------------


async def _validate_file(file: UploadFile) -> bytes:
    content = b""
    chunk_size = 1024 * 1024  # 1MB chunks
    total_size = 0

    while True:
        chunk = await file.read(chunk_size)
        if not chunk:
            break
        total_size += len(chunk)
        if total_size > MAX_FILE_SIZE:
            raise HTTPException(
                status_code=400,
                detail=f"File too large. Maximum size is {MAX_FILE_SIZE // (1024 * 1024)}MB",
            )
        content += chunk

    await file.seek(0)

    extension = file.filename.split(".")[-1].lower() if "." in file.filename else ""
    if extension not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"File type not allowed. Allowed types: {', '.join(sorted(ALLOWED_EXTENSIONS))}",
        )

    return content


def _compress_image(content: bytes, extension: str) -> bytes:
    try:
        img = Image.open(io.BytesIO(content))
        # Apply EXIF orientation so phone photos aren't rotated
        img = ImageOps.exif_transpose(img)
        if img.mode in ("RGBA", "P"):
            img = img.convert("RGB")

        if max(img.width, img.height) > MAX_IMAGE_DIMENSION:
            ratio = MAX_IMAGE_DIMENSION / max(img.width, img.height)
            new_size = (int(img.width * ratio), int(img.height * ratio))
            img = img.resize(new_size, Image.Resampling.LANCZOS)

        output = io.BytesIO()
        save_format = "JPEG" if extension in ("jpg", "jpeg") else "PNG"
        img.save(output, format=save_format, optimize=True)
        return output.getvalue()
    except Exception:
        return content


@router.post("/work-orders/{work_order_id}/attachments")
async def upload_attachment(
    work_order_id: str,
    file: UploadFile = File(...),
    uploaded_by: str = Form(...),
):
    existing = (
        supabase.table("work_orders").select("id").eq("id", work_order_id).execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    content = await _validate_file(file)

    file_id = str(uuid.uuid4())
    extension = file.filename.split(".")[-1].lower() if "." in file.filename else "bin"
    filename = f"wo_{file_id}.{extension}"

    if extension in IMAGE_EXTENSIONS:
        content = _compress_image(content, extension)
        if extension in ("jpg", "jpeg"):
            filename = f"wo_{file_id}.jpg"

    file_path = os.path.join(UPLOAD_DIR, filename)

    with open(file_path, "wb") as f:
        f.write(content)

    public_url = f"/files/{filename}"

    try:
        supabase.table("work_order_attachments").insert(
            {
                "work_order_id": work_order_id,
                "file_name": file.filename,
                "file_url": public_url,
                "file_type": file.content_type or f"image/{extension}"
                if extension in IMAGE_EXTENSIONS
                else "application/octet-stream",
                "uploaded_by": uploaded_by,
            }
        ).execute()
    except Exception as e:
        print(
            f"[upload_attachment] Failed to insert attachment for WO {work_order_id}: {e}"
        )
        raise HTTPException(status_code=500, detail=f"Failed to save attachment: {e}")

    return {"status": "uploaded", "file_url": public_url, "file_name": file.filename}


@router.get("/work-orders/{work_order_id}/attachments")
async def get_attachments(work_order_id: str):
    result = (
        supabase.table("work_order_attachments")
        .select("*")
        .eq("work_order_id", work_order_id)
        .order("created_at")
        .execute()
    )
    return {"attachments": result.data or []}


@router.delete("/work-orders/{work_order_id}/attachments/{attachment_id}")
async def delete_attachment(
    work_order_id: str,
    attachment_id: str,
    email: str = Query(...),
):
    result = (
        supabase.table("work_order_attachments")
        .select("file_url")
        .eq("id", attachment_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=404, detail="Attachment not found")

    file_path = result.data[0].get("file_url")
    if file_path:
        fname = os.path.basename(file_path)
        abs_path = os.path.join(UPLOAD_DIR, fname)
        if os.path.exists(abs_path):
            os.remove(abs_path)

    supabase.table("work_order_attachments").delete().eq("id", attachment_id).execute()
    return {"status": "deleted"}
