# Tasks: Link Payment Certificates to Letters (Merged PDF Export)

**Feature**: 029-link-cert-letter
**Spec**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Contracts**: [contracts/api.md](contracts/api.md) · **Data Model**: [data-model.md](data-model.md)

---

## Phase 1: Setup

- [ ] T001 Create Supabase migration at `supabase/migrations/20260407_letter_cert_link_order.sql` adding `letter_link_order INTEGER NULL` column and composite index `idx_payment_certificates_letter_order(letter_id, letter_link_order)` on `payment_certificates`.
- [ ] T002 [P] Add `pypdf` to `backend/requirements.txt` (no version pin required beyond `>=4.0`).

## Phase 2: Foundational

- [ ] T003 Extend `LetterBodyV2` Pydantic model in `backend/routers/letters_v2.py` to add `payment_certificate_ids: list[str] = []` and `force_reassign: bool = False` fields.
- [ ] T004 [P] Extend `GeneratedLetter` model in `frontend/lib/models/generated_letter.dart` to add `final List<LinkedPaymentCertificate> linkedPaymentCertificates` and a nested `LinkedPaymentCertificate { String id; String certificateNumber; String subject; int letterLinkOrder; }` class, plus JSON (de)serialization for the new `payment_certificates` array field.

## Phase 3: User Story 1 — Attach + Merged PDF Export (P1)

**Story goal**: Author attaches payment certificates from the letter form and exports a single combined PDF.
**Independent test**: Create letter → attach 2 certs → export → downloaded file is one PDF with letter pages followed by both cert PDFs in attached order.

### Backend

- [ ] T005 [US1] In `backend/routers/letters_v2.py`, add helper `def _apply_cert_links(letter_id: str, cert_ids: list[str], force_reassign: bool) -> list[dict]` that (a) fetches each cert, (b) collects conflicts where `letter_id` is set and ≠ current letter and `force_reassign` is false, (c) on conflicts raises `HTTPException(status_code=409, detail={"error":"certificates_already_linked","conflicts":[{"certificate_id":..., "existing_letter_id":...}]})`, (d) otherwise updates each cert with `letter_id` + `letter_link_order = index`, (e) clears `letter_id`/`letter_link_order` on certs previously linked to this letter but not in the new list. Returns the final linked cert list.
- [ ] T006 [US1] In `backend/routers/letters_v2.py` `create_letter_v2` (POST `/letters-v2`), after letter insert, call `_apply_cert_links(letter_id, data.payment_certificate_ids, data.force_reassign)`.
- [ ] T007 [US1] In `backend/routers/letters_v2.py` `update_letter_v2` (PUT `/letters-v2/{letter_id}`), after letter update, call `_apply_cert_links(letter_id, data.payment_certificate_ids, data.force_reassign)`.
- [ ] T008 [US1] In `backend/routers/letters_v2.py` `get_letters_v2` (GET `/letters-v2`), change the payment_certificates subquery to `.select("id, certificate_number, subject, letter_link_order").eq("letter_id", letter["id"]).order("letter_link_order")`.
- [ ] T009 [US1] In `backend/routers/letters_v2.py` `delete_letter_v2`, update the existing unlink call to also clear `letter_link_order`: `.update({"letter_id": None, "letter_link_order": None})`.
- [ ] T010 [US1] In `backend/routers/letters_v2.py`, add new endpoint `@router.post("/letters-v2/{letter_id}/export-with-attachments") async def export_with_attachments(letter_id: str, letter_body: str = Form(...), order: str = Form(...), requester_email: str = Form(...), files: list[UploadFile] = File(default=[]))`. Signature/behavior: parse `letter_body` JSON into `LetterBodyV2`; enforce author/admin permission against stored letter; build letter PDF via `_build_letter_pdf_v2(body)`; parse `order` as JSON list of cert ids; for each id in `order`, look up the matching upload by filename (cert id), read its bytes, and append via `pypdf.PdfWriter.append(PdfReader(io.BytesIO(bytes)))`; return the merged bytes as `Response(content=..., media_type="application/pdf", headers={"Content-Disposition": f'attachment; filename="letter_{ts}.pdf"'})`. Log `log_activity(requester_email, "exported", "letter", letter_id)`. Raise 403 if not permitted, 404 if letter missing, 422 if `order` contains an id with no matching upload.

