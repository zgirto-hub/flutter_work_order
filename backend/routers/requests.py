from fastapi import APIRouter, Query, HTTPException, UploadFile, File, Form
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import os
import uuid

from db import supabase
from utils.notifications import send_push_notification
from utils.activity import log_activity

UPLOAD_DIR = "uploaded_files"

router = APIRouter()


class CreateRequestBody(BaseModel):
    title: str
    description: Optional[str] = None
    created_by: str
    requester_name: str
    location: Optional[str] = None


class CloseRequestBody(BaseModel):
    closed_by: str
    tech_notes: Optional[str] = None


class UpdateRequestBody(BaseModel):
    title: str
    description: str = ""
    requester_name: str
    location: str = ""
    email: str


@router.get("/requests/count-open")
async def count_open_requests():
    result = supabase.table("requests").select("id").eq("status", "Open").execute()
    return {"count": len(result.data or [])}


@router.get("/requests")
async def get_requests(email: str = Query(...), user_role: str = Query(...)):
    query = supabase.table("requests").select("*")
    if user_role == "requester":
        query = query.eq("created_by", email)
    result = query.order("created_at", desc=True).execute()
    return {"requests": result.data or []}


@router.post("/requests")
async def create_request(body: CreateRequestBody):
    result = supabase.table("requests").insert({
        "title": body.title,
        "description": body.description,
        "created_by": body.created_by,
        "requester_name": body.requester_name,
        "location": body.location,
        "status": "Open",
    }).execute()

    # Get the generated id from the insert result
    if result.data and result.data[0].get("id") is not None:
        request_id = str(result.data[0]["id"])
    else:
        # Fallback: query the most recently created request by this user
        latest = supabase.table("requests") \
            .select("id") \
            .eq("created_by", body.created_by) \
            .order("created_at", desc=True) \
            .limit(1) \
            .execute()
        request_id = str(latest.data[0]["id"]) if latest.data else None

    send_push_notification(
        title="New Request",
        body=f"{body.requester_name}: {body.title}",
    )
    log_activity(body.created_by, "request", "created",
        target_label=body.title, target_id=request_id or "")
    return {"status": "created", "id": request_id}


@router.delete("/requests/{request_id}")
async def delete_request(request_id: str, email: str = Query(...)):
    result = supabase.table("requests") \
        .select("created_by") \
        .eq("id", request_id) \
        .execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Request not found")
    row = result.data[0]
    if row["created_by"] != email:
        raise HTTPException(status_code=403, detail="Not allowed to delete this request")
    supabase.table("requests").delete().eq("id", request_id).execute()
    log_activity(email, "request", "deleted",
        target_label=request_id, target_id=request_id)
    return {"status": "deleted"}


@router.post("/requests/{request_id}/update")
async def update_request(request_id: str, body: UpdateRequestBody):
    result = supabase.table("requests") \
        .select("status, created_by") \
        .eq("id", request_id) \
        .execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Request not found")
    req = result.data[0]
    if req["status"] == "Closed":
        raise HTTPException(status_code=400, detail="Cannot edit a closed request")
    if req["created_by"] != body.email:
        raise HTTPException(status_code=403, detail="Not authorized to edit this request")
    supabase.table("requests").update({
        "title": body.title,
        "description": body.description,
        "requester_name": body.requester_name,
        "location": body.location,
    }).eq("id", request_id).execute()
    return {"status": "updated"}


@router.patch("/requests/{request_id}/close")
async def close_request(request_id: str, body: CloseRequestBody):
    result = supabase.table("requests") \
        .select("status") \
        .eq("id", request_id) \
        .execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Request not found")
    if result.data[0]["status"] == "Closed":
        raise HTTPException(status_code=400, detail="Request already closed")
    supabase.table("requests").update({
        "status": "Closed",
        "closed_by": body.closed_by,
        "closed_at": datetime.utcnow().isoformat(),
        "tech_notes": body.tech_notes,
    }).eq("id", request_id).execute()
    log_activity(body.closed_by, "request", "closed",
        target_label=request_id, target_id=request_id)
    return {"status": "closed"}


# ── Attachments ───────────────────────────────────────────────────────────────

@router.post("/requests/{request_id}/attachments")
async def upload_request_attachment(
    request_id: str,
    file: UploadFile = File(...),
    uploaded_by: str = Form(...),
):
    file_id = str(uuid.uuid4())
    extension = file.filename.split(".")[-1].lower() if "." in file.filename else "bin"
    filename = f"req_{file_id}.{extension}"
    file_path = os.path.join(UPLOAD_DIR, filename)

    with open(file_path, "wb") as f:
        content = await file.read()
        f.write(content)

    public_url = f"/files/{filename}"

    supabase.table("request_attachments").insert({
        "request_id": request_id,
        "file_name": file.filename,
        "file_path": public_url,
        "mime_type": file.content_type,
        "uploaded_by": uploaded_by,
    }).execute()

    return {"status": "uploaded", "file_url": public_url}


@router.get("/requests/{request_id}/attachments")
async def get_request_attachments(request_id: str):
    result = supabase.table("request_attachments") \
        .select("*") \
        .eq("request_id", request_id) \
        .order("created_at") \
        .execute()
    return {"attachments": result.data or []}


@router.delete("/requests/{request_id}/attachments/{attachment_id}")
async def delete_request_attachment(
    request_id: str,
    attachment_id: str,
    email: str = Query(...),
):
    result = supabase.table("request_attachments") \
        .select("uploaded_by, file_path") \
        .eq("id", attachment_id) \
        .execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Attachment not found")
    att = result.data[0]
    if att["uploaded_by"] != email:
        raise HTTPException(status_code=403, detail="Not allowed to delete this attachment")

    file_path = att["file_path"]
    if file_path:
        fname = os.path.basename(file_path)
        abs_path = os.path.join(UPLOAD_DIR, fname)
        if os.path.exists(abs_path):
            os.remove(abs_path)

    supabase.table("request_attachments").delete().eq("id", attachment_id).execute()
    return {"status": "deleted"}
