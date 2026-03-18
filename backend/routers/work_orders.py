from fastapi import APIRouter, Query, HTTPException, UploadFile, File, Form
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
import os
import uuid

from db import supabase
from utils.activity import log_activity
from utils.notification_service import dispatch_work_order_comment_notification

router = APIRouter()

UPLOAD_DIR = "uploaded_files"

# --------------------
# Pydantic Models
# --------------------

class CreateWorkOrderBody(BaseModel):
    job_no: str
    title: str
    description: Optional[str] = ""
    location: str = ""
    mobile_number: Optional[str] = ""
    department: str
    type: str = "Technical"
    status: str = "Pending"
    created_by: str
    created_by_email: Optional[str] = ""
    assigned_employee_ids: Optional[List[str]] = []


class UpdateWorkOrderBody(BaseModel):
    job_no: str
    title: str
    description: Optional[str] = ""
    location: str
    mobile_number: Optional[str] = ""
    department: str
    type: str
    status: str
    assigned_employee_ids: Optional[List[str]] = []


class CloseWorkOrderBody(BaseModel):
    closed_by: str
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

ALLOWED_TYPES = {"Technical", "Inspection", "Other"}
ALLOWED_STATUSES = {"Pending", "In Progress", "Closed"}


def _get_user_role(email: str) -> str:
    normalized = email.strip().lower()
    if not normalized:
        return "admin"
    result = supabase.table("user_profiles") \
        .select("user_type") \
        .eq("email", normalized) \
        .limit(1) \
        .execute()
    if not result.data:
        return "admin"
    return (result.data[0].get("user_type") or "admin").strip().lower()


def _get_user_department(email: str) -> Optional[str]:
    normalized = email.strip().lower()
    result = supabase.table("employees") \
        .select("department") \
        .eq("profile_id", normalized) \
        .execute()
    if result.data and result.data[0].get("department"):
        return result.data[0]["department"]
    return None


def _ensure_not_requester(email: str):
    if _get_user_role(email) == "requester":
        raise HTTPException(
            status_code=403,
            detail="Requester is not allowed to modify or delete work orders",
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
    result = supabase.table("work_orders").select("""
        *,
        work_order_assignments (
            employee_id,
            employees (
                id,
                full_name,
                department
            )
        )
    """).eq("id", work_order_id).single().execute()
    return result.data


def _sync_assignments(work_order_id: str, employee_ids: List[str]):
    supabase.table("work_order_assignments") \
        .delete() \
        .eq("work_order_id", work_order_id) \
        .execute()
    if employee_ids:
        assignments = [
            {"work_order_id": work_order_id, "employee_id": emp_id}
            for emp_id in employee_ids
        ]
        supabase.table("work_order_assignments").insert(assignments).execute()


# --------------------
# Endpoints
# --------------------

@router.get("/work-orders")
async def list_work_orders(
    email: Optional[str] = Query(None),
    user_role: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    type: Optional[str] = Query(None),
    department: Optional[str] = Query(None),
):
    query = supabase.table("work_orders").select("""
        *,
        work_order_assignments (
            employee_id,
            employees (
                id,
                full_name,
                department
            )
        )
    """).order("created_at", desc=True)

    if status:
        query = query.eq("status", status)
    if type:
        query = query.eq("type", type)
    if department:
        query = query.eq("department", department)

    result = query.execute()
    work_orders = result.data or []
    
    if user_role == "requester" and email:
        work_orders = [wo for wo in work_orders if wo.get("created_by") == email]
    elif user_role == "tech" and email:
        user_dept = _get_user_department(email)
        if user_dept:
            work_orders = [wo for wo in work_orders if wo.get("department") == user_dept]
    
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

    try:
        supabase.table("work_orders").insert({
            "job_no": body.job_no,
            "title": body.title,
            "description": body.description,
            "location": body.location,
            "mobile_number": body.mobile_number,
            "department": body.department,
            "type": body.type,
            "status": body.status,
            "created_by": body.created_by,
        }).execute()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"DB insert failed: {e}")

    fetch = supabase.table("work_orders").select("id").eq("job_no", body.job_no).single().execute()
    if not fetch.data:
        raise HTTPException(status_code=500, detail="Work order created but could not retrieve ID")

    work_order_id = fetch.data["id"]

    if body.assigned_employee_ids:
        try:
            _sync_assignments(work_order_id, body.assigned_employee_ids)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Assignment sync failed: {e}")

    try:
        supabase.table("work_order_comments").insert({
            "work_order_id": work_order_id,
            "author_email": body.created_by_email or body.created_by,
            "author_name": (body.created_by_email or "").split("@")[0] or body.created_by[:8],
            "body": "Work order created.",
            "type": "system",
            "meta": None,
        }).execute()
    except Exception:
        pass

    log_activity(body.created_by_email or body.created_by, "work_order", "created",
        target_label=body.title, target_id=work_order_id,
        detail=body.job_no)

    return {"work_order": _fetch_full_work_order(work_order_id)}


