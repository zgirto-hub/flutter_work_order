from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional

from db import supabase

router = APIRouter()


# --------------------
# Pydantic Models
# --------------------

class CreateFolderBody(BaseModel):
    name: str
    parent_id: Optional[str] = None
    created_by: str


class RenameFolderBody(BaseModel):
    name: str


class MoveFolderBody(BaseModel):
    parent_id: Optional[str] = None


class MoveDocumentBody(BaseModel):
    folder_id: Optional[str] = None


# --------------------
# Folder Endpoints
# --------------------

@router.get("/folders")
async def list_folders(
    user_email: str = Query(...),
    parent_id: Optional[str] = Query(None),
    all: bool = Query(False),
):
    query = supabase.table("document_folders").select("*")
    if not all:
        if parent_id:
            query = query.eq("parent_id", parent_id)
        else:
            query = query.is_("parent_id", "null")
    result = query.order("name", desc=False).execute()
    return {"folders": result.data or []}


@router.post("/folders")
async def create_folder(body: CreateFolderBody):
    data = {
        "name": body.name.strip(),
        "created_by": body.created_by,
    }
    if body.parent_id:
        data["parent_id"] = body.parent_id
    result = supabase.table("document_folders").insert(data).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create folder")
    return {"folder": result.data[0]}


@router.patch("/folders/{folder_id}/rename")
async def rename_folder(folder_id: str, body: RenameFolderBody, user_email: str = Query(...)):
    result = supabase.table("document_folders") \
        .select("created_by") \
        .eq("id", folder_id) \
        .execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Folder not found")
    if result.data[0]["created_by"] != user_email:
        raise HTTPException(status_code=403, detail="Not allowed to rename this folder")
    supabase.table("document_folders") \
        .update({"name": body.name.strip()}) \
        .eq("id", folder_id) \
        .execute()
    return {"status": "renamed"}


@router.delete("/folders/{folder_id}")
async def delete_folder(folder_id: str, user_email: str = Query(...)):
    result = supabase.table("document_folders") \
        .select("created_by") \
        .eq("id", folder_id) \
        .execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Folder not found")
    if result.data[0]["created_by"] != user_email:
        raise HTTPException(status_code=403, detail="Not allowed to delete this folder")
    # Orphan documents in this folder back to root before deleting
    supabase.table("documents") \
        .update({"folder_id": None}) \
        .eq("folder_id", folder_id) \
        .execute()
    supabase.table("document_folders").delete().eq("id", folder_id).execute()
    return {"status": "deleted"}


@router.patch("/folders/{folder_id}/move")
async def move_folder(folder_id: str, body: MoveFolderBody, user_email: str = Query(...)):
    result = supabase.table("document_folders") \
        .select("created_by") \
        .eq("id", folder_id) \
        .execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Folder not found")
    if result.data[0]["created_by"] != user_email:
        raise HTTPException(status_code=403, detail="Not allowed to move this folder")
    if body.parent_id == folder_id:
        raise HTTPException(status_code=400, detail="Cannot move a folder into itself")
    supabase.table("document_folders") \
        .update({"parent_id": body.parent_id}) \
        .eq("id", folder_id) \
        .execute()
    return {"status": "moved"}


# --------------------
# Move Document Endpoint
# --------------------

@router.patch("/documents/{doc_id}/move")
async def move_document(doc_id: str, body: MoveDocumentBody, user_email: str = Query(...)):
    result = supabase.table("documents") \
        .select("uploaded_by") \
        .eq("id", doc_id) \
        .execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Document not found")
    if result.data[0]["uploaded_by"] != user_email:
        raise HTTPException(status_code=403, detail="Not allowed to move this document")
    supabase.table("documents") \
        .update({"folder_id": body.folder_id}) \
        .eq("id", doc_id) \
        .execute()
    return {"status": "moved"}
