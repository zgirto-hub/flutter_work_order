from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

from db import supabase
from utils.activity import log_activity
from utils.notification_service import dispatch_work_order_comment_notification

router = APIRouter()

# --------------------
# Pydantic Models
# --------------------

class CreateWorkOrderBody(BaseModel):
    job_no: str
    title: str
    description: Optional[str] = ""
    location: str
    type: str = "Technical"
    status: str = "Pending"
    created_by: str
    created_by_email: Optional[str] = ""
    assigned_employee_ids: Optional[List[str]] = []
    source_request_id: Optional[str] = None


class UpdateWorkOrderBody(BaseModel):
    job_no: str
    title: str
    description: Optional[str] = ""
    location: str
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
    type: str = "comment"        # 'comment' | 'status_change' | 'system'
    meta: Optional[dict] = None  # e.g. {"from": "Pending", "to": "In Progress"}


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
    """Fetch a work order with its assigned employees."""
    result = supabase.table("work_orders").select("""
        *,
        work_order_assignments (
            employee_id,
            employees (
                id,
                full_name
            )
        )
    """).eq("id", work_order_id).single().execute()
    return result.data


def _sync_assignments(work_order_id: str, employee_ids: List[str]):
    """Delete existing assignments and insert new ones."""
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
    status: Optional[str] = Query(None),
    type: Optional[str] = Query(None),
    request_id: Optional[str] = Query(None),
):
    query = supabase.table("work_orders").select("""
        *,
        work_order_assignments (
            employee_id,
            employees (
                id,
                full_name
            )
        )
    """).order("created_at", desc=True)

    if status:
        query = query.eq("status", status)
    if type:
        query = query.eq("type", type)
    if request_id:
        query = query.eq("request_id", request_id)

    result = query.execute()
    return {"work_orders": result.data or []}


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

    if body.source_request_id:
        existing = supabase.table("work_orders") \
            .select("id") \
            .eq("request_id", body.source_request_id) \
            .limit(1) \
            .execute()
        if existing.data:
            raise HTTPException(
                status_code=409,
                detail="Request already linked to a work order",
            )

    try:
        supabase.table("work_orders").insert({
            "job_no": body.job_no,
            "title": body.title,
            "description": body.description,
            "location": body.location,
            "type": body.type,
            "status": body.status,
            "created_by": body.created_by,
            "request_id": body.source_request_id,
        }).execute()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"DB insert failed: {e}")

    fetch = supabase.table("work_orders").select("id").eq("job_no", body.job_no).single().execute()
    if not fetch.data:
        raise HTTPException(status_code=500, detail="Work order created but could not retrieve ID")

    work_order_id = fetch.data["id"]

    # Insert employee assignments
    if body.assigned_employee_ids:
        try:
            _sync_assignments(work_order_id, body.assigned_employee_ids)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Assignment sync failed: {e}")

    # Auto-log creation as a system event (best-effort)
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
    import sys
    print(f"[CASCADE DEBUG] update_work_order called for {work_order_id}, status={body.status}", file=sys.stderr)
    _ensure_not_requester(user_email)
    _validate_type(body.type)
    _validate_status(body.status)

    # Check exists and capture current status for change detection
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
        "type": body.type,
        "status": body.status,
        "updated_at": datetime.utcnow().isoformat(),
    }).eq("id", work_order_id).execute()

    _sync_assignments(work_order_id, body.assigned_employee_ids or [])

    # Cascade status change to linked request (best-effort)
    try:
        import sys
        wo = supabase.table("work_orders") \
            .select("id, request_id, status, closed_at") \
            .eq("id", work_order_id) \
            .execute()
        print(f"[CASCADE DEBUG] WO fetch result: {wo.data}", file=sys.stderr)
        if wo.data:
            wo_data = wo.data[0]
            request_id = wo_data.get("request_id")
            status = wo_data.get("status")
            print(f"[CASCADE DEBUG] WO data: request_id={request_id}, status={status}", file=sys.stderr)
            if request_id and status:
                req = supabase.table("requests") \
                    .select("id, status") \
                    .eq("id", request_id) \
                    .execute()
                print(f"[CASCADE DEBUG] Request fetch result: {req.data}", file=sys.stderr)
                if req.data:
                    current_req_status = req.data[0].get("status")
                    print(f"[CASCADE DEBUG] Current request status: {current_req_status}, WO status: {status}", file=sys.stderr)
                    if current_req_status != status:
                        print(f"[CASCADE DEBUG] Updating request {request_id} to status {status}", file=sys.stderr)
                        update_data = {"status": status}
                        if status == "Closed":
                            update_data["closed_at"] = wo_data.get("closed_at")
                        supabase.table("requests").update(update_data).eq("id", request_id).execute()
                        print(f"[CASCADE DEBUG] Request update completed", file=sys.stderr)
                    else:
                        print(f"[CASCADE DEBUG] Skipped - statuses already match", file=sys.stderr)
    except Exception as e:
        print(f"[CASCADE ERROR] {e}", file=sys.stderr)

    # Auto-log status change (best-effort)
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
        .select("id, status, request_id") \
        .eq("id", work_order_id) \
        .execute()

    if not existing.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    wo = existing.data[0]
    if wo["status"] == "Closed":
        raise HTTPException(status_code=400, detail="Work order already closed")

    now = datetime.utcnow().isoformat()

    supabase.table("work_orders").update({
        "status": "Closed",
        "closed_by": body.closed_by,
        "closed_at": now,
        "tech_notes": body.tech_notes,
        "updated_at": now,
    }).eq("id", work_order_id).execute()

    # If linked to a request, close it too
    request_id = wo.get("request_id")
    if request_id:
        req = supabase.table("requests") \
            .select("status") \
            .eq("id", request_id) \
            .execute()
        if req.data and req.data[0]["status"] != "Closed":
            supabase.table("requests").update({
                "status": "Closed",
                "closed_by": body.closed_by,
                "closed_at": now,
                "tech_notes": body.tech_notes,
            }).eq("id", request_id).execute()

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

    # Assignments deleted by DB cascade
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
