"""
Letter Generator v2 — WeasyPrint HTML→PDF approach.
Renders a Jinja2 HTML template with the DGCA layout,
injects the rich HTML body from the WYSIWYG editor,
and converts to PDF via WeasyPrint.
"""

import os
import re
import base64
import io
import json
import uuid
from datetime import datetime
from fastapi import APIRouter, HTTPException, Response, Form, File, UploadFile
from pydantic import BaseModel
from jinja2 import Environment, FileSystemLoader
import PyPDF2 as pypdf
from PIL import Image

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
    html = re.sub(r'font-family:\s*[^;"]+;?\s*', "", html)

    return html


def _font_data_uri(filename: str) -> str:
    """Convert a local font file to a base64 data URI for embedding in CSS."""
    path = os.path.join(_assets, filename)
    if not os.path.exists(path):
        return ""
    with open(path, "rb") as f:
        data = base64.b64encode(f.read()).decode()
    return f"data:font/truetype;base64,{data}"


def _generate_barcode_data_uri(value: str) -> str | None:
    """Generate a Code 39 barcode as a base64 PNG data URI."""
    if not value or not value.strip():
        return None
    try:
        from barcode import Code39
        from barcode.writer import ImageWriter

        buffer = io.BytesIO()
        # Code 39 is case-insensitive and typically uppercase; normalize
        # to uppercase so digits + dash encode cleanly.
        Code39(value.upper(), writer=ImageWriter(), add_checksum=False).write(
            buffer,
            options={
                "module_height": 6.0,
                "module_width": 0.3,
                "font_size": 10,
                "text_distance": 4.0,
                "quiet_zone": 2.0,
                "write_text": True,
            },
        )
        return f"data:image/png;base64,{base64.b64encode(buffer.getvalue()).decode('ascii')}"
    except Exception:
        return None


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
    signer_title: str = ""
    alasm: str
    signature_base64: str | None = None
    reply_required: bool = False
    cc_list: str | None = None
    ref_font_size: float = 11
    ref_bold: bool = False
    ref_underline: bool = False
    tarikh_font_size: float = 11
    tarikh_bold: bool = False
    tarikh_underline: bool = False
    recipient_font_size: float = 12
    recipient_bold: bool = False
    recipient_underline: bool = False
    subject_font_size: float = 13
    subject_bold: bool = True
    subject_underline: bool = True
    created_by_email: str
    attachments: list[AttachmentItem] = []
    payment_certificate_ids: list[str] = []
    force_reassign: bool = False


def _coalesce_letter_format(row: dict) -> dict:
    """Return a dict containing the 12 formatting keys with NULL → defaults applied."""
    return {
        "ref_font_size": row.get("ref_font_size")
        if row.get("ref_font_size") is not None
        else 11,
        "ref_bold": row.get("ref_bold") if row.get("ref_bold") is not None else False,
        "ref_underline": row.get("ref_underline")
        if row.get("ref_underline") is not None
        else False,
        "tarikh_font_size": row.get("tarikh_font_size")
        if row.get("tarikh_font_size") is not None
        else 11,
        "tarikh_bold": row.get("tarikh_bold")
        if row.get("tarikh_bold") is not None
        else False,
        "tarikh_underline": row.get("tarikh_underline")
        if row.get("tarikh_underline") is not None
        else False,
        "recipient_font_size": row.get("recipient_font_size")
        if row.get("recipient_font_size") is not None
        else 12,
        "recipient_bold": row.get("recipient_bold")
        if row.get("recipient_bold") is not None
        else False,
        "recipient_underline": row.get("recipient_underline")
        if row.get("recipient_underline") is not None
        else False,
        "subject_font_size": row.get("subject_font_size")
        if row.get("subject_font_size") is not None
        else 13,
        "subject_bold": row.get("subject_bold")
        if row.get("subject_bold") is not None
        else True,
        "subject_underline": row.get("subject_underline")
        if row.get("subject_underline") is not None
        else True,
    }


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
        saved.append(
            {
                "name": att.name,
                "path": f"/files/letters/{safe_name}",
                "is_image": att.is_image,
            }
        )
    return saved


