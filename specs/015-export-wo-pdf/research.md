# Research: Export PDF Report for Closed Work Orders

**Date**: 2026-04-04 | **Branch**: `015-export-wo-pdf`

## R-001: Server-Side PDF Generation Library

**Decision**: Use reportlab (Python) for server-side PDF generation.

**Rationale**: The project constitution explicitly lists "PDF (server): reportlab with logos from backend/assets/" as the established technology constraint. Signature image files reside on the server filesystem (`backend/uploaded_files/`), making server-side generation the natural choice — avoids transferring binary image data to the client.

**Alternatives considered**:
- Client-side Flutter `pdf` package: Already used for work order PDF themes, but cannot access server filesystem signature files directly. Would require downloading all signature PNGs to client first.
- WeasyPrint (Python HTML-to-PDF): More complex dependency chain (Cairo, Pango). Overkill for structured report layout.
- fpdf2 (Python): Lighter than reportlab but less mature for image embedding and complex layouts.

## R-002: reportlab Dependency Status

**Decision**: reportlab must be added to `requirements.txt` — it is NOT currently installed.

**Rationale**: Inspection of `requirements.txt` shows reportlab is not listed despite being mentioned in the constitution as the server PDF tool. This is the first feature to use server-side PDF generation via reportlab.

**Action**: Add `reportlab` to `requirements.txt` and install.

## R-003: Authentication Pattern for Export Endpoint

**Decision**: Follow existing query-parameter auth pattern (email + user_role).

**Rationale**: All existing endpoints in `backend/routers/work_orders.py` use `email: Optional[str] = Query(None)` and `user_role: Optional[str] = Query(None)` for authentication. The export endpoint must replicate the same RBAC logic found in `get_work_order()`:
- Reporter: `created_by` must match user ID looked up by email
- Technician: WO `department_id` must match user's department
- Admin: unrestricted access

## R-004: PDF Response Streaming Pattern

**Decision**: Use FastAPI `StreamingResponse` with `media_type="application/pdf"`.

**Rationale**: The PDF is generated in-memory using reportlab's `BytesIO` buffer, then streamed back as a binary response. This matches standard FastAPI patterns for binary file responses and avoids writing temporary files to disk.

**Response headers**:
- `Content-Type: application/pdf`
- `Content-Disposition: attachment; filename="WO-{job_no}-report.pdf"`

## R-005: Frontend PDF Preview Integration

**Decision**: Reuse existing `PdfPreviewScreen` widget.

**Rationale**: `PdfPreviewScreen` accepts `title` (String) and `buildPdf` (Future<dynamic> Function()). The export flow will:
1. Call `ReportService.exportWorkOrderPdf(workOrderId)` which returns `Future<Uint8List>`
2. Navigate to `PdfPreviewScreen(title: 'WO-{job_no} Report', buildPdf: () => service.exportWorkOrderPdf(id))`

The `buildPdf` callback is invoked by the `PdfPreview` widget from the `printing` package, which handles the preview rendering.

## R-006: Signature Selection Logic

**Decision**: When multiple signatures exist per role, use the first (oldest) approved signature.

**Rationale**: Clarified during spec phase — the PDF layout has exactly two fixed signature columns (technician left, admin right). Query signatures ordered by `signed_at ASC`, filter by role, and take the first with status != 'rejected'.

## R-007: Audit Logging for Export

**Decision**: Log PDF export as `category="work_order"`, `action="pdf_exported"`.

**Rationale**: Constitution Principle VI requires all user-facing actions to produce an activity log entry. Use existing `log_activity()` from `backend/utils/activity.py` (fire-and-forget pattern — does not block the response).

## R-008: reportlab Arabic Text Handling

**Decision**: Use reportlab's built-in Helvetica font. Arabic characters render as-is without RTL enforcement.

**Rationale**: Per the feature spec, Arabic text should be displayed as-is. reportlab's default fonts have limited Arabic glyph support, but the spec explicitly states "do NOT use pytesseract or pdf2image here, just display as-is." If Arabic glyphs render as boxes, this is acceptable for v1. A follow-up feature could add Arabic font support via registered TTF fonts.
