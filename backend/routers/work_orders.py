from fastapi import APIRouter, Query, HTTPException, UploadFile, File, Form
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
import os
import uuid
import io
import traceback

from PIL import Image
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
    location: str = ""
    mobile_number: Optional[str] = ""
    department_id: str  # Changed from 'department' to 'department_id' (UUID)
    type: str = "Technical"
    status: str = "Pending"
    created_by: str  # user UUID
    created_by_email: Optional[str] = ""
    assigned_fixer_ids: Optional[List[str]] = []


class UpdateWorkOrderBody(BaseModel):
    job_no: str
    title: str
    description: Optional[str] = ""
    location: str
    mobile_number: Optional[str] = ""
    department_id: str  # Changed from 'department' to 'department_id' (UUID)
    type: str
    status: str
    assigned_fixer_ids: Optional[List[str]] = []


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
        return "admin"
    return (user.get("user_type") or "admin").strip().lower()


def _get_user_id_by_email(email: str) -> Optional[str]:
    user = _get_user_by_email(email)
    if user:
        return user.get("id")
    return None


def _get_fixers_by_department(department_id: str) -> List[str]:
    """Get list of fixer user IDs that handle a specific department"""
    # Updated to use department_id instead of department name
    result = supabase.table("fixer_departments").select("fixer_id").eq("department_id", department_id).execute()
    return [r.get("fixer_id") for r in (result.data or [])]


def _get_fixer_departments(fixer_id: str) -> List[str]:
    """Get list of department IDs that a fixer handles"""
    if not fixer_id:
        return []
    # Updated to return department_id instead of department name
    result = supabase.table("fixer_departments").select("department_id").eq("fixer_id", fixer_id).execute()
    return [r.get("department_id") for r in (result.data or []) if r.get("department_id")]


def _ensure_not_reporter(email: str):
    if _get_user_role(email) == "reporter":
        raise HTTPException(
            status_code=403,
            detail="Reporter is not allowed to modify or delete work orders",
        )


def _validate_type(type: str):
    if type not in ALLOWED_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid type. Must be one of: {', '.join(ALLOWED_TYPES)}"
        )


def _validate_status(status: str):
    if status not in ALLOWED_STATUSES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid status. Must be one of: {', '.join(ALLOWED_STATUSES)}"
        )


def _fetch_full_work_order(work_order_id: str):
    # Updated query to include department details via JOIN
    result = supabase.table("work_orders").select("""
        *,
        departments!work_orders_department_id_fkey (
            id,
            name,
            is_active
        ),
        work_order_assignments (
            fixer_id,
            assigned_at,
            assigned_by,
            users!work_order_assignments_fixer_id_fkey (
                id,
                email,
                full_name
            )
        )
    """).eq("id", work_order_id).execute()
    if not result.data:
        return None
    return result.data[0]


