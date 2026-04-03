# Tasks: Export PDF Report for Closed Work Orders

**Input**: Design documents from `/specs/015-export-wo-pdf/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api-endpoints.md

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Add the reportlab dependency required for server-side PDF generation.

- [X] T001 Add `reportlab` to `backend/requirements.txt`

**Step-by-step for T001**:
1. Open `backend/requirements.txt`
2. Add `reportlab` on a new line (alphabetical position, between `realtime` and `requests`). Do NOT pin a version — let pip resolve the latest compatible version.
3. Save the file.

**Checkpoint**: `reportlab` is listed in requirements.txt. Run `pip install reportlab` to verify it installs.

---

## Phase 2: Foundational (Backend PDF Generation Engine)

**Purpose**: Build the core PDF generation function in the backend. This is the most complex task and MUST be complete before any user story UI work begins.

- [X] T002 Implement `_fetch_wo_for_pdf()` helper function in `backend/routers/reports.py`
- [X] T003 Implement `_build_work_order_pdf()` reportlab function in `backend/routers/reports.py`

**Step-by-step for T002** — Add a helper that fetches all data needed for the PDF:

1. Open `backend/routers/reports.py`. Currently it has one endpoint `get_closed_work_orders`.
2. Add these imports at the top (merge with existing imports):
   ```python
   import os
   import io
   from datetime import datetime
   from typing import Optional
   from fastapi import Query, HTTPException
   from fastapi.responses import StreamingResponse
   from reportlab.lib.pagesizes import A4
   from reportlab.lib.units import mm, cm
   from reportlab.lib.colors import HexColor, white, black, lightgrey, green
   from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, Image as RLImage
   from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
   from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
   from utils.activity import log_activity
   ```
3. Add a helper function `_fetch_wo_for_pdf(work_order_id: str)` that:
   - Queries `work_orders` table with select joining `departments` (name), `users` via `created_by` (full_name, email), and `work_order_assignments` → `users` (full_name, email). Use the same Supabase nested select pattern found in `backend/routers/work_orders.py` function `_fetch_full_work_order()`.
   - Example query pattern:
     ```python
     result = supabase.table("work_orders").select("""
         *,
         creator:users!work_orders_created_by_fkey(full_name, email),
         departments!work_orders_department_id_fkey(id, name),
         work_order_assignments(
             technician_id,
             users!work_order_assignments_technician_id_fkey(full_name, email)
         )
     """).eq("id", work_order_id).execute()
     ```
   - Returns `result.data[0]` if found, else `None`.
4. Add a helper function `_fetch_signatures_for_pdf(work_order_id: str)` that:
   - Queries `work_order_signatures` where `work_order_id = id`, ordered by `signed_at` ASC.
   - For each signature, looks up the signer's `full_name` from the `users` table by matching `signer_email`.
   - Returns a dict with keys `"technician"` and `"admin"`, each containing the **first** (oldest) non-rejected signature for that role, or `None` if no such signature exists.
   - Each signature dict should include: `signer_email`, `signer_role`, `signature_path`, `signed_at`, `status`, `signer_full_name`.

**Step-by-step for T003** — Build the PDF rendering function:

1. Still in `backend/routers/reports.py`, add function `_build_work_order_pdf(wo_data: dict, signatures: dict) -> bytes`:
2. This function uses reportlab to generate a PDF. Here is the layout specification:

   **Page Setup**:
   - Page size: A4
   - Margins: 2cm left/right, 1.5cm top/bottom
   - Use `SimpleDocTemplate` with a `BytesIO` buffer

   **HEADER Section**:
   - Three logos side by side: `logo_emblem.png`, `logo_civilaviation.png`, `logo_newkuwait.png` from `backend/assets/`
   - For each logo: check if file exists with `os.path.exists()`. If missing, skip it. Use try/except around `RLImage()` to handle corrupt files.
   - Logo dimensions: approximately 2cm height each, arranged in a 3-column Table.
   - Below logos: Title "Work Order Completion Report" — centered, bold, 16pt, dark navy color (`#1a2744`).
   - Below title: Subtitle with department name + export date — centered, 10pt, gray.
   - A horizontal line (light gray) to separate header from body.

   **WORK ORDER DETAILS Section**:
   - Section title: "Work Order Details" — bold, 12pt, dark navy.
   - Display as a 2-column table (label: value), with these rows:
     - Job No: `wo_data["job_no"]`
     - Title: `wo_data["title"]`
     - Type: `wo_data["type"]`
     - Status: `wo_data["status"]`
     - Department: `wo_data["departments"]["name"]`
     - Location: `wo_data["location"]`
     - Mobile Number: `wo_data["mobile_number"]`
     - Created By: `wo_data["creator"]["full_name"]`
     - Created At: formatted datetime from `wo_data["created_at"]`
     - Closed At: formatted datetime from `wo_data["closed_at"]` (or "N/A" if null)
   - Below the table: Description (full text, wrapped using `Paragraph` with `TA_LEFT`).
   - If `wo_data["tech_notes"]` is not None/empty: show Tech Notes (full text, wrapped). Otherwise omit entirely.

   **ASSIGNED TECHNICIANS Section**:
   - Section title: "Assigned Technicians" — bold, 12pt, dark navy.
   - Extract technician names from `wo_data["work_order_assignments"]` — each assignment has a nested `users` object with `full_name`.
   - Display as a bulleted list or simple table of names.

   **SIGNATURE Section** (two columns side by side):
   - Section title: "Signatures" — bold, 12pt, dark navy.
   - Two columns using a 2-column Table:
   - **Left column** — "Technician Signature":
     - If `signatures["technician"]` exists:
       - Signer name + email
       - Signed at date
       - Signature image: read from `backend/uploaded_files/{signature_path}`. If file missing, show "Signature file not found" text.
       - Status badge: green "Approved" text if status == "approved", otherwise show actual status.
     - If `signatures["technician"]` is None:
       - Show "Awaiting Signature" placeholder text in a bordered box.
   - **Right column** — "Authorized By" (admin):
     - Same pattern as left column but for `signatures["admin"]`.
   - Signature boxes should have a light border and rounded feel (use `TableStyle` with `BOX` and `ROUNDEDCORNERS` if available, or just `BOX`).

   **FOOTER**:
   - Use `SimpleDocTemplate`'s `onFirstPage` and `onLaterPages` callbacks to draw footer on every page.
   - Footer content: "Generated by Civil Aviation Work Order System" (left-aligned), export timestamp (center), "Page X" (right-aligned).
   - Footer is drawn at the bottom of the page using `canvas.drawString()` at y=1cm.

