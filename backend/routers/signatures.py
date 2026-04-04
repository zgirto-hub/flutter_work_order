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
    signature_data: Optional[str] = None  # base64 PNG from approver
    use_saved: bool = False


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
    # Validate work order exists
    wo = (
        supabase.table("work_orders")
        .select("id, status, job_no, title, signature_status, department_id")
        .eq("id", work_order_id)
        .execute()
    )
    if not wo.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    wo_data = wo.data[0]
    current_sig_status = wo_data.get("signature_status", "unsigned")

    signer_email = body.signer_email.strip().lower()
    signer_role = body.signer_role.strip().lower()

    # T008(1): Only 'technician' is valid for signing
    if signer_role != "technician":
        raise HTTPException(
            status_code=400, detail="signer_role must be 'technician' only"
        )

    # Validate role matches actual user role
    actual_role = _get_user_role(signer_email)
    if actual_role not in ("technician", "admin"):
        raise HTTPException(status_code=403, detail="User is not a technician or admin")

    # Validate technician is assigned to this WO
    if actual_role == "technician" and not _is_technician_assigned(
        work_order_id, signer_email
    ):
        raise HTTPException(
            status_code=403, detail="Technician is not assigned to this work order"
        )

    # T008(2): Check signature_status before allowing tech sign
    if current_sig_status not in ("unsigned", "rejected"):
        raise HTTPException(status_code=409, detail="Cannot sign at current status")

    # T008(3): On re-sign after rejection - clear existing non-rejected signatures
    if current_sig_status == "rejected":
        supabase.table("work_order_signatures").update({"status": "rejected"}).eq(
            "work_order_id", work_order_id
        ).neq("status", "rejected").execute()
        supabase.table("work_orders").update({"signature_status": "unsigned"}).eq(
            "id", work_order_id
        ).execute()

    # Check for existing pending/approved technician signature
    existing = (
        supabase.table("work_order_signatures")
        .select("id, status")
        .eq("work_order_id", work_order_id)
        .eq("signer_role", "technician")
        .execute()
    )
    if existing.data:
        for row in existing.data:
            if row.get("status") in ("pending", "approved"):
                raise HTTPException(
                    status_code=400, detail="A technician signature already exists"
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
        "signer_role": "technician",
        "signature_path": signature_path,
        "status": "pending",
    }
    result = supabase.table("work_order_signatures").insert(record).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to save signature")

    # T008(4): Update WO signature_status to 'tech_signed'
    supabase.table("work_orders").update({"signature_status": "tech_signed"}).eq(
        "id", work_order_id
    ).execute()

    # T008(5): Call _advance_chain - may skip to next level
    new_status = _advance_chain(work_order_id, "tech_signed")
    if new_status != "tech_signed":
        supabase.table("work_orders").update({"signature_status": new_status}).eq(
            "id", work_order_id
        ).execute()

    # T008(6): Send notification via dispatch_signature_notification
    try:
        dispatch_signature_notification(
            work_order_id=work_order_id,
            signature_id=str(result.data[0].get("id")),
            signer_email=signer_email,
            kind="signature_pending_supervisor",
            job_no=wo_data.get("job_no", ""),
            wo_department_id=wo_data.get("department_id", ""),
        )
    except Exception as e:
        print(f"Signature notification dispatch failed: {e}")

    # T008(7): Log to activity log
    try:
        log_activity(
            signer_email,
            "work_order",
            "signature_submitted",
            target_label=wo_data.get("title", ""),
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
    print(f"[PATCH sig] user_email={user_email}, wo={work_order_id}, sig={signature_id}, status={body.status}, use_saved={body.use_saved}")

    # T009(1): Get caller info via _get_user_approval_info
    caller_info = _get_user_approval_info(user_email)
    if not caller_info:
        print(f"[PATCH sig] FAIL: user not found for {user_email}")
        raise HTTPException(status_code=403, detail="User not found")

    print(f"[PATCH sig] caller: type={caller_info.get('user_type')}, level={caller_info.get('approval_level')}, depts={caller_info.get('department_ids')}")

    # T009(2): If caller is admin, return 403
    if caller_info.get("user_type") == "admin":
        raise HTTPException(status_code=403, detail="Admin cannot approve signatures")

    if body.status not in ("approved", "rejected"):
        raise HTTPException(
            status_code=400, detail="status must be 'approved' or 'rejected'"
        )

    # Verify signature exists
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

    # T009(3): Get WO's current signature_status
    wo = (
        supabase.table("work_orders")
        .select("id, job_no, title, signature_status, department_id")
        .eq("id", work_order_id)
        .execute()
    )
    if not wo.data:
        raise HTTPException(status_code=404, detail="Work order not found")

    wo_data = wo.data[0]
    current_sig_status = wo_data.get("signature_status", "unsigned")
    print(f"[PATCH sig] WO sig_status={current_sig_status}, dept={wo_data.get('department_id')}")

    # T009(4): Get required approval level
    try:
        required_level = _get_required_approval_level(current_sig_status)
    except ValueError:
        print(f"[PATCH sig] FAIL: invalid sig status '{current_sig_status}'")
        raise HTTPException(
            status_code=400, detail="Invalid signature status for approval"
        )

    # T009(5): Check caller's approval_level matches required level
    caller_level = caller_info.get("approval_level")
    print(f"[PATCH sig] required_level={required_level}, caller_level={caller_level}")
    if caller_level != required_level:
        raise HTTPException(
            status_code=403,
            detail=f"Your approval level does not match required level {required_level}",
        )

    # T009(6): For level 1 (supervisor), verify department
    if required_level == 1:
        wo_dept_id = wo_data.get("department_id")
        caller_dept_ids = caller_info.get("department_ids", [])
        if wo_dept_id not in caller_dept_ids:
            raise HTTPException(
                status_code=403, detail="You are not authorized for this department"
            )

    # T009(7): Self-approval check - cannot approve own signature
    tech_sigs = (
        supabase.table("work_order_signatures")
        .select("signer_email")
        .eq("work_order_id", work_order_id)
        .eq("signer_role", "technician")
        .execute()
    )
    for ts in tech_sigs.data or []:
        if ts.get("signer_email", "").lower() == user_email.lower():
            raise HTTPException(
                status_code=403, detail="Cannot approve your own signature"
            )

    approver_role = "supervisor" if required_level == 1 else "superintendent"

    # T009(9): Handle rejection separately — do NOT advance chain
    if body.status == "rejected":
        # Optimistic concurrency: ensure status hasn't changed
        update_result = (
            supabase.table("work_orders")
            .update({"signature_status": "rejected"})
            .eq("id", work_order_id)
            .eq("signature_status", current_sig_status)
            .execute()
        )
        if not update_result.data:
            raise HTTPException(status_code=409, detail="Already approved at this level")

        supabase.table("work_order_signatures").insert({
            "work_order_id": work_order_id,
            "signer_email": user_email,
            "signer_role": approver_role,
            "status": "rejected",
            "rejection_reason": body.rejection_reason or "",
        }).execute()

        final_status = "rejected"
    else:
        # T009(8): Optimistic concurrency - advance chain
        new_status_map = {
            "tech_signed": "supervisor_approved",
            "supervisor_approved": "superintendent_approved",
        }
        expected_new_status = new_status_map.get(current_sig_status, current_sig_status)

        update_result = (
            supabase.table("work_orders")
            .update({"signature_status": expected_new_status})
            .eq("id", work_order_id)
            .eq("signature_status", current_sig_status)
            .execute()
        )
        if not update_result.data:
            raise HTTPException(status_code=409, detail="Already approved at this level")

        # Resolve approver's signature image
        approver_sig_path = None
        if body.use_saved:
            saved_path = _get_saved_signature_path(user_email)
            if saved_path:
                approver_sig_path = _copy_saved_signature(saved_path)
        elif body.signature_data:
            approver_sig_path = _decode_signature_to_file(body.signature_data)

        approver_record = {
            "work_order_id": work_order_id,
            "signer_email": user_email,
            "signer_role": approver_role,
            "status": "approved",
        }
        if approver_sig_path:
            approver_record["signature_path"] = approver_sig_path

        supabase.table("work_order_signatures").insert(approver_record).execute()

        # Call _advance_chain to check if next level should be skipped
        final_status = _advance_chain(work_order_id, expected_new_status)
        if final_status != expected_new_status:
            supabase.table("work_orders").update({"signature_status": final_status}).eq(
                "id", work_order_id
            ).execute()

    # T009(10) & (11): Notifications
    notification_kind = (
        f"signature_approved_{approver_role}"
        if body.status == "approved"
        else "signature_rejected"
    )
    try:
        dispatch_signature_notification(
            work_order_id=work_order_id,
            signature_id=signature_id,
            signer_email=sig.get("signer_email", ""),
            kind=notification_kind,
            job_no=wo_data.get("job_no", ""),
            actor_email=user_email,
            wo_department_id=wo_data.get("department_id", ""),
        )
    except Exception as e:
        print(f"Signature notification dispatch failed: {e}")

    # T009(12): Log activity
    try:
        log_activity(
            user_email,
            "work_order",
            f"signature_{body.status}_by_{approver_role}",
            target_label=wo_data.get("title", ""),
            target_id=work_order_id,
            detail=f"Approved by {approver_role} {user_email}",
        )
    except Exception as e:
        print(f"Activity log failed: {e}")

    return {"status": body.status, "signature_status": final_status}


@router.delete("/work-orders/{work_order_id}/signatures/{signature_id}")
async def delete_signature(
    work_order_id: str,
    signature_id: str,
    user_email: str = Query(...),
):
    role = _get_user_role(user_email)
    if role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can remove signatures")

    existing = (
        supabase.table("work_order_signatures")
        .select("id, signer_role, signer_email, signature_path")
        .eq("id", signature_id)
        .eq("work_order_id", work_order_id)
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Signature not found")

    sig = existing.data[0]

    # Delete the signature record
    supabase.table("work_order_signatures").delete().eq("id", signature_id).execute()

    # Delete the signature file from disk
    sig_path = sig.get("signature_path")
    if sig_path:
        sig_filename = os.path.basename(sig_path)
        file_path = os.path.join(UPLOAD_DIR, sig_filename)
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
            except Exception:
                pass

    # If admin deleted their own signature, revert tech sig back to pending
    if sig.get("signer_role") == "admin":
        tech_sigs = (
            supabase.table("work_order_signatures")
            .select("id, status")
            .eq("work_order_id", work_order_id)
            .eq("signer_role", "technician")
            .order("signed_at", desc=True)
            .execute()
        )
        for ts in tech_sigs.data or []:
            if ts.get("status") == "approved":
                supabase.table("work_order_signatures").update(
                    {"status": "pending"}
                ).eq("id", ts["id"]).execute()
                break

    wo = (
        supabase.table("work_orders")
        .select("job_no, title")
        .eq("id", work_order_id)
        .execute()
    )
    wo_info = wo.data[0] if wo.data else {}

    try:
        log_activity(
            user_email,
            "work_order",
            "signature_removed",
            target_label=wo_info.get("title", wo_info.get("job_no", "")),
            target_id=work_order_id,
            detail=f"Removed {sig.get('signer_role')} signature by {sig.get('signer_email')}",
        )
    except Exception:
        pass

    return {"deleted": True}


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

    # T011: Get signature_status from work_orders table
    wo_result = (
        supabase.table("work_orders")
        .select("id, signature_status")
        .in_("id", ids_list)
        .execute()
    )
    wo_status_map = {
        w.get("id"): w.get("signature_status", "unsigned")
        for w in (wo_result.data or [])
    }

    # Get all signatures for these work orders
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
            signatures_by_wo[wo_id] = {
                "technician": None,
                "supervisor": None,
                "superintendent": None,
            }
        if role in ("technician", "supervisor", "superintendent"):
            signatures_by_wo[wo_id][role] = status

    statuses = {}
    for wo_id in ids_list:
        sigs = signatures_by_wo.get(
            wo_id, {"technician": None, "supervisor": None, "superintendent": None}
        )
        tech = sigs.get("technician")
        sup = sigs.get("supervisor")
        superintendent = sigs.get("superintendent")

        statuses[wo_id] = {
            "signature_status": wo_status_map.get(wo_id, "unsigned"),
            "technician_signed": tech is not None,
            "technician_status": tech,
            "supervisor_signed": sup is not None,
            "supervisor_status": sup,
            "superintendent_signed": superintendent is not None,
            "superintendent_status": superintendent,
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


# ================================================
# Approval Chain Helpers (T002, T003)
# ================================================


def _get_required_approval_level(signature_status: str) -> int:
    """Maps signature_status to required approval level"""
    mapping = {
        "tech_signed": 1,
        "supervisor_approved": 2,
        "superintendent_approved": 3,
    }
    if signature_status not in mapping:
        raise ValueError(f"Invalid signature_status: {signature_status}")
    return mapping[signature_status]


def _get_approvers_for_level(level: int, department_id: str) -> list:
    """Get list of approvers for a given level and department"""
    if level == 1:
        result = (
            supabase.table("users")
            .select("id, email, full_name")
            .eq("is_supervisor", True)
            .execute()
        )
        approvers = result.data or []
        filtered = []
        for a in approvers:
            a_id = a.get("id")
            td_result = (
                supabase.table("technician_departments")
                .select("department_id")
                .eq("technician_id", a_id)
                .eq("department_id", department_id)
                .execute()
            )
            if td_result.data:
                filtered.append(a)
        return filtered
    elif level == 2:
        result = (
            supabase.table("users")
            .select("id, email, full_name")
            .eq("is_superintendent", True)
            .execute()
        )
        return result.data or []
    else:
        return []


def _advance_chain(work_order_id: str, current_status: str) -> str:
    """Check if the next required approval level has approvers.

    If the next level has no approvers, skip it and try the level after.
    If ALL remaining levels have no approvers, do NOT auto-complete (blocked).
    If we skip past all levels (found at least one earlier), mark completed.
    Returns the new signature_status the WO should be set to.
    """
    status_to_level = {
        "tech_signed": 1,
        "supervisor_approved": 2,
        "superintendent_approved": 3,
    }
    level_to_status = {
        1: "tech_signed",        # waiting for supervisor
        2: "supervisor_approved", # waiting for superintendent
    }

    required_level = status_to_level.get(current_status)
    if required_level is None:
        return current_status

    wo = (
        supabase.table("work_orders")
        .select("id, department_id")
        .eq("id", work_order_id)
        .execute()
    )
    if not wo.data:
        return current_status

    department_id = wo.data[0].get("department_id")
    skipped_levels = []

    for level in range(required_level, 3):  # levels 1 and 2 only (3 is reserved)
        approvers = _get_approvers_for_level(level, department_id)
        if approvers:
            # Found approvers at this level — chain waits here
            break
        else:
            skipped_levels.append(level)
    else:
        # Loop completed without break — no approvers found at any level
        if not skipped_levels:
            return current_status
        # All remaining levels have no approvers
        # Per spec: if BOTH supervisor AND superintendent are missing, block
        if required_level == 1 and len(skipped_levels) >= 2:
            # Both levels missing — blocked
            _log_skipped_levels(work_order_id, skipped_levels)
            return current_status
        # Only one level missing — skip and complete
        _log_skipped_levels(work_order_id, skipped_levels)
        return "completed"

    # Log any skipped levels
    _log_skipped_levels(work_order_id, skipped_levels)

    if skipped_levels:
        # We skipped some levels and found approvers at a later one
        # Advance the status to match where we're waiting
        return level_to_status.get(level, current_status)

    # No levels skipped — chain waits at current status
    return current_status


def _log_skipped_levels(work_order_id: str, skipped_levels: list):
    """Log skipped approval levels to activity log."""
    level_names = {1: "supervisor", 2: "superintendent", 3: "manager"}
    for lvl in skipped_levels:
        try:
            log_activity(
                "system",
                "work_order",
                "chain_level_skipped",
                target_id=work_order_id,
                target_label=f"WO {work_order_id}",
                detail=f"Level {lvl} ({level_names.get(lvl, 'unknown')}) skipped - no approvers found",
            )
        except Exception:
            pass


def _get_user_approval_info(email: str) -> Optional[dict]:
    """Get user approval info for authorization checks"""
    normalized = email.strip().lower()
    if not normalized:
        return None

    result = (
        supabase.table("users")
        .select(
            "id, email, user_type, approval_level, is_supervisor, is_superintendent"
        )
        .eq("email", normalized)
        .execute()
    )

    if not result.data:
        return None

    user = result.data[0]

    user_id = user.get("id")
    td_result = (
        supabase.table("technician_departments")
        .select("department_id")
        .eq("technician_id", user_id)
        .execute()
    )
    department_ids = [row.get("department_id") for row in (td_result.data or [])]

    return {
        "user_type": user.get("user_type"),
        "approval_level": user.get("approval_level"),
        "is_supervisor": user.get("is_supervisor", False),
        "is_superintendent": user.get("is_superintendent", False),
        "id": user_id,
        "email": email,
        "department_ids": department_ids,
    }