### Frontend

- [ ] T011 [P] [US1] In `frontend/lib/services/letter_service.dart`:
  - Extend `createLetter` and `updateLetter` payloads with `"payment_certificate_ids": certIds` and `"force_reassign": forceReassign` (add parameters `List<String> paymentCertificateIds = const []`, `bool forceReassign = false`).
  - Add method `Future<Uint8List> exportLetterWithAttachments({required String letterId, required Map<String, dynamic> letterBody, required List<String> orderedCertIds, required Map<String, Uint8List> certPdfs, required String requesterEmail})` that POSTs multipart to `/letters-v2/{letterId}/export-with-attachments` with `letter_body` (json-encoded), `order` (json-encoded), `requester_email` and one `files` part per cert named by cert id, returning the response bytes.
- [ ] T012 [P] [US1] Create `frontend/lib/screens/letters_v2/widgets/payment_cert_picker.dart` exporting `class PaymentCertPicker extends StatefulWidget` with `static Future<List<PaymentCertificate>?> show(BuildContext context, {required List<String> alreadySelectedIds})`. The widget shows a bottom sheet with a search TextField filtering by `certificate_number` and `subject` (fetched once via `PaymentCertificateService().listAll()`), a multi-select list, and confirm/cancel buttons. Returns the newly selected certificates.
- [ ] T013 [US1] In `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`:
  - Add state field `List<LinkedPaymentCertificate> _linkedCerts = []` (initialized from the loaded letter, else empty).
  - Add an "Attachments" section below the existing form body rendering `_linkedCerts` as a `ReorderableListView` of cert rows (certificate number + subject + delete icon).
  - Add an "Add Payment Certificate" button that calls `PaymentCertPicker.show(...)` and appends the selected certs.
  - On save, pass `_linkedCerts.map((c) => c.id).toList()` into `LetterService.createLetter`/`updateLetter` via the new `paymentCertificateIds` parameter.
  - Add an "Export Combined PDF" button that: (a) generates each cert's PDF bytes locally via `PaymentCertificatePdfService().buildPdf(cert)`; (b) calls `LetterService().exportLetterWithAttachments(...)` with the current form body, ordered cert ids, and cert PDF map; (c) triggers browser download using the existing `openInNewTab`/download helper.

## Phase 4: User Story 2 — Reassignment Confirmation (P2)

**Story goal**: Attaching a cert already linked to another letter requires explicit user confirmation.
**Independent test**: Attach cert C to Letter A → try to attach C to Letter B → dialog appears → confirm → C is on B only.

- [ ] T014 [US2] In `frontend/lib/services/letter_service.dart`, when `createLetter`/`updateLetter` receive HTTP 409 with body `{"error":"certificates_already_linked","conflicts":[...]}`, throw a dedicated `CertificatesAlreadyLinkedException` carrying the conflicts list.
- [ ] T015 [US2] In `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart` save handler, catch `CertificatesAlreadyLinkedException`, show an `AlertDialog` listing the conflicting certificate numbers and the message "This certificate is already linked to another letter. Reassign it?" with Confirm/Cancel. On Confirm, retry the save with `forceReassign: true`.

## Phase 5: User Story 3 — Preserve Unlink On Delete (P3)

**Story goal**: Deleting a letter leaves its certificates intact but unlinked.
**Independent test**: Delete letter with 2 linked certs → both certs still exist with `letter_id IS NULL` and `letter_link_order IS NULL`.

- [ ] T016 [US3] Manually verify T009 covers this story — no new code. Add a quickstart step executing the scenario against a staging DB.

## Phase 6: Polish & Cross-Cutting

- [ ] T017 Execute [quickstart.md](quickstart.md) end-to-end on staging. Capture the combined PDF and attach to the PR.
- [ ] T018 [P] Update `CLAUDE.md` "Active Technologies" section to note `pypdf` (backend) under feature 029.

---

## Dependency Graph

