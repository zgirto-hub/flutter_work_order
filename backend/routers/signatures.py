import base64
import os
import shutil
import uuid

from fastapi import APIRouter, Query, HTTPException, UploadFile, File, Form
from pydantic import BaseModel
from typing import Optional

from db import supabase
from utils.activity import log_activity
from utils.notification_service import dispatch_signature_notification

router = APIRouter()

UPLOAD_DIR = "uploaded_files"
os.makedirs(UPLOAD_DIR, exist_ok=True)


# --------------------
# Pydantic Models
# --------------------


class AddSignatureBody(BaseModel):
    signer_email: str
    signer_role: str  # 'technician' or 'admin'
    signature_data: Optional[str] = None  # base64 PNG
    use_saved: bool = False


class UpdateSignatureBody(BaseModel):
    status: str  # 'approved' or 'rejected'
    rejection_reason: Optional[str] = None


# --------------------
# Helpers
# --------------------


def _get_user_by_email(email: str):
    normalized = email.strip().lower()
    if not normalized:
        return None
    result = supabase.table("users").select("*").eq("email", normalized).execute()
    return result.data[0] if result.data else None


def _get_user_role(email: str) -> str:
    user = _get_user_by_email(email)
    if not user:
        raise HTTPException(status_code=403, detail="User not found")
    return (user.get("user_type") or "reporter").strip().lower()


def _is_technician_assigned(work_order_id: str, email: str) -> bool:
    user = _get_user_by_email(email)
    if not user:
        return False
    user_id = user.get("id")
    result = (
        supabase.table("work_order_assignments")
        .select("technician_id")
        .eq("work_order_id", work_order_id)
        .eq("technician_id", user_id)
        .execute()
    )
    return bool(result.data)


# --------------------
# Endpoints
# --------------------


@router.post("/work-orders/{work_order_id}/signatures")
async def add_signature(work_order_id: str, body: AddSignatureBody):
    # Validate work order exists and is Closed
    wo = (
        supabase.table("work_orders")
        .select("id, status, job_no, title")
        .eq("id", work_order_id)
        .execute()
    )
    if not wo.data:
        raise HTTPException(status_code=404, detail="Work order not found")
    if wo.data[0].get("status") != "Closed":
        raise HTTPException(status_code=400, detail="Work order must be Closed to sign")

    signer_email = body.signer_email.strip().lower()
    signer_role = body.signer_role.strip().lower()

    if signer_role not in ("technician", "admin"):
        raise HTTPException(
            status_code=400, detail="signer_role must be 'technician' or 'admin'"
        )

    # Validate role matches actual user role
    actual_role = _get_user_role(signer_email)

    if signer_role == "technician":
        if actual_role not in ("technician", "admin"):
            raise HTTPException(
                status_code=403, detail="User is not a technician or admin"
            )
        # Validate technician is assigned to this WO
        if actual_role == "technician" and not _is_technician_assigned(
            work_order_id, signer_email
        ):
            raise HTTPException(
                status_code=403, detail="Technician is not assigned to this work order"
            )

    if signer_role == "admin":
        if actual_role != "admin":
            raise HTTPException(status_code=403, detail="Only admins can sign as admin")
        # Validate technician signature exists and is pending
        tech_sig = (
            supabase.table("work_order_signatures")
            .select("id, status")
            .eq("work_order_id", work_order_id)
            .eq("signer_role", "technician")
            .order("signed_at", desc=True)
            .execute()
        )
        if not tech_sig.data:
            raise HTTPException(status_code=400, detail="Technician must sign first")
        # Find the latest non-rejected technician signature
        latest_tech = next(
            (s for s in tech_sig.data if s.get("status") != "rejected"), None
        )
        if not latest_tech:
            raise HTTPException(status_code=400, detail="Technician must sign first")
        if latest_tech.get("status") != "pending":
            raise HTTPException(
                status_code=400, detail="Technician signature must be in pending state"
            )

    # Upsert: only block if there's already a pending or approved signature
    # (rejected records are preserved for audit)
    existing = (
        supabase.table("work_order_signatures")
        .select("id, status")
        .eq("work_order_id", work_order_id)
        .eq("signer_role", signer_role)
        .execute()
    )
    if existing.data:
        for row in existing.data:
            if row.get("status") in ("pending", "approved"):
                raise HTTPException(
                    status_code=400, detail=f"A {signer_role} signature already exists"
                )

    if body.use_saved:
        saved_path = _get_saved_signature_path(signer_email)
        signature_path = _copy_saved_signature(saved_path)
    else:
        if not body.signature_data:
            raise HTTPException(status_code=400, detail="signature_data is required")
        signature_path = _decode_signature_to_file(body.signature_data)

    record = {
        "work_order_id": work_order_id,
        "signer_email": signer_email,
        "signer_role": signer_role,
        "signature_path": signature_path,
        "status": "approved" if signer_role == "admin" else "pending",
    }
    result = supabase.table("work_order_signatures").insert(record).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to save signature")

    # Notify: technician signed → notify admins
    if signer_role == "technician":
        try:
            dispatch_signature_notification(
                work_order_id=work_order_id,
                signature_id=str(result.data[0].get("id")),
                signer_email=signer_email,
                kind="signature_pending",
                job_no=wo.data[0].get("job_no", ""),
            )
        except Exception as e:
            print(f"Signature notification dispatch failed: {e}")

    try:
        log_activity(
            signer_email,
            "work_order",
            "signature_submitted",
            target_label=wo.data[0].get("title", ""),
            target_id=work_order_id,
        )
    except Exception as e:
        print(f"Activity log failed: {e}")

    payload = result.data[0]
    payload.pop("signature_data", None)

    return {"signature": payload}


