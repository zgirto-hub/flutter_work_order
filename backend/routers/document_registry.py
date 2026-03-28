from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from db import supabase
from utils.activity import log_activity

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
