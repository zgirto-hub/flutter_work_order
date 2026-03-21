import io
import os
from typing import List, Optional

from fastapi import APIRouter, Query
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel

from db import supabase

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
    Image, HRFlowable, KeepTogether
)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

router = APIRouter()

# ── Logo paths (relative to project root where uvicorn runs) ──────────────────
LOGO_DIR = "backend/assets"
LOGO_NEWKUWAIT    = os.path.join(LOGO_DIR, "logo_newkuwait.png")
LOGO_EMBLEM       = os.path.join(LOGO_DIR, "logo_emblem.png")
LOGO_CIVILAVIATION = os.path.join(LOGO_DIR, "logo_civilaviation.png")

# ── Colour palette ─────────────────────────────────────────────────────────────
NAVY        = colors.HexColor("#0D1B3E")       # dark navy — top banner, headings
NAVY_MED    = colors.HexColor("#1A2B5E")       # rule line, table header
TEAL_RULE   = colors.HexColor("#1A5276")       # horizontal rule below logos
GREY_TEXT   = colors.HexColor("#555555")
LIGHT_GREY  = colors.HexColor("#F7F7F7")       # alternate row fill
WHITE       = colors.white
COL_HEADER  = colors.HexColor("#1F3864")       # task-log table header
ROW_ALT     = colors.HexColor("#F0F4F8")       # alternating row bg
BORDER_COL  = colors.HexColor("#CCCCCC")

# ── Paragraph styles ───────────────────────────────────────────────────────────
def _style(name, font="Helvetica", size=10, color=colors.black,
           align=TA_LEFT, bold=False, leading=None):
    return ParagraphStyle(
        name,
        fontName="Helvetica-Bold" if bold else font,
        fontSize=size,
        textColor=color,
        alignment=align,
        leading=leading or (size * 1.3),
    )

S_BANNER    = _style("banner",    size=8,  color=WHITE,      align=TA_CENTER)
S_DEPT      = _style("dept",      size=13, color=NAVY,       align=TA_CENTER, bold=True)
S_SECTION   = _style("section",   size=9,  color=GREY_TEXT,  align=TA_CENTER)
S_TITLE     = _style("title",     size=20, color=NAVY,       align=TA_CENTER, bold=True)
S_MONTH     = _style("month",     size=26, color=WHITE,      align=TA_CENTER, bold=True)
S_YEAR      = _style("year",      size=11, color=colors.HexColor("#BBCCDD"), align=TA_CENTER)
S_LABEL     = _style("label",     size=8,  color=GREY_TEXT,  align=TA_LEFT)
S_VALUE     = _style("value",     size=10, color=NAVY,       align=TA_LEFT, bold=True)
S_TASKLOG   = _style("tasklog",   size=11, color=WHITE,      align=TA_LEFT,  bold=True)
S_TASKCOUNT = _style("taskcount", size=8,  color=colors.HexColor("#AABBDD"), align=TA_RIGHT)
S_COL_HDR   = _style("colhdr",   size=9,  color=WHITE,       align=TA_LEFT,  bold=True)
S_CELL      = _style("cell",      size=9,  color=colors.HexColor("#333333"), align=TA_LEFT)
S_CELL_NUM  = _style("cellnum",   size=9,  color=GREY_TEXT,  align=TA_CENTER)
S_STAT_NUM  = _style("statnum",   size=22, color=NAVY,       align=TA_CENTER, bold=True)
S_STAT_LBL  = _style("statlbl",  size=8,  color=GREY_TEXT,  align=TA_CENTER)
S_DATE_TOP  = _style("datetop",  size=11, color=WHITE,      align=TA_CENTER, bold=True)
S_DATE_BOT  = _style("datebot",  size=9,  color=colors.HexColor("#BBCCDD"), align=TA_CENTER)
S_PREP_LBL  = _style("preplbl",  size=8,  color=GREY_TEXT,  align=TA_LEFT)
S_PREP_NAME = _style("prepname", size=11, color=NAVY,       align=TA_LEFT,  bold=True)
S_SIG_LBL   = _style("siglbl",  size=8,  color=GREY_TEXT,  align=TA_CENTER)
S_FOOTER    = _style("footer",   size=7,  color=GREY_TEXT,  align=TA_LEFT)
S_FOOTER_C  = _style("footerc",  size=7,  color=GREY_TEXT,  align=TA_CENTER)
S_FOOTER_R  = _style("footerr",  size=7,  color=GREY_TEXT,  align=TA_RIGHT)