def _sync_assignments(work_order_id: str, fixer_ids: List[str], assigned_by: str):
    supabase.table("work_order_assignments") \
        .delete() \
        .eq("work_order_id", work_order_id) \
        .execute()
    if fixer_ids:
        assignments = [
            {
                "work_order_id": work_order_id,
                "fixer_id": fixer_id,
                "assigned_by": assigned_by
            }
            for fixer_id in fixer_ids
        ]
        supabase.table("work_order_assignments").insert(assignments).execute()


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
    department_id: Optional[str] = Query(None),  # Changed from 'department' to 'department_id'
):
    # Updated query to include department details
    query = supabase.table("work_orders").select("""
        *,
        departments!work_orders_department_id_fkey (
            id,
            name,
            is_active
        ),
        work_order_assignments (
            fixer_id,
            assigned_at,
            assigned_by,
            users!work_order_assignments_fixer_id_fkey (
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
            # Reporters see only work orders they created
            work_orders = [wo for wo in work_orders if wo.get("created_by") == reporter_user_id]
        else:
            work_orders = []
    elif user_role == "fixer" and email:
        fixer_user = _get_user_by_email(email)
        if fixer_user:
            fixer_id = str(fixer_user.get("id") or "")
            fixer_department_ids = _get_fixer_departments(fixer_id)
            if fixer_department_ids:
                # Fixers see work orders in departments they handle
                work_orders = [wo for wo in work_orders if wo.get("department_id") in fixer_department_ids]
            else:
                # Fixer with no assigned departments - show nothing
                work_orders = []
        else:
            work_orders = []
    # Admin sees all (no filtering)
    
    return {"work_orders": work_orders}


@router.get("/work-orders/{work_order_id}")
async def get_work_order(work_order_id: str):
    data = _fetch_full_work_order(work_order_id)
    if not data:
        raise HTTPException(status_code=404, detail="Work order not found")
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

    payload = {
        "job_no": body.job_no,
        "title": body.title,
        "description": body.description,
        "location": body.location,
        "mobile_number": body.mobile_number,
        "department_id": body.department_id,  # Changed from 'department' to 'department_id'
        "type": body.type,
        "status": body.status,
        "created_by": body.created_by,
        "created_by_email": body.created_by_email.strip().lower() if body.created_by_email else "",
    }
    result = supabase.table("work_orders").insert(payload).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create work order")

    work_order_id = result.data[0].get("id")
    
    # Sync assignments
    fixer_ids = body.assigned_fixer_ids or []
    if not fixer_ids:
        fixer_ids = _get_fixers_by_department(body.department_id)
    
    if fixer_ids:
        _sync_assignments(work_order_id, fixer_ids, body.created_by)

    created_user_email = body.created_by_email or "unknown"
    log_activity(created_user_email, "work_order", "created",
        target_label=body.title, target_id=work_order_id)

    return {"work_order": _fetch_full_work_order(work_order_id)}


@router.put("/work-orders/{work_order_id}")
async def update_work_order(
    work_order_id: str,
    body: UpdateWorkOrderBody,
    user_email: str = Query(...),
):
    _ensure_not_reporter(user_email)
    _validate_type(body.type)
    _validate_status(body.status)

    existing = supabase.table("work_orders") \
        .select("id, status") \
        .eq("id", work_order_id) \
        .execute()

    if not existing.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    old_status = existing.data[0]["status"]
    
    # Verify department exists and is active
    dept_result = supabase.table("departments").select("id, name, is_active").eq("id", body.department_id).execute()
    if not dept_result.data:
        raise HTTPException(status_code=400, detail="Invalid department_id: department not found")
    if not dept_result.data[0].get("is_active", True):
        raise HTTPException(status_code=400, detail="Cannot update work order to inactive department")

    payload = {
        "job_no": body.job_no,
        "title": body.title,
        "description": body.description,
        "location": body.location,
        "mobile_number": body.mobile_number,
        "department_id": body.department_id,  # Changed from 'department' to 'department_id'
        "type": body.type,
        "status": body.status,
        "updated_at": datetime.utcnow().isoformat(),
    }
    supabase.table("work_orders").update(payload).eq("id", work_order_id).execute()

    user_id = _get_user_id_by_email(user_email) or "unknown"
    _sync_assignments(work_order_id, body.assigned_fixer_ids or [], user_id)

    if old_status != body.status:
        _log_status_change(work_order_id, old_status, body.status, user_id)

    log_activity(user_email, "work_order", "updated",
        target_label=body.title, target_id=work_order_id)

    return {"work_order": _fetch_full_work_order(work_order_id)}


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
    _ensure_not_reporter(user_email)
    existing = supabase.table("work_orders") \
        .select("id") \
        .eq("id", work_order_id) \
        .execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    supabase.table("work_orders").delete().eq("id", work_order_id).execute()
    log_activity(user_email, "work_order", "deleted",
        target_label=work_order_id, target_id=work_order_id)
    return {"status": "deleted"}


@router.delete("/work-orders")
async def delete_work_orders_bulk(
    ids: str = Query(..., description="Comma-separated work order IDs"),
    user_email: str = Query(...),
):
    _ensure_not_reporter(user_email)
    id_list = [i.strip() for i in ids.split(",") if i.strip()]
    if not id_list:
        raise HTTPException(status_code=400, detail="No IDs provided")

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

    return {"status": "uploaded", "file_url": public_url}


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
