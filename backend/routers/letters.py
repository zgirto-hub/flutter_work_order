import os
import io
import re
import base64
from datetime import datetime
from fastapi import APIRouter, HTTPException, Response
from pydantic import BaseModel
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm, cm
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_RIGHT
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Table,
    TableStyle,
    Spacer,
    Image as RLImage,
)
from reportlab.lib.colors import HexColor

import arabic_reshaper
from bidi.algorithm import get_display

from db import supabase
from utils.activity import log_activity

_assets = os.path.join(os.path.dirname(__file__), "..", "assets")
try:
    pdfmetrics.registerFont(
        TTFont("NotoArabic", os.path.join(_assets, "NotoSansArabic-Regular.ttf"))
    )
    pdfmetrics.registerFont(
        TTFont("NotoArabic-Bold", os.path.join(_assets, "NotoSansArabic-Bold.ttf"))
    )
except Exception:
    pass

_ARABIC_RE = re.compile(
    r"[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]"
)


def _reshape(text: str) -> str:
    if not _ARABIC_RE.search(text):
        return text
    reshaped = arabic_reshaper.reshape(text)
    return get_display(reshaped)


class LetterBody(BaseModel):
    ishara: str
    tarikh: str
    alsayed: str
    almawdoo: str
    body_text: str
    alasm: str
    signature_base64: str | None = None
    created_by_email: str


def _build_letter_pdf(data: LetterBody) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=2 * cm,
        rightMargin=2 * cm,
        topMargin=1 * cm,
        bottomMargin=2.5 * cm,
    )

    styles = getSampleStyleSheet()
    header_style = ParagraphStyle(
        "Header",
        fontName="NotoArabic-Bold",
        fontSize=12,
        alignment=TA_CENTER,
    )
    subject_style = ParagraphStyle(
        "Subject",
        fontName="NotoArabic-Bold",
        fontSize=13,
        alignment=TA_CENTER,
        spaceAfter=12 * mm,
    )
    body_style = ParagraphStyle(
        "Body",
        fontName="NotoArabic",
        fontSize=12,
        alignment=TA_RIGHT,
        firstLineIndent=40,
        leading=20,
    )
    label_style = ParagraphStyle(
        "Label",
        fontName="NotoArabic",
        fontSize=11,
        alignment=TA_RIGHT,
    )
    footer_style = ParagraphStyle(
        "Footer",
        fontName="NotoArabic",
        fontSize=8,
        alignment=TA_CENTER,
    )

    flowables = []

    def load_image(filename):
        path = os.path.join(_assets, filename)
        if os.path.exists(path):
            return path
        return None

    emblem_path = load_image("logo_civilaviation.png")
    civil_path = load_image("logo_emblem.png")

    if emblem_path and civil_path:
        logo_table = Table(
            [
                [
                    RLImage(emblem_path, width=2.5 * cm, height=2.5 * cm),
                    RLImage(civil_path, width=2.5 * cm, height=2.5 * cm),
                ]
            ],
            colWidths=[8 * cm, 8 * cm],
        )
        logo_table.setStyle(
            TableStyle(
                [
                    ("ALIGN", (0, 0), (0, 0), "LEFT"),
                    ("ALIGN", (1, 0), (1, 0), "RIGHT"),
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                    ("BOX", (0, 0), (-1, -1), 0, "white"),
                ]
            )
        )
        flowables.append(logo_table)
        flowables.append(Spacer(1, 4 * mm))

    red_bar = Table([[""]], colWidths=[16 * cm], rowHeights=[3 * mm])
    red_bar.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), HexColor("#CC0000")),
            ]
        )
    )
    flowables.append(red_bar)

    formatted_date = ""
    try:
        d = datetime.strptime(data.tarikh, "%Y-%m-%d")
        formatted_date = d.strftime("%d/%m/%Y")
    except Exception:
        formatted_date = data.tarikh

    flowables.append(Paragraph(_reshape(f"الإشارة: {data.ishara}"), label_style))
    flowables.append(Paragraph(_reshape(f"التاريخ: {formatted_date}"), label_style))

    flowables.append(Paragraph(_reshape(f"السيد / {data.alsayed}"), label_style))

    subject_lines = data.almawdoo.split("\n")
    subject_text = "<br/>".join([_reshape(line) for line in subject_lines])
    flowables.append(Paragraph(f"<b>{subject_text}</b>", subject_style))

    body_lines = data.body_text.split("\n")
    body_text = "<br/>".join([_reshape(line) for line in body_lines])
    flowables.append(Paragraph(body_text, body_style))

    flowables.append(Paragraph(_reshape(data.alasm), label_style))

    if data.signature_base64:
        sig_data = data.signature_base64
        if sig_data.startswith("data:image"):
            sig_data = sig_data.split(",")[1]
        try:
            img_bytes = base64.b64decode(sig_data)
            sig_img = RLImage(io.BytesIO(img_bytes), width=3 * cm, height=1.5 * cm)
            flowables.append(sig_img)
        except Exception:
            pass

    flowables.append(Paragraph(_reshape("المرفقات:"), label_style))

    def _draw_footer(canvas, doc):
        canvas.saveState()
        canvas.setStrokeColor(HexColor("#CCCCCC"))
        canvas.setLineWidth(0.5)
        canvas.line(2 * cm, 2 * cm, A4[0] - 2 * cm, 2 * cm)
        footer_text = "E-mail: info@dgca.gov.kw | www.dgca.gov.kw | P.O.Box: 17 Safat, 13001 Kuwait | Tel: (+965) 2434-7171 | Fax: (+965) 2431-5504"
        canvas.drawCentredString(A4[0] / 2, 1.5 * cm, footer_text)
        canvas.restoreState()

    doc.build(flowables, onFirstPage=_draw_footer, onLaterPages=_draw_footer)
    return buffer.getvalue()


