# Quickstart: Editor Image Insertion

**Feature**: 034-editor-image-insert  
**Branch**: `034-editor-image-insert`

## What This Feature Does

Adds an "Insert Image" button to the letter body WYSIWYG editor toolbar. Users can upload images (PNG, JPG, GIF, WebP) that appear inline in the letter body and are included in the generated PDF.

## Files to Modify

### Backend (Python/FastAPI)

| File | Change |
|------|--------|
| `backend/routers/letters_v2.py` | Add `POST /letters-v2/upload-image` endpoint; add `_convert_images_to_data_uris()` helper for PDF generation; update `_sanitize_editor_html()` or `_build_letter_pdf_v2()` to convert image URLs to data URIs |

### Frontend (Dart/Flutter)

| File | Change |
|------|--------|
| `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart` | Add `INSERT_IMAGE_REQUEST` handler in `_listenForMessages()`; add `_uploadImage()` method; add image toolbar button in `_editorHtml` JS/HTML; add JS handler for `INSERT_IMAGE` and `INSERT_IMAGE_ERROR` messages |
| `frontend/lib/services/letter_service.dart` | Add `uploadImage(Uint8List bytes, String filename)` method for multipart upload |

### No Changes Needed

- No database migration (images stored on filesystem, referenced in existing `body_text` HTML column)
- No new Flutter packages (FilePicker and http already available)
- No new Python packages (Pillow already in requirements.txt)

## Architecture Overview

```
User clicks "Insert Image" button in editor toolbar
    │
    ▼
Iframe JS → postMessage('INSERT_IMAGE_REQUEST') → Flutter parent
    │
    ▼
Flutter opens FilePicker (PNG/JPG/GIF/WebP, max 5MB client check)
    │
    ▼
Flutter uploads via multipart POST → /api/letters-v2/upload-image
    │
    ▼
Backend: validate → resize if >1920px → compress 80% → save to uploaded_files/letters/
    │
    ▼
Backend returns { url: "/files/letters/letter_img_..." }
    │
    ▼
Flutter → postMessage('INSERT_IMAGE:/files/letters/...') → Iframe
    │
    ▼
Iframe JS inserts <img src="..." style="max-width:100%"> at cursor
    │
    ▼
On PDF generation: backend converts /files/letters/ URLs → base64 data URIs → WeasyPrint
```

## Key Design Decisions

1. **Separate from attachments** — inline images are independent from "Add Attachment" feature
2. **Filesystem storage** — no DB records for images (per constitution: Server-First File Storage)
3. **Data URI conversion for PDF** — matches existing pattern for logos/signatures/barcodes
4. **PostMessage protocol** — extends existing iframe↔Flutter communication with 3 new message types
5. **Client + server validation** — defense-in-depth for file size and format checks
