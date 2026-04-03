import os
import io
from datetime import datetime
from typing import Optional
from xml.sax.saxutils import escape as xml_escape
from fastapi import APIRouter, Query, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse

from db import supabase
from utils.activity import log_activity
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm, cm
from reportlab.lib.colors import HexColor, white, black, lightgrey, green
from reportlab.platypus import (
    SimpleDocTemplate,
    Table,
    TableStyle,
    Paragraph,
    Spacer,
    Image as RLImage,
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT

router = APIRouter()


def _fetch_wo_for_pdf(work_order_id: str):
    result = (
        supabase.table("work_orders")
        .select("""
        *,
        creator:users!work_orders_created_by_fkey (
            full_name,
            email
        ),
        departments!work_orders_department_id_fkey (
            id,
            name,
            is_active
        ),
        work_order_assignments (
            technician_id,
            assigned_at,
            assigned_by,
            users!work_order_assignments_technician_id_fkey (
                id,
                email,
                full_name
            )
        )
    """)
        .eq("id", work_order_id)
        .execute()
    )
    if not result.data:
        return None
    data = result.data[0]
    if not data.get("creator") and data.get("created_by"):
        fallback_user = (
            supabase.table("users")
            .select("full_name, email")
            .eq("auth_id", data["created_by"])
            .execute()
        )
        if fallback_user.data:
            data["creator"] = fallback_user.data[0]
    return data


def _get_user_by_email(email: str) -> Optional[dict]:
    result = supabase.table("users").select("*").eq("email", email).execute()
    return result.data[0] if result.data else None


def _get_user_id_by_email(email: str) -> Optional[str]:
    user = _get_user_by_email(email)
    if user:
        return user.get("id")
    return None


def _fetch_signatures_for_pdf(work_order_id: str):
    sigs_result = (
        supabase.table("work_order_signatures")
        .select("*")
        .eq("work_order_id", work_order_id)
        .order("signed_at", desc=False)
        .execute()
    )
    sigs = sigs_result.data or []

    technician_sig = None
    admin_sig = None

    for sig in sigs:
        if sig.get("status") == "rejected":
            continue
        signer_email = sig.get("signer_email")
        if not signer_email:
            continue
        user_result = (
            supabase.table("users")
            .select("full_name")
            .eq("email", signer_email)
            .execute()
        )
        signer_full_name = (
            user_result.data[0].get("full_name") if user_result.data else None
        )

        sig["signer_full_name"] = signer_full_name

        if sig.get("signer_role") == "technician" and technician_sig is None:
            technician_sig = sig
        elif sig.get("signer_role") == "admin" and admin_sig is None:
            admin_sig = sig

    return {
        "technician": technician_sig,
        "admin": admin_sig,
    }


def _build_work_order_pdf(wo_data: dict, signatures: dict) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=2 * cm,
        rightMargin=2 * cm,
        topMargin=1.5 * cm,
        bottomMargin=1.5 * cm,
    )

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        "Title",
        parent=styles["Heading1"],
        fontSize=16,
        textColor=HexColor("#1a2744"),
        alignment=TA_CENTER,
        spaceAfter=6,
    )
    subtitle_style = ParagraphStyle(
        "Subtitle",
        parent=styles["Normal"],
        fontSize=10,
        textColor=HexColor("#666666"),
        alignment=TA_CENTER,
        spaceAfter=12,
    )
    section_style = ParagraphStyle(
        "Section",
        parent=styles["Heading2"],
        fontSize=12,
        textColor=HexColor("#1a2744"),
        spaceBefore=16,
        spaceAfter=8,
    )
    normal_style = styles["Normal"]

    elements = []

    logo_dir = os.path.join(os.path.dirname(__file__), "..", "assets")
    logos = []
    for logo_name in [
        "logo_emblem.png",
        "logo_civilaviation.png",
        "logo_newkuwait.png",
    ]:
        logo_path = os.path.join(logo_dir, logo_name)
        if os.path.exists(logo_path):
            try:
                img = RLImage(logo_path, width=2 * cm, height=2 * cm)
                logos.append(img)
            except Exception:
                pass

    if logos:
        logo_table_data = [
            [
                logos[0] if len(logos) > 0 else "",
                logos[1] if len(logos) > 1 else "",
                logos[2] if len(logos) > 2 else "",
            ]
        ]
        logo_table = Table(logo_table_data, colWidths=[5.5 * cm, 5.5 * cm, 5.5 * cm])
        logo_table.setStyle(
            TableStyle(
                [
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                    ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ]
            )
        )
        elements.append(logo_table)

    elements.append(Paragraph("Work Order Completion Report", title_style))

    dept_name = wo_data.get("departments", {}).get("name", "N/A")
    export_date = datetime.now().strftime("%Y-%m-%d %H:%M")
    elements.append(Paragraph(f"{dept_name} • {export_date}", subtitle_style))

    line_style = TableStyle([("LINEABOVE", (0, 0), (-1, 0), 0.5, lightgrey)])
    line_table = Table([[""]], colWidths=[15 * cm])
    line_table.setStyle(line_style)
    elements.append(line_table)
    elements.append(Spacer(1, 8))

    elements.append(Paragraph("Work Order Details", section_style))

    def safe_str(val):
        return str(val or "")

    details_data = [
        ("Job No:", safe_str(wo_data.get("job_no"))),
        ("Title:", safe_str(wo_data.get("title"))),
        ("Type:", safe_str(wo_data.get("type"))),
        ("Status:", safe_str(wo_data.get("status"))),
        ("Department:", safe_str(wo_data.get("departments", {}).get("name"))),
        ("Location:", safe_str(wo_data.get("location"))),
        ("Mobile Number:", safe_str(wo_data.get("mobile_number"))),
        ("Created By:", safe_str(wo_data.get("creator", {}).get("full_name"))),
        ("Created At:", safe_str(wo_data.get("created_at"))),
        (
            "Closed At:",
            safe_str(wo_data.get("closed_at")) if wo_data.get("closed_at") else "N/A",
        ),
    ]

    details_table = Table(details_data, colWidths=[3.5 * cm, 11.5 * cm])
    details_table.setStyle(
        TableStyle(
            [
                ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
                ("FONTNAME", (1, 0), (1, -1), "Helvetica"),
                ("FONTSIZE", (0, 0), (-1, -1), 10),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    elements.append(details_table)

    description = wo_data.get("description")
    if description:
        elements.append(Spacer(1, 8))
        elements.append(Paragraph("<b>Description</b>", normal_style))
        elements.append(Paragraph(xml_escape(safe_str(description)), normal_style))

    tech_notes = wo_data.get("tech_notes")
    if tech_notes:
        elements.append(Spacer(1, 8))
        elements.append(Paragraph("<b>Tech Notes</b>", normal_style))
        elements.append(Paragraph(xml_escape(safe_str(tech_notes)), normal_style))

    assignments = wo_data.get("work_order_assignments", [])
    if assignments:
        elements.append(Paragraph("Assigned Technicians", section_style))
        tech_names = []
        for a in assignments:
            user = a.get("users")
            if user and user.get("full_name"):
                tech_names.append(user["full_name"])
        if tech_names:
            for name in tech_names:
                elements.append(Paragraph(f"• {xml_escape(name)}", normal_style))

    elements.append(Paragraph("Signatures", section_style))

    def render_signature_box(sig, role_label):
        """Build a list of flowables for one signature column."""
        items = [Paragraph(f"<b>{xml_escape(role_label)}</b>", normal_style)]

        if sig is None:
            items.append(Spacer(1, 6))
            items.append(Paragraph("Awaiting Signature", normal_style))
            return items

        sig_status = sig.get("status", "")
        status_color = "green" if sig_status == "approved" else "black"
        status_text = "Approved" if sig_status == "approved" else sig_status

        signer_name = xml_escape(
            sig.get("signer_full_name") or sig.get("signer_email") or "Unknown"
        )
        signer_email = xml_escape(sig.get("signer_email") or "")
        signed_at = xml_escape(str(sig.get("signed_at") or ""))

        items.append(Spacer(1, 4))
        items.append(Paragraph(signer_name, normal_style))
        items.append(Paragraph(signer_email, normal_style))
        items.append(Paragraph(f"Signed: {signed_at}", normal_style))
        items.append(
            Paragraph(f'<font color="{status_color}">{xml_escape(status_text)}</font>', normal_style)
        )

        # Embed signature image as a proper RLImage flowable
        sig_path = sig.get("signature_path")
        if sig_path:
            sig_file_path = os.path.join(
                os.path.dirname(__file__), "..", "uploaded_files", sig_path
            )
            if os.path.exists(sig_file_path):
                try:
                    items.append(Spacer(1, 4))
                    items.append(RLImage(sig_file_path, width=150, height=50))
                except Exception:
                    items.append(Paragraph("[Signature image error]", normal_style))
            else:
                items.append(Paragraph("[Signature file not found]", normal_style))

        return items

    tech_items = render_signature_box(
        signatures.get("technician"), "Technician Signature"
    )
    admin_items = render_signature_box(
        signatures.get("admin"), "Authorized By"
    )

    # Wrap each column's flowables in a nested Table cell so they stack vertically
    tech_cell = Table([[item] for item in tech_items], colWidths=[7 * cm])
    tech_cell.setStyle(TableStyle([
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 1),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
    ]))
    admin_cell = Table([[item] for item in admin_items], colWidths=[7 * cm])
    admin_cell.setStyle(TableStyle([
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 1),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
    ]))

    sig_table = Table([[tech_cell, admin_cell]], colWidths=[7.5 * cm, 7.5 * cm])
    sig_table.setStyle(
        TableStyle(
            [
                ("BOX", (0, 0), (0, 0), 0.5, lightgrey),
                ("BOX", (1, 0), (1, 0), 0.5, lightgrey),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    elements.append(sig_table)

    def draw_footer(canvas, doc):
        canvas.saveState()
        canvas.setFont("Helvetica", 8)
        footer_text = "Generated by Civil Aviation Work Order System"
        page_num = doc.page
        page_text = f"Page {page_num}"
        date_text = datetime.now().strftime("%Y-%m-%d %H:%M")
        canvas.drawString(2 * cm, 1 * cm, footer_text)
        canvas.drawString(7.5 * cm, 1 * cm, date_text)
        canvas.drawRightString(19 * cm - 2 * cm, 1 * cm, page_text)
        canvas.restoreState()

    doc.build(elements, onFirstPage=draw_footer, onLaterPages=draw_footer)

    return buffer.getvalue()


@router.get("/reports/closed-work-orders")
def get_closed_work_orders(
    technician_id: str = Query(...),
    start_date: str = Query(...),
    end_date: str = Query(...),
):
    try:
        resp = (
            supabase.from_("work_orders")
            .select(
                "title, location, closed_at, work_order_assignments!inner(technician_id)"
            )
            .eq("work_order_assignments.technician_id", technician_id)
            .gte("closed_at", start_date)
            .lte("closed_at", end_date)
            .order("closed_at", desc=True)
            .execute()
        )
        rows = resp.data or []
        return [
            {
                "title": r["title"],
                "location": r["location"],
                "closed_at": r["closed_at"],
            }
            for r in rows
        ]
    except Exception as e:
        return JSONResponse(status_code=500, content={"detail": str(e)})


@router.post("/reports/work-order-pdf/{work_order_id}")
async def export_work_order_pdf(
    work_order_id: str,
    email: Optional[str] = Query(None),
    user_role: Optional[str] = Query(None),
):
    wo_data = _fetch_wo_for_pdf(work_order_id)
    if not wo_data:
        raise HTTPException(status_code=404, detail="Work order not found")

    if user_role == "reporter" and email:
        reporter_user_id = _get_user_id_by_email(email)
        if reporter_user_id and wo_data.get("created_by") != reporter_user_id:
            raise HTTPException(status_code=403, detail="Access denied")

    if user_role == "technician" and email:
        user = _get_user_by_email(email)
        if user and wo_data.get("department_id") != user.get("department_id"):
            raise HTTPException(status_code=403, detail="Access denied")

    signatures = _fetch_signatures_for_pdf(work_order_id)

    try:
        pdf_bytes = _build_work_order_pdf(wo_data, signatures)
    except Exception as e:
        return JSONResponse(
            status_code=500, content={"detail": f"Failed to generate PDF: {str(e)}"}
        )

    job_no = wo_data.get("job_no", "unknown")
    log_activity(
        email or "unknown",
        "work_order",
        "pdf_exported",
        target_label=f"WO {job_no}",
        target_id=work_order_id,
    )

    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="WO-{job_no}-report.pdf"'
        },
    )