3. The function returns the PDF bytes from the `BytesIO` buffer: `buffer.getvalue()`.

4. **Important edge cases to handle**:
   - All text fields: use `str(value or "")` to avoid None errors.
   - Long description/tech notes: use `Paragraph` which automatically wraps and flows to next page.
   - Missing logos: skip with try/except, do not crash.
   - Missing signature images: show placeholder text "Signature file not found" instead.
   - Arabic text: render as-is using Helvetica. Do not attempt RTL or special font handling.

**Checkpoint**: The two helper functions exist and can be called. No endpoint yet — that's T004.

---

## Phase 3: User Story 1 — Export PDF from Work Order Details (Priority: P1) — MVP

**Goal**: User can tap "Export PDF Report" on a closed WO detail screen and see the generated PDF in a preview screen.

**Independent Test**: Open any closed work order → tap "Export PDF Report" → PDF preview opens with all content.

### Implementation for User Story 1

- [X] T004 [US1] Add `POST /api/reports/work-order-pdf/{work_order_id}` endpoint with RBAC and audit logging in `backend/routers/reports.py`
- [X] T005 [P] [US1] Add `exportWorkOrderPdf()` method in `frontend/lib/services/report_service.dart`
- [X] T006 [US1] Add "Export PDF Report" button in `frontend/lib/screens/Work_Orders/add_work_order.dart`

**Step-by-step for T004** — Add the POST endpoint:

1. In `backend/routers/reports.py`, add a new endpoint:
   ```python
   @router.post("/reports/work-order-pdf/{work_order_id}")
   async def export_work_order_pdf(
       work_order_id: str,
       email: Optional[str] = Query(None),
       user_role: Optional[str] = Query(None),
   ):
   ```
2. **Fetch the work order** using `_fetch_wo_for_pdf(work_order_id)`. If not found, raise `HTTPException(status_code=404, detail="Work order not found")`.
3. **RBAC enforcement** — replicate the exact same logic from `backend/routers/work_orders.py` `get_work_order()`:
   - If `user_role == "reporter"` and `email`: look up user ID by email from `users` table. If `wo_data["created_by"] != user_id`, raise `HTTPException(status_code=403, detail="Access denied")`.
   - If `user_role == "technician"` and `email`: look up user by email from `users` table. If `wo_data["department_id"] != user["department_id"]`, raise `HTTPException(status_code=403, detail="Access denied")`.
   - If `user_role == "admin"`: no restriction.
   - Helper functions `_get_user_id_by_email()` and `_get_user_by_email()` may already exist in `work_orders.py`. If so, either import them or duplicate the simple Supabase lookup in `reports.py` to avoid circular imports.
