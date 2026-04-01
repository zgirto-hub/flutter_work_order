from fastapi import APIRouter, UploadFile, File, Form, Query, HTTPException
from typing import Optional
import os
import uuid

from db import supabase
from utils.text_extraction import extract_text
from utils.permissions import can
from utils.activity import log_activity

router = APIRouter()

UPLOAD_DIR = "uploaded_files"


@router.post("/upload")
async def upload_file(
    file: UploadFile = File(...),
    title: str = Form(...),
    file_type: str = Form(...),
    is_private: bool = Form(False),
    uploaded_by: str = Form(...),
    folder_id: Optional[str] = Form(None),
    expiration_date: Optional[str] = Form(None),
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
        "file_type": file_type,
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
    if expiration_date:
        record["expiration_date"] = expiration_date

    supabase.table("files").insert(record).execute()

    log_activity(uploaded_by, "file", "uploaded",
        target_label=title, target_id=file_id, detail=file_type)

    return {"status": "success", "file_url": public_url}


@router.delete("/delete/{file_id}")
async def delete_file(file_id: str, user_email: str = Query(...)):
    response = supabase.table("files") \
        .select("file_path, uploaded_by, folder_id") \
        .eq("id", file_id) \
        .execute()

    if not response.data:
        return {"error": "File not found"}

    doc = response.data[0]

    if not can(
        user_email, "delete", file_id, "file",
        folder_id=doc.get("folder_id"),
        resource_owner=doc["uploaded_by"]
    ):
        raise HTTPException(status_code=403, detail="You are not allowed to delete this file")

    file_path = doc["file_path"]
    if file_path:
        filename = os.path.basename(file_path)
        absolute_path = os.path.join(UPLOAD_DIR, filename)
        if os.path.exists(absolute_path):
            os.remove(absolute_path)

    supabase.table("files").delete().eq("id", file_id).execute()
    log_activity(user_email, "file", "deleted",
        target_label=doc.get("title", ""), target_id=file_id)
    # Also clean up any permissions for this file
    supabase.table("resource_permissions") \
        .delete() \
        .eq("resource_id", file_id) \
        .eq("resource_type", "file") \
        .execute()

    return {"status": "deleted"}


@router.post("/share-file")
async def share_file(
    file_id: str = Form(...),
    owner_email: str = Form(...),
    share_with: str = Form(...),
    role: str = Form("viewer"),   # 'viewer' | 'editor'
):
    if role not in ("viewer", "editor"):
        raise HTTPException(status_code=400, detail="role must be 'viewer' or 'editor'")

    response = supabase.table("files") \
        .select("uploaded_by") \
        .eq("id", file_id) \
        .execute()

    if not response.data:
        raise HTTPException(status_code=404, detail="File not found")

    owner = response.data[0]["uploaded_by"]

    if owner != owner_email:
        raise HTTPException(status_code=403, detail="Only the owner can share this file")

    if owner_email == share_with:
        raise HTTPException(status_code=400, detail="You already own this file")

    # Upsert — update role if already shared
    supabase.table("resource_permissions").upsert({
        "resource_id": file_id,
        "resource_type": "file",
        "user_email": share_with,
        "role": role,
        "granted_by": owner_email,
    }, on_conflict="resource_id,resource_type,user_email").execute()

    log_activity(owner_email, "file", "shared",
        target_label=file_id, target_id=file_id,
        detail=f"with {share_with} as {role}")

    return {"status": "file shared", "role": role}


@router.get("/file-shares/{file_id}")
async def get_file_shares(file_id: str):
    response = supabase.table("resource_permissions") \
        .select("user_email, role") \
        .eq("resource_id", file_id) \
        .eq("resource_type", "file") \
        .execute()

    if not response.data:
        return {"users": [], "shares": []}

    users = [row["user_email"] for row in response.data]
    shares = [{"email": row["user_email"], "role": row["role"]} for row in response.data]
    return {"users": users, "shares": shares}


@router.delete("/remove-share")
async def remove_share(
    file_id: str = Query(...),
    owner_email: str = Query(...),
    remove_user: str = Query(...)
):
    response = supabase.table("files") \
        .select("uploaded_by") \
        .eq("id", file_id) \
        .execute()

    if not response.data:
        raise HTTPException(status_code=404, detail="File not found")

    owner = response.data[0]["uploaded_by"]

    if owner != owner_email:
        raise HTTPException(status_code=403, detail="Only owner can remove access")

    # Remove from new table
    supabase.table("resource_permissions") \
        .delete() \
        .eq("resource_id", file_id) \
        .eq("resource_type", "file") \
        .eq("user_email", remove_user) \
        .execute()

    return {"status": "access removed"}


@router.patch("/files/{file_id}/expiration")
async def update_expiration(
    file_id: str,
    expiration_date: Optional[str] = Query(None),
    user_email: str = Query(...),
):
    """Set or clear the expiration date on a file."""
    doc = supabase.table("files") \
        .select("uploaded_by, folder_id") \
        .eq("id", file_id) \
        .execute()

    if not doc.data:
        raise HTTPException(status_code=404, detail="File not found")

    d = doc.data[0]

    if not can(
        user_email, "edit", file_id, "file",
        folder_id=d.get("folder_id"),
        resource_owner=d["uploaded_by"]
    ):
        raise HTTPException(status_code=403, detail="Not allowed to edit this file")

    supabase.table("files") \
        .update({"expiration_date": expiration_date}) \
        .eq("id", file_id) \
        .execute()

    log_activity(user_email, "file", "updated_expiration",
        target_label=file_id, target_id=file_id,
        detail=f"expiration set to {expiration_date or 'none'}")

    return {"status": "updated", "expiration_date": expiration_date}


@router.get("/file-uploaders")
async def list_file_uploaders():
    response = supabase.table("files").select("uploaded_by").execute()

    if not response.data:
        return {"users": []}

    users = list({row["uploaded_by"] for row in response.data if row["uploaded_by"]})
    users.sort()
    return {"users": users}


@router.get("/files/{file_id}/my-role")
async def get_my_role(file_id: str, user_email: str = Query(...)):
    """Returns the calling user's effective role on a file."""
    doc = supabase.table("files") \
        .select("uploaded_by, folder_id") \
        .eq("id", file_id) \
        .execute()

    if not doc.data:
        raise HTTPException(status_code=404, detail="File not found")

    d = doc.data[0]

    if d["uploaded_by"] == user_email:
        return {"role": "owner"}

    from utils.permissions import get_effective_role
    role = get_effective_role(
        user_email, file_id, "file",
        folder_id=d.get("folder_id"),
        resource_owner=d["uploaded_by"]
    )
    return {"role": role or "none"}
