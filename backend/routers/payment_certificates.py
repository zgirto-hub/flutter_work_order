import os
import io
from fastapi import APIRouter, Query, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional, List, Any
from datetime import datetime
from xml.sax.saxutils import escape as xml_escape
from db import supabase
from utils.activity import log_activity
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm, cm
from reportlab.lib.colors import HexColor, lightgrey
from reportlab.platypus import (
    SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer,
    Image as RLImage,
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_RIGHT

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


# ---------- PDF Export ----------

def _fmt_date(val):
    """Format an ISO date string to dd/mm/yyyy."""
    if not val:
        return ""
    try:
        d = datetime.fromisoformat(str(val).replace("Z", "+00:00"))
        return d.strftime("%d/%m/%Y")
    except Exception:
        return str(val)


def _build_payment_certificate_pdf(cert: dict) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer, pagesize=A4,
        leftMargin=2 * cm, rightMargin=2 * cm,
        topMargin=1.5 * cm, bottomMargin=1.5 * cm,
    )

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        "PCTitle", parent=styles["Heading1"],
        fontSize=16, textColor=HexColor("#1a2744"),
        alignment=TA_CENTER, spaceAfter=6,
    )
    subtitle_style = ParagraphStyle(
        "PCSubtitle", parent=styles["Normal"],
        fontSize=10, textColor=HexColor("#666666"),
        alignment=TA_CENTER, spaceAfter=12,
    )
    section_style = ParagraphStyle(
        "PCSection", parent=styles["Heading2"],
        fontSize=12, textColor=HexColor("#1a2744"),
        spaceBefore=16, spaceAfter=8,
    )
    normal_style = styles["Normal"]
    small_style = ParagraphStyle(
        "PCSmall", parent=normal_style, fontSize=9, leading=12,
    )

    elements = []

    # ── Logos ──
    logo_dir = os.path.join(os.path.dirname(__file__), "..", "assets")

    def _load_logo(name, w, h):
        path = os.path.join(logo_dir, name)
        if os.path.exists(path):
            try:
                from reportlab.lib.utils import ImageReader
                reader = ImageReader(path)
                iw, ih = reader.getSize()
                scale = min(w / iw, h / ih)
                return RLImage(path, width=iw * scale, height=ih * scale)
            except Exception:
                pass
        return ""

    logo_newkuwait = _load_logo("logo_newkuwait.png", 3.5 * cm, 3.5 * cm)
    logo_emblem = _load_logo("logo_emblem.png", 4 * cm, 4 * cm)
    logo_civilaviation = _load_logo("logo_civilaviation.png", 7 * cm, 5 * cm)

    if any([logo_newkuwait, logo_emblem, logo_civilaviation]):
        logo_table = Table(
            [[logo_newkuwait, logo_emblem, logo_civilaviation]],
            colWidths=[5.5 * cm, 5.5 * cm, 5.5 * cm],
        )
        logo_table.setStyle(TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("ALIGN", (0, 0), (0, 0), "LEFT"),
            ("ALIGN", (1, 0), (1, 0), "CENTER"),
            ("ALIGN", (2, 0), (2, 0), "RIGHT"),
        ]))
        elements.append(logo_table)

    # Red line below logos
    red_line = Table([[""]], colWidths=[16.5 * cm])
    red_line.setStyle(TableStyle([
        ("LINEBELOW", (0, 0), (-1, 0), 2, HexColor("#D42027")),
    ]))
    elements.append(red_line)
    elements.append(Spacer(1, 8))

    elements.append(Paragraph("Payment Certificate Report", title_style))

    export_date = datetime.now().strftime("%Y-%m-%d %H:%M")
    cert_num = xml_escape(cert.get("certificate_number", ""))
    elements.append(Paragraph(f"Certificate #{cert_num} - {export_date}", subtitle_style))

    # Divider
    line_table = Table([[""]], colWidths=[15 * cm])
    line_table.setStyle(TableStyle([("LINEABOVE", (0, 0), (-1, 0), 0.5, lightgrey)]))
    elements.append(line_table)
    elements.append(Spacer(1, 8))

    # ── Certificate Details ──
    elements.append(Paragraph("Certificate Details", section_style))

    def s(val):
        return xml_escape(str(val or ""))

    details_data = [
        ("Certificate No:", s(cert.get("certificate_number"))),
        ("Subject:", s(cert.get("subject"))),
        ("Contract No:", s(cert.get("contract_number"))),
        ("Invoice No:", s(cert.get("invoice_number"))),
        ("Invoice Amount:", f"{cert.get('invoice_amount', 0)} {s(cert.get('currency', 'USD'))}"),
        ("Period:", f"{_fmt_date(cert.get('period_from'))} - {_fmt_date(cert.get('period_to'))}"),
        ("Executing Entity:", s(cert.get("executing_entity"))),
        ("Supervising Entity:", s(cert.get("supervising_entity"))),
    ]

    details_table = Table(details_data, colWidths=[4 * cm, 11 * cm])
    details_table.setStyle(TableStyle([
        ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
        ("FONTNAME", (1, 0), (1, -1), "Helvetica"),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    elements.append(details_table)

    # ── Contract Info ──
    elements.append(Paragraph("Contract Information", section_style))

    contract_data = [
        ("Original Value (USD):", s(cert.get("original_value_usd", 0))),
        ("Original Value (KWD):", s(cert.get("original_value_kwd", 0))),
        ("Additional Works:", s(cert.get("additional_works"))),
        ("Contract Signing Date:", _fmt_date(cert.get("contract_signing_date"))),
        ("Contract Duration:", s(cert.get("contract_duration"))),
        ("Contract Start:", _fmt_date(cert.get("contract_start_date"))),
        ("Contract End:", _fmt_date(cert.get("contract_end_date"))),
        ("Work Commencement:", _fmt_date(cert.get("work_commencement_date"))),
        ("Renewal Info:", s(cert.get("renewal_info"))),
        ("Renewal Expiry:", _fmt_date(cert.get("renewal_expiry_date"))),
    ]

    contract_table = Table(contract_data, colWidths=[4 * cm, 11 * cm])
    contract_table.setStyle(TableStyle([
        ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
        ("FONTNAME", (1, 0), (1, -1), "Helvetica"),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    elements.append(contract_table)

    # ── Extension Info ──
    ext_value = cert.get("extension_value", 0)
    ext_duration = cert.get("extension_duration", "")
    if ext_value or ext_duration:
        elements.append(Paragraph("Extension Information", section_style))
        ext_data = [
            ("Extension Value:", s(ext_value)),
            ("Extension Duration:", s(ext_duration)),
            ("Extension 1 Start:", _fmt_date(cert.get("extension_1_start_date"))),
            ("Extension 1 End:", _fmt_date(cert.get("extension_1_end_date"))),
            ("Extension 2 Start:", _fmt_date(cert.get("extension_2_start_date"))),
            ("Extension 2 End:", _fmt_date(cert.get("extension_2_end_date"))),
            ("Extension Period:", s(cert.get("extension_period_label"))),
        ]
        ext_table = Table(ext_data, colWidths=[4 * cm, 11 * cm])
        ext_table.setStyle(TableStyle([
            ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
            ("FONTNAME", (1, 0), (1, -1), "Helvetica"),
            ("FONTSIZE", (0, 0), (-1, -1), 10),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]))
        elements.append(ext_table)

    # ── Payment Rows ──
    payment_rows = cert.get("payment_rows") or []
    if payment_rows:
        elements.append(Paragraph("Payment Details", section_style))

        header = ["Reason", "Due (Dinar)", "Due (Fils)",
                  "Deduction (Dinar)", "Deduction (Fils)",
                  "Net (Dinar)", "Net (Fils)"]
        table_data = [header]
        for row in payment_rows:
            table_data.append([
                s(row.get("reason", "")),
                s(row.get("duePaymentDinar", row.get("duePaymentDollars", 0))),
                s(row.get("duePaymentFils", row.get("duePaymentCents", 0))),
                s(row.get("deductionDinar", 0)),
                s(row.get("deductionFils", 0)),
                s(row.get("netDinar", 0)),
                s(row.get("netFils", 0)),
            ])

        pay_table = Table(table_data, colWidths=[3.5 * cm] + [2 * cm] * 6)
        pay_table.setStyle(TableStyle([
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("FONTSIZE", (0, 0), (-1, -1), 8),
            ("BACKGROUND", (0, 0), (-1, 0), HexColor("#E8EDF2")),
            ("GRID", (0, 0), (-1, -1), 0.5, lightgrey),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
        ]))
        elements.append(pay_table)

    # ── Attachment Checklist ──
    checklist = cert.get("attachment_checklist") or {}
    if checklist:
        elements.append(Paragraph("Attachment Checklist", section_style))
        for label, checked in checklist.items():
            mark = "[x]" if checked else "[ ]"
            elements.append(Paragraph(f"{mark}  {xml_escape(str(label))}", normal_style))

    # ── Approvals ──
    dept_head = cert.get("dept_head", "")
    controller = cert.get("controller", "")
    director = cert.get("director", "")
    auditor = cert.get("auditor", "")
    if any([dept_head, controller, director, auditor]):
        elements.append(Paragraph("Approvals", section_style))
        approvals = [
            ("Department Head:", s(dept_head)),
            ("Controller:", s(controller)),
            ("Director:", s(director)),
            ("Auditor:", s(auditor)),
        ]
        approval_table = Table(approvals, colWidths=[4 * cm, 11 * cm])
        approval_table.setStyle(TableStyle([
            ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
            ("FONTNAME", (1, 0), (1, -1), "Helvetica"),
            ("FONTSIZE", (0, 0), (-1, -1), 10),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]))
        elements.append(approval_table)

    # ── Meta ──
    elements.append(Spacer(1, 12))
    created_by = cert.get("created_by", "")
    created_at = cert.get("created_at", "")
    if created_by or created_at:
        meta_text = []
        if created_by:
            meta_text.append(f"Created By: {xml_escape(created_by)}")
        if created_at:
            meta_text.append(f"Created At: {_fmt_date(created_at)}")
        elements.append(Paragraph(" | ".join(meta_text), small_style))

    # ── Footer ──
    def draw_footer(canvas, doc):
        canvas.saveState()
        canvas.setFont("Helvetica", 8)
        canvas.drawString(2 * cm, 1 * cm, "Generated by Civil Aviation Payment Certificate System")
        canvas.drawString(7.5 * cm, 1 * cm, datetime.now().strftime("%Y-%m-%d %H:%M"))
        canvas.drawRightString(19 * cm - 2 * cm, 1 * cm, f"Page {doc.page}")
        canvas.restoreState()

    doc.build(elements, onFirstPage=draw_footer, onLaterPages=draw_footer)
    return buffer.getvalue()


@router.post("/payment-certificates/{cert_id}/pdf")
async def export_payment_certificate_pdf(cert_id: str):
    cert = _get_by_id(cert_id)
    if not cert:
        raise HTTPException(status_code=404, detail="Certificate not found")

    try:
        pdf_bytes = _build_payment_certificate_pdf(cert)
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to generate PDF: {str(e)}",
        )

    cert_num = cert.get("certificate_number", "unknown")
    log_activity(
        cert.get("created_by_email", "unknown"),
        "payment_certificate", "pdf_exported",
        target_label=f"Cert {cert_num}",
        target_id=cert_id,
    )

    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="PC-{cert_num}-report.pdf"'
        },
    )