```text
T001 ─┐
T002 ─┤
T003 ─┤                               (Phase 1+2 — no ordering between T002/T004)
T004 ─┤
      ▼
T005 → T006 → T007 → T008 → T009 → T010    (US1 backend, sequential — same file)
                                    │
                                    ▼
T011 [P] ── T012 [P] ── T013         (US1 frontend; T013 depends on T011 + T012 + T004)
                           │
                           ▼
T014 → T015                          (US2)
                           │
                           ▼
T016                                 (US3)
                           │
                           ▼
T017, T018 [P]                       (Polish)
```

**MVP scope**: T001–T013 (Setup + Foundational + US1) delivers a working merged PDF export. US2 and US3 are enhancements/regression guards.

---

## Implementation Prompts

--- IMPLEMENTATION PROMPT T001 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: SQL
File: supabase/migrations/20260407_letter_cert_link_order.sql
Task: Create a new Supabase migration file that adds a nullable INTEGER column `letter_link_order` to `payment_certificates` and a composite index on `(letter_id, letter_link_order)`.
Signatures required:
  - `ALTER TABLE payment_certificates ADD COLUMN IF NOT EXISTS letter_link_order INTEGER NULL;`
  - `CREATE INDEX IF NOT EXISTS idx_payment_certificates_letter_order ON payment_certificates(letter_id, letter_link_order);`
Constraints: Pure SQL. Idempotent (IF NOT EXISTS). No other table changes.
Acceptance criteria: Running the migration against a database that already has feature 026 applied adds the new column and index without error; re-running it is a no-op.
--- END PROMPT T001 ---

--- IMPLEMENTATION PROMPT T002 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python (requirements file)
File: backend/requirements.txt
Task: Append `pypdf>=4.0` as a new line in alphabetical position. Do not remove or reorder existing lines.
Signatures required: N/A
Constraints: Preserve existing pinnings and comments.
Acceptance criteria: `pip install -r backend/requirements.txt` installs pypdf alongside existing deps; other pins are untouched.
--- END PROMPT T002 ---

--- IMPLEMENTATION PROMPT T003 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: Locate the `LetterBodyV2` Pydantic model and add two new optional fields: `payment_certificate_ids: list[str] = []` and `force_reassign: bool = False`. Do not touch any other field or any function in the file.
Signatures required:
  - `payment_certificate_ids: list[str] = []`
  - `force_reassign: bool = False`
Constraints: Use `list[str]` (PEP 585) consistent with surrounding code; keep field ordering stable — add at the end of the class body.
Acceptance criteria: `LetterBodyV2(**existing_payload)` continues to work; new payloads including the two fields parse correctly; omitted fields default to empty list / False.
--- END PROMPT T003 ---

--- IMPLEMENTATION PROMPT T004 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/models/generated_letter.dart
Task: Add a nested class `LinkedPaymentCertificate` with fields `final String id; final String certificateNumber; final String subject; final int letterLinkOrder;`, plus `factory LinkedPaymentCertificate.fromJson(Map<String, dynamic> json)` and `Map<String, dynamic> toJson()`. Extend `GeneratedLetter` with `final List<LinkedPaymentCertificate> linkedPaymentCertificates`, default `const []`. Update `GeneratedLetter.fromJson` to parse the existing `payment_certificates` array into this list (tolerate absent/null).
Signatures required:
  - `class LinkedPaymentCertificate { final String id; final String certificateNumber; final String subject; final int letterLinkOrder; ... }`
  - `factory LinkedPaymentCertificate.fromJson(Map<String, dynamic> json)`
  - `final List<LinkedPaymentCertificate> linkedPaymentCertificates;` on `GeneratedLetter`
Constraints: Preserve existing GeneratedLetter public API; do not rename any existing field; use `json['letter_link_order'] ?? 0` for the int; use `json['certificate_number'] ?? ''` and `json['subject'] ?? ''`. No new imports beyond what is already there unless strictly needed.
Acceptance criteria: Loading an existing letter JSON that includes `payment_certificates: [{ id, certificate_number, subject, letter_link_order }]` produces a `GeneratedLetter` with a populated `linkedPaymentCertificates` list; letters without the field produce an empty list.
--- END PROMPT T004 ---