@router.post("/letters-v2/upload-image")
async def upload_letter_image(file: UploadFile = File(...)) -> dict:
    """Upload an image for inline use in the letter editor."""
    ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "gif", "webp"}
    MAX_SIZE = 5 * 1024 * 1024  # 5MB

    ext = file.filename.rsplit(".", 1)[-1].lower() if file.filename else ""
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Unsupported file format. Accepted: png, jpg, jpeg, gif, webp")

    file_bytes = await file.read()
    if len(file_bytes) > MAX_SIZE:
        raise HTTPException(status_code=400, detail="File size exceeds 5MB limit")

    try:
        img = Image.open(io.BytesIO(file_bytes))
        if img.width > 1920:
            ratio = 1920 / img.width
            new_height = int(img.height * ratio)
            img = img.resize((1920, new_height), Image.LANCZOS)

        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        uuid8 = uuid.uuid4().hex[:8]
        filename = f"letter_img_{timestamp}_{uuid8}.{ext}"
        save_path = os.path.join(_uploads, filename)

        buf = io.BytesIO()
        if ext in ("jpg", "jpeg"):
            img.save(buf, format="JPEG", quality=80)
        elif ext == "webp":
            img.save(buf, format="WebP", quality=80)
        elif ext == "gif":
            img.save(buf, format="GIF")
        else:
            img.save(buf, format="PNG")

        with open(save_path, "wb") as f:
            f.write(buf.getvalue())

        log_activity("system", "uploaded_image", "letter", filename)
        return {"status": "success", "url": f"/files/letters/{filename}"}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=500, detail="Failed to process image")


def _convert_body_images_to_data_uris(html: str) -> str:
    """Replace /files/letters/... image URLs with base64 data URIs for PDF rendering."""
    import mimetypes

    def _replace_img_src(match):
        rel_path = match.group(1)
        fs_rel = rel_path.lstrip("/").replace("files/", "", 1)
        abs_path = os.path.realpath(
            os.path.join(
                os.path.dirname(__file__), "..", "uploaded_files", fs_rel
            )
        )
        allowed_dir = os.path.realpath(
            os.path.join(os.path.dirname(__file__), "..", "uploaded_files")
        )
        if not abs_path.startswith(allowed_dir + os.sep):
            return match.group(0)  # reject path traversal
        if not os.path.exists(abs_path):
            return match.group(0)
        mime, _ = mimetypes.guess_type(abs_path)
        if not mime:
            mime = "image/png"
        with open(abs_path, "rb") as f:
            data = base64.b64encode(f.read()).decode()
        return f'src="data:{mime};base64,{data}"'

    return re.sub(
        r'src="(?:https?://[^/]+)?(/files/letters/[^"]+)"',
        _replace_img_src,
        html,
    )


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
        barcode_data_uri=_generate_barcode_data_uri(data.ishara),
        tarikh=data.tarikh,
        alsayed=data.alsayed,
        almawdoo=data.almawdoo,
        body_html=_convert_body_images_to_data_uris(_sanitize_editor_html(data.body_html)),
        signer_title=data.signer_title,
        alasm=data.alasm,
        signature_img=sig_img,
        reply_required=data.reply_required,
        cc_list=data.cc_list or "",
        cc_names=[n.strip() for n in (data.cc_list or "").split("\n") if n.strip()],
        logo_civil_aviation=_logo_data_uri("logo_civilaviation.png"),
        logo_emblem=_logo_data_uri("logo_emblem.png"),
        logo_newkuwait=_logo_data_uri("logo_newkuwait.png"),
        font_regular=_font_data_uri("calibri.ttf"),
        font_bold=_font_data_uri("calibrib.ttf"),
        ref_font_size=data.ref_font_size,
        ref_bold=data.ref_bold,
        ref_underline=data.ref_underline,
        tarikh_font_size=data.tarikh_font_size,
        tarikh_bold=data.tarikh_bold,
        tarikh_underline=data.tarikh_underline,
        recipient_font_size=data.recipient_font_size,
        recipient_bold=data.recipient_bold,
        recipient_underline=data.recipient_underline,
        subject_font_size=data.subject_font_size,
        subject_bold=data.subject_bold,
        subject_underline=data.subject_underline,
    )

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=html_str).write_pdf(font_config=font_config)
    return pdf_bytes


