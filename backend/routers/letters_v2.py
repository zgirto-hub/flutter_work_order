"""
Letter Generator v2 — WeasyPrint HTML→PDF approach.
Renders a Jinja2 HTML template with the DGCA layout,
injects the rich HTML body from the WYSIWYG editor,
and converts to PDF via WeasyPrint.
"""

import os
import re
import base64
from datetime import datetime
from fastapi import APIRouter, HTTPException, Response
from pydantic import BaseModel
from jinja2 import Environment, FileSystemLoader

from db import supabase
from utils.activity import log_activity

router = APIRouter(tags=["letters_v2"])

_assets = os.path.join(os.path.dirname(__file__), "..", "assets")
_templates = os.path.join(os.path.dirname(__file__), "..", "templates")

# Jinja2 template engine
_jinja = Environment(loader=FileSystemLoader(_templates), autoescape=False)


def _logo_data_uri(filename: str) -> str:
    """Convert a local logo file to a base64 data URI for embedding in HTML."""
    path = os.path.join(_assets, filename)
    if not os.path.exists(path):
        return ""
    with open(path, "rb") as f:
        data = base64.b64encode(f.read()).decode()
    return f"data:image/png;base64,{data}"


def _sanitize_editor_html(html: str) -> str:
    """Clean up editor HTML for WeasyPrint compatibility.
    - Convert <font color="X"> to <span style="color: X">
    - Strip font-family from inline styles (let CSS handle it)
    """
    # Convert <font color="#cc0000">...</font> to <span style="color:#cc0000">...</span>
    html = re.sub(
        r'<font\s+color="([^"]*)"[^>]*>',
        r'<span style="color: \1;">',
        html,
        flags=re.IGNORECASE,
    )
    html = html.replace("</font>", "</span>")

    # Strip font-family from inline styles so our CSS Calibri takes over
    html = re.sub(r'font-family:\s*[^;"]+;?\s*', '', html)

    return html


def _font_data_uri(filename: str) -> str:
    """Convert a local font file to a base64 data URI for embedding in CSS."""
    path = os.path.join(_assets, filename)
    if not os.path.exists(path):
        return ""
    with open(path, "rb") as f:
        data = base64.b64encode(f.read()).decode()
    return f"data:font/truetype;base64,{data}"


class AttachmentItem(BaseModel):
    name: str
    data: str  # base64-encoded file content
    is_image: bool = False


class LetterBodyV2(BaseModel):
    ishara: str
    tarikh: str = ""  # DD/MM/YYYY date string
    alsayed: str
    almawdoo: str
    body_html: str  # Rich HTML from WYSIWYG editor
    alasm: str
    signature_base64: str | None = None
    reply_required: bool = False
    cc_list: str | None = None
    ref_font_size: float = 11
    ref_bold: bool = False
    recipient_font_size: float = 12
    recipient_bold: bool = False
    created_by_email: str
    attachments: list[AttachmentItem] = []


_uploads = os.path.join(os.path.dirname(__file__), "..", "uploaded_files", "letters")
os.makedirs(_uploads, exist_ok=True)


def _save_attachments(attachments: list[AttachmentItem], letter_id: str) -> list[dict]:
    """Save attachment files to server filesystem, return metadata list."""
    saved = []
    for att in attachments:
        file_bytes = base64.b64decode(att.data)
        safe_name = f"{letter_id}_{att.name}"
        file_path = os.path.join(_uploads, safe_name)
        with open(file_path, "wb") as f:
            f.write(file_bytes)
        saved.append({
            "name": att.name,
            "path": f"/files/letters/{safe_name}",
            "is_image": att.is_image,
        })
    return saved


def _build_letter_pdf_v2(data: LetterBodyV2) -> bytes:
    """Render HTML template with data, then convert to PDF via WeasyPrint."""
    # Lazy import — WeasyPrint pulls in Cairo/Pango at import time
    from weasyprint import HTML
    from weasyprint.text.fonts import FontConfiguration

    template = _jinja.get_template("letter_template.html")

    # Prepare signature image as data URI
    sig_img = None
    if data.signature_base64:
        sig = data.signature_base64
        if not sig.startswith("data:"):
            sig = f"data:image/png;base64,{sig}"
        sig_img = sig

    html_str = template.render(
        ishara=data.ishara,
        tarikh=data.tarikh,
        alsayed=data.alsayed,
        almawdoo=data.almawdoo,
        body_html=_sanitize_editor_html(data.body_html),
        alasm=data.alasm,
        signature_img=sig_img,
        reply_required=data.reply_required,
        cc_list=data.cc_list or "",
        logo_civil_aviation=_logo_data_uri("logo_civilaviation.png"),
        logo_emblem=_logo_data_uri("logo_emblem.png"),
        logo_newkuwait=_logo_data_uri("logo_newkuwait.png"),
        font_regular=_font_data_uri("calibri.ttf"),
        font_bold=_font_data_uri("calibrib.ttf"),
        ref_font_size=data.ref_font_size,
        ref_bold=data.ref_bold,
        recipient_font_size=data.recipient_font_size,
        recipient_bold=data.recipient_bold,
    )

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=html_str).write_pdf(font_config=font_config)
    return pdf_bytes


# ── Endpoints ────────────────────────────────────────────────────────────────