--- IMPLEMENTATION PROMPT T005 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: Add a new helper `_apply_cert_links(letter_id: str, cert_ids: list[str], force_reassign: bool) -> list[dict]`. Steps:
  1. Fetch all rows from `payment_certificates` currently having `letter_id == letter_id` — call this `previously_linked`.
  2. For each id in `cert_ids`, fetch the cert row. If the row does not exist, raise `HTTPException(404, f"payment_certificate {id} not found")`.
  3. Collect conflicts: any requested cert whose current `letter_id` is not None and != `letter_id` and `force_reassign` is False.
  4. If conflicts exist, raise `HTTPException(status_code=409, detail={"error":"certificates_already_linked","conflicts":[{"certificate_id": c["id"], "existing_letter_id": c["letter_id"]} for c in conflicts]})`.
  5. For each cert in `previously_linked` whose id is NOT in `cert_ids`: update with `{"letter_id": None, "letter_link_order": None}`.
  6. For index, cid in enumerate(cert_ids): update the cert row with `{"letter_id": letter_id, "letter_link_order": index}`.
  7. Return a list of the final linked certs (id, certificate_number, subject, letter_link_order) ordered by letter_link_order.
Signatures required:
  - `def _apply_cert_links(letter_id: str, cert_ids: list[str], force_reassign: bool) -> list[dict]:`
Constraints: Use the existing `supabase` client imported at the top of the file. Match surrounding style (no async — this is a sync helper called from async handlers). Do not add new imports besides possibly `HTTPException` if missing.
Acceptance criteria: Calling with conflicting ids and `force_reassign=False` raises 409 with the correct payload. Calling with valid ids sets the FK and order correctly, and any previously-linked cert not in the new list is cleared.
--- END PROMPT T005 ---

--- IMPLEMENTATION PROMPT T006 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: In `create_letter_v2` (the POST `/letters-v2` handler), immediately after the letter row is inserted and `letter_id` is determined (around line 230), call `_apply_cert_links(str(letter_id), data.payment_certificate_ids, data.force_reassign)`. Do not alter any other behavior. Keep PDF generation and response unchanged.
Signatures required: N/A (modifying existing function body only)
Constraints: Must run after the letter is inserted so `letter_id` exists. Do not wrap in try/except — let HTTPException propagate.
Acceptance criteria: Creating a letter with `payment_certificate_ids: ["u1","u2"]` persists `letter_id` + `letter_link_order` on both certs; conflicts surface as HTTP 409.
--- END PROMPT T006 ---

--- IMPLEMENTATION PROMPT T007 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: In `update_letter_v2` (the PUT `/letters-v2/{letter_id}` handler), immediately after the `generated_letters.update(...)` call, call `_apply_cert_links(letter_id, data.payment_certificate_ids, data.force_reassign)`. Do not alter any other behavior.
Signatures required: N/A
Constraints: Same as T006.
Acceptance criteria: PUT request updating a letter with a new cert id list reflects the changes in `payment_certificates`, including unlinking certs removed from the list.
--- END PROMPT T007 ---

--- IMPLEMENTATION PROMPT T008 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: In `get_letters_v2` (GET `/letters-v2`), modify the inner supabase query that fetches linked payment certificates so it selects `"id, certificate_number, subject, letter_link_order"` and adds `.order("letter_link_order")` before `.execute()`.
Signatures required: N/A
Constraints: Do not change the outer function signature or response shape besides the added field inside each cert dict.
Acceptance criteria: GET response returns `payment_certificates` entries with `letter_link_order` present and sorted ascending.
--- END PROMPT T008 ---

--- IMPLEMENTATION PROMPT T009 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: In `delete_letter_v2`, change the existing unlink statement from `.update({"letter_id": None})` to `.update({"letter_id": None, "letter_link_order": None})`. No other changes.
Signatures required: N/A
Constraints: Keep the `.eq("letter_id", letter_id)` filter intact.
Acceptance criteria: Deleting a letter resets both fields on every previously linked cert.
--- END PROMPT T009 ---

