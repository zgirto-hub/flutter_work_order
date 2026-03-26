from fastapi import APIRouter, Query, HTTPException, UploadFile, File, Form
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
import os
import uuid
import io
import traceback

from PIL import Image, ImageOps
from db import supabase
from utils.activity import log_activity
from utils.notification_service import dispatch_work_order_comment_notification

router = APIRouter()

UPLOAD_DIR = "uploaded_files"

MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
MAX_IMAGE_DIMENSION = 1920
ALLOWED_EXTENSIONS = {"pdf", "doc", "docx", "jpg", "jpeg", "png", "gif"}
IMAGE_EXTENSIONS = {"jpg", "jpeg", "png", "gif"}

ALLOWED_TYPES = {"Technical", "Inspection", "Other"}
ALLOWED_STATUSES = {"Pending", "In Progress", "Resolved", "Closed"}

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
    assigned_technician_ids: Optional[List[str]] = []


class UpdateWorkOrderBody(BaseModel):
    job_no: str
    title: str
    description: Optional[str] = ""
    location: str
    mobile_number: Optional[str] = ""
    department_id: str
    type: str
    status: str
    assigned_technician_ids: Optional[List[str]] = []


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
    result = supabase.table("users").select("id").eq("department_id", department_id).eq("user_type", "technician").eq("is_active", True).execute()
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
            detail=f"Invalid type. Must be one of: {', '.join(ALLOWED_TYPES)}"
        )


def _validate_status(status: Optional[str]):
    if status is not None and status not in ALLOWED_STATUSES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid status. Must be one of: {', '.join(ALLOWED_STATUSES)}"
        )


def _fetch_full_work_order(work_order_id: str):
    # Updated query to include department details via JOIN
    result = supabase.table("work_orders").select("""
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
    """).eq("id", work_order_id).execute()
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


def _sync_assignments(work_order_id: str, technician_ids: List[str], assigned_by: str):
    supabase.table("work_order_assignments") \
        .delete() \
        .eq("work_order_id", work_order_id) \
        .execute()
    if technician_ids:
        assignments = [
            {
                "work_order_id": work_order_id,
                "technician_id": technician_id,
                "assigned_by": assigned_by
            }
            for technician_id in technician_ids
        ]
        supabase.table("work_order_assignments").insert(assignments).execute()


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
    users_result = supabase.table("users").select("id, full_name, email") \
        .in_("id", affected_ids).execute()
    user_map = {u["id"]: (u.get("full_name") or u.get("email") or "Unknown")
                for u in (users_result.data or [])}

    comments = []
    for uid in added:
        name = user_map.get(uid, "Unknown")
        comments.append({
            "work_order_id": work_order_id,
            "author_email": changed_by_email,
            "author_name": changed_by_name,
            "body": f"Assigned technician: {name}",
            "type": "system",
        })
    for uid in removed:
        name = user_map.get(uid, "Unknown")
        comments.append({
            "work_order_id": work_order_id,
            "author_email": changed_by_email,
            "author_name": changed_by_name,
            "body": f"Removed technician: {name}",
            "type": "system",
        })

    if comments:
        try:
            supabase.table("work_order_comments").insert(comments).execute()
        except Exception as e:
            print(f"[_log_assignment_changes] Failed to insert comments: {e}")


def _log_status_change(work_order_id: str, old_status: str, new_status: str, changed_by: str, note: Optional[str] = None):
    """Log status change to audit trail"""
    supabase.table("work_order_status_logs").insert({
        "work_order_id": work_order_id,
        "changed_by": changed_by,
        "old_status": old_status,
        "new_status": new_status,
        "note": note,
    }).execute()


