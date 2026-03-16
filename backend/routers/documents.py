from fastapi import APIRouter, UploadFile, File, Form, Query, HTTPException
from typing import Optional
import os
import uuid

from db import supabase
from utils.text_extraction import extract_text
from utils.permissions import can

router = APIRouter()

UPLOAD_DIR = "uploaded_files"


@router.post("/upload")
async def upload_file(
    file: UploadFile = File(...),
    title: str = Form(...),
    document_type: str = Form(...),
    is_private: bool = Form(False),
    uploaded_by: str = Form(...),
    folder_id: Optional[str] = Form(None),
):
    file_id = str(uuid.uuid4())
    extension = file.filename.split(".")[-1].lower()
    filename = f"{file_id}.{extension}"
    file_path = os.path.join(UPLOAD_DIR, filename)

    with open(file_path, "wb") as f:
        content = await file.read()
        f.write(content)

    public_url = f"/files/{filename}"
    parsed_text = extract_text(file_path, extension)

    record = {
        "title": title,
        "document_type": document_type,
        "file_name": file.filename,
        "file_extension": extension,
        "mime_type": file.content_type,
        "file_path": public_url,
        "parsed_text": parsed_text,
        "is_private": is_private,
        "uploaded_by": uploaded_by,
        "file_size": len(content),
    }
    if folder_id:
        record["folder_id"] = folder_id

    supabase.table("documents").insert(record).execute()

    return {"status": "success", "file_url": public_url}


@router.delete("/delete/{doc_id}")
async def delete_document(doc_id: str, user_email: str = Query(...)):
    response = supabase.table("documents") \
        .select("file_path, uploaded_by, folder_id") \
        .eq("id", doc_id) \
        .execute()

    if not response.data:
        return {"error": "Document not found"}

    doc = response.data[0]

    if not can(
        user_email, "delete", doc_id, "document",
        folder_id=doc.get("folder_id"),
        resource_owner=doc["uploaded_by"]
    ):
        raise HTTPException(status_code=403, detail="You are not allowed to delete this document")

    file_path = doc["file_path"]
    if file_path:
        filename = os.path.basename(file_path)
        absolute_path = os.path.join(UPLOAD_DIR, filename)
        if os.path.exists(absolute_path):
            os.remove(absolute_path)

    supabase.table("documents").delete().eq("id", doc_id).execute()
    # Also clean up any permissions for this document
    supabase.table("resource_permissions") \
        .delete() \
        .eq("resource_id", doc_id) \
        .eq("resource_type", "document") \
        .execute()

    return {"status": "deleted"}


@router.post("/share-document")
async def share_document(
    document_id: str = Form(...),
    owner_email: str = Form(...),
    share_with: str = Form(...),
    role: str = Form("viewer"),   # 'viewer' | 'editor'
):
    if role not in ("viewer", "editor"):
        raise HTTPException(status_code=400, detail="role must be 'viewer' or 'editor'")

    response = supabase.table("documents") \
        .select("uploaded_by") \
        .eq("id", document_id) \
        .execute()

    if not response.data:
        raise HTTPException(status_code=404, detail="Document not found")

    owner = response.data[0]["uploaded_by"]

    if owner != owner_email:
        raise HTTPException(status_code=403, detail="Only the owner can share this document")

    if owner_email == share_with:
        raise HTTPException(status_code=400, detail="You already own this document")

    # Upsert — update role if already shared
    supabase.table("resource_permissions").upsert({
        "resource_id": document_id,
        "resource_type": "document",
        "user_email": share_with,
        "role": role,
        "granted_by": owner_email,
    }, on_conflict="resource_id,resource_type,user_email").execute()

    return {"status": "document shared", "role": role}


@router.get("/document-shares/{doc_id}")
async def get_document_shares(doc_id: str):
    response = supabase.table("resource_permissions") \
        .select("user_email, role") \
        .eq("resource_id", doc_id) \
        .eq("resource_type", "document") \
        .execute()

    if not response.data:
        return {"users": [], "shares": []}

    users = [row["user_email"] for row in response.data]
    shares = [{"email": row["user_email"], "role": row["role"]} for row in response.data]
    return {"users": users, "shares": shares}


@router.delete("/remove-share")
async def remove_share(
    document_id: str = Query(...),
    owner_email: str = Query(...),
    remove_user: str = Query(...)
):
    response = supabase.table("documents") \
        .select("uploaded_by") \
        .eq("id", document_id) \
        .execute()

    if not response.data:
        raise HTTPException(status_code=404, detail="Document not found")

    owner = response.data[0]["uploaded_by"]

    if owner != owner_email:
        raise HTTPException(status_code=403, detail="Only owner can remove access")

    # Remove from new table
    supabase.table("resource_permissions") \
        .delete() \
        .eq("resource_id", document_id) \
        .eq("resource_type", "document") \
        .eq("user_email", remove_user) \
        .execute()

    return {"status": "access removed"}


@router.get("/users")
async def list_users():
    response = supabase.table("documents").select("uploaded_by").execute()

    if not response.data:
        return {"users": []}

    users = list({row["uploaded_by"] for row in response.data if row["uploaded_by"]})
    users.sort()
    return {"users": users}


@router.get("/documents/{doc_id}/my-role")
async def get_my_role(doc_id: str, user_email: str = Query(...)):
    """Returns the calling user's effective role on a document."""
    doc = supabase.table("documents") \
        .select("uploaded_by, folder_id") \
        .eq("id", doc_id) \
        .execute()

    if not doc.data:
        raise HTTPException(status_code=404, detail="Document not found")

    d = doc.data[0]

    if d["uploaded_by"] == user_email:
        return {"role": "owner"}

    from utils.permissions import get_effective_role
    role = get_effective_role(
        user_email, doc_id, "document",
        folder_id=d.get("folder_id"),
        resource_owner=d["uploaded_by"]
    )
    return {"role": role or "none"}
