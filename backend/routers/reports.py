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
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

# Register fonts
_font_dir = os.path.join(os.path.dirname(__file__), "..", "assets")
try:
    pdfmetrics.registerFont(
        TTFont("Inter", os.path.join(_font_dir, "Inter-Regular.ttf"))
    )
    pdfmetrics.registerFont(
        TTFont("Inter-Bold", os.path.join(_font_dir, "Inter-Bold.ttf"))
    )
    _FONT = "Inter"
    _FONT_BOLD = "Inter-Bold"
except Exception:
    _FONT = "Helvetica"
    _FONT_BOLD = "Helvetica-Bold"

# Register Arabic font
try:
    pdfmetrics.registerFont(
        TTFont("NotoArabic", os.path.join(_font_dir, "NotoSansArabic-Regular.ttf"))
    )
    pdfmetrics.registerFont(
        TTFont("NotoArabic-Bold", os.path.join(_font_dir, "NotoSansArabic-Bold.ttf"))
    )
    _FONT_AR = "NotoArabic"
    _FONT_AR_BOLD = "NotoArabic-Bold"
except Exception:
    _FONT_AR = _FONT
    _FONT_AR_BOLD = _FONT_BOLD

import re

_ARABIC_RE = re.compile(
    r"[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]"
)


def _has_arabic(text: str) -> bool:
    return bool(_ARABIC_RE.search(text or ""))


def _reshape_arabic(text: str) -> str:
    """Reshape and reorder Arabic text for correct RTL display in reportlab."""
    try:
        import arabic_reshaper
        from bidi.algorithm import get_display

        reshaped = arabic_reshaper.reshape(text)
        return get_display(reshaped)
    except Exception:
        return text


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
    if not isinstance(data, dict):
        raise ValueError(f"Expected dict from Supabase, got {type(data).__name__}")

    # Normalize nested relationships that may come back as strings instead of dicts
    for key in ("creator", "departments"):
        val = data.get(key)
        if val is not None and not isinstance(val, dict):
            data[key] = None  # clear bad join data

    if not data.get("creator") and data.get("created_by"):
        fallback_user = (
            supabase.table("users")
            .select("full_name, email")
            .eq("auth_id", data["created_by"])
            .execute()
        )
        if fallback_user.data and isinstance(fallback_user.data[0], dict):
            data["creator"] = fallback_user.data[0]

    # Normalize work_order_assignments
    assignments = data.get("work_order_assignments")
    if assignments is not None and not isinstance(assignments, list):
        data["work_order_assignments"] = []
    elif isinstance(assignments, list):
        data["work_order_assignments"] = [a for a in assignments if isinstance(a, dict)]

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
        .eq("status", "approved")
        .order("signed_at", desc=False)
        .execute()
    )
    sigs = sigs_result.data or []

    technician_sig = None
    supervisor_sig = None
    superindent_sig = None

    for sig in sigs:
        if not isinstance(sig, dict):
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
        signer_full_name = None
        if user_result.data and isinstance(user_result.data[0], dict):
            signer_full_name = user_result.data[0].get("full_name")

        sig["signer_full_name"] = signer_full_name

        role = sig.get("signer_role")
        if role == "technician" and technician_sig is None:
            technician_sig = sig
        elif role == "supervisor" and supervisor_sig is None:
            supervisor_sig = sig
        elif role == "superintendent" and superindent_sig is None:
            superindent_sig = sig

    return {
        "technician": technician_sig,
        "supervisor": supervisor_sig,
        "superintendent": superindent_sig,
    }