--- IMPLEMENTATION PROMPT T010 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: Add a new endpoint:

    @router.post("/letters-v2/{letter_id}/export-with-attachments")
    async def export_with_attachments(
        letter_id: str,
        letter_body: str = Form(...),
        order: str = Form(...),
        requester_email: str = Form(...),
        files: list[UploadFile] = File(default=[]),
    ):

Behavior:
  1. Fetch letter row by id; 404 if missing.
  2. Permission: allow if `rec["created_by_email"] == requester_email` OR the requester's role (looked up from `users` table by email) is `admin`. Otherwise 403.
  3. Parse `letter_body` JSON string into `LetterBodyV2(**json.loads(letter_body))`.
  4. Parse `order` JSON into `list[str]` of cert ids.
  5. Build `letter_pdf = _build_letter_pdf_v2(body)`.
  6. Create `writer = pypdf.PdfWriter()` and append the letter pdf: `writer.append(pypdf.PdfReader(io.BytesIO(letter_pdf)))`.
  7. Build a filename→bytes map from `files` (key = `f.filename`, value = `await f.read()`).
  8. For each cid in `order`: if cid not in map → raise 422 `{"error":"missing_cert_upload","certificate_id":cid}`. Otherwise `writer.append(pypdf.PdfReader(io.BytesIO(map[cid])))`.
  9. Serialize `writer` to `io.BytesIO`, read bytes.
  10. `log_activity(requester_email, "exported", "letter", letter_id)`.
  11. Return `Response(content=merged_bytes, media_type="application/pdf", headers={"Content-Disposition": f'attachment; filename="letter_{ts}.pdf"'})` where `ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")`.

Signatures required:
  - `async def export_with_attachments(letter_id: str, letter_body: str = Form(...), order: str = Form(...), requester_email: str = Form(...), files: list[UploadFile] = File(default=[]))`
Constraints: Add `import io, json, pypdf` at the top if not present; use `from fastapi import Form, File, UploadFile` (add to the existing fastapi import line). Do not modify existing endpoints.
Acceptance criteria: POSTing multipart with a valid letter_body, an `order` list, and matching cert PDF files returns a single application/pdf response whose page count equals letter pages + sum of cert pages. 403 for unauthorized. 422 for missing uploads.
--- END PROMPT T010 ---