router = APIRouter(tags=["letters"])


@router.post("/letters/generate")
async def generate_letter(data: LetterBody):
    if not all(
        [
            data.ishara,
            data.tarikh,
            data.alsayed,
            data.almawdoo,
            data.body_text,
            data.alasm,
            data.created_by_email,
        ]
    ):
        raise HTTPException(status_code=400, detail="Missing required fields")

    pdf_bytes = _build_letter_pdf(data)

    insert_data = {
        "ishara": data.ishara,
        "tarikh": data.tarikh,
        "alsayed": data.alsayed,
        "almawdoo": data.almawdoo,
        "body_text": data.body_text,
        "alasm": data.alasm,
        "signature_base64": data.signature_base64,
        "created_by_email": data.created_by_email,
    }
    result = supabase.table("generated_letters").insert(insert_data).execute()
    letter_id = result.data[0]["id"] if result.data else ""

    log_activity(data.created_by_email, "created", "letter", letter_id)

    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="letter_{timestamp}.pdf"',
            "X-Letter-Id": str(letter_id),
        },
    )


@router.get("/letters")
async def get_letters(email: str = ""):
    if not email:
        raise HTTPException(status_code=400, detail="Email is required")

    result = (
        supabase.table("generated_letters")
        .select("*")
        .eq("created_by_email", email)
        .order("created_at", desc=True)
        .execute()
    )
    letters = result.data if result.data else []

    for letter in letters:
        certs_result = (
            supabase.table("payment_certificates")
            .select("id, certificate_number, subject")
            .eq("letter_id", letter["id"])
            .execute()
        )
        letter["payment_certificates"] = certs_result.data if certs_result.data else []

    return {"letters": letters}


@router.post("/letters/{letter_id}/regenerate")
async def regenerate_letter(letter_id: str):
    result = (
        supabase.table("generated_letters").select("*").eq("id", letter_id).execute()
    )
    if not result.data:
        raise HTTPException(status_code=404, detail="Letter not found")

    letter = result.data[0]
    data = LetterBody(
        ishara=letter["ishara"],
        tarikh=letter["tarikh"],
        alsayed=letter["alsayed"],
        almawdoo=letter["almawdoo"],
        body_text=letter["body_text"],
        alasm=letter["alasm"],
        signature_base64=letter.get("signature_base64"),
        created_by_email=letter["created_by_email"],
    )

    pdf_bytes = _build_letter_pdf(data)
    log_activity(letter["created_by_email"], "regenerated", "letter", letter_id)

    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="letter_{timestamp}.pdf"',
        },
    )


@router.patch("/payment-certificates/{cert_id}/link-letter")
async def link_certificate(cert_id: str, body: dict):
    letter_id = body.get("letter_id")
    if not letter_id:
        raise HTTPException(status_code=400, detail="letter_id is required")

    letter_result = (
        supabase.table("generated_letters").select("id").eq("id", letter_id).execute()
    )
    if not letter_result.data:
        raise HTTPException(status_code=404, detail="Letter not found")

    supabase.table("payment_certificates").update({"letter_id": letter_id}).eq(
        "id", cert_id
    ).execute()
    return {"status": "linked", "letter_id": letter_id}