def _build_work_order_pdf(wo_data: dict, signatures: dict) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=1.2 * cm,
        rightMargin=1.2 * cm,
        topMargin=0.8 * cm,
        bottomMargin=1.5 * cm,
    )

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        "Title",
        parent=styles["Heading1"],
        fontName=_FONT_BOLD,
        fontSize=16,
        textColor=HexColor("#3D3929"),
        alignment=TA_CENTER,
        spaceAfter=6,
    )
    subtitle_style = ParagraphStyle(
        "Subtitle",
        parent=styles["Normal"],
        fontName=_FONT,
        fontSize=10,
        textColor=HexColor("#8C8575"),
        alignment=TA_CENTER,
        spaceAfter=12,
    )
    section_style = ParagraphStyle(
        "Section",
        parent=styles["Heading2"],
        fontName=_FONT_BOLD,
        fontSize=12,
        textColor=HexColor("#3D3929"),
        spaceBefore=16,
        spaceAfter=8,
    )
    normal_style = ParagraphStyle(
        "Body",
        parent=styles["Normal"],
        fontName=_FONT,
        fontSize=10,
        textColor=HexColor("#4A4538"),
        leading=14,
    )

    elements = []

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

    # Order: NewKuwait (left), Emblem (center, largest), Civil Aviation (right)
    logo_newkuwait = _load_logo("logo_newkuwait.png", 3.5 * cm, 3.5 * cm)
    logo_emblem = _load_logo("logo_emblem.png", 4 * cm, 4 * cm)
    logo_civilaviation = _load_logo("logo_civilaviation.png", 4.5 * cm, 2.5 * cm)

    if any([logo_newkuwait, logo_emblem, logo_civilaviation]):
        logo_table = Table(
            [[logo_newkuwait, logo_emblem, logo_civilaviation]],
            colWidths=[6 * cm, 6 * cm, 6 * cm],
        )
        logo_table.setStyle(
            TableStyle(
                [
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                    ("ALIGN", (0, 0), (0, 0), "LEFT"),
                    ("ALIGN", (1, 0), (1, 0), "CENTER"),
                    ("ALIGN", (2, 0), (2, 0), "RIGHT"),
                ]
            )
        )
        elements.append(logo_table)

    def safe_str(val):
        return str(val or "")

    def _ar(text):
        """Reshape Arabic text for RTL display and wrap with Arabic font."""
        raw = safe_str(text)
        if _has_arabic(raw):
            shaped = _reshape_arabic(raw)
            return f'<font face="{_FONT_AR}">{xml_escape(shaped)}</font>'
        return xml_escape(raw)

    elements.append(Spacer(1, 8))
    elements.append(Paragraph("Work Order Completion Report", title_style))

    dept_raw = wo_data.get("departments")
    if isinstance(dept_raw, dict):
        dept_name_val = dept_raw.get("name") or "N/A"
    elif isinstance(dept_raw, str):
        dept_name_val = dept_raw or "N/A"
    else:
        dept_name_val = "N/A"
    dept_name = _ar(dept_name_val)

    creator_raw = wo_data.get("creator")
    if isinstance(creator_raw, dict):
        creator_name = creator_raw.get("full_name") or "N/A"
    elif isinstance(creator_raw, str):
        creator_name = creator_raw or "N/A"
    else:
        creator_name = "N/A"
    export_date = datetime.now().strftime("%Y-%m-%d %H:%M")
    elements.append(Paragraph(f"{dept_name} • {export_date}", subtitle_style))

    line_style = TableStyle([("LINEABOVE", (0, 0), (-1, 0), 0.5, lightgrey)])
    line_table = Table([[""]], colWidths=[15 * cm])
    line_table.setStyle(line_style)
    elements.append(line_table)
    elements.append(Spacer(1, 8))

    elements.append(Paragraph("Work Order Details", section_style))

    def fmt_date(val):
        """Format ISO timestamp to Kuwait local time (UTC+3)."""
        if not val:
            return "N/A"
        try:
            from dateutil import parser as dateparser, tz

            dt = dateparser.parse(str(val))
            kuwait_tz = tz.tzoffset("AST", 3 * 3600)
            dt = dt.astimezone(kuwait_tz)
            return dt.strftime("%-d %b %Y, %I:%M %p")
        except Exception:
            try:
                from datetime import timedelta, timezone

                dt = datetime.fromisoformat(str(val).replace("Z", "+00:00"))
                dt = dt.astimezone(timezone(timedelta(hours=3)))
                return dt.strftime("%d %b %Y, %I:%M %p").lstrip("0")
            except Exception:
                return str(val)

    label_style = ParagraphStyle(
        "Label",
        parent=normal_style,
        fontName=_FONT_BOLD,
        fontSize=10,
    )
    details_data = [
        (
            Paragraph("Job No:", label_style),
            Paragraph(_ar(wo_data.get("job_no")), normal_style),
        ),
        (
            Paragraph("Title:", label_style),
            Paragraph(_ar(wo_data.get("title")), normal_style),
        ),
        (
            Paragraph("Type:", label_style),
            Paragraph(_ar(wo_data.get("type")), normal_style),
        ),
        (
            Paragraph("Status:", label_style),
            Paragraph(_ar(wo_data.get("status")), normal_style),
        ),
        (
            Paragraph("Department:", label_style),
            Paragraph(_ar(dept_name_val), normal_style),
        ),
        (
            Paragraph("Location:", label_style),
            Paragraph(_ar(wo_data.get("location")), normal_style),
        ),
        (
            Paragraph("Mobile Number:", label_style),
            Paragraph(safe_str(wo_data.get("mobile_number")), normal_style),
        ),
        (
            Paragraph("Created By:", label_style),
            Paragraph(_ar(creator_name), normal_style),
        ),
        (
            Paragraph("Created At:", label_style),
            Paragraph(fmt_date(wo_data.get("created_at")), normal_style),
        ),
        (
            Paragraph("Closed At:", label_style),
            Paragraph(fmt_date(wo_data.get("closed_at")), normal_style),
        ),
    ]

    details_table = Table(details_data, colWidths=[3.5 * cm, 14 * cm])
    details_table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    elements.append(details_table)

    description = wo_data.get("description")
    if description:
        elements.append(Paragraph("Description", section_style))
        elements.append(Paragraph(_ar(description), normal_style))

    tech_notes = wo_data.get("tech_notes")
    if tech_notes:
        elements.append(Paragraph("Tech Notes", section_style))
        elements.append(Paragraph(_ar(tech_notes), normal_style))

    assignments = wo_data.get("work_order_assignments") or []
    if isinstance(assignments, list) and assignments:
        elements.append(Paragraph("Assigned Technicians", section_style))
        tech_names = []
        for a in assignments:
            if not isinstance(a, dict):
                continue
            user = a.get("users")
            if isinstance(user, dict) and user.get("full_name"):
                tech_names.append(user["full_name"])
        if tech_names:
            for name in tech_names:
                elements.append(Paragraph(f"• {_ar(name)}", normal_style))

    elements.append(Paragraph("Signatures", section_style))

    small_style = ParagraphStyle(
        "SigSmall",
        parent=normal_style,
        fontSize=9,
        leading=12,
    )

    def _load_sig_image(sig_path):
        """Load signature image, return RLImage or None."""
        if not sig_path:
            return None
        sig_filename = os.path.basename(sig_path)
        sig_file_path = os.path.join(
            os.path.dirname(__file__), "..", "uploaded_files", sig_filename
        )
        if not os.path.exists(sig_file_path):
            return None
        try:
            from reportlab.lib.utils import ImageReader

            reader = ImageReader(sig_file_path)
            iw, ih = reader.getSize()
            max_w = 6 * cm
            max_h = 3 * cm
            scale = min(max_w / iw, max_h / ih)
            return RLImage(sig_file_path, width=iw * scale, height=ih * scale)
        except Exception:
            return None

    def render_sig_column(sig, role_label):
        """Build a compact 2-row table: [image] then [label + info]."""
        if sig is None or not isinstance(sig, dict):
            return Paragraph(
                f"<b>{xml_escape(role_label)}</b><br/><br/>Awaiting Signature",
                small_style,
            )

        sig_status = sig.get("status", "")
        status_color = "#228B22" if sig_status == "approved" else "black"
        status_text = "Approved" if sig_status == "approved" else sig_status
        raw_name = sig.get("signer_full_name") or sig.get("signer_email") or "Unknown"
        signer_name = _ar(raw_name)
        signer_email = xml_escape(sig.get("signer_email") or "")

        sig_img = _load_sig_image(sig.get("signature_path"))

        rows = []
        # Signature image first (visually prominent)
        if sig_img:
            rows.append([sig_img])
        else:
            rows.append([Paragraph("[Signature file not found]", small_style)])

        # Label + signer info below
        info_text = (
            f"<b>{xml_escape(role_label)}</b><br/>"
            f"{signer_name}<br/>"
            f"<font color='#666666'>{signer_email}</font><br/>"
            f"<font color='{status_color}'><b>{xml_escape(status_text)}</b></font>"
        )
        rows.append([Paragraph(info_text, small_style)])

        cell = Table(rows, colWidths=[7 * cm])
        cell.setStyle(
            TableStyle(
                [
                    ("LEFTPADDING", (0, 0), (-1, -1), 0),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                    ("TOPPADDING", (0, 0), (-1, -1), 2),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
                ]
            )
        )
        return cell

    tech_col = render_sig_column(signatures.get("technician"), "Technician Signature")
    admin_col = render_sig_column(
        signatures.get("supervisor") or signatures.get("superintendent"),
        "Authorized By",
    )

    sig_table = Table([[tech_col, admin_col]], colWidths=[8 * cm, 8 * cm])
    sig_table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
            ]
        )
    )
    elements.append(sig_table)

    def draw_footer(canvas, doc):
        canvas.saveState()
        canvas.setFont(_FONT, 7)
        page_w = A4[0]
        footer_text = "Generated by Civil Aviation Work Order System"
        page_text = f"Page {doc.page}"
        date_text = datetime.now().strftime("%Y-%m-%d %H:%M")
        canvas.drawString(1.2 * cm, 0.8 * cm, footer_text)
        canvas.drawCentredString(page_w / 2, 0.8 * cm, date_text)
        canvas.drawRightString(page_w - 1.2 * cm, 0.8 * cm, page_text)
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
        import traceback
        tb = traceback.format_exc()
        print(f"[PDF ERROR] work_order_id={work_order_id}\n{tb}")
        # Include traceback line info for debugging
        return JSONResponse(
            status_code=500,
            content={"detail": f"Failed to generate PDF: {str(e)}", "trace": tb},
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
