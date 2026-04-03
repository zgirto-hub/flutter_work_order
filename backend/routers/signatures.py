from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional

from db import supabase
from utils.notification_service import dispatch_signature_notification

router = APIRouter()


# --------------------
# Pydantic Models
# --------------------

class AddSignatureBody(BaseModel):
    signer_email: str
    signer_role: str  # 'technician' or 'admin'
    signature_data: str  # base64 PNG


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
    result = supabase.table("work_order_assignments") \
        .select("technician_id") \
        .eq("work_order_id", work_order_id) \
        .eq("technician_id", user_id) \
        .execute()
    return bool(result.data)


# --------------------
# Endpoints
# --------------------

@router.post("/work-orders/{work_order_id}/signatures")
async def add_signature(work_order_id: str, body: AddSignatureBody):
    # Validate work order exists and is Closed
    wo = supabase.table("work_orders").select("id, status, job_no, title") \
        .eq("id", work_order_id).execute()
    if not wo.data:
        raise HTTPException(status_code=404, detail="Work order not found")
    if wo.data[0].get("status") != "Closed":
        raise HTTPException(status_code=400, detail="Work order must be Closed to sign")

    signer_email = body.signer_email.strip().lower()
    signer_role = body.signer_role.strip().lower()

    if signer_role not in ("technician", "admin"):
        raise HTTPException(status_code=400, detail="signer_role must be 'technician' or 'admin'")

    # Validate role matches actual user role
    actual_role = _get_user_role(signer_email)

    if signer_role == "technician":
        if actual_role not in ("technician", "admin"):
            raise HTTPException(status_code=403, detail="User is not a technician or admin")
        # Validate technician is assigned to this WO
        if actual_role == "technician" and not _is_technician_assigned(work_order_id, signer_email):
            raise HTTPException(status_code=403, detail="Technician is not assigned to this work order")

    if signer_role == "admin":
        if actual_role != "admin":
            raise HTTPException(status_code=403, detail="Only admins can sign as admin")
        # Validate technician signature exists and is pending
        tech_sig = supabase.table("work_order_signatures") \
            .select("id, status") \
            .eq("work_order_id", work_order_id) \
            .eq("signer_role", "technician") \
            .execute()
        if not tech_sig.data:
            raise HTTPException(status_code=400, detail="Technician must sign first")
        if tech_sig.data[0].get("status") != "pending":
            raise HTTPException(status_code=400, detail="Technician signature must be in pending state")

    # Upsert: delete existing signature for this role if rejected previously
    existing = supabase.table("work_order_signatures") \
        .select("id, status") \
        .eq("work_order_id", work_order_id) \
        .eq("signer_role", signer_role) \
        .execute()
    if existing.data:
        existing_status = existing.data[0].get("status")
        if existing_status == "rejected":
            supabase.table("work_order_signatures") \
                .delete().eq("id", existing.data[0]["id"]).execute()
        elif existing_status in ("pending", "approved"):
            raise HTTPException(status_code=400, detail=f"A {signer_role} signature already exists")

    record = {
        "work_order_id": work_order_id,
        "signer_email": signer_email,
        "signer_role": signer_role,
        "signature_data": body.signature_data,
        "status": "pending",
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

    return {"signature": result.data[0]}


@router.get("/work-orders/{work_order_id}/signatures")
async def get_signatures(work_order_id: str):
    result = supabase.table("work_order_signatures") \
        .select("*") \
        .eq("work_order_id", work_order_id) \
        .order("signed_at") \
        .execute()
    return {"signatures": result.data or []}


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
        raise HTTPException(status_code=403, detail="Only admins can approve or reject signatures")

    if body.status not in ("approved", "rejected"):
        raise HTTPException(status_code=400, detail="status must be 'approved' or 'rejected'")

    existing = supabase.table("work_order_signatures") \
        .select("id, signer_role, signer_email, status") \
        .eq("id", signature_id) \
        .eq("work_order_id", work_order_id) \
        .execute()
    if not existing.data:
        raise HTTPException(status_code=404, detail="Signature not found")

    sig = existing.data[0]
    if sig.get("signer_role") != "technician":
        raise HTTPException(status_code=400, detail="Can only approve/reject technician signatures")

    update_payload = {"status": body.status}
    if body.status == "rejected":
        update_payload["rejection_reason"] = body.rejection_reason or ""

    supabase.table("work_order_signatures") \
        .update(update_payload).eq("id", signature_id).execute()

    # Get WO info for notification
    wo = supabase.table("work_orders").select("job_no").eq("id", work_order_id).execute()
    job_no = wo.data[0].get("job_no", "") if wo.data else ""

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

    return {"status": body.status}
