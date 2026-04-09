# Research: Editor Image Insertion

**Feature**: 034-editor-image-insert  
**Date**: 2026-04-08

## Decision 1: Image Upload Flow (Iframe → Flutter → Backend)

**Decision**: Use a two-hop postMessage pattern: iframe toolbar button sends `INSERT_IMAGE_REQUEST` to Flutter parent, Flutter opens FilePicker, validates, uploads to backend via multipart POST, receives URL, sends `INSERT_IMAGE:{url}` back to iframe which inserts `<img>` via `execCommand('insertHTML')`.

**Rationale**: 
- FilePicker is already used for attachments in the same file (`_pickAttachments` uses `FilePicker.platform.pickFiles`)
- Client-side validation (size, format) is cleanest in Flutter before uploading
- Avoids passing large base64 strings through postMessage (which has performance limits)
- Consistent with existing Flutter-first file handling pattern

**Alternatives considered**:
- Iframe-native `<input type="file">` with base64 postMessage to Flutter → rejected due to large postMessage payload and inability to leverage Flutter's FilePicker with format filtering
- Direct iframe-to-backend upload via fetch() → rejected because iframe is sandboxed via srcdoc and lacks backend URL context

## Decision 2: WeasyPrint Image Resolution

**Decision**: Convert `/files/letters/` image URLs to base64 data URIs in the backend before passing HTML to WeasyPrint, matching the existing pattern used for logos, signatures, and barcodes.

**Rationale**:
- Current `_build_letter_pdf_v2` passes `HTML(string=html_str)` with no `base_url` — all images are already data URIs
- Logos use `_logo_data_uri()`, signatures use base64, barcodes use data URIs
- Converting inline image URLs to data URIs keeps the pattern consistent and avoids requiring WeasyPrint to reach the server via HTTP
- Simple: read file from `uploaded_files/letters/`, encode to base64, replace `src` in HTML

**Alternatives considered**:
- Pass `base_url` to WeasyPrint `HTML()` constructor → rejected because it would require the server to be HTTP-reachable from itself (localhost may not be configured), and breaks the established data URI pattern
- Store images as base64 in the database → rejected per constitution (Server-First File Storage)

## Decision 3: Backend Upload Endpoint Design

**Decision**: Create a new dedicated endpoint `POST /api/letters-v2/upload-image` that accepts a multipart file upload, validates format and size, resizes/compresses with Pillow, saves to `uploaded_files/letters/`, and returns the file URL.

**Rationale**:
- Existing `/api/upload` endpoint in files.py is designed for the file management system (requires title, file_type, folder_id, creates DB record in `files` table) — too heavy for inline editor images
- Existing `_save_attachments` is a private function that takes base64 input (not multipart) and is tied to letter generation flow
- A lightweight endpoint on the letters_v2 router keeps the feature self-contained
- Pillow (v12.1.1) is already in requirements.txt

**Alternatives considered**:
- Extend existing `/api/upload` endpoint with optional parameters → rejected because it would add complexity to an unrelated feature and create unnecessary DB records
- Reuse `_save_attachments` → rejected because it takes base64 input (not multipart) and doesn't do image processing

## Decision 4: Image Filename Pattern

**Decision**: Use `letter_img_{timestamp}_{uuid4_short}.{ext}` where timestamp is `YYYYMMDDHHMMSS` and uuid4_short is first 8 chars of a UUID4.

**Rationale**:
- Timestamp prefix enables chronological sorting and debugging
- UUID suffix prevents collisions even with concurrent uploads
- `letter_img_` prefix clearly identifies these files vs attachment files (which use `{letter_id}_{filename}`)
- Short enough to be readable in file listings

**Alternatives considered**:
- Full UUID only → rejected because it lacks temporal ordering for debugging
- Include letter_id in filename → rejected because image is uploaded before the letter is saved (no letter_id yet during creation)

## Decision 5: PostMessage Protocol Extension

**Decision**: Add three new message types to the iframe↔Flutter postMessage protocol:

| Direction | Message | Purpose |
|-----------|---------|---------|
| Iframe → Flutter | `INSERT_IMAGE_REQUEST` | User clicked image button, requesting file picker |
| Flutter → Iframe | `INSERT_IMAGE:{url}` | Upload succeeded, insert image at cursor |
| Flutter → Iframe | `INSERT_IMAGE_ERROR:{msg}` | Upload failed, show error in editor |

**Rationale**:
- Follows existing naming convention (`EDITOR_READY`, `EDITOR_HTML`, `SET_HTML`, `GET_HTML`)
- Colon-delimited payload matches `EDITOR_HTML:` and `SET_HTML:` patterns
- Error message type allows the iframe to show inline feedback without Flutter UI

**Alternatives considered**:
- JSON-encoded messages → rejected for consistency with existing simple string protocol
- Flutter-side SnackBar for errors → could be added alongside, but iframe feedback is more contextual