def _apply_cert_links(
    letter_id: str, cert_ids: list[str], force_reassign: bool
) -> list[dict]:
    """Apply payment certificate links to a letter.

    If cert_ids is empty, any currently linked certificates are unlinked.
    """
    previously_linked = (
        supabase.table("payment_certificates")
        .select("id")
        .eq("letter_id", letter_id)
        .execute()
        .data
        or []
    )

    conflicts = []
    for cid in cert_ids:
        cert = (
            supabase.table("payment_certificates")
            .select("id, letter_id")
            .eq("id", cid)
            .execute()
            .data
        )
        if not cert:
            raise HTTPException(404, f"payment_certificate {cid} not found")
        if (
            cert[0].get("letter_id")
            and cert[0]["letter_id"] != letter_id
            and not force_reassign
        ):
            conflicts.append(
                {"certificate_id": cid, "existing_letter_id": cert[0]["letter_id"]}
            )

    if conflicts:
        raise HTTPException(
            status_code=409,
            detail={"error": "certificates_already_linked", "conflicts": conflicts},
        )

    for prev in previously_linked:
        if prev["id"] not in cert_ids:
            supabase.table("payment_certificates").update(
                {"letter_id": None, "letter_link_order": None}
            ).eq("id", prev["id"]).execute()

    final_certs = []
    for idx, cid in enumerate(cert_ids):
        supabase.table("payment_certificates").update(
            {"letter_id": letter_id, "letter_link_order": idx}
        ).eq("id", cid).execute()
        cert = (
            supabase.table("payment_certificates")
            .select("id, certificate_number, subject, letter_link_order")
            .eq("id", cid)
            .execute()
            .data[0]
        )
        final_certs.append(cert)

    return final_certs


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
        barcode_data_uri=_generate_barcode_data_uri(data.ishara),
        tarikh=data.tarikh,
        alsayed=data.alsayed,
        almawdoo=data.almawdoo,
        body_html=_convert_body_images_to_data_uris(_sanitize_editor_html(data.body_html)),
        signer_title=data.signer_title,
        alasm=data.alasm,
        signature_img=sig_img,
        reply_required=data.reply_required,
        cc_list=data.cc_list or "",
        cc_names=[n.strip() for n in (data.cc_list or "").split("\n") if n.strip()],
        logo_civil_aviation=_logo_data_uri("logo_civilaviation.png"),
        logo_emblem=_logo_data_uri("logo_emblem.png"),
        logo_newkuwait=_logo_data_uri("logo_newkuwait.png"),
        font_regular=_font_data_uri("calibri.ttf"),
        font_bold=_font_data_uri("calibrib.ttf"),
        ref_font_size=data.ref_font_size,
        ref_bold=data.ref_bold,
        ref_underline=data.ref_underline,
        tarikh_font_size=data.tarikh_font_size,
        tarikh_bold=data.tarikh_bold,
        tarikh_underline=data.tarikh_underline,
        recipient_font_size=data.recipient_font_size,
        recipient_bold=data.recipient_bold,
        recipient_underline=data.recipient_underline,
        subject_font_size=data.subject_font_size,
        subject_bold=data.subject_bold,
        subject_underline=data.subject_underline,
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
        "tarikh": data.tarikh
        if data.tarikh
        else datetime.utcnow().strftime("%Y-%m-%d"),
        "alsayed": data.alsayed,
        "almawdoo": data.almawdoo,
        "body_text": data.body_html,
        "signer_title": data.signer_title,
        "alasm": data.alasm,
        "signature_base64": data.signature_base64,
        "reply_required": data.reply_required,
        "cc_list": data.cc_list,
        "created_by_email": data.created_by_email,
        "ref_font_size": data.ref_font_size,
        "ref_bold": data.ref_bold,
        "ref_underline": data.ref_underline,
        "tarikh_font_size": data.tarikh_font_size,
        "tarikh_bold": data.tarikh_bold,
        "tarikh_underline": data.tarikh_underline,
        "recipient_font_size": data.recipient_font_size,
        "recipient_bold": data.recipient_bold,
        "recipient_underline": data.recipient_underline,
        "subject_font_size": data.subject_font_size,
        "subject_bold": data.subject_bold,
        "subject_underline": data.subject_underline,
    }
    result = supabase.table("generated_letters").insert(record).execute()
    letter_id = result.data[0]["id"] if result.data else ""

    # Apply payment certificate links
    if data.payment_certificate_ids:
        _apply_cert_links(
            str(letter_id), data.payment_certificate_ids, data.force_reassign
        )

    # Save attachments to server filesystem
    if data.attachments:
        att_meta = _save_attachments(data.attachments, str(letter_id))
        supabase.table("generated_letters").update({"attachments": att_meta}).eq(
            "id", letter_id
        ).execute()

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
    # Select only the columns needed for the list view (exclude heavy body_text, signature_base64)
    result = (
        supabase.table("generated_letters")
        .select(
            "id, created_at, ishara, tarikh, alsayed, almawdoo, alasm, signer_title,"
            " reply_required, cc_list, created_by_email, body_text,"
            " ref_font_size, ref_bold, ref_underline,"
            " tarikh_font_size, tarikh_bold, tarikh_underline,"
            " recipient_font_size, recipient_bold, recipient_underline,"
            " subject_font_size, subject_bold, subject_underline"
        )
        .eq("created_by_email", email)
        .order("created_at", desc=True)
        .execute()
    )
    letters = result.data or []

    # Build a plain-text preview from body_text (strip HTML, truncate to 300 chars)
    for letter in letters:
        raw = letter.pop("body_text", "") or ""
        plain = re.sub(r"<[^>]*>", "", raw).replace("&nbsp;", " ").replace("&amp;", "&").strip()
        letter["body_preview"] = plain[:300]

    if letters:
        # Batch-fetch all payment certificates for these letters in one query
        letter_ids = [l["id"] for l in letters]
        certs_result = (
            supabase.table("payment_certificates")
            .select("id, certificate_number, subject, letter_link_order, letter_id")
            .in_("letter_id", letter_ids)
            .order("letter_link_order")
            .execute()
        )
        # Group certs by letter_id
        certs_by_letter = {}
        for cert in (certs_result.data or []):
            lid = cert.pop("letter_id", None)
            if lid:
                certs_by_letter.setdefault(lid, []).append(cert)

        for letter in letters:
            letter["payment_certificates"] = certs_by_letter.get(letter["id"], [])
            letter.update(_coalesce_letter_format(letter))

    return {"letters": letters}