@router.patch("/work-orders/{work_order_id}")
async def update_work_order(
    work_order_id: str,
    body: UpdateWorkOrderBody,
    user_email: str = Query(...),
):
    _ensure_not_requester(user_email)
    _validate_type(body.type)
    _validate_status(body.status)

    existing = supabase.table("work_orders") \
        .select("id, created_by, status") \
        .eq("id", work_order_id) \
        .execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    existing_status = existing.data[0].get("status")

    supabase.table("work_orders").update({
        "job_no": body.job_no,
        "title": body.title,
        "description": body.description,
        "location": body.location,
        "mobile_number": body.mobile_number,
        "department": body.department,
        "type": body.type,
        "status": body.status,
        "updated_at": datetime.utcnow().isoformat(),
    }).eq("id", work_order_id).execute()

    _sync_assignments(work_order_id, body.assigned_employee_ids or [])

    if existing_status and existing_status != body.status:
        try:
            supabase.table("work_order_comments").insert({
                "work_order_id": work_order_id,
                "author_email": user_email,
                "author_name": user_email.split("@")[0],
                "body": f"Status changed from {existing_status} to {body.status}",
                "type": "status_change",
                "meta": {"from": existing_status, "to": body.status},
            }).execute()
        except Exception:
            pass

    log_activity(user_email, "work_order", "updated",
        target_label=body.title, target_id=work_order_id,
        detail=f"status: {body.status}")

    return {"work_order": _fetch_full_work_order(work_order_id)}


@router.patch("/work-orders/{work_order_id}/close")
async def close_work_order(
    work_order_id: str,
    body: CloseWorkOrderBody,
):
    _ensure_not_requester(body.closed_by)
    existing = supabase.table("work_orders") \
        .select("id, status") \
        .eq("id", work_order_id) \
        .execute()

    if not existing.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    if existing.data[0]["status"] == "Closed":
        raise HTTPException(status_code=400, detail="Work order already closed")

    now = datetime.utcnow().isoformat()

    supabase.table("work_orders").update({
        "status": "Closed",
        "closed_by": body.closed_by,
        "closed_at": now,
        "tech_notes": body.tech_notes,
        "updated_at": now,
    }).eq("id", work_order_id).execute()

    log_activity(body.closed_by, "work_order", "closed",
        target_label=work_order_id, target_id=work_order_id)

    return {"status": "closed"}


@router.delete("/work-orders/{work_order_id}")
async def delete_work_order(
    work_order_id: str,
    user_email: str = Query(...),
):
    _ensure_not_requester(user_email)
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
    _ensure_not_requester(user_email)
    id_list = [i.strip() for i in ids.split(",") if i.strip()]
    if not id_list:
        raise HTTPException(status_code=400, detail="No IDs provided")

    supabase.table("work_orders").delete().in_("id", id_list).execute()
    return {"status": "deleted", "count": len(id_list)}


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

@router.post("/work-orders/{work_order_id}/attachments")
async def upload_attachment(
    work_order_id: str,
    file: UploadFile = File(...),
    uploaded_by: str = Form(...),
):
    file_id = str(uuid.uuid4())
    extension = file.filename.split(".")[-1].lower() if "." in file.filename else "bin"
    filename = f"wo_{file_id}.{extension}"
    file_path = os.path.join(UPLOAD_DIR, filename)

    with open(file_path, "wb") as f:
        content = await file.read()
        f.write(content)

    public_url = f"/files/{filename}"

    supabase.table("work_order_attachments").insert({
        "work_order_id": work_order_id,
        "file_name": file.filename,
        "file_url": public_url,
        "file_type": file.content_type,
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