# --------------------
# Endpoints
# --------------------

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
    query = supabase.table("work_orders").select("""
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
    """).order("created_at", desc=True)

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
            work_orders = [wo for wo in work_orders if wo.get("created_by") == reporter_user_id]
        else:
            work_orders = []
    elif user_role == "technician" and email:
        tech_user = _get_user_by_email(email)
        if tech_user:
            tech_dept_id = tech_user.get("department_id")
            if tech_dept_id:
                work_orders = [wo for wo in work_orders if wo.get("department_id") == tech_dept_id]
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
async def create_work_order(body: CreateWorkOrderBody):
    _validate_type(body.type)
    _validate_status(body.status)
    
    # Verify department exists and is active
    dept_result = supabase.table("departments").select("id, name, is_active").eq("id", body.department_id).execute()
    if not dept_result.data:
        raise HTTPException(status_code=400, detail="Invalid department_id: department not found")
    if not dept_result.data[0].get("is_active", True):
        raise HTTPException(status_code=400, detail="Cannot create work order for inactive department")

    # Validate department routing for non-admin users
    if body.created_by_email:
        creator = _get_user_by_email(body.created_by_email)
        if creator and creator.get("user_type") != "admin":
            creator_dept_id = creator.get("department_id")
            if creator_dept_id and creator_dept_id != body.department_id:
                route_check = supabase.table("department_routes") \
                    .select("id") \
                    .eq("source_department_id", creator_dept_id) \
                    .eq("target_department_id", body.department_id) \
                    .execute()
                if not route_check.data:
                    raise HTTPException(
                        status_code=403,
                        detail="Your department is not allowed to create work orders for this target department"
                    )

    # Resolve the public.users.id from email (frontend sends auth UUID which differs)
    resolved_created_by = body.created_by
    if body.created_by_email:
        resolved_id = _get_user_id_by_email(body.created_by_email)
        if resolved_id:
            resolved_created_by = resolved_id
    # Fallback: if email lookup failed, try matching via auth_id
    if resolved_created_by == body.created_by and body.created_by:
        auth_user = _get_user_by_auth_id(body.created_by)
        if auth_user:
            resolved_created_by = auth_user.get("id", body.created_by)

    now = datetime.utcnow().isoformat()
    payload = {
        "job_no": body.job_no,
        "title": body.title,
        "description": body.description or "",
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
    
    # Sync assignments
    technician_ids = body.assigned_technician_ids or []
    if not technician_ids and body.created_by_email:
        # Auto-assign creator if technician preference is enabled
        pref_res = supabase.table("notification_preferences") \
            .select("technician_auto_assign_self") \
            .eq("user_email", body.created_by_email.strip().lower()) \
            .limit(1).execute()
        auto_assign = (pref_res.data or [{}])[0].get("technician_auto_assign_self", False)
        if auto_assign:
            creator_user = _get_user_by_email(body.created_by_email)
            if creator_user:
                technician_ids = [str(creator_user.get("id"))]
    if technician_ids:
        _sync_assignments(work_order_id, technician_ids, resolved_created_by)

    created_user_email = body.created_by_email or "unknown"
    log_activity(created_user_email, "work_order", "created",
        target_label=body.title, target_id=work_order_id)

    # Insert system comment so Activity tab shows "Work order created"
    user_name = created_user_email.split("@")[0]
    try:
        supabase.table("work_order_comments").insert({
            "work_order_id": work_order_id,
            "author_email": created_user_email,
            "author_name": user_name,
            "body": "Work order created",
            "type": "system",
        }).execute()
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
    user_role = editor_user.get("user_type", "reporter") if editor_user else "reporter"
    user_id = editor_user.get("id", "unknown") if editor_user else "unknown"
    editor_name = (editor_user.get("full_name") or user_email.split("@")[0]) if editor_user else user_email.split("@")[0]

    existing = supabase.table("work_orders") \
        .select("id, status, type, created_by") \
        .eq("id", work_order_id) \
        .execute()

    if not existing.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    if user_role == "reporter":
        if existing.data[0].get("created_by") != user_id:
            raise HTTPException(status_code=403, detail="Reporters can only edit their own work orders")
    else:
        _validate_type(body.type)
        _validate_status(body.status)

    old_status = existing.data[0]["status"]

    # Verify department exists and is active
    dept_result = supabase.table("departments").select("id, name, is_active").eq("id", body.department_id).execute()
    if not dept_result.data:
        raise HTTPException(status_code=400, detail="Invalid department_id: department not found")
    if not dept_result.data[0].get("is_active", True):
        raise HTTPException(status_code=400, detail="Cannot update work order to inactive department")

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
        if body.status == "Closed" and old_status != "Closed":
            payload["closed_at"] = now
            payload["closed_by"] = user_id

    supabase.table("work_orders").update(payload).eq("id", work_order_id).execute()

    if user_role != "reporter":
        new_ids = body.assigned_technician_ids or []
        # Fetch current assignments before syncing so we can diff them
        old_assignments = supabase.table("work_order_assignments") \
            .select("technician_id") \
            .eq("work_order_id", work_order_id) \
            .execute()
        old_ids = [r["technician_id"] for r in (old_assignments.data or [])]

        _sync_assignments(work_order_id, new_ids, user_id)
        _log_assignment_changes(
            work_order_id, old_ids, new_ids,
            changed_by_email=user_email,
            changed_by_name=editor_name,
        )
        if old_status != body.status:
            _log_status_change(work_order_id, old_status, body.status, user_id)

    log_activity(user_email, "work_order", "updated",
        target_label=body.title, target_id=work_order_id)

    return {"work_order": {"id": work_order_id, "status": body.status or old_status}}


@router.post("/work-orders/{work_order_id}/close")
async def close_work_order(
    work_order_id: str,
    body: CloseWorkOrderBody,
    user_email: str = Query(...),
):
    _ensure_not_reporter(user_email)
    existing = supabase.table("work_orders") \
        .select("id, status") \
        .eq("id", work_order_id) \
        .execute()

    if not existing.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    if existing.data[0]["status"] == "Closed":
        raise HTTPException(status_code=400, detail="Work order already closed")

    old_status = existing.data[0]["status"]
    now = datetime.utcnow().isoformat()

    supabase.table("work_orders").update({
        "status": "Closed",
        "closed_by": body.closed_by,
        "closed_at": now,
        "tech_notes": body.tech_notes,
        "updated_at": now,
    }).eq("id", work_order_id).execute()

    _log_status_change(work_order_id, old_status, "Closed", body.closed_by, body.tech_notes)

    log_activity(user_email, "work_order", "closed",
        target_label=work_order_id, target_id=work_order_id)

    return {"status": "closed"}


@router.delete("/work-orders/{work_order_id}")
async def delete_work_order(
    work_order_id: str,
    user_email: str = Query(...),
):
    user_role = _get_user_role(user_email)
    existing = supabase.table("work_orders") \
        .select("id, created_by") \
        .eq("id", work_order_id) \
        .execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    if user_role == "reporter":
        reporter_id = _get_user_id_by_email(user_email)
        if existing.data[0].get("created_by") != reporter_id:
            raise HTTPException(status_code=403, detail="Reporters can only delete their own work orders")

    supabase.table("work_orders").delete().eq("id", work_order_id).execute()
    log_activity(user_email, "work_order", "deleted",
        target_label=work_order_id, target_id=work_order_id)
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
    if user_role == "reporter":
        reporter_id = _get_user_id_by_email(user_email)
        wo_check = supabase.table("work_orders").select("id, created_by").in_("id", id_list).execute()
        not_owned = [w["id"] for w in (wo_check.data or []) if w.get("created_by") != reporter_id]
        if not_owned:
            raise HTTPException(status_code=403, detail="Reporters can only delete their own work orders")

    supabase.table("work_orders").delete().in_("id", id_list).execute()
    return {"status": "deleted", "count": len(id_list)}


# --------------------
# Status History
# --------------------

@router.get("/work-orders/{work_order_id}/status-history")
async def get_status_history(work_order_id: str):
    """Get status change history for a work order"""
    result = supabase.table("work_order_status_logs") \
        .select("*, users(full_name, email)") \
        .eq("work_order_id", work_order_id) \
        .order("changed_at", desc=True) \
        .execute()
    return {"status_history": result.data or []}


# --------------------
# Comments
# --------------------

@router.get("/work-orders/{work_order_id}/comments")
async def get_comments(work_order_id: str):
    result = supabase.table("work_order_comments") \
        .select("*") \
        .eq("work_order_id", work_order_id) \
        .order("created_at", desc=False) \
        .execute()
    return {"comments": result.data or []}


@router.post("/work-orders/{work_order_id}/comments")
async def add_comment(work_order_id: str, body: AddCommentBody):
    existing = supabase.table("work_orders") \
        .select("id") \
        .eq("id", work_order_id) \
        .execute()
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
    result = supabase.table("work_order_comments").insert(record).execute()
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
                detail=f"File too large. Maximum size is {MAX_FILE_SIZE // (1024*1024)}MB"
            )
        content += chunk
    
    await file.seek(0)
    
    extension = file.filename.split(".")[-1].lower() if "." in file.filename else ""
    if extension not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"File type not allowed. Allowed types: {', '.join(sorted(ALLOWED_EXTENSIONS))}"
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
    existing = supabase.table("work_orders") \
        .select("id") \
        .eq("id", work_order_id) \
        .execute()
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

    supabase.table("work_order_attachments").insert({
        "work_order_id": work_order_id,
        "file_name": file.filename,
        "file_url": public_url,
        "file_type": file.content_type or f"image/{extension}" if extension in IMAGE_EXTENSIONS else "application/octet-stream",
        "uploaded_by": uploaded_by,
    }).execute()

    return {"status": "uploaded", "file_url": public_url, "file_name": file.filename}


@router.get("/work-orders/{work_order_id}/attachments")
async def get_attachments(work_order_id: str):
    result = supabase.table("work_order_attachments") \
        .select("*") \
        .eq("work_order_id", work_order_id) \
        .order("created_at") \
        .execute()
    return {"attachments": result.data or []}


@router.delete("/work-orders/{work_order_id}/attachments/{attachment_id}")
async def delete_attachment(
    work_order_id: str,
    attachment_id: str,
    email: str = Query(...),
):
    result = supabase.table("work_order_attachments") \
        .select("file_url") \
        .eq("id", attachment_id) \
        .execute()
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