--- IMPLEMENTATION PROMPT T011 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/services/letter_service.dart
Task:
  1. Extend `createLetter` and `updateLetter` methods with named parameters `List<String> paymentCertificateIds = const []` and `bool forceReassign = false`, and include `"payment_certificate_ids": paymentCertificateIds` and `"force_reassign": forceReassign` in the JSON body sent.
  2. When either method receives an HTTP 409 response whose body decodes to a map with `error == "certificates_already_linked"`, throw `CertificatesAlreadyLinkedException(conflicts)` (see T014 — for now define the exception class at the bottom of this file if it doesn't already exist, holding `final List<Map<String, dynamic>> conflicts`).
  3. Add new method:
     ```
     Future<Uint8List> exportLetterWithAttachments({
       required String letterId,
       required Map<String, dynamic> letterBody,
       required List<String> orderedCertIds,
       required Map<String, Uint8List> certPdfs,
       required String requesterEmail,
     }) async
     ```
     that builds a `http.MultipartRequest('POST', Uri.parse('$baseUrl/letters-v2/$letterId/export-with-attachments'))`, adds fields `letter_body = jsonEncode(letterBody)`, `order = jsonEncode(orderedCertIds)`, `requester_email = requesterEmail`, and for each entry in `certPdfs` adds `http.MultipartFile.fromBytes('files', bytes, filename: certId, contentType: MediaType('application','pdf'))`. Sends the request and returns `response.bodyBytes` on 200; throws on non-200.
Signatures required: see above.
Constraints: Use the existing `baseUrl` constant / pattern already used in this file. Add imports `dart:convert`, `dart:typed_data`, `package:http/http.dart as http`, `package:http_parser/http_parser.dart` only if missing. Do not reformat unrelated code.
Acceptance criteria: New parameters reach the backend; 409 responses throw the typed exception; the new export method returns the merged PDF bytes from a successful multipart call.
--- END PROMPT T011 ---

--- IMPLEMENTATION PROMPT T012 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/letters_v2/widgets/payment_cert_picker.dart
Task: Create a new Flutter widget file. Export:

    class PaymentCertPicker extends StatefulWidget {
      final List<String> alreadySelectedIds;
      const PaymentCertPicker({super.key, required this.alreadySelectedIds});

      static Future<List<PaymentCertificate>?> show(
        BuildContext context, {
        required List<String> alreadySelectedIds,
      }) => showModalBottomSheet<List<PaymentCertificate>>(
            context: context,
            isScrollControlled: true,
            builder: (_) => PaymentCertPicker(alreadySelectedIds: alreadySelectedIds),
          );

      @override
      State<PaymentCertPicker> createState() => _PaymentCertPickerState();
    }

State behavior:
  - On init: call `PaymentCertificateService().listAll()` to load all certificates. Show a CircularProgressIndicator while loading.
  - Render a `TextField` for search (filter by `certificate_number` and `subject`, case-insensitive).
  - Render a scrollable `ListView` of `CheckboxListTile` rows excluding certs whose id is in `alreadySelectedIds`.
  - Bottom row: `TextButton("Cancel")` pops null; `ElevatedButton("Add")` pops the list of selected `PaymentCertificate` objects.

Signatures required: see above.
Constraints: Imports: `package:flutter/material.dart`, the project's `PaymentCertificate` model, and `PaymentCertificateService`. Do not add any new dependency. Keep file under ~200 lines.
Acceptance criteria: Opening the picker from any screen and selecting two certs returns those two as a `List<PaymentCertificate>`; cancelling returns null; already-selected ids are not shown.
--- END PROMPT T012 ---

--- IMPLEMENTATION PROMPT T013 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: Extend the existing letter form screen.
  1. Add state field `List<LinkedPaymentCertificate> _linkedCerts = []`. In `initState` (or wherever the letter is loaded), populate from `widget.letter?.linkedPaymentCertificates ?? []`.
  2. Below the existing form fields, add a new `Column` labeled "Attachments" containing:
     - A `ReorderableListView.builder` binding to `_linkedCerts`, each item a `ListTile(key: ValueKey(cert.id), title: Text(cert.certificateNumber), subtitle: Text(cert.subject), trailing: IconButton(Icons.delete, onPressed: () => setState(() => _linkedCerts.removeAt(index))))`. On reorder, update the list order.
     - An `OutlinedButton.icon(icon: Icons.add, label: "Add Payment Certificate")` whose onPressed calls `PaymentCertPicker.show(context, alreadySelectedIds: _linkedCerts.map((c)=>c.id).toList())`. On non-null result, map each selected `PaymentCertificate` to a `LinkedPaymentCertificate` (letterLinkOrder = current length) and append to `_linkedCerts` inside `setState`.
  3. In the save handler, pass `paymentCertificateIds: _linkedCerts.map((c) => c.id).toList()` to `LetterService.createLetter` / `updateLetter`.
  4. Add an `ElevatedButton.icon(icon: Icons.picture_as_pdf, label: "Export Combined PDF")` whose onPressed:
     a. Shows a loading dialog.
     b. For each `LinkedPaymentCertificate` in `_linkedCerts`, fetch the full `PaymentCertificate` via `PaymentCertificateService().getById(id)`, then generate `Uint8List pdfBytes = await PaymentCertificatePdfService().buildPdf(cert)`.
     c. Build `letterBody` map matching the LetterBodyV2 shape from the current form state.
     d. Call `LetterService().exportLetterWithAttachments(letterId: widget.letter!.id, letterBody: letterBody, orderedCertIds: _linkedCerts.map((c)=>c.id).toList(), certPdfs: {for (var e in entries) e.id: e.bytes}, requesterEmail: currentUserEmail)`.
     e. On success, trigger browser download of the returned bytes via the existing download helper used elsewhere in this file.
     f. Dismiss loading dialog; show SnackBar on error.
Signatures required: State-level modifications; no new public methods required.
Constraints: Do not rename existing widgets or state fields. Add imports only for `PaymentCertPicker`, `PaymentCertificatePdfService`, `PaymentCertificateService`, `LinkedPaymentCertificate`. Reuse existing download helper already imported in this file (if none, import via conditional import matching pattern used in other letters_v2 files). Do not touch the existing letter body fields' logic.
Acceptance criteria: Opening an existing letter shows previously linked certs; adding/removing/reordering updates the list; Save persists the cert ids; Export downloads a single combined PDF (verified by opening the file).
--- END PROMPT T013 ---

--- IMPLEMENTATION PROMPT T014 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/services/letter_service.dart
Task: Ensure `CertificatesAlreadyLinkedException` is declared (if T011 placed it at file bottom, leave it; otherwise add it now) with:

    class CertificatesAlreadyLinkedException implements Exception {
      final List<Map<String, dynamic>> conflicts;
      CertificatesAlreadyLinkedException(this.conflicts);
      @override
      String toString() => 'CertificatesAlreadyLinkedException(${conflicts.length} conflicts)';
    }

Confirm that both `createLetter` and `updateLetter` throw this exception on HTTP 409 with body `{"error":"certificates_already_linked","conflicts":[...]}`.
Signatures required: see above.
Constraints: No duplication — if already defined, this task is a no-op.
Acceptance criteria: Importing `CertificatesAlreadyLinkedException` from the letter service works; both methods throw it on 409.
--- END PROMPT T014 ---

--- IMPLEMENTATION PROMPT T015 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: In the save handler, wrap the `createLetter`/`updateLetter` call in `try/catch`. Catch `CertificatesAlreadyLinkedException` and show an `AlertDialog` with:
  - Title: `"Reassign payment certificate?"`
  - Content: A message listing the conflicting certificate ids (`e.conflicts.map((c) => c['certificate_id']).join(', ')`) and the text `"These certificates are already linked to another letter. Reassign them to this letter?"`
  - Actions: `TextButton("Cancel")` that dismisses, `ElevatedButton("Reassign")` that dismisses and retries the same save call with `forceReassign: true`.
Signatures required: N/A (modifying save handler only)
Constraints: Do not add any new state fields for this; perform retry inline. Import `CertificatesAlreadyLinkedException` from `letter_service.dart`.
Acceptance criteria: Saving a letter that includes an already-linked cert shows the dialog; tapping Reassign completes the save successfully; tapping Cancel leaves the form unchanged.
--- END PROMPT T015 ---

--- IMPLEMENTATION PROMPT T016 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: (verification — no code)
File: specs/029-link-cert-letter/quickstart.md
Task: Append a section "US3 verification" describing: create a letter with 2 linked certs, delete the letter, then run the SQL `SELECT id, letter_id, letter_link_order FROM payment_certificates WHERE id IN ('<id1>','<id2>');` and confirm both rows show `letter_id IS NULL` and `letter_link_order IS NULL`.
Signatures required: N/A
Constraints: Documentation only.
Acceptance criteria: quickstart.md contains an explicit US3 verification procedure.
--- END PROMPT T016 ---

--- IMPLEMENTATION PROMPT T017 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: (manual verification)
File: N/A
Task: Execute every step of specs/029-link-cert-letter/quickstart.md against staging. Record pass/fail per step. Save the downloaded merged PDF as evidence and attach it to the PR description.
Signatures required: N/A
Constraints: Do not modify source code; this is a verification step.
Acceptance criteria: All quickstart steps pass; merged PDF attached to PR.
--- END PROMPT T017 ---

--- IMPLEMENTATION PROMPT T018 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Markdown
File: CLAUDE.md
Task: Under the `## Active Technologies` section, add a new bullet for feature 029:
`- Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, pypdf (backend — NEW); http, Flutter pdf, existing PaymentCertificatePdfService (frontend) (029-link-cert-letter)`
Also append a bullet under `## Recent Changes`:
`- 029-link-cert-letter: Added pypdf (backend) for merged letter+cert PDF export`
Signatures required: N/A
Constraints: Do not remove or reorder existing bullets. Do not touch any other section.
Acceptance criteria: CLAUDE.md shows the new entries in the two target sections.
--- END PROMPT T018 ---
