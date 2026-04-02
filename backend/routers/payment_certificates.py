from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional, List, Any
from datetime import datetime
from db import supabase
from utils.activity import log_activity

router = APIRouter()


# ---------- Pydantic models ----------

class PaymentCertificateBody(BaseModel):
    certificate_number: Optional[str] = ""
    subject: Optional[str] = ""
    contract_number: Optional[str] = ""
    invoice_number: Optional[str] = ""
    invoice_amount: Optional[float] = 0
    currency: Optional[str] = "USD"
    period_from: Optional[str] = None
    period_to: Optional[str] = None
    executing_entity: Optional[str] = ""
    supervising_entity: Optional[str] = ""
    original_value_usd: Optional[float] = 0
    original_value_kwd: Optional[float] = 0
    additional_works: Optional[str] = ""
    contract_signing_date: Optional[str] = None
    contract_duration: Optional[str] = ""
    contract_start_date: Optional[str] = None
    contract_end_date: Optional[str] = None
    work_commencement_date: Optional[str] = None
    renewal_info: Optional[str] = ""
    renewal_expiry_date: Optional[str] = None
    extension_value: Optional[float] = 0
    extension_duration: Optional[str] = ""
    extension_1_start_date: Optional[str] = None
    extension_1_end_date: Optional[str] = None
    extension_2_start_date: Optional[str] = None
    extension_2_end_date: Optional[str] = None
    extension_period_label: Optional[str] = ""
    payment_rows: Optional[List[Any]] = []
    attachment_checklist: Optional[dict] = {}
    dept_head: Optional[str] = ""
    controller: Optional[str] = ""
    director: Optional[str] = ""
    auditor: Optional[str] = ""
    created_by: Optional[str] = ""
    created_by_email: Optional[str] = ""


# ---------- Helpers ----------

def _get_by_id(cert_id: str):
    result = supabase.table("payment_certificates").select("*").eq("id", cert_id).execute()
    return result.data[0] if result.data else None


def _to_payload(body: PaymentCertificateBody) -> dict:
    return {
        "certificate_number": body.certificate_number,
        "subject": body.subject or "",
        "contract_number": body.contract_number or "",
        "invoice_number": body.invoice_number or "",
        "invoice_amount": body.invoice_amount or 0,
        "currency": body.currency or "USD",
        "period_from": body.period_from,
        "period_to": body.period_to,
        "executing_entity": body.executing_entity or "",
        "supervising_entity": body.supervising_entity or "",
        "original_value_usd": body.original_value_usd or 0,
        "original_value_kwd": body.original_value_kwd or 0,
        "additional_works": body.additional_works or "",
        "contract_signing_date": body.contract_signing_date,
        "contract_duration": body.contract_duration or "",
        "contract_start_date": body.contract_start_date,
        "contract_end_date": body.contract_end_date,
        "work_commencement_date": body.work_commencement_date,
        "renewal_info": body.renewal_info or "",
        "renewal_expiry_date": body.renewal_expiry_date,
        "extension_value": body.extension_value or 0,
        "extension_duration": body.extension_duration or "",
        "extension_1_start_date": body.extension_1_start_date,
        "extension_1_end_date": body.extension_1_end_date,
        "extension_2_start_date": body.extension_2_start_date,
        "extension_2_end_date": body.extension_2_end_date,
        "extension_period_label": body.extension_period_label or "",
        "payment_rows": body.payment_rows or [],
        "attachment_checklist": body.attachment_checklist or {},
        "dept_head": body.dept_head or "",
        "controller": body.controller or "",
        "director": body.director or "",
        "auditor": body.auditor or "",
        "created_by": body.created_by or "",
        "created_by_email": body.created_by_email or "",
    }


# ---------- Endpoints ----------

@router.get("/payment-certificates")
async def list_certificates(
    email: Optional[str] = Query(None),
    limit: Optional[int] = Query(None),
    offset: int = Query(0),
):
    query = supabase.table("payment_certificates") \
        .select("*") \
        .order("created_at", desc=True)

    result = query.execute()
    items = result.data or []
    total = len(items)

    if offset > 0:
        items = items[offset:]
    if limit is not None:
        items = items[:limit]

    return {"certificates": items, "total": total}


@router.get("/payment-certificates/{cert_id}")
async def get_certificate(cert_id: str):
    item = _get_by_id(cert_id)
    if not item:
        raise HTTPException(status_code=404, detail="Certificate not found")
    return {"certificate": item}


@router.post("/payment-certificates")
async def create_certificate(body: PaymentCertificateBody):
    payload = _to_payload(body)
    result = supabase.table("payment_certificates").insert(payload).execute()
    cert = result.data[0] if result.data else {}

    try:
        log_activity(
            body.created_by_email or "",
            "payment_certificate", "created",
            target_label=body.certificate_number,
            target_id=cert.get("id", ""),
        )
    except Exception:
        pass

    return {"certificate": cert}


@router.put("/payment-certificates/{cert_id}")
async def update_certificate(
    cert_id: str,
    body: PaymentCertificateBody,
    user_email: str = Query(""),
):
    existing = _get_by_id(cert_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Certificate not found")

    payload = _to_payload(body)
    payload["updated_at"] = datetime.utcnow().isoformat()

    supabase.table("payment_certificates") \
        .update(payload).eq("id", cert_id).execute()

    try:
        log_activity(
            user_email, "payment_certificate", "updated",
            target_label=body.certificate_number,
            target_id=cert_id,
        )
    except Exception:
        pass

    return {"certificate": {**existing, **payload, "id": cert_id}}


@router.delete("/payment-certificates/{cert_id}")
async def delete_certificate(
    cert_id: str,
    user_email: str = Query(""),
):
    existing = _get_by_id(cert_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Certificate not found")

    supabase.table("payment_certificates") \
        .delete().eq("id", cert_id).execute()

    try:
        log_activity(
            user_email, "payment_certificate", "deleted",
            target_label=existing.get("certificate_number", ""),
            target_id=cert_id,
        )
    except Exception:
        pass

    return {"status": "deleted"}