@router.get("/work-orders/{work_order_id}/signatures")
async def get_signatures(work_order_id: str):
    result = (
        supabase.table("work_order_signatures")
        .select(
            "id, work_order_id, signer_email, signer_role, signature_path, signed_at, status, rejection_reason"
        )
        .eq("work_order_id", work_order_id)
        .order("signed_at")
        .execute()
    )

    signatures = result.data or []
    for sig in signatures:
        sig.setdefault("signature_path", None)
        sig.pop("signature_data", None)

    return {"signatures": signatures}


@router.patch("/work-orders/{work_order_id}/signatures/{signature_id}")
async def update_signature(
    work_order_id: str,
    signature_id: str,
    body: UpdateSignatureBody,
    user_email: str = Query(...),
):
    # Admin only
    role = _get_user_role(user_email)
    if role != "admin":
        raise HTTPException(
            status_code=403, detail="Only admins can approve or reject signatures"
        )

    if body.status not in ("approved", "rejected"):
        raise HTTPException(
            status_code=400, detail="status must be 'approved' or 'rejected'"
        )

    existing = (
        supabase.table("work_order_signatures")
        .select("id, signer_role, signer_email, status")
        .eq("id", signature_id)
        .eq("work_order_id", work_order_id)
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Signature not found")

    sig = existing.data[0]
    if sig.get("signer_role") != "technician":
        raise HTTPException(
            status_code=400, detail="Can only approve/reject technician signatures"
        )

    update_payload = {"status": body.status}
    if body.status == "rejected":
        update_payload["rejection_reason"] = body.rejection_reason or ""

    supabase.table("work_order_signatures").update(update_payload).eq(
        "id", signature_id
    ).execute()

    # Get WO info for notification + logging
    wo = (
        supabase.table("work_orders")
        .select("job_no, title")
        .eq("id", work_order_id)
        .execute()
    )
    wo_info = wo.data[0] if wo.data else {}
    job_no = wo_info.get("job_no", "")

    # Notify technician
    kind = "signature_approved" if body.status == "approved" else "signature_rejected"
    try:
        dispatch_signature_notification(
            work_order_id=work_order_id,
            signature_id=signature_id,
            signer_email=sig["signer_email"],
            kind=kind,
            job_no=job_no,
            actor_email=user_email,
        )
    except Exception as e:
        print(f"Signature notification dispatch failed: {e}")

    try:
        log_activity(
            user_email,
            "work_order",
            "signature_approved" if body.status == "approved" else "signature_rejected",
            target_label=wo_info.get("title", job_no),
            target_id=work_order_id,
        )
    except Exception as e:
        print(f"Activity log failed: {e}")

    return {"status": body.status}


@router.post("/users/{user_id}/signature")
async def save_user_signature(
    user_id: str,
    user_email: str = Form(...),
    signature_data: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
):
    # Validate requester is the user themselves or an admin
    requester = _get_user_by_email(user_email)
    if not requester:
        raise HTTPException(status_code=403, detail="User not found")

    requester_role = requester.get("user_type", "reporter").strip().lower()

    target_user = (
        supabase.table("users")
        .select("id, email, user_type, full_name")
        .eq("id", user_id)
        .execute()
    )
    if not target_user.data:
        raise HTTPException(status_code=404, detail="Target user not found")

    target = target_user.data[0]

    # Authorization: user can only update their own signature unless admin
    is_self = requester.get("id") == user_id
    if not is_self and requester_role != "admin":
        raise HTTPException(status_code=403, detail="Not authorized")

    user_role = target.get("user_type", "reporter").strip().lower()
    if user_role not in ("technician", "admin"):
        raise HTTPException(
            status_code=400,
            detail="Only technicians and admins can have saved signatures",
        )

    # Delete old file if exists
    old_path = target.get("signature_path")
    if old_path:
        relative = old_path.replace("\\", "/")
        if relative.startswith("/files/"):
            relative = relative[len("/files/") :]
        relative = relative.lstrip("/")
        safe_path = os.path.normpath(relative)
        if not safe_path.startswith(".."):
            old_file = os.path.join(UPLOAD_DIR, safe_path)
            try:
                os.remove(old_file)
            except FileNotFoundError:
                pass

    # Write new file
    filename = f"usersig_{user_id}.png"
    dest_path = os.path.join(UPLOAD_DIR, filename)

    if file:
        content = await file.read()
        with open(dest_path, "wb") as f:
            f.write(content)
    elif signature_data:
        payload = signature_data.split(",", 1)[-1].strip()
        try:
            decoded = base64.b64decode(payload)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid signature data")
        with open(dest_path, "wb") as f:
            f.write(decoded)
    else:
        raise HTTPException(status_code=400, detail="Provide signature_data or file")

    # Update DB
    signature_path = _public_file_path(filename)
    supabase.table("users").update({"signature_path": signature_path}).eq(
        "id", user_id
    ).execute()

    try:
        log_activity(
            user_email,
            "work_order",
            "saved_signature_updated",
            target_label=target.get("full_name", ""),
            target_id=user_id,
        )
    except Exception as e:
        print(f"Activity log failed: {e}")

    return {"signature_path": signature_path}


@router.get("/users/{user_id}/signature")
async def get_user_signature(user_id: str, user_email: str = Query(...)):
    # Validate requester
    requester = _get_user_by_email(user_email)
    if not requester:
        raise HTTPException(status_code=403, detail="User not found")

    requester_role = requester.get("user_type", "reporter").strip().lower()

    # Authorization check
    is_self = requester.get("id") == user_id
    if not is_self and requester_role != "admin":
        raise HTTPException(status_code=403, detail="Not authorized")

    result = (
        supabase.table("users").select("signature_path").eq("id", user_id).execute()
    )
    if not result.data:
        return {"signature_path": None}

    return {"signature_path": result.data[0].get("signature_path")}


@router.delete("/users/{user_id}/signature")
async def delete_user_signature(user_id: str, user_email: str = Query(...)):
    # Validate requester
    requester = _get_user_by_email(user_email)
    if not requester:
        raise HTTPException(status_code=403, detail="User not found")

    requester_role = requester.get("user_type", "reporter").strip().lower()

    # Authorization check
    is_self = requester.get("id") == user_id
    if not is_self and requester_role != "admin":
        raise HTTPException(status_code=403, detail="Not authorized")

    target_user = (
        supabase.table("users")
        .select("signature_path, full_name")
        .eq("id", user_id)
        .execute()
    )
    if not target_user.data:
        raise HTTPException(status_code=404, detail="User not found")

    target = target_user.data[0]
    old_path = target.get("signature_path")

    if old_path:
        relative = old_path.replace("\\", "/")
        if relative.startswith("/files/"):
            relative = relative[len("/files/") :]
        relative = relative.lstrip("/")
        safe_path = os.path.normpath(relative)
        if not safe_path.startswith(".."):
            old_file = os.path.join(UPLOAD_DIR, safe_path)
            try:
                os.remove(old_file)
            except FileNotFoundError:
                pass

    supabase.table("users").update({"signature_path": None}).eq("id", user_id).execute()

    try:
        log_activity(
            user_email,
            "work_order",
            "saved_signature_updated",
            target_label=target.get("full_name", ""),
            target_id=user_id,
        )
    except Exception as e:
        print(f"Activity log failed: {e}")

    return {"status": "deleted"}


@router.get("/signatures/bulk")
async def get_bulk_signature_status(work_order_ids: str = Query(...)):
    ids_list = [x.strip() for x in work_order_ids.split(",") if x.strip()]
    if not ids_list:
        return {"statuses": {}}

    result = (
        supabase.table("work_order_signatures")
        .select("work_order_id, signer_role, status")
        .in_("work_order_id", ids_list)
        .execute()
    )

    signatures_by_wo = {}
    for sig in result.data or []:
        wo_id = sig.get("work_order_id")
        role = sig.get("signer_role")
        status = sig.get("status")
        if wo_id not in signatures_by_wo:
            signatures_by_wo[wo_id] = {"technician": None, "admin": None}
        if role in ("technician", "admin"):
            signatures_by_wo[wo_id][role] = status

    statuses = {}
    for wo_id in ids_list:
        sigs = signatures_by_wo.get(wo_id, {"technician": None, "admin": None})
        tech = sigs.get("technician")
        admin = sigs.get("admin")
        statuses[wo_id] = {
            "technician_signed": tech is not None,
            "technician_status": tech,
            "admin_signed": admin is not None,
            "admin_status": admin,
        }

    return {"statuses": statuses}


def _public_file_path(filename: str) -> str:
    return f"/files/{filename}"


def _decode_signature_to_file(signature_data: str) -> str:
    payload = signature_data.split(",", 1)[-1].strip()
    try:
        decoded = base64.b64decode(payload)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid signature data")

    filename = f"sig_{uuid.uuid4().hex}.png"
    dest_path = os.path.join(UPLOAD_DIR, filename)
    with open(dest_path, "wb") as f:
        f.write(decoded)
    return _public_file_path(filename)


def _copy_saved_signature(existing_path: str) -> str:
    if not existing_path:
        raise HTTPException(status_code=400, detail="No saved signature on file")

    relative = existing_path.replace("\\", "/")
    if relative.startswith("/files/"):
        relative = relative[len("/files/") :]
    relative = relative.lstrip("/")
    safe_path = os.path.normpath(relative)
    if safe_path.startswith(".."):
        raise HTTPException(status_code=400, detail="Invalid saved signature path")

    source = os.path.join(UPLOAD_DIR, safe_path)
    if not os.path.exists(source):
        raise HTTPException(status_code=400, detail="Saved signature file not found")

    filename = f"sig_{uuid.uuid4().hex}.png"
    dest = os.path.join(UPLOAD_DIR, filename)
    shutil.copyfile(source, dest)
    return _public_file_path(filename)


def _get_saved_signature_path(email: str) -> Optional[str]:
    result = (
        supabase.table("users").select("signature_path").eq("email", email).execute()
    )
    if not result.data:
        return None
    return result.data[0].get("signature_path")
