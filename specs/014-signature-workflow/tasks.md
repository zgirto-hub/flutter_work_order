# Tasks: Signature Workflow

**Input**: Design documents from `/specs/014-signature-workflow/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api-endpoints.md, quickstart.md

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story. Each task is written to be self-contained so another LLM can execute it without additional conversation context.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `backend/` (FastAPI Python)
- **Frontend**: `frontend/lib/` (Flutter Dart)
- **Migrations**: `supabase/migrations/`

---

## Phase 1: Setup

**Purpose**: No new project setup needed — this feature modifies an existing codebase. Phase 1 is empty.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Database schema changes and shared model/service updates that ALL user stories depend on. No user story work can begin until this phase is complete.

- [X] T001 Create database migration file `supabase/migrations/20260403_signature_file_storage.sql` that: (1) adds `signature_path TEXT` column to `work_order_signatures` table, (2) makes existing `signature_data` column nullable with `ALTER TABLE work_order_signatures ALTER COLUMN signature_data DROP NOT NULL`, (3) adds `signature_path TEXT` column to `users` table. Follow existing migration naming pattern in `supabase/migrations/`. See `specs/014-signature-workflow/data-model.md` for full column definitions.

- [X] T002 Update the Flutter model in `frontend/lib/models/work_order_signature.dart`: Replace the `signatureData` field (String) with `signaturePath` field (String?, nullable). Update `fromJson` to read from `json['signature_path']` instead of `json['signature_data']`. The model currently has fields: id, workOrderId, signerEmail, signerRole, signatureData, signedAt, status, rejectionReason. After change: replace signatureData with signaturePath (nullable String?).

- [X] T003 Add foundational methods to `frontend/lib/services/signature_service.dart`: (1) Add `fetchBulkSignatureStatus(List<String> workOrderIds)` method that calls `GET /api/signatures/bulk?work_order_ids=id1,id2,...` and returns `Map<String, Map<String, dynamic>>` (keyed by WO ID with technician_signed, technician_status, admin_signed, admin_status). (2) Add `fetchUserSignature(String userId)` method that calls `GET /api/users/{userId}/signature?user_email={currentEmail}` and returns `String?` (the signature_path or null). (3) Add `saveUserSignature({required String userId, String? base64Data, Uint8List? fileBytes, String? fileName})` method that calls `POST /api/users/{userId}/signature` — if base64Data provided, send as form field `signature_data`; if fileBytes provided, send as multipart file. (4) Add `deleteUserSignature(String userId)` method that calls `DELETE /api/users/{userId}/signature?user_email={currentEmail}`. Follow existing service patterns: use `AppConfig.baseUrl`, `Supabase.instance.client.auth.currentUser?.email` for user_email, and the existing `_errorDetail()` helper. Also update `saveSignature()` to accept an optional `useSaved` bool parameter — when true, send `{"use_saved": true}` in the JSON body instead of `signature_data`. See `specs/014-signature-workflow/contracts/api-endpoints.md` for all request/response schemas.

**Checkpoint**: Schema and shared frontend code ready — user story implementation can now begin.

---

## Phase 3: User Story 1 — Technician Signs a Closed Work Order (Priority: P1)

**Goal**: When a technician opens a closed work order, they can sign it using their saved signature or by drawing a new one. The signature is stored as a PNG file on the server filesystem (not base64 in DB). Only assigned technicians or admins can sign.

**Independent Test**: Close a work order, open it as the assigned technician, draw a signature, submit. Verify a `sig_*.png` file appears in `backend/uploaded_files/` and the signature record has `signature_path` set (not `signature_data`). Try submitting as an unassigned technician — should get 403.

### Implementation for User Story 1

- [X] T004 [US1] Modify `POST /work-orders/{work_order_id}/signatures` in `backend/routers/signatures.py` to store signatures as files instead of base64. Changes: (1) Import `uuid`, `os`, `base64` at top. (2) Add `UPLOAD_DIR = "uploaded_files"` constant. (3) In `AddSignatureBody`, add optional field `use_saved: bool = False`. (4) In `add_signature()` handler: if `body.use_saved` is True, look up the user's saved signature via `supabase.table("users").select("signature_path").eq("email", signer_email).execute()` — if found, copy that file to a new `sig_{uuid}.png` file; if not found, raise 400. If `body.use_saved` is False, decode `body.signature_data` from base64 and write to `uploaded_files/sig_{uuid}.png`. (5) Store `signature_path` (e.g., `/files/sig_{uuid}.png`) in the DB record instead of `signature_data`. (6) Add activity logging after successful insert: `from utils.activity import log_activity` then `log_activity(signer_email, "work_order", "signature_submitted", target_label=wo.data[0].get("title", ""), target_id=work_order_id)`. (7) Update the insert record dict to use `signature_path` key instead of `signature_data`. Keep all existing authorization logic (role check, assignment check) unchanged. See `specs/014-signature-workflow/contracts/api-endpoints.md` POST section for full request/response schema.

- [X] T005 [US1] Modify `GET /work-orders/{work_order_id}/signatures` in `backend/routers/signatures.py` to return `signature_path` instead of `signature_data` in response. The endpoint at line ~143 currently returns `result.data` directly which includes `signature_data`. Change the select to explicitly list columns: `.select("id, work_order_id, signer_email, signer_role, signature_path, signed_at, status, rejection_reason")` — this excludes `signature_data` from the response. For backward compat with old records that only have `signature_data`, add a post-processing loop: for each sig in result.data, if `signature_path` is None but `signature_data` exists, set `signature_path` to None (old records show no image rather than breaking).

- [X] T006 [US1] Update the signature section in `frontend/lib/screens/Work_Orders/add_work_order.dart` to handle file-based signatures and the saved signature flow. Changes to `_buildSignatureSection()` (around line 1162): (1) When displaying a signature preview (`_signaturePreview()`), instead of decoding base64 from `signature.signatureData`, display the image from the network URL: use `Image.network('${AppConfig.baseUrl.replaceAll('/api', '')}${signature.signaturePath}')` (the signaturePath is like `/files/sig_xxx.png`). (2) Before showing the signing UI, check if the current user has a saved signature by calling `_signatureService.fetchUserSignature(userId)`. If they have one: show a preview of the saved signature image + a "Use Saved Signature" ElevatedButton that calls `_signatureService.saveSignature(workOrderId: ..., signerEmail: ..., signerRole: ..., signatureData: '', useSaved: true)` + a "Draw New Instead" TextButton that opens `SignatureCanvas.show(context)`. If no saved signature: show `SignatureCanvas.show(context)` directly (current behavior). (3) When `_openSignatureCanvas()` gets a base64 result, continue calling `saveSignature()` with the base64 data as before — the backend now handles file conversion. Add state variable `_savedSignaturePath` loaded in `initState` via the service.

**Checkpoint**: Technician can sign closed WOs with file-based storage. Saved signature pre-selection works if user has one.

---

## Phase 4: User Story 2 — Admin Reviews, Approves, and Countersigns (Priority: P1)

**Goal**: Admin can view a technician's submitted signature, approve + countersign (with their saved sig or drawing), or reject with a reason. The admin's countersignature is auto-approved. Critical bug fix: capture admin canvas BEFORE committing the approval API call.

**Independent Test**: Have a technician sign a WO, log in as admin, approve + countersign. Verify: technician sig status = "approved", admin sig record created with status = "approved", both have `signature_path` values pointing to real files. Then test rejection: reject a pending sig, verify status = "rejected" with reason.

### Implementation for User Story 2

- [X] T007 [US2] Modify `PATCH /work-orders/{work_order_id}/signatures/{signature_id}` in `backend/routers/signatures.py` to add activity logging. After the existing `supabase.table("work_order_signatures").update(update_payload)` call (around line 184), add: `wo_info = wo.data[0] if wo.data else {}` then `log_activity(user_email, "work_order", "signature_approved" if body.status == "approved" else "signature_rejected", target_label=wo_info.get("title", job_no), target_id=work_order_id)`. The `log_activity` import should already be present from T004. Also: when the admin approves, the admin's own countersignature is submitted via a separate POST call from the frontend (already handled by T004) — ensure the POST endpoint creates admin signatures with status `"approved"` instead of `"pending"`. In the `add_signature()` function, change the record dict: `"status": "approved" if signer_role == "admin" else "pending"`.

- [X] T008 [US2] Fix the `_approveAndSign` bug in `frontend/lib/screens/Work_Orders/add_work_order.dart`. The current `_approveAndSign()` method (around line 1375) calls the approve API FIRST and THEN opens the signature canvas for the admin — but if the admin cancels the canvas, the approval is already committed without a countersignature. Fix: (1) FIRST open `SignatureCanvas.show(context)` to capture the admin's signature (or show saved sig option like in T006). (2) If the admin cancels (returns null), abort entirely — do not call approve. (3) Only AFTER the admin's signature bytes/selection are captured, call `_signatureService.updateSignature(status: 'approved')` to approve the technician sig, THEN call `_signatureService.saveSignature()` with the admin's signature data (signer_role: 'admin'). This ensures both operations happen atomically from the user's perspective. Also update the admin's signature preview display to use `Image.network` for file-based paths (same pattern as T006).

**Checkpoint**: Full dual-signature workflow functional. Admin approve/reject works correctly with countersignature captured first.

---

## Phase 5: User Story 3 — Saved Signature Management in Settings (Priority: P2)

**Goal**: Technicians and admins can draw, upload, preview, and remove their saved signature from the Settings screen. Reporters do not see this section.

**Independent Test**: Open Settings as a technician, draw a signature on the canvas, save it. Verify preview appears. Navigate away and back — preview persists. Upload an image file — preview updates. Remove signature — preview disappears. Login as reporter — no "My Signature" section visible.

### Implementation for User Story 3

- [X] T009 [P] [US3] Add user signature CRUD endpoints to `backend/routers/signatures.py`. Add three new endpoints: (1) `POST /users/{user_id}/signature` — accepts multipart/form-data with optional `file` (UploadFile) or form field `signature_data` (base64 string), plus required `user_email` form field. Validate: user_email matches the user_id's email (or requester is admin), user_type is technician or admin. Save file as `usersig_{user_id}.png` in `uploaded_files/` (overwrite if exists). If base64 provided, decode and write; if file provided, read bytes and write. Update `users.signature_path` to `/files/usersig_{user_id}.png`. Log activity: `log_activity(user_email, "work_order", "saved_signature_updated", target_label=user.get("full_name", ""), target_id=user_id)`. Return `{"signature_path": "/files/usersig_{user_id}.png"}`. (2) `GET /users/{user_id}/signature` — query param `user_email` for auth. Select `signature_path` from users table for the user_id. Return `{"signature_path": value_or_null}`. (3) `DELETE /users/{user_id}/signature` — query param `user_email` for auth. Validate user_email matches or is admin. Delete the file from `uploaded_files/` if it exists (use `os.remove`, catch FileNotFoundError). Set `users.signature_path` to None. Return `{"status": "deleted"}`. Use FastAPI's `File(...)` and `Form(...)` for the POST endpoint. See `specs/014-signature-workflow/contracts/api-endpoints.md` for full schemas.

- [X] T010 [US3] Add "My Signature" section to `frontend/lib/screens/settings_page.dart`. This section should appear between the "Account" section and the "Appearance" section, but ONLY if the current user's role is technician or admin (not reporter). Implementation: (1) Get the current user's ID and role (from Supabase auth or stored user data). (2) Add a new section with `SectionLabel('My Signature')` (matching existing section pattern). (3) Show a signature preview: on init, call `SignatureService().fetchUserSignature(userId)` to get the path. If path exists, display `Image.network('${AppConfig.baseUrl.replaceAll('/api', '')}$signaturePath')` in a Container with border and rounded corners (matching the signature preview style in add_work_order.dart). If path is null, show a placeholder text "No saved signature". (4) Add three action buttons using the existing `SettingsRow` or button patterns: "Draw Signature" — opens `SignatureCanvas.show(context)`, on result calls `SignatureService().saveUserSignature(userId: userId, base64Data: result)`, refreshes preview. "Upload Image" — uses `FilePicker.platform.pickFiles(type: FileType.image, withData: true)` (import `file_picker` package), on result calls `saveUserSignature(userId: userId, fileBytes: result.files.single.bytes, fileName: result.files.single.name)`, refreshes preview. "Remove Signature" — shows confirmation dialog, on confirm calls `SignatureService().deleteUserSignature(userId)`, clears preview. (5) Add `file_picker` to `frontend/pubspec.yaml` if not already present (check first). (6) Wrap the section in a `SurfaceCard` matching existing Settings sections.

**Checkpoint**: Users can manage their saved signature in Settings independently of any work order.

---

## Phase 6: User Story 4 — Bulk Signature Status on Work Order List (Priority: P2)

**Goal**: The work order list fetches signature status for all visible closed WOs in a single API call and displays a small icon/badge indicating state (unsigned, pending, fully signed).

**Independent Test**: Load the WO list with multiple closed WOs. In browser dev tools Network tab, verify only ONE request to `/api/signatures/bulk` (not individual requests per WO). Verify each closed WO shows an appropriate colored icon.

### Implementation for User Story 4

- [X] T011 [P] [US4] Add bulk signature status endpoint to `backend/routers/signatures.py`. Add: `GET /signatures/bulk` with query param `work_order_ids: str` (comma-separated UUIDs). Implementation: (1) Split the comma string into a list of IDs. (2) Query `work_order_signatures` using `.in_("work_order_id", ids_list)` to get all signatures for those WOs in one query. (3) Build a response dict keyed by work_order_id: for each WO, determine `technician_signed` (bool), `technician_status` (str or null), `admin_signed` (bool), `admin_status` (str or null) based on the signatures found. (4) For WO IDs with no signatures, include them with all values false/null. Return `{"statuses": {...}}`. See `specs/014-signature-workflow/contracts/api-endpoints.md` bulk section for exact response schema.

- [X] T012 [US4] Replace the N+1 signature status fetch in `frontend/lib/screens/Work_Orders/work_order_home.dart`. The current `_refreshSignatureStatus()` method (around line 138) loops through closed WO IDs calling `fetchSignatures(woId)` individually. Replace with: (1) Collect all closed WO IDs into a list. (2) If list is empty, skip. (3) Call `_signatureService.fetchBulkSignatureStatus(closedIds)` (added in T003) to get the status map. (4) From the result map, determine each WO's signature state: "unsigned" (no technician sig), "pending" (technician signed, not yet approved), "fully_signed" (both approved). Store in a new `Map<String, String> _signatureStates` field. (5) In the WO list item builder, for closed WOs, display a small colored icon next to the status badge: grey pen icon for "unsigned", yellow/amber pen icon for "pending", green pen icon for "fully_signed". Use `Icon(Icons.draw, size: 16, color: stateColor)` or similar. Keep the existing `_pendingSigWoIds` set if used elsewhere, or replace it with the new map.

- [X] T013 [US6] Update the rejection and re-sign flow in `frontend/lib/screens/Work_Orders/add_work_order.dart`. The existing `_buildSignatureSection()` already shows a rejection state (around line 1162-1291). Verify and enhance: (1) When the technician signature has `status == 'rejected'`, display the `rejectionReason` in a visible error card/banner (red background, icon). (2) Show a "Re-sign" button that opens the signature flow (saved sig option or canvas, same as T006). (3) When re-signing, the backend already handles this: the existing `add_signature()` endpoint deletes the rejected record and creates a new one (lines 102-114 in signatures.py). However, per spec FR-017, rejected records must be PRESERVED for audit. Modify `backend/routers/signatures.py` `add_signature()`: instead of deleting the rejected record, leave it in place. Just insert a new record. The query for "existing pending/approved" signature should only prevent duplicate if status is pending or approved (already the case at line 113-114), so the rejected record is naturally preserved. Remove the delete call at line 112: `supabase.table("work_order_signatures").delete().eq("id", existing.data[0]["id"]).execute()`. Instead, only check if there's a pending or approved record and block on that.

- [X] T014 [US5] Verify and complete activity logging across all signature endpoints in `backend/routers/signatures.py`. By this point, T004 added logging to `add_signature()`, T007 added logging to `update_signature()`, and T009 added logging to the user signature POST endpoint. Verify all four log events are present: (1) `log_activity(email, "work_order", "signature_submitted", ...)` in `add_signature()`. (2) `log_activity(email, "work_order", "signature_approved", ...)` in `update_signature()` approve path. (3) `log_activity(email, "work_order", "signature_rejected", ...)` in `update_signature()` reject path. (4) `log_activity(email, "work_order", "saved_signature_updated", ...)` in `POST /users/{user_id}/signature`. If any are missing, add them. Ensure `target_id` is the work_order_id for WO signature events and the user_id for saved signature events. Ensure `target_label` is the WO title for WO events and the user's full_name for saved sig events.

- [X] T015 [P] Verify `file_picker` dependency is in `frontend/pubspec.yaml` — if not added by T010, add `file_picker: ^8.0.0` (or latest compatible version) under dependencies and run `flutter pub get`.

- [X] T016 [P] Register the new user signature routes in `backend/main.py` if needed. The existing `signatures.router` is already mounted at line ~61 with `app.include_router(signatures.router, prefix="/api")`. Since the new endpoints (`/users/{user_id}/signature` and `/signatures/bulk`) are added to the same router, they should be automatically included. Verify by checking that all new routes appear when running the backend — if `/api/users/{user_id}/signature` returns 404, check the router prefix and route definitions.

- [X] T017 Update `CLAUDE.md` Active Technologies section to reflect this feature: add `signature` Flutter package, `file_picker` Flutter package, and the `work_order_signatures` table under Active Technologies for 014-signature-workflow.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: Empty — skip
- **Phase 2 (Foundational)**: No dependencies — start immediately. BLOCKS all user stories.
- **Phase 3 (US1)**: Depends on Phase 2 completion
- **Phase 4 (US2)**: Depends on Phase 3 (US1 must exist for admin to review)
- **Phase 5 (US3)**: Depends on Phase 2 only — can run in parallel with Phase 3
- **Phase 6 (US4)**: Depends on Phase 2 only — can run in parallel with Phase 3
- **Phase 7 (US6)**: Depends on Phase 3 (US1 signing must work for rejection flow)
- **Phase 8 (US5)**: Depends on Phases 3, 4, 5 (logging is verified across all endpoints)
- **Phase 9 (Polish)**: Depends on all previous phases

### User Story Dependencies

- **US1 (P1)**: Foundational only — core signing
- **US2 (P1)**: Depends on US1 — admin reviews what technician signed
- **US3 (P2)**: Foundational only — Settings is independent of WO signing
- **US4 (P2)**: Foundational only — bulk status is independent read-only endpoint
- **US6 (P2)**: Depends on US1 — re-sign requires initial sign to exist
- **US5 (P3)**: Cross-cutting — verify after US1, US2, US3 are done

### Within Each User Story

- Backend changes before frontend changes (frontend depends on API)
- Model/service updates before screen changes

### Parallel Opportunities

- **T009 + T011**: User signature endpoints (US3) and bulk endpoint (US4) touch different code paths — can run in parallel
- **T010 + T012**: Settings UI (US3) and WO home changes (US4) are different screens — can run in parallel after their respective backend tasks
- **Phase 5 (US3) and Phase 6 (US4)**: Entirely independent — can execute in parallel

---

## Parallel Example: After Phase 2

```
# These can run simultaneously:
Stream A: T004 → T005 → T006 (US1 backend → frontend)
Stream B: T009 → T010 (US3 backend → frontend)
Stream C: T011 → T012 (US4 backend → frontend)
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 2: Foundational (migration + model + service stubs)
2. Complete Phase 3: US1 — technician can sign with file storage
3. Complete Phase 4: US2 — admin can approve/reject/countersign
4. **STOP and VALIDATE**: Full signing workflow works end-to-end
5. Deploy/demo if ready

### Incremental Delivery

1. Phase 2 → Foundation ready
2. Phase 3 (US1) → Technician signing works → Deploy
3. Phase 4 (US2) → Admin review works → Deploy
4. Phase 5 (US3) + Phase 6 (US4) in parallel → Settings + bulk status → Deploy
5. Phase 7 (US6) → Re-sign after rejection → Deploy
6. Phase 8 (US5) → Verify activity logging → Deploy
7. Phase 9 → Polish → Final deploy

---

## Notes

- All tasks modify EXISTING files — no new files are created except the migration SQL and this tasks.md
- The `signature_canvas.dart` widget needs NO changes — it already exports base64 PNG which the backend now decodes to file
- Existing authorization logic in `signatures.py` (assignment check, role check) is already correct — tasks only add file storage and logging on top
- The `signature_data` column is kept nullable for backward compat — old records with base64 will show no preview image (acceptable per clarification: migration out of scope)
- Admin countersignature records are created with `status: "approved"` (auto-approved per clarification)
- Each task references the specific lines/methods to modify in existing files for precision