# ── Page geometry ──────────────────────────────────────────────────────────────
PAGE_W, PAGE_H = A4
MARGIN_L = 18 * mm
MARGIN_R = 18 * mm
MARGIN_T = 14 * mm
MARGIN_B = 14 * mm
BANNER_H  = 9 * mm
FOOTER_H  = 8 * mm

# ── Pydantic models ────────────────────────────────────────────────────────────

class MonthlyTaskItem(BaseModel):
    description: str
    date: str        # "DD/MM/YYYY"
    location: str


class MonthlyTasksRequest(BaseModel):
    name: str
    start_date: str                                        # e.g. "01 Jan 2026"
    end_date: str                                          # e.g. "31 Jan 2026"
    tasks: List[MonthlyTaskItem]
    department: str = "Navigational Equipment Department"  # kept for future use
    section:    str = "AFTN/AMHS Section"                 # kept for future use
    title:      str = ""                                   # kept for future use
    dgca_id:    str = "—"                                  # kept for future use
    civil_id:   str = "—"


# ── Task categorisation ────────────────────────────────────────────────────────

def _classify(tasks: List[MonthlyTaskItem]):
    system = cadas = cctv = 0
    for t in tasks:
        d = t.description.upper()
        if "CADAS" in d:
            cadas += 1
        elif "CAMERA" in d or "CCTV" in d or "PTZ" in d:
            cctv += 1
        elif "AFTN" in d or "AMHS" in d or "INSPECTING" in d or "CHECKING" in d:
            system += 1
    return system, cadas, cctv


# ── Page template (banner + footer drawn on canvas) ───────────────────────────

def _on_page(canvas, doc):
    canvas.saveState()
    w, h = PAGE_W, PAGE_H

    # ── Top banner ──────────────────────────────────────────────────────────
    canvas.setFillColor(NAVY)
    canvas.rect(0, h - BANNER_H, w, BANNER_H, stroke=0, fill=1)
    canvas.setFillColor(WHITE)
    canvas.setFont("Helvetica-Bold", 8)
    canvas.drawCentredString(w / 2, h - BANNER_H + 3 * mm,
                             "STATE OF KUWAIT — DIRECTORATE GENERAL OF CIVIL AVIATION")

    # ── Footer ──────────────────────────────────────────────────────────────
    canvas.setFillColor(NAVY)
    canvas.rect(0, 0, w, FOOTER_H, stroke=0, fill=1)
    canvas.setFillColor(WHITE)
    canvas.setFont("Helvetica", 7)
    left_text   = f"Navigational Equipment Dept. — AFTN/AMHS Section"
    centre_text = f"Page {doc.page}"
    right_text  = "CONFIDENTIAL — INTERNAL USE"
    pad = MARGIN_L
    canvas.drawString(pad, 2.5 * mm, left_text)
    canvas.drawCentredString(w / 2, 2.5 * mm, centre_text)
    canvas.drawRightString(w - pad, 2.5 * mm, right_text)

    canvas.restoreState()


# ── PDF builder ────────────────────────────────────────────────────────────────