@router.get("/letters-v2/{letter_id}")
async def get_letter_v2(letter_id: str):
    """Fetch a single letter with all fields (including body_text)."""
    result = (
        supabase.table("generated_letters")
        .select("*")
        .eq("id", letter_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(404, "Letter not found")

    letter = result.data[0]
    certs = (
        supabase.table("payment_certificates")
        .select("id, certificate_number, subject, letter_link_order")
        .eq("letter_id", letter_id)
        .order("letter_link_order")
        .execute()
    )
    letter["payment_certificates"] = certs.data or []
    letter.update(_coalesce_letter_format(letter))
    return letter


@router.put("/letters-v2/{letter_id}")
async def update_letter_v2(letter_id: str, data: LetterBodyV2):
    """Update an existing letter record and regenerate its PDF."""
    result = (
        supabase.table("generated_letters").select("id").eq("id", letter_id).execute()
    )
    if not result.data:
        raise HTTPException(404, "Letter not found")

    update_data = {
        "ishara": data.ishara,
        "tarikh": data.tarikh
        if data.tarikh
        else datetime.utcnow().strftime("%Y-%m-%d"),
        "alsayed": data.alsayed,
        "almawdoo": data.almawdoo,
        "body_text": data.body_html,
        "signer_title": data.signer_title,
        "alasm": data.alasm,
        "signature_base64": data.signature_base64,
        "reply_required": data.reply_required,
        "cc_list": data.cc_list,
        "ref_font_size": data.ref_font_size,
        "ref_bold": data.ref_bold,
        "ref_underline": data.ref_underline,
        "tarikh_font_size": data.tarikh_font_size,
        "tarikh_bold": data.tarikh_bold,
        "tarikh_underline": data.tarikh_underline,
        "recipient_font_size": data.recipient_font_size,
        "recipient_bold": data.recipient_bold,
        "recipient_underline": data.recipient_underline,
        "subject_font_size": data.subject_font_size,
        "subject_bold": data.subject_bold,
        "subject_underline": data.subject_underline,
    }
    supabase.table("generated_letters").update(update_data).eq(
        "id", letter_id
    ).execute()

    # Apply payment certificate links (empty list clears any existing links)
    _apply_cert_links(letter_id, data.payment_certificate_ids, data.force_reassign)

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


@router.delete("/letters-v2/{letter_id}")
async def delete_letter_v2(letter_id: str):
    """Delete a letter record."""
    result = (
        supabase.table("generated_letters")
        .select("id, created_by_email")
        .eq("id", letter_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(404, "Letter not found")

    # Unlink any payment certificates
    supabase.table("payment_certificates").update(
        {"letter_id": None, "letter_link_order": None}
    ).eq("letter_id", letter_id).execute()
    # Delete the letter
    supabase.table("generated_letters").delete().eq("id", letter_id).execute()

    log_activity(result.data[0]["created_by_email"], "deleted", "letter", letter_id)
    return {"status": "deleted", "id": letter_id}


@router.post("/letters-v2/{letter_id}/regenerate")
async def regenerate_letter_v2(letter_id: str):
    """Regenerate a PDF from a saved letter record."""
    result = (
        supabase.table("generated_letters").select("*").eq("id", letter_id).execute()
    )
    if not result.data:
        raise HTTPException(404, "Letter not found")

    rec = result.data[0]
    fmt = _coalesce_letter_format(rec)
    body = LetterBodyV2(
        ishara=rec["ishara"],
        tarikh=rec.get("tarikh", ""),
        alsayed=rec["alsayed"],
        almawdoo=rec["almawdoo"],
        body_html=rec.get("body_text", ""),
        signer_title=rec.get("signer_title", ""),
        alasm=rec["alasm"],
        signature_base64=rec.get("signature_base64"),
        reply_required=rec.get("reply_required", False),
        cc_list=rec.get("cc_list"),
        created_by_email=rec["created_by_email"],
        **fmt,
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


@router.post("/letters-v2/{letter_id}/export-with-attachments")
async def export_with_attachments(
    letter_id: str,
    letter_body: str = Form(...),
    order: str = Form(...),
    requester_email: str = Form(...),
    files: list[UploadFile] = File(default=[]),
):
    """Export a letter with attached payment certificates as a merged PDF."""
    result = (
        supabase.table("generated_letters")
        .select("id, created_by_email")
        .eq("id", letter_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(404, "Letter not found")

    rec = result.data[0]
    user_result = (
        supabase.table("users")
        .select("user_type")
        .eq("email", requester_email)
        .execute()
    )
    is_admin = user_result.data and user_result.data[0].get("user_type") == "admin"
    if rec["created_by_email"] != requester_email and not is_admin:
        raise HTTPException(403, "Not authorized to export this letter")

    body = LetterBodyV2(**json.loads(letter_body))
    cert_order = json.loads(order)

    letter_pdf = _build_letter_pdf_v2(body)

    writer = pypdf.PdfWriter()
    writer.append(pypdf.PdfReader(io.BytesIO(letter_pdf)))

    file_map = {}
    for f in files:
        file_map[f.filename] = await f.read()

    for cid in cert_order:
        if cid not in file_map:
            raise HTTPException(
                status_code=422,
                detail={"error": "missing_cert_upload", "certificate_id": cid},
            )
        writer.append(pypdf.PdfReader(io.BytesIO(file_map[cid])))

    output = io.BytesIO()
    writer.write(output)
    merged_bytes = output.getvalue()

    log_activity(requester_email, "exported", "letter", letter_id)

    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    return Response(
        content=merged_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="letter_{ts}.pdf"'},
    )