4. **Fetch signatures** using `_fetch_signatures_for_pdf(work_order_id)`.
5. **Generate the PDF** by calling `_build_work_order_pdf(wo_data, signatures)`. Wrap in try/except — on error, return `JSONResponse(status_code=500, content={"detail": f"Failed to generate PDF: {str(e)}"})`.
6. **Audit log** — after successful PDF generation:
   ```python
   job_no = wo_data.get("job_no", "unknown")
   log_activity(email or "unknown", "work_order", "pdf_exported",
                target_label=f"WO {job_no}", target_id=work_order_id)
   ```
7. **Return the PDF** as a `StreamingResponse`:
   ```python
   job_no = wo_data.get("job_no", "unknown")
   return StreamingResponse(
       io.BytesIO(pdf_bytes),
       media_type="application/pdf",
       headers={"Content-Disposition": f'attachment; filename="WO-{job_no}-report.pdf"'}
   )
   ```

**Step-by-step for T005** — Add the frontend service method:

1. Open `frontend/lib/services/report_service.dart`.
2. Add `import 'dart:typed_data';` at the top (for `Uint8List`).
3. Add this method to the `ReportService` class:
   ```dart
   /// Export a work order as a PDF report.
   /// Returns raw PDF bytes from the server.
   Future<Uint8List> exportWorkOrderPdf({
     required String workOrderId,
     required String email,
     required String userRole,
   }) async {
     final uri = Uri.parse(
       '${AppConfig.baseUrl}/reports/work-order-pdf/$workOrderId',
     ).replace(queryParameters: {
       'email': email,
       'user_role': userRole,
     });
     final res = await http.post(uri);
     if (res.statusCode != 200) {
       throw Exception(_errorDetail(res, 'Failed to generate PDF'));
     }
     return res.bodyBytes;
   }
   ```
4. The method follows the same pattern as `getClosedWorkOrders()` but:
   - Uses `http.post()` instead of `http.get()`
   - Returns `res.bodyBytes` (Uint8List) instead of parsed JSON
   - Passes `email` and `user_role` as query parameters

**Step-by-step for T006** — Add the Export PDF button on the WO detail screen:

1. Open `frontend/lib/screens/Work_Orders/add_work_order.dart`.
2. Add these imports at the top (if not already present):
   ```dart
   import '../../services/report_service.dart';
   import '../../widgets/pdf_preview_screen.dart';
   ```
3. Find the section around line 1208-1228 where the signature section and delete button are. The current structure is:
   ```dart
   // ── Signature Section (Closed WOs only) ──────────────
   if (widget.workOrder != null &&
       widget.workOrder!.status == 'Closed')
     _buildSignatureSection(),

   if (canEdit)
     ElevatedButton(onPressed: submit, ...),
   if (widget.workOrder != null && canEdit) ...[
     SizedBox(height: 12),
     TextButton.icon(icon: ..., label: "Delete work order", ...),
   ],
   ```
4. Add the Export PDF button **after** the signature section and **before** the Save/Submit button. Insert this block right after `_buildSignatureSection(),` (around line 1211):
   ```dart
   // ── Export PDF Report (Closed WOs only) ──────────────
   if (widget.workOrder != null &&
       widget.workOrder!.status == 'Closed') ...[
     SizedBox(height: 16),
     SizedBox(
       width: double.infinity,
       child: OutlinedButton.icon(
         icon: Icon(Icons.picture_as_pdf_outlined, size: 18),
         label: Text("Export PDF Report"),
         onPressed: _exportPdf,
       ),
     ),
   ],
   ```
5. Add the `_exportPdf()` method to the State class (e.g., `_AddWorkOrderScreenState`):
   ```dart
   bool _exportingPdf = false;

   Future<void> _exportPdf() async {
     if (_exportingPdf) return;
     setState(() => _exportingPdf = true);
     try {
       final currentUser = Supabase.instance.client.auth.currentUser;
       final email = currentUser?.email ?? '';
       final workOrderId = widget.workOrder!.id;
       final jobNo = widget.workOrder!.jobNo ?? 'unknown';

       await Navigator.push(
         context,
         MaterialPageRoute(
           builder: (_) => PdfPreviewScreen(
             title: 'WO-$jobNo Report',
             buildPdf: () => ReportService().exportWorkOrderPdf(
               workOrderId: workOrderId,
               email: email,
               userRole: _userRole ?? 'reporter',
             ),
           ),
         ),
       );
     } catch (e) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Failed to export PDF: $e')),
         );
       }
     } finally {
       if (mounted) setState(() => _exportingPdf = false);
     }
   }
   ```