@router.post("/letters-v2/preview-html")
async def preview_letter_html(data: LetterBodyV2):
    """Debug: return the rendered HTML (before PDF conversion) for inspection."""
    from weasyprint.text.fonts import FontConfiguration

    template = _jinja.get_template("letter_template.html")
    sig_img = None
    if data.signature_base64:
        sig = data.signature_base64
        if not sig.startswith("data:"):
            sig = f"data:image/png;base64,{sig}"
        sig_img = sig

    html_str = template.render(
        ishara=data.ishara,
        tarikh=data.tarikh,
        alsayed=data.alsayed,
        almawdoo=data.almawdoo,
        body_html=_sanitize_editor_html(data.body_html),
        alasm=data.alasm,
        signature_img=sig_img,
        reply_required=data.reply_required,
        cc_list=data.cc_list or "",
        logo_civil_aviation=_logo_data_uri("logo_civilaviation.png"),
        logo_emblem=_logo_data_uri("logo_emblem.png"),
        logo_newkuwait=_logo_data_uri("logo_newkuwait.png"),
        font_regular=_font_data_uri("calibri.ttf"),
        font_bold=_font_data_uri("calibrib.ttf"),
        ref_font_size=data.ref_font_size,
        ref_bold=data.ref_bold,
        recipient_font_size=data.recipient_font_size,
        recipient_bold=data.recipient_bold,
    )
    return Response(content=html_str, media_type="text/html")


@router.post("/letters-v2/generate")
async def generate_letter_v2(data: LetterBodyV2):
    """Generate a PDF letter and save the record to Supabase."""
    if not all([data.ishara, data.alsayed, data.almawdoo, data.body_html, data.alasm]):
        raise HTTPException(400, "Missing required fields")

    # Debug: log the body HTML to see what the editor sends
    print(f"[LETTER-V2] body_html snippet: {data.body_html[:500]}")

    pdf_bytes = _build_letter_pdf_v2(data)

    # Save letter record to Supabase
    record = {
        "ishara": data.ishara,
        "tarikh": datetime.utcnow().strftime("%Y-%m-%d"),
        "alsayed": data.alsayed,
        "almawdoo": data.almawdoo,
        "body_text": data.body_html,
        "alasm": data.alasm,
        "signature_base64": data.signature_base64,
        "reply_required": data.reply_required,
        "cc_list": data.cc_list,
        "created_by_email": data.created_by_email,
    }
    result = supabase.table("generated_letters").insert(record).execute()
    letter_id = result.data[0]["id"] if result.data else ""

    # Save attachments to server filesystem
    if data.attachments:
        att_meta = _save_attachments(data.attachments, str(letter_id))
        supabase.table("generated_letters").update(
            {"attachments": att_meta}
        ).eq("id", letter_id).execute()

    log_activity(data.created_by_email, "created", "letter", str(letter_id))

    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="letter_{ts}.pdf"',
            "X-Letter-Id": str(letter_id),
        },
    )


@router.get("/letters-v2")
async def get_letters_v2(email: str):
    """Fetch letter history for a user."""
    result = (
        supabase.table("generated_letters")
        .select("*")
        .eq("created_by_email", email)
        .order("created_at", desc=True)
        .execute()
    )
    letters = result.data or []

    # Attach linked payment certificates to each letter
    for letter in letters:
        certs = (
            supabase.table("payment_certificates")
            .select("id, certificate_number, subject")
            .eq("letter_id", letter["id"])
            .execute()
        )
        letter["payment_certificates"] = certs.data or []

    return {"letters": letters}


@router.put("/letters-v2/{letter_id}")
async def update_letter_v2(letter_id: str, data: LetterBodyV2):
    """Update an existing letter record and regenerate its PDF."""
    result = (
        supabase.table("generated_letters")
        .select("id")
        .eq("id", letter_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(404, "Letter not found")

    update_data = {
        "ishara": data.ishara,
        "alsayed": data.alsayed,
        "almawdoo": data.almawdoo,
        "body_text": data.body_html,
        "alasm": data.alasm,
        "signature_base64": data.signature_base64,
        "reply_required": data.reply_required,
        "cc_list": data.cc_list,
    }
    supabase.table("generated_letters").update(update_data).eq("id", letter_id).execute()

    pdf_bytes = _build_letter_pdf_v2(data)
    log_activity(data.created_by_email, "updated", "letter", letter_id)

    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="letter_{ts}.pdf"',
            "X-Letter-Id": letter_id,
        },
    )


@router.post("/letters-v2/{letter_id}/regenerate")
async def regenerate_letter_v2(letter_id: str):
    """Regenerate a PDF from a saved letter record."""
    result = (
        supabase.table("generated_letters")
        .select("*")
        .eq("id", letter_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(404, "Letter not found")

    rec = result.data[0]
    body = LetterBodyV2(
        ishara=rec["ishara"],
        alsayed=rec["alsayed"],
        almawdoo=rec["almawdoo"],
        body_html=rec.get("body_text", ""),
        alasm=rec["alasm"],
        signature_base64=rec.get("signature_base64"),
        reply_required=rec.get("reply_required", False),
        cc_list=rec.get("cc_list"),
        created_by_email=rec["created_by_email"],
    )

    pdf_bytes = _build_letter_pdf_v2(body)
    log_activity(rec["created_by_email"], "regenerated", "letter", letter_id)

    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="letter_{ts}.pdf"',
        },
    )
