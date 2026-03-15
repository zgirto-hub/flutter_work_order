from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

from db import supabase
from utils.notifications import send_push_notification

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
    supabase.table("requests").insert({
        "title": body.title,
        "description": body.description,
        "created_by": body.created_by,
        "requester_name": body.requester_name,
        "location": body.location,
        "status": "Open",
    }).execute()
    send_push_notification(
        title="New Request",
        body=f"{body.requester_name}: {body.title}",
    )
    return {"status": "created"}


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
    return {"status": "closed"}