def _build_pdf(data: MonthlyTasksRequest) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=MARGIN_L,
        rightMargin=MARGIN_R,
        topMargin=MARGIN_T + BANNER_H,
        bottomMargin=MARGIN_B + FOOTER_H,
    )

    body_w = PAGE_W - MARGIN_L - MARGIN_R
    story  = []

    # ── 1. Logos row ──────────────────────────────────────────────────────
    logo_h = 18 * mm
    def _logo(path):
        if os.path.exists(path):
            img = Image(path)
            aspect = img.imageWidth / img.imageHeight
            img._restrictSize(logo_h * aspect, logo_h)
            return img
        return Paragraph("", S_CELL)

    logo_table = Table(
        [[_logo(LOGO_NEWKUWAIT), _logo(LOGO_EMBLEM), _logo(LOGO_CIVILAVIATION)]],
        colWidths=[body_w / 3] * 3,
    )
    logo_table.setStyle(TableStyle([
        ("ALIGN",       (0, 0), (-1, -1), "CENTER"),
        ("VALIGN",      (0, 0), (-1, -1), "MIDDLE"),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING",  (0, 0), (-1, -1), 4),
    ]))
    story.append(logo_table)
    story.append(Spacer(1, 2 * mm))

    # ── 2. Horizontal rule ────────────────────────────────────────────────
    story.append(HRFlowable(width="100%", thickness=2.5, color=TEAL_RULE,
                            spaceAfter=3 * mm))

    # ── 3. Title heading ──────────────────────────────────────────────────
    story.append(Paragraph("Report of Monthly Tasks", S_TITLE))
    story.append(Spacer(1, 5 * mm))

    # ── 4. Info table ─────────────────────────────────────────────────────
    #  | Date range (navy bg) | Full Name label+value | Civil ID |
    name_parts = data.name.split()
    name_display = "\n".join(name_parts) if len(name_parts) > 2 else data.name

    date_cell = Table(
        [[Paragraph(data.start_date, S_DATE_TOP)],
         [Paragraph("to",            S_DATE_BOT)],
         [Paragraph(data.end_date,   S_DATE_TOP)]],
    )
    date_cell.setStyle(TableStyle([
        ("BACKGROUND",    (0, 0), (-1, -1), NAVY),
        ("ALIGN",         (0, 0), (-1, -1), "CENTER"),
        ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING",    (0, 0), (-1, -1), 8),
        ("LEFTPADDING",   (0, 0), (-1, -1), 6),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 6),
    ]))

    def _info_cell(label, value_text):
        return Table(
            [[Paragraph(label, S_LABEL)],
             [Paragraph(value_text, S_VALUE)]],
        )

    info_table = Table(
        [[
            date_cell,
            _info_cell("Full Name", name_display),
            _info_cell("Civil ID",  data.civil_id),
        ]],
        colWidths=[38 * mm, 90 * mm, 47 * mm],
    )
    info_table.setStyle(TableStyle([
        ("BOX",           (0, 0), (-1, -1), 0.5, BORDER_COL),
        ("LINEBEFORE",    (1, 0), (-1, -1), 0.5, BORDER_COL),
        ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING",   (0, 0), (-1, -1), 6),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 6),
        ("TOPPADDING",    (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(info_table)
    story.append(Spacer(1, 5 * mm))

    # ── 5. Task log header bar ─────────────────────────────────────────────
    n = len(data.tasks)
    task_header = Table(
        [[
            Paragraph("TASK LOG", S_TASKLOG),
            Paragraph(f"{n} task{'s' if n != 1 else ''} recorded — {data.start_date} to {data.end_date}", S_TASKCOUNT),
        ]],
        colWidths=[body_w * 0.5, body_w * 0.5],
    )
    task_header.setStyle(TableStyle([
        ("BACKGROUND",    (0, 0), (-1, -1), COL_HEADER),
        ("TOPPADDING",    (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ("LEFTPADDING",   (0, 0), (-1, -1), 8),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 8),
        ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
    ]))
    story.append(task_header)

    # ── 6. Column header row ──────────────────────────────────────────────
    col_w = [12 * mm, body_w - 12 * mm - 28 * mm - 40 * mm, 28 * mm, 40 * mm]

    col_headers = Table(
        [[
            Paragraph("No.", S_COL_HDR),
            Paragraph("Task Description", S_COL_HDR),
            Paragraph("Date", S_COL_HDR),
            Paragraph("Location", S_COL_HDR),
        ]],
        colWidths=col_w,
    )
    col_headers.setStyle(TableStyle([
        ("BACKGROUND",    (0, 0), (-1, -1), colors.HexColor("#2C4A7C")),
        ("TOPPADDING",    (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING",   (0, 0), (-1, -1), 6),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 6),
        ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
        ("LINEBELOW",     (0, 0), (-1, -1), 0.5, colors.HexColor("#1A3060")),
    ]))
    story.append(col_headers)

    # ── 7. Task rows ──────────────────────────────────────────────────────
    for i, task in enumerate(data.tasks):
        bg = ROW_ALT if i % 2 == 0 else WHITE
        row_table = Table(
            [[
                Paragraph(str(i + 1), S_CELL_NUM),
                Paragraph(task.description, S_CELL),
                Paragraph(task.date, S_CELL),
                Paragraph(task.location, S_CELL),
            ]],
            colWidths=col_w,
        )
        row_table.setStyle(TableStyle([
            ("BACKGROUND",    (0, 0), (-1, -1), bg),
            ("TOPPADDING",    (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ("LEFTPADDING",   (0, 0), (-1, -1), 6),
            ("RIGHTPADDING",  (0, 0), (-1, -1), 6),
            ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
            ("LINEBELOW",     (0, 0), (-1, -1), 0.3, BORDER_COL),
            ("ALIGN",         (0, 0), (0, 0),   "CENTER"),
        ]))
        story.append(row_table)

    story.append(Spacer(1, 5 * mm))

    # ── 8. Summary stats row ──────────────────────────────────────────────
    system_n, cadas_n, cctv_n = _classify(data.tasks)
    stats = [
        (str(n),        "Total Tasks"),
        (str(system_n), "System Inspections"),
        (str(cadas_n),  "CADAS Mailbox Tasks"),
        (str(cctv_n),   "CCTV / Camera Tasks"),
    ]

    stat_cells = []
    for num, lbl in stats:
        cell = Table(
            [[Paragraph(num, S_STAT_NUM)],
             [Paragraph(lbl, S_STAT_LBL)]],
        )
        cell.setStyle(TableStyle([
            ("TOPPADDING",    (0, 0), (-1, -1), 8),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ("LEFTPADDING",   (0, 0), (-1, -1), 4),
            ("RIGHTPADDING",  (0, 0), (-1, -1), 4),
            ("ALIGN",         (0, 0), (-1, -1), "CENTER"),
        ]))
        stat_cells.append(cell)

    stat_table = Table(
        [stat_cells],
        colWidths=[body_w / 4] * 4,
    )
    stat_table.setStyle(TableStyle([
        ("BOX",        (0, 0), (-1, -1), 0.5, BORDER_COL),
        ("LINEBEFORE", (1, 0), (-1, -1), 0.5, BORDER_COL),
        ("VALIGN",     (0, 0), (-1, -1), "MIDDLE"),
    ]))
    story.append(stat_table)

    # ── 9. Signature block (flows naturally after stats — no forced page break) ──
    story.append(Spacer(1, 10 * mm))

    sig_content = [
        [Paragraph("Prepared by", S_PREP_LBL)],
        [Paragraph(data.name, S_PREP_NAME)],
        [Spacer(1, 8 * mm)],
        [HRFlowable(width=60 * mm, thickness=0.8, color=GREY_TEXT, spaceAfter=1 * mm)],
        [Paragraph("Signature", S_SIG_LBL)],
    ]
    sig_table = Table(sig_content, colWidths=[body_w])
    sig_table.setStyle(TableStyle([
        ("ALIGN",         (0, 0), (-1, -1), "RIGHT"),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 30 * mm),
        ("TOPPADDING",    (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
    ]))
    story.append(sig_table)

    # ── Build ─────────────────────────────────────────────────────────────
    doc.build(story, onFirstPage=_on_page, onLaterPages=_on_page)
    buffer.seek(0)
    return buffer.read()


# ── Endpoints ──────────────────────────────────────────────────────────────────

@router.post("/reports/monthly-tasks")
def generate_monthly_tasks(data: MonthlyTasksRequest):
    pdf_bytes = _build_pdf(data)
    filename  = f"monthly_report_{data.start_date}_to_{data.end_date}.pdf"
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f"inline; filename={filename}"},
    )


@router.get("/reports/closed-work-orders")
def get_closed_work_orders(
    technician_id: str = Query(...),
    start_date:    str = Query(...),
    end_date:      str = Query(...),
):
    try:
        resp = (
            supabase
            .from_("work_orders")
            .select("title, location, closed_at, work_order_assignments!inner(technician_id)")
            .eq("work_order_assignments.technician_id", technician_id)
            .gte("closed_at", start_date)
            .lte("closed_at", end_date)
            .order("closed_at", desc=True)
            .execute()
        )
        rows = resp.data or []
        return [
            {"title": r["title"], "location": r["location"], "closed_at": r["closed_at"]}
            for r in rows
        ]
    except Exception as e:
        return JSONResponse(status_code=500, content={"detail": str(e)})