6. Note: `_userRole` is already available in the state class (it's used for the signature section). `Supabase` is already imported. The `PdfPreviewScreen` handles its own loading state internally via the `PdfPreview` widget.

**Checkpoint**: At this point, User Story 1 should be fully functional:
- Backend generates PDF with all content
- Frontend calls backend and opens preview
- RBAC is enforced
- Audit log is written
- Test by opening a closed WO → tap "Export PDF Report" → verify PDF content

---

## Phase 4: User Story 2 — Export PDF from Work Order List (Priority: P2)

**Goal**: Closed WO cards in the list show an "Export PDF" icon button that triggers the same PDF flow.

**Independent Test**: Expand a closed WO card in the list → tap PDF icon → PDF preview opens.

### Implementation for User Story 2

- [X] T007 [US2] Add `onExportPdf` callback parameter to `WorkOrderCard` in `frontend/lib/widgets/work_order_card.dart`
- [X] T008 [US2] Wire up `onExportPdf` callback in `frontend/lib/screens/Work_Orders/work_order_home.dart`

**Step-by-step for T007** — Add Export PDF icon to the card widget:

1. Open `frontend/lib/widgets/work_order_card.dart`.
2. Add a new callback parameter to the `WorkOrderCard` constructor. Find the existing parameters (around line 6-18):
   ```dart
   final VoidCallback? onStatusTap;
   ```
   Add after it:
   ```dart
   final VoidCallback? onExportPdf;
   ```
3. Add the parameter to the constructor as well:
   ```dart
   this.onExportPdf,
   ```
4. Find the action buttons Row (around line 354-428). This Row has the "Activity" button and "Edit" button. Add an "Export PDF" button **before** the Activity button, only for closed WOs. Insert this at the beginning of the `children` list of the Row:
   ```dart
   if (widget.onExportPdf != null &&
       widget.workOrder.status.toLowerCase() == 'closed')
     Padding(
       padding: const EdgeInsets.only(right: 8),
       child: Semantics(
         label: 'Export PDF report',
         button: true,
         child: GestureDetector(
           onTap: widget.onExportPdf,
           child: Container(
             padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
             decoration: BoxDecoration(
               color: AppColors.bgSurface,
               borderRadius: BorderRadius.circular(9),
               border: Border.all(color: AppColors.border2, width: 0.5),
             ),
             child: Row(
               mainAxisSize: MainAxisSize.min,
               children: [
                 Icon(Icons.picture_as_pdf_outlined,
                     size: 13, color: AppColors.textSecondary),
                 SizedBox(width: 5),
                 Text('PDF',
                     style: TextStyle(
                         fontSize: 12,
                         color: AppColors.textSecondary,
                         fontWeight: FontWeight.w500)),
               ],
             ),
           ),
         ),
       ),
     ),
   ```

**Step-by-step for T008** — Wire up the callback in work_order_home.dart:

1. Open `frontend/lib/screens/Work_Orders/work_order_home.dart`.
2. Add these imports at the top (if not already present):
   ```dart
   import '../../services/report_service.dart';
   import '../../widgets/pdf_preview_screen.dart';
   ```
3. Find the `WorkOrderCard(` constructor call (around line 920). After the `onEdit:` callback (which ends around line 990), add the `onExportPdf` parameter:
   ```dart
   onExportPdf: wo.status.toLowerCase() == 'closed'
       ? () async {
           final currentUser = Supabase.instance.client.auth.currentUser;
           final email = currentUser?.email ?? '';
           try {
             await Navigator.push(
               context,
               MaterialPageRoute(
                 builder: (_) => PdfPreviewScreen(
                   title: 'WO-${wo.jobNo ?? "unknown"} Report',
                   buildPdf: () => ReportService().exportWorkOrderPdf(
                     workOrderId: wo.id,
                     email: email,
                     userRole: _userRole ?? 'reporter',
                   ),
                 ),
               ),
             );
           } catch (e) {
             if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('Failed to export PDF: $e')),
               );
             }
           }
         }
       : null,
   ```
4. Note: `_userRole` is already available in the `_WorkOrderHomeState` class. `Supabase` is already imported. The `wo` variable is the current `WorkOrder` object in the list builder.

**Checkpoint**: User Story 2 is now functional:
- Closed WO cards show a "PDF" button in the expanded action row
- Non-closed WOs do not show the button
- Tapping it opens the same PDF preview as Story 1

---

## Phase 5: User Story 3 — Role-Based Export Access (Priority: P1)

**Goal**: RBAC is enforced so reporters/technicians can only export WOs they have access to.

**Note**: RBAC is already implemented in T004 (the backend endpoint). This phase is a verification step only — no new code needed unless T004 was not implemented correctly.

- [X] T009 [US3] Verify RBAC enforcement in the export endpoint in `backend/routers/reports.py`

**Step-by-step for T009** — Verification checklist:

1. Open `backend/routers/reports.py` and verify the `export_work_order_pdf` endpoint has these checks:
   - **Reporter check**: If `user_role == "reporter"`, look up user by email, compare `created_by` field. Return 403 if mismatch.
   - **Technician check**: If `user_role == "technician"`, look up user by email, compare `department_id`. Return 403 if mismatch.
   - **Admin**: No restriction (passes through).
2. Verify the RBAC logic matches exactly what `backend/routers/work_orders.py` does in `get_work_order()`.
3. If any of these checks are missing from T004's implementation, add them now.

**Checkpoint**: All three user stories are functional and RBAC is enforced.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanup and edge case verification.

- [X] T010 Verify edge cases in PDF generation in `backend/routers/reports.py`
- [X] T011 Update CLAUDE.md recent changes section

**Step-by-step for T010** — Edge case verification:

1. In `_build_work_order_pdf()`, verify these edge cases are handled:
   - Missing logo files: wrapped in try/except, skipped gracefully
   - Missing signature PNG files: shows "Signature file not found" text
   - Empty `tech_notes`: tech notes row is omitted
   - Very long description: uses `Paragraph` which auto-wraps
   - `closed_at` is null (non-closed WO): shows "N/A" instead of crashing
   - Arabic text in fields: rendered as-is (no special handling needed)
2. If any edge case is not handled, add the handling now.

**Step-by-step for T011** — CLAUDE.md update:

1. Open `CLAUDE.md` at the project root.
2. In the `## Recent Changes` section, verify the `015-export-wo-pdf` entry exists (it was added by the agent context script). If not, add it.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start here
- **Foundational (Phase 2)**: Depends on Phase 1 (reportlab must be in requirements.txt)
- **User Story 1 (Phase 3)**: Depends on Phase 2 (PDF generation functions must exist)
- **User Story 2 (Phase 4)**: Depends on Phase 3, T005 specifically (needs `ReportService.exportWorkOrderPdf()`)
- **User Story 3 (Phase 5)**: Depends on Phase 3, T004 specifically (RBAC is in the endpoint)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Foundational (Phase 2) — this is the MVP
- **User Story 2 (P2)**: Depends on US1 completion (reuses the same service method and endpoint)
- **User Story 3 (P1)**: Built into US1 endpoint — verification only

### Within Each User Story

- Backend endpoint before frontend service
- Frontend service before frontend UI
- T005 (frontend service) can be done in parallel with T004 (backend endpoint) since they're different codebases

### Parallel Opportunities

- T002 and T003 are sequential (T003 depends on data structures from T002)
- T004 and T005 can run in parallel [P] (different codebases — Python vs Dart)
- T007 and T008 are sequential (T008 depends on the callback parameter from T007)

---

## Parallel Example: User Story 1

```text
# These can run in parallel (backend and frontend are independent):
Task T004: Backend endpoint in backend/routers/reports.py
Task T005: Frontend service method in frontend/lib/services/report_service.dart

# Then sequentially:
Task T006: Frontend UI button in frontend/lib/screens/Work_Orders/add_work_order.dart (depends on T005)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001) — add reportlab dependency
2. Complete Phase 2: Foundational (T002, T003) — build PDF generation engine
3. Complete Phase 3: User Story 1 (T004, T005, T006) — endpoint + service + button
4. **STOP and VALIDATE**: Open a closed WO → tap "Export PDF Report" → verify PDF
5. Deploy if ready — this is a functional MVP

### Incremental Delivery

1. Setup + Foundational → PDF engine ready
2. Add User Story 1 → Test → Deploy (MVP!)
3. Add User Story 2 → Test → Deploy (convenience shortcut from list)
4. Verify User Story 3 → Confirm RBAC works
5. Polish → Edge cases verified, docs updated

---

## Notes

- Total tasks: 11
- Tasks per story: US1=3, US2=2, US3=1, Setup=1, Foundation=2, Polish=2
- The backend PDF generation (T002 + T003) is the most complex work — allocate time accordingly
- reportlab uses `Paragraph` for text wrapping which handles page overflow automatically
- `PdfPreviewScreen` already exists and handles loading/printing — no need to build preview UI
- The `_userRole` variable is already available in both `add_work_order.dart` and `work_order_home.dart` state classes
- Do NOT commit `backend/version.json` — it is managed on the server independently
