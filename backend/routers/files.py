from fastapi import APIRouter, UploadFile, File, Form, Query, HTTPException
from pydantic import BaseModel
from typing import Optional
import os
import uuid

from db import supabase
from utils.text_extraction import extract_text
from utils.permissions import can
from utils.activity import log_activity
from utils.file_visibility import is_global_viewer, get_user_department_ids, get_user_by_email

router = APIRouter()

UPLOAD_DIR = "uploaded_files"


class PatchDepartmentBody(BaseModel):
    department_id: Optional[str] = None


def _flatten_file(row: dict) -> dict:
    """Extract department_name from the Supabase join result and clean up."""
    dept_name = None
    if row.get("departments") and isinstance(row["departments"], dict):
        dept_name = row["departments"].get("name")
    row["department_name"] = dept_name
    row.pop("departments", None)
    return row


@router.get("/files/list")
async def list_files(user_email: str = Query(...)):
    """List files visible to the caller, applying department-scope filtering (FR-002, FR-003, FR-016).

    Visibility for scoped viewers:
        A file is visible when (privacy_ok AND scope_ok), OR it is explicitly shared.
        privacy_ok = not is_private OR uploaded_by == self
        scope_ok  = department_id IS NULL OR department_id IN user_depts
        An explicit share (resource_permissions) overrides both checks (FR-016).

    Global viewers (admin/supervisor/superintendent) see all files with no filter (FR-002).
    """
    if not user_email:
        raise HTTPException(status_code=400, detail="user_email is required")

    user = get_user_by_email(user_email)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    all_rows = supabase.table("files") \
        .select("*, departments(name)") \
        .order("created_at", desc=True) \
        .execute()
    files = [_flatten_file(r) for r in (all_rows.data or [])]

    # Global viewers see everything (FR-002)
    if is_global_viewer(user):
        return {"files": files}

    # --- Scoped viewer ---
    user_id = user["id"]
    dept_ids = set(get_user_department_ids(user_id))

    shared_resp = supabase.table("resource_permissions") \
        .select("resource_id, role") \
        .eq("resource_type", "file") \
        .eq("user_email", user_email) \
        .execute()
    shared_ids = {r["resource_id"] for r in (shared_resp.data or [])}
    shared_roles = {r["resource_id"]: r["role"] for r in (shared_resp.data or [])}

    result = []
    for f in files:
        fid = f.get("id")

        # Explicit share overrides both privacy and scope (FR-016)
        if fid in shared_ids:
            f["role"] = shared_roles[fid]
            f["is_shared"] = True
            result.append(f)
            continue

        # privacy_ok: not private OR owned by self
        privacy_ok = (not f.get("is_private")) or (f.get("uploaded_by") == user_email)
        if not privacy_ok:
            continue

        # scope_ok: global (no dept) OR dept is one of user's depts
        dept_id = f.get("department_id")
        scope_ok = (dept_id is None) or (dept_id in dept_ids)
        if not scope_ok:
            continue

        # Assign role for owned files
        if f.get("uploaded_by") == user_email:
            f["role"] = "owner"

        result.append(f)

    return {"files": result}


@router.get("/files/{file_id}")
async def get_file(file_id: str, user_email: str = Query(...)):
    """Get a single file by ID if visible to the caller (SC-006).

    Visibility for scoped viewers:
        visible iff (privacy_ok AND scope_ok) OR explicitly shared,
        where privacy_ok = not is_private OR uploaded_by == self
        and   scope_ok  = department_id IS NULL OR department_id IN user_depts
        An explicit share overrides both (FR-016).
    """
    if not user_email:
        raise HTTPException(status_code=400, detail="user_email is required")

    user = get_user_by_email(user_email)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    response = supabase.table("files") \
        .select("*, departments(name)") \
        .eq("id", file_id) \
        .single() \
        .execute()

    if not response.data:
        raise HTTPException(status_code=404, detail="File not found")

    f = _flatten_file(response.data)

    # Global viewers bypass all checks (FR-002)
    if is_global_viewer(user):
        return {"file": f}

    # --- Scoped viewer ---
    user_id = user["id"]
    dept_ids = set(get_user_department_ids(user_id))

    # Check explicit share first (FR-016)
    shared = supabase.table("resource_permissions") \
        .select("role") \
        .eq("resource_id", file_id) \
        .eq("resource_type", "file") \
        .eq("user_email", user_email) \
        .execute()
    if shared.data:
        f["role"] = shared.data[0]["role"]
        f["is_shared"] = True
        return {"file": f}

    # privacy_ok AND scope_ok
    privacy_ok = (not f.get("is_private")) or (f.get("uploaded_by") == user_email)
    scope_ok = (f.get("department_id") is None) or (f.get("department_id") in dept_ids)

    if not (privacy_ok and scope_ok):
        raise HTTPException(status_code=403, detail="Access denied")

    if f.get("uploaded_by") == user_email:
        f["role"] = "owner"

    return {"file": f}


@router.post("/upload")
async def upload_file(
    file: UploadFile = File(...),
    title: str = Form(...),
    file_type: str = Form(...),
    is_private: bool = Form(False),
    uploaded_by: str = Form(...),
    folder_id: Optional[str] = Form(None),
    expiration_date: Optional[str] = Form(None),
    department_id: Optional[str] = Form(None),
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

    if department_id and department_id.strip():
        dept_check = supabase.table("departments").select("id").eq("id", department_id).single().execute()
        if not dept_check.data:
            raise HTTPException(status_code=400, detail="Invalid department_id")
        record["department_id"] = department_id

    supabase.table("files").insert(record).execute()

    detail = file_type
    if department_id and department_id.strip():
        detail = f"{file_type} · dept={department_id}"

    log_activity(uploaded_by, "file", "uploaded",
        target_label=title, target_id=file_id, detail=detail)

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


@router.patch("/files/{file_id}/department")
async def update_file_department(
    file_id: str,
    user_email: str = Query(...),
    body: PatchDepartmentBody = None,
):
    """Change a single file's department association (FR-017). Admin only."""
    user = get_user_by_email(user_email)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if user.get("user_type") != "admin":
        raise HTTPException(status_code=403, detail="Only admins can change file department")

    existing = supabase.table("files") \
        .select("id, title, department_id") \
        .eq("id", file_id) \
        .single() \
        .execute()

    if not existing.data:
        raise HTTPException(status_code=404, detail="File not found")

    old_dept = existing.data.get("department_id") or "global"
    new_dept_id = body.department_id if body else None

    if new_dept_id:
        dept_check = supabase.table("departments").select("id").eq("id", new_dept_id).single().execute()
        if not dept_check.data:
            raise HTTPException(status_code=400, detail="Invalid department_id")

    supabase.table("files") \
        .update({"department_id": new_dept_id}) \
        .eq("id", file_id) \
        .execute()

    new_label = new_dept_id or "global"
    log_activity(user_email, "file", "updated",
        target_label=existing.data.get("title", file_id),
        target_id=file_id,
        detail=f"dept: {old_dept} → {new_label}")

    dept_name = None
    if new_dept_id:
        dept_row = supabase.table("departments").select("name").eq("id", new_dept_id).single().execute()
        if dept_row.data:
            dept_name = dept_row.data["name"]

    return {
        "status": "success",
        "file": {
            "id": file_id,
            "department_id": new_dept_id,
            "department_name": dept_name,
        }
    }


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