# Implementation Plan: Editor Image Insertion

**Branch**: `034-editor-image-insert` | **Date**: 2026-04-08 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/034-editor-image-insert/spec.md`

## Summary

Add inline image insertion to the letter body WYSIWYG editor. Users click an "Insert Image" toolbar button, select an image file via the device file picker, and the image is uploaded to the server, resized/compressed if needed, and inserted at the cursor position in the editor as an `<img>` tag. Images are stored on the server filesystem and converted to base64 data URIs during PDF generation so WeasyPrint renders them in the final letter PDF.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, Pillow 12.1.1 (backend); http, file_picker, Flutter Material (frontend)  
**Storage**: Server filesystem `backend/uploaded_files/letters/` — no database changes  
**Testing**: Manual testing (editor interaction, PDF output)  
**Target Platform**: Web (PWA via Flutter Web, canvaskit renderer)  
**Project Type**: Web application (FastAPI backend + Flutter frontend)  
**Performance Goals**: Image upload + insertion visible in editor within 10 seconds for files under 2MB  
**Constraints**: 5MB max file size, 1920px max width, 80% compression quality, Nginx 50MB upload ceiling  
**Scale/Scope**: Soft limit of 10 images per letter; single-server deployment

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Feature spans backend (upload endpoint, PDF conversion) and frontend (toolbar button, upload flow, postMessage protocol). No database layer needed — images are filesystem-only, which is explicitly documented. |
| II. Explicit Over Automatic | PASS | Image upload is user-initiated (explicit button click). No auto-upload, no implicit behavior. |
| III. Role-Based Access Control | PASS | Image upload endpoint is accessible to any authenticated user who can create/edit letters (same access as existing letter endpoints). No new role-based restrictions needed. |
| IV. Server-First File Storage | PASS | Images stored on server filesystem at `uploaded_files/letters/`. No cloud storage. Served via FastAPI StaticFiles at `/files/`. Pillow auto-compression at 1920px max width. Matches constitution exactly. |
| V. Client-Side Computation | N/A | No dataset filtering or computation involved. |
| VI. Audit Everything | PASS | Image upload will be logged via existing `log_activity()` pattern with category `letter` and action `uploaded_image`. |
| VII. Simplicity & YAGNI | PASS | Minimal implementation: one new endpoint, three new postMessage types, one toolbar button. No abstraction layers, no image management UI, no database tables. |

**Post-Phase 1 Re-check**: All gates still pass. Data model confirms no DB changes. Contract confirms single lightweight endpoint. Architecture follows established patterns.

## Project Structure

### Documentation (this feature)

```text
specs/034-editor-image-insert/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 research decisions
├── data-model.md        # Phase 1 data model
├── quickstart.md        # Phase 1 quickstart guide
├── contracts/
│   └── upload-image.md  # API contract for upload endpoint
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── letters_v2.py          # Add upload-image endpoint + data URI conversion
└── uploaded_files/
    └── letters/               # Image files stored here (runtime, not committed)

frontend/
└── lib/
    ├── screens/
    │   └── letters_v2/
    │       └── letter_form_tab_v2.dart  # Toolbar button + postMessage handler + upload logic
    └── services/
        └── letter_service.dart          # Add uploadImage() multipart method
```

**Structure Decision**: Existing web application structure (backend/ + frontend/) is used. No new directories or modules created — changes are additions to existing files only.

## Complexity Tracking

> No constitution violations. Table left empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
