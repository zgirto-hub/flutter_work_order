from fastapi import APIRouter, HTTPException, Query, UploadFile, File, Form
from pydantic import BaseModel
from typing import Optional
import os
import uuid

from db import supabase
from utils.activity import log_activity

UPLOAD_DIR = "uploaded_files"
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
ALLOWED_EXTENSIONS = {"pdf", "doc", "docx", "jpg", "jpeg", "png", "gif"}

router = APIRouter()


class CreateRegistryEntryBody(BaseModel):
    document_name: str
    document_number: str
    date: str
    replied: bool = False
    created_by: str


class UpdateRegistryEntryBody(BaseModel):
    document_name: str
    document_number: str
    date: str
    replied: bool = False
    user_email: str


@router.get("/document-registry")
async def list_registry_entries(search: Optional[str] = Query(None)):
    """List all document registry entries, optionally filtered by search query."""
    result = supabase.table("document_registry") \
        .select("*") \
        .order("created_at", desc=True) \
        .execute()

    entries = result.data or []

    if search and search.strip():
        q = search.strip().lower()
        entries = [
            e for e in entries
            if q in (e.get("document_name") or "").lower()
            or q in (e.get("document_number") or "").lower()
        ]

    return {"entries": entries}


@router.post("/document-registry")
async def create_registry_entry(body: CreateRegistryEntryBody):
    """Create a new document registry entry."""
    if not body.document_name.strip():
        raise HTTPException(status_code=400, detail="Document name is required")
    if not body.document_number.strip():
        raise HTTPException(status_code=400, detail="Document number is required")
    if not body.date.strip():
        raise HTTPException(status_code=400, detail="Date is required")

    result = supabase.table("document_registry").insert({
        "document_name": body.document_name.strip(),
        "document_number": body.document_number.strip(),
        "date": body.date.strip(),
        "replied": body.replied,
        "created_by": body.created_by,
    }).execute()

    entry_id = result.data[0]["id"] if result.data else None

    log_activity(
        body.created_by,
        "document_registry",
        "created",
        target_label=body.document_name.strip(),
        target_id=str(entry_id or ""),
    )

    return {"status": "created", "id": entry_id}


@router.put("/document-registry/{entry_id}")
async def update_registry_entry(entry_id: str, body: UpdateRegistryEntryBody):
    """Update a document registry entry by ID."""
    existing = supabase.table("document_registry") \
        .select("id") \
        .eq("id", entry_id) \
        .execute()

    if not existing.data:
        raise HTTPException(status_code=404, detail="Entry not found")

    if not body.document_name.strip():
        raise HTTPException(status_code=400, detail="Document name is required")
    if not body.document_number.strip():
        raise HTTPException(status_code=400, detail="Document number is required")
    if not body.date.strip():
        raise HTTPException(status_code=400, detail="Date is required")

    supabase.table("document_registry").update({
        "document_name": body.document_name.strip(),
        "document_number": body.document_number.strip(),
        "date": body.date.strip(),
        "replied": body.replied,
    }).eq("id", entry_id).execute()

    log_activity(
        body.user_email,
        "document_registry",
        "updated",
        target_label=body.document_name.strip(),
        target_id=entry_id,
    )

    return {"status": "updated"}


@router.delete("/document-registry/{entry_id}")
async def delete_registry_entry(
    entry_id: str,
    user_email: str = Query(..., description="Email of the user performing the delete"),
):
    """Delete a document registry entry by ID."""
    existing = supabase.table("document_registry") \
        .select("id, document_name") \
        .eq("id", entry_id) \
        .execute()

    if not existing.data:
        raise HTTPException(status_code=404, detail="Entry not found")

    label = existing.data[0].get("document_name", "")

    supabase.table("document_registry").delete().eq("id", entry_id).execute()

    log_activity(
        user_email,
        "document_registry",
        "deleted",
        target_label=label,
        target_id=entry_id,
    )

    return {"status": "deleted"}


@router.post("/document-registry/{entry_id}/attachment")
async def upload_registry_attachment(
    entry_id: str,
    file: UploadFile = File(...),
    uploaded_by: str = Form(...),
):
    """Upload a file attachment for a registry entry."""
    existing = supabase.table("document_registry") \
        .select("id") \
        .eq("id", entry_id) \
        .execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Entry not found")

    # Read and validate file
    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=400,
            detail=f"File too large. Maximum size is {MAX_FILE_SIZE // (1024*1024)}MB",
        )

    extension = file.filename.split(".")[-1].lower() if "." in file.filename else ""
    if extension not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"File type not allowed. Allowed: {', '.join(sorted(ALLOWED_EXTENSIONS))}",
        )

    file_id = str(uuid.uuid4())
    filename = f"reg_{file_id}.{extension}"
    file_path = os.path.join(UPLOAD_DIR, filename)

    with open(file_path, "wb") as f:
        f.write(content)

    public_url = f"/files/{filename}"

    supabase.table("document_registry").update({
        "file_name": file.filename,
        "file_url": public_url,
    }).eq("id", entry_id).execute()

    log_activity(
        uploaded_by,
        "document_registry",
        "attachment_uploaded",
        target_label=file.filename,
        target_id=entry_id,
    )

    return {"status": "uploaded", "file_url": public_url, "file_name": file.filename}


@router.delete("/document-registry/{entry_id}/attachment")
async def delete_registry_attachment(
    entry_id: str,
    user_email: str = Query(...),
):
    """Remove the file attachment from a registry entry."""
    existing = supabase.table("document_registry") \
        .select("id, file_url, file_name") \
        .eq("id", entry_id) \
        .execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Entry not found")

    file_url = existing.data[0].get("file_url")
    if file_url:
        fname = os.path.basename(file_url)
        abs_path = os.path.join(UPLOAD_DIR, fname)
        if os.path.exists(abs_path):
            os.remove(abs_path)

    supabase.table("document_registry").update({
        "file_name": None,
        "file_url": None,
    }).eq("id", entry_id).execute()

    log_activity(
        user_email,
        "document_registry",
        "attachment_deleted",
        target_id=entry_id,
    )

    return {"status": "deleted"}
