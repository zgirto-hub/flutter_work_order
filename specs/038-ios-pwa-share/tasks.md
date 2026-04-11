---
description: "Task list for feature 038-ios-pwa-share"
---

# Tasks: iOS PWA Native Share for Letters & Work Order PDFs

**Input**: Design documents from `C:\Development\flutter_work_order\specs\038-ios-pwa-share\`
**Prerequisites**:
- [plan.md](plan.md)
- [spec.md](spec.md)
- [research.md](research.md)
- [data-model.md](data-model.md)
- [contracts/activity-log-shared.md](contracts/activity-log-shared.md)
- [quickstart.md](quickstart.md)

**Tests**: NOT requested for this feature. Per [research.md](research.md) decision 9, validation is manual via the [quickstart.md](quickstart.md) device matrix. No automated test tasks are included in this list.

**Audience**: This list is written for an implementer agent. Follow each task **in order** unless a task is marked `[P]` (parallelizable, different file, no dependency on an incomplete task). Each task includes the exact file path, the exact change, and a "Done when" acceptance check.

**Format**: `- [ ] [TaskID] [P?] [Story?] Description — Done when: <check>`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Read the context you need. This is a frontend-heavy change to an existing Flutter web app; there is no project scaffolding to create.

- [X] T001 Read [plan.md](plan.md), [research.md](research.md), and [contracts/activity-log-shared.md](contracts/activity-log-shared.md) end-to-end before writing any code. The research doc contains 9 numbered decisions you will be implementing verbatim; the contracts doc contains the exact endpoint shape. — Done when: you can name the six files you will touch without re-reading the plan.

- [X] T002 [P] Open the following existing files in read-only mode to build a mental model of the current code; do NOT edit them in this task:
  - `frontend/lib/services/download_helper_web.dart` (existing iOS share-sheet implementation you will extend)
  - `frontend/lib/services/download_helper.dart` (conditional-import façade pattern — use as a template for `share_capability.dart`)
  - `frontend/lib/services/download_helper_mobile.dart` (native stub — use as a template)
  - `frontend/lib/services/activity_log_service.dart` (existing `logSignIn` / `logSignOut` / `logUpdateCheck` methods — use as the template for `logShared`)
  - `frontend/lib/screens/letters_v2/letter_html_viewer_screen.dart` (the primary US1 target)
  - `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart` (search for `_generatePdf` and the `LetterHtmlViewerScreen(` constructor call around line 392)
  - `frontend/lib/screens/letters_v2/letter_history_tab_v2.dart` (search for `_previewLetter` around line 79)
  - `frontend/lib/widgets/pdf_preview_screen.dart` (the primary US2 target)
  - `frontend/lib/screens/Work_Orders/work_order_home.dart` lines 1305–1334 (the `onExportPdf` call site — you do NOT modify this file, but you need to know the shape of `buildPdf`)
  - `backend/routers/activity_log.py` (if it exists — confirm path; if the activity log router lives elsewhere, locate it via grep for `/activity-log/sign-in`)
  - `backend/utils/activity.py` (confirm the helper function name and signature used to write `user_activity_log` rows)
  - Done when: you have confirmed the exact path to the backend activity log router and the exact signature of the activity-log helper function.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the shared infrastructure (share helper, capability gate, audit endpoint, audit service method) that both US1 and US2 depend on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete. The letter viewer (US1) and the PDF preview screen (US2) both consume `sharePdfBytes`, `canUseNativeShareControl`, and `ActivityLogService.logShared`. Do not start Phase 3 before all foundational tasks are ticked off.

### Frontend foundation

- [X] T003 **Extend `frontend/lib/services/download_helper_web.dart`** with a new public function `sharePdfBytes` that takes bytes directly (no URL fetch) and a `title` for the share sheet source label:
  ```dart
  /// Share PDF bytes via the native share sheet.
  /// - [bytes]: the PDF payload (must be non-empty)
  /// - [fileName]: ASCII-safe filename ending in .pdf (e.g. "letter_abc12345.pdf", "WO-123.pdf")
  /// - [title]: UTF-8 title shown in the share sheet source label (may be Arabic)
  ///
  /// Behaviour:
  /// 1. If `navigator.canShare({files: [file]})` is true, opens the native share sheet.
  ///    - Cancellation (AbortError) is a silent no-op (returns normally).
  ///    - Other share errors propagate as thrown exceptions.
  /// 2. If `canShare` returns false, the share promise throws a non-cancel error,
  ///    or blob/file construction fails, fall back to anchor-download
  ///    (PDF saved to the device's Files/Downloads), NOT open-in-new-tab.
  Future<void> sharePdfBytes(
    Uint8List bytes,
    String fileName,
    String title,
  ) async { ... }
  ```
  Implementation details:
  - Defensive filename: if `fileName` does not end in `.pdf` (case-insensitive), append `.pdf` before building the `File`.
  - Throw a `StateError('empty PDF bytes')` if `bytes.isEmpty` — call site must handle.
  - Build the `Blob` with `type: 'application/pdf'`. Build the `File` with the same MIME type and the filename.
  - Build the `shareData` JS object with `files: [file]` and `title: title` (pattern matches existing `_buildShareData` helper — reuse or duplicate as needed).
  - Wrap `_canShare(shareData)` in try/catch returning `false` on error (match existing pattern at lines 56–61).
  - On successful `canShare`: `await _share(shareData).toDart;` inside try/catch.
    - If the error message contains `AbortError`, `cancel`, or `abort` → return silently (no fallback).
    - Any other error → fall through to the anchor-download fallback (do NOT throw to caller; treat as "best effort saved to Files").
  - Anchor-download fallback: create a `Blob` URL via `web.URL.createObjectURL(blob)`, invoke the existing `_anchorDownload(blobUrl, fileName)` helper, then `web.URL.revokeObjectURL(blobUrl)` on a short `Future.delayed` (match the 150ms pattern used at line 108).
  - Return type is `Future<void>`. The function does not need to signal which path was taken; the caller shows the same confirmation either way (the share sheet is self-evident; the anchor-download shows a "Saved to Files" snackbar from the caller).

  — Done when: `sharePdfBytes` is exported from `download_helper_web.dart`, the file compiles in a web build, and the anchor-download fallback branch is exercisable (verify by temporarily forcing `canShare` to return false during a throwaway manual test).

- [X] T004 **Change the existing iOS fallback in `_iosShare` (same file, `frontend/lib/services/download_helper_web.dart`)** from `_openInNewTab(url)` to `_anchorDownload(url, fileName)`. This is the existing URL-based `downloadFile` → `_iosShare` path used by attachments (NOT the new `sharePdfBytes` path from T003). Locate the line `_openInNewTab(url);` at approximately line 83 of the current file and replace it with `_anchorDownload(url, fileName);`. This ensures ALL mobile fallbacks across the helper consistently save-to-Files instead of kicking to Safari, per the Q2 clarification in [spec.md](spec.md) and FR-013.
  **Preserve** the top-level `openInNewTab(String url)` public function (line 96–100) — it is still used elsewhere in the codebase (desktop call sites). Only change the fallback path inside `_iosShare`.
  — Done when: `grep -n "_openInNewTab" frontend/lib/services/download_helper_web.dart` shows `_openInNewTab` is still defined as a private helper and is still called by the public `openInNewTab(String)` wrapper, but is NO LONGER called from inside `_iosShare`.

- [X] T005 [P] **Create `frontend/lib/services/share_capability.dart`** as a conditional-import façade, following the exact pattern of `download_helper.dart`:
- [X] T006 [P] **Create `frontend/lib/services/share_capability_stub.dart`** with a single top-level function:
- [X] T007 [P] **Create `frontend/lib/services/share_capability_web.dart`** with a top-level function that UA-sniffs for iOS or Android mobile Chrome:
  ```dart
  import 'package:web/web.dart' as web;

  /// Returns true on mobile form factors where the native share sheet is the
  /// preferred affordance (iOS Safari installed PWA or regular tab, Android Chrome).
  /// Returns false on all desktop browsers regardless of `navigator.canShare` support —
  /// this is a FORM-FACTOR gate, not a capability gate (per spec clarification Q1).
  bool canUseNativeShareControl() {
    final ua = web.window.navigator.userAgent.toLowerCase();
    final isIos = ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
    // Android Chrome / Samsung Internet / etc. — "mobile" token is present on Android phone UAs.
    final isAndroid = ua.contains('android') && ua.contains('mobile');
    return isIos || isAndroid;
  }
  ```
  Do NOT call `navigator.canShare` here — the actual capability check happens inside `sharePdfBytes` at invocation time. This helper is purely about WHICH control to render in the AppBar.
  — Done when: the file compiles, and calling `canUseNativeShareControl()` in a web build returns `true` under an iOS user agent and `false` under a Windows/macOS Chrome user agent.

### Backend foundation

- [X] T008 **Add `POST /activity-log/shared` to the backend activity log router** (exact file: `backend/routers/users.py` — confirmed path in T002 via activity-log routes). The implementation must match the contract in [contracts/activity-log-shared.md](contracts/activity-log-shared.md) exactly:
  ```python
  from pydantic import BaseModel
  from fastapi import HTTPException
  from backend.utils.activity import log_activity  # verify exact import in T002

  class SharedLogBody(BaseModel):
      user_email: str
      document_type: str
      document_id: str

  @router.post("/activity-log/shared")
  async def log_shared(body: SharedLogBody):
      if body.document_type not in ("letter", "work_order"):
          raise HTTPException(
              status_code=400,
              detail="document_type must be 'letter' or 'work_order'",
          )
      category = "work_order" if body.document_type == "work_order" else "file"
      log_activity(
          user_email=body.user_email,
          category=category,
          action="shared",
          target_type=body.document_type,
          target_id=body.document_id,
      )
      return {"status": "logged"}
  ```
  **CRITICAL**: verify the actual helper function signature in `backend/utils/activity.py` during T002 — if the helper is named differently (e.g., `write_activity_log`, `log_user_activity`) or takes different keyword arguments, adapt the call accordingly. Do NOT invent new columns; only pass arguments the existing helper accepts. If the helper does not accept `target_type`/`target_id` keyword arguments, fall back to encoding them into whatever "details" / "metadata" field exists, or adjust the helper with a minimal additive change (and note it as a deviation in a comment).
  — Done when: running `curl -X POST http://localhost:<port>/activity-log/shared -H 'Content-Type: application/json' -d '{"user_email":"test@example.com","document_type":"letter","document_id":"test-id"}'` returns `{"status":"logged"}` with HTTP 200, and `{"document_type":"bogus",...}` returns HTTP 400.

- [X] T009 **Extend `frontend/lib/services/activity_log_service.dart`** with a `logShared` method that matches the existing fire-and-forget pattern in `logSignIn` / `logSignOut` / `logUpdateCheck`. Exact implementation:
  ```dart
  Future<void> logShared({
    required String documentType,  // 'letter' or 'work_order'
    required String documentId,
  }) async {
    try {
      await http.post(
        Uri.parse('${AppConfig.baseUrl}/activity-log/shared'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': Supabase.instance.client.auth.currentUser?.email ?? '',
          'document_type': documentType,
          'document_id': documentId,
        }),
      );
    } catch (_) {}
  }
  ```
  You will need to add `import 'package:supabase_flutter/supabase_flutter.dart';` at the top of the file if it is not already present. Errors are swallowed silently — the share action never blocks on the audit write.
  — Done when: the file compiles, `logShared` is a public method on `ActivityLogService`, and the import for `supabase_flutter` is present.

**Checkpoint**: Foundation ready. `sharePdfBytes`, `canUseNativeShareControl`, the backend `/activity-log/shared` endpoint, and `ActivityLogService.logShared` all exist and work. US1 and US2 can now be implemented in parallel.

---

## Phase 3: User Story 1 — Share a generated letter from iPhone PWA (Priority: P1) 🎯 MVP

**Goal**: A user on iOS PWA can open a letter in the HTML viewer, tap a share control in the AppBar, and the native share sheet opens with a PDF of the letter. Cancellation leaves them on the same screen. Desktop users still see "Open in new tab".

**Independent Test**: Run rows 1, 2, 3 (and desktop rows 5–8 regression) of [quickstart.md](quickstart.md) § "Letters V2 — share from the HTML viewer". If those pass, this story is done.

**Maps to spec sections**: [spec.md](spec.md) User Story 1, FR-001, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-010, FR-011, FR-012, FR-013, FR-015.

### Implementation for User Story 1

- [X] T010 [US1] **Modify `frontend/lib/screens/letters_v2/letter_html_viewer_screen.dart`** to add an `onShare` callback parameter and conditionally render the share control on mobile or the "Open in new tab" control on desktop. Exact changes:
  1. Add a new optional constructor parameter: `final Future<Uint8List> Function()? onShare;` alongside the existing `onGeneratePdf`. The callback returns PDF bytes when invoked.
  2. Add a new optional parameter: `final String? shareFileName;` — the ASCII-safe filename the share sheet should use. Caller provides this per research decision 3.
  3. Convert the class from `StatelessWidget` to `StatefulWidget` so it can track a `_isSharing` boolean for the loading/disabled state required by FR-012.
  4. Import `share_capability.dart` and `download_helper_web.dart` (the latter via the existing `if (dart.library.io)` conditional-import pattern — check how `file_viewer_web.dart` is already imported in this file at lines 7–8 and follow the same approach for `sharePdfBytes`).
  5. Import `activity_log_service.dart`.
  6. In the `build` method's AppBar `actions` list, replace the unconditional "Open in new tab" IconButton (currently at lines 56–61) with a conditional:
     ```dart
     if (onShare != null && canUseNativeShareControl())
       IconButton(
         icon: Icon(Icons.ios_share_rounded, size: 18, color: AppColors.textSecondary),
         tooltip: 'Share',
         onPressed: _isSharing ? null : _handleShare,
       )
     else
       IconButton(
         icon: Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.textSecondary),
         tooltip: 'Open in new tab (for printing)',
         onPressed: _openInNewTab,
       ),
     ```
     Keep the `Generate PDF` IconButton (currently lines 49–55) unchanged — it is orthogonal to this change.
  7. Implement `_handleShare`:
     ```dart
     Future<void> _handleShare() async {
       if (widget.onShare == null) return;
       setState(() => _isSharing = true);
       // Fire-and-forget audit (do NOT await)
       // Note: this screen doesn't know its own document id. The caller is
       // responsible for logging the audit — see T011 and T012. This handler
       // just fetches bytes and calls sharePdfBytes.
       try {
         final bytes = await widget.onShare!();
         final fileName = widget.shareFileName ?? 'letter.pdf';
         await sharePdfBytes(bytes, fileName, widget.title);
       } catch (e) {
         if (!mounted) return;
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Couldn\'t share PDF: $e')),
         );
       } finally {
         if (mounted) setState(() => _isSharing = false);
       }
     }
     ```
     NOTE on audit logging: the original plan called for `_handleShare` to fire the audit log, but the viewer screen does not have access to the letter id (only `title` and `html`). Push the audit log call to the caller (form tab + history tab) in T011 and T012. Add a TODO comment in `_handleShare` noting this: `// Audit log is fired by the caller (form tab / history tab) before invoking onShare, because this screen does not know the document id.`
  8. Preserve the existing `_openInNewTab` method. It is still used on desktop.
  — Done when: (a) the file compiles, (b) on a web build with an iOS user agent a letter viewer opened without `onShare` still shows "Open in new tab" (backward compatible), (c) opened with `onShare` it shows the share icon, (d) opened on a desktop user agent it shows "Open in new tab" regardless of whether `onShare` is provided.

- [X] T011 [US1] **Modify `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`** to supply the `onShare` callback when pushing `LetterHtmlViewerScreen`. Exact changes:
  1. Locate the `LetterHtmlViewerScreen(` constructor call at approximately line 392.
  2. Refactor the existing `_generatePdf` method: extract the PDF-byte-fetching logic (everything from `final body = { ... }` through `pdfBytes = await LetterService().generateV2(...) / updateV2(...)` including the `CertificatesAlreadyLinkedException` recovery path) into a new private method:
     ```dart
     Future<Uint8List> _buildPdfBytesForShare() async {
       // Same logic as _generatePdf's byte-fetching phase, but returns bytes
       // instead of downloading them. Does NOT call _downloadPdfBytes.
       if (!_formKey.currentState!.validate()) {
         throw Exception('Form validation failed');
       }
       final bodyHtml = await _getEditorHtml();
       if (bodyHtml.trim().isEmpty) {
         throw Exception('Please enter the letter body');
       }
       // ... rest identical to _generatePdf's body-assembly + generateV2/updateV2 call ...
       return pdfBytes;
     }
     ```
     Then have the existing `_generatePdf` call `_buildPdfBytesForShare()` followed by `_downloadPdfBytes(...)`. This keeps the existing Generate PDF button behaviour 100% unchanged while making the bytes reusable for share.
  3. In the `LetterHtmlViewerScreen(` constructor call, add:
     ```dart
     onShare: () async {
       // Fire-and-forget audit — don't await
       ActivityLogService().logShared(
         documentType: 'letter',
         documentId: _editingLetterId ?? 'new-letter',
       );
       return await _buildPdfBytesForShare();
     },
     shareFileName: 'letter_${DateTime.now().millisecondsSinceEpoch}.pdf',
     ```
  4. Add the necessary import: `import '../../services/activity_log_service.dart';`
  — Done when: (a) the file compiles, (b) the existing "Generate PDF" button still works and still downloads via `_downloadPdfBytes`, (c) on an iOS web build tapping the share icon in the form preview viewer successfully returns PDF bytes and invokes the share sheet.

- [X] T012 [US1] **Modify `frontend/lib/screens/letters_v2/letter_history_tab_v2.dart`** to supply the `onShare` callback when pushing `LetterHtmlViewerScreen`. Exact changes:
  1. Locate the `_previewLetter` method (approximately line 79) and the `LetterHtmlViewerScreen(` constructor call inside it (approximately lines 85–90).
  2. In the constructor call, add:
     ```dart
     onShare: () async {
       // Fire-and-forget audit — don't await
       ActivityLogService().logShared(
         documentType: 'letter',
         documentId: letterId,
       );
       return await LetterService().regenerateV2(letterId);
     },
     shareFileName: 'letter_${letterId.substring(0, letterId.length < 8 ? letterId.length : 8)}.pdf',
     ```
  3. Add the necessary imports:
     - `import '../../services/activity_log_service.dart';`
     - `import '../../services/letter_service.dart';` (verify it is not already imported — if it is, skip)
  4. Do NOT pass `onGeneratePdf` — the history tab does not currently do so, per existing code, so leave that unchanged.
  — Done when: (a) the file compiles, (b) on an iOS web build opening a saved letter from history and tapping the share icon successfully calls `regenerateV2` and invokes the share sheet with a PDF named `letter_<first8chars>.pdf`.

**Checkpoint for US1**: Run rows 1, 2, 3 of [quickstart.md](quickstart.md) § "Letters V2 — share from the HTML viewer → Mobile path", plus rows 5–8 desktop regression. All must pass before moving to US2.

---

## Phase 4: User Story 2 — Share a closed Work Order PDF from iPhone PWA (Priority: P1)

**Goal**: A user on iOS PWA can trigger the work order PDF export for a closed WO, and the `PdfPreviewScreen` that appears has a share icon in the AppBar that invokes the native share sheet with the WO PDF. The built-in `printing` toolbar actions (print/share/download) are hidden on mobile so there is exactly one share affordance.

**Independent Test**: Run rows 1, 2, 3 (and desktop rows 5–8 regression) of [quickstart.md](quickstart.md) § "Work Order PDF export — share from the preview".

**Maps to spec sections**: [spec.md](spec.md) User Story 2, FR-002, FR-003, FR-005, FR-006, FR-007, FR-009, FR-010, FR-011, FR-012, FR-013, FR-014, FR-015.

### Implementation for User Story 2

- [X] T013 [US2] **Modify `frontend/lib/widgets/pdf_preview_screen.dart`** to add a mobile-only AppBar share button, cache the `buildPdf()` result, and hide the `printing` package's built-in toolbar actions on mobile. Exact changes:
  1. Convert from `StatelessWidget` to `StatefulWidget` so the state can hold `Uint8List? _cachedBytes` and `bool _isSharing = false`.
  2. Add two new optional constructor parameters:
     - `final String? shareFileName;` — e.g., `"WO-123.pdf"`. If null, falls back to the existing `pdfFileName` logic.
     - `final String? documentId;` — the underlying WO id, used for audit logging. If null, audit logging is skipped.
     - `final String? documentType;` — e.g., `'work_order'`. If null, audit logging is skipped.
  3. Wrap the existing `buildPdf` callback in a closure that populates `_cachedBytes` on first call:
     ```dart
     Future<Uint8List> _buildAndCache() async {
       if (_cachedBytes != null) return _cachedBytes!;
       final bytes = await widget.buildPdf();
       _cachedBytes = bytes as Uint8List;
       return _cachedBytes!;
     }
     ```
     Pass the cached version to `PdfPreview.build`:
     ```dart
     build: (format) async => await _buildAndCache(),
     ```
     Note: the existing code casts to `dynamic`/`Uint8List` — preserve that behaviour.
  4. Import `share_capability.dart`, `download_helper_web.dart` (via conditional import — use the same pattern as the letter viewer), and `activity_log_service.dart`.
  5. Add a boolean `_isMobile` computed in `build` as `canUseNativeShareControl()`.
  6. Set `allowPrinting: !_isMobile` and `allowSharing: !_isMobile` on the `PdfPreview` widget. **Verify** these parameter names against the `printing` package version actually used in `pubspec.yaml` (the package is at `^5.12.0` per `CLAUDE.md`). If the parameter names differ, use the correct ones. The goal is to suppress the printing package's built-in print button, share button, and (if possible) download button on mobile.
  7. Add a mobile-only share IconButton to the AppBar actions:
     ```dart
     actions: [
       if (_isMobile)
         IconButton(
           icon: Icon(Icons.ios_share_rounded, size: 18, color: AppColors.textSecondary),
           tooltip: 'Share',
           onPressed: _isSharing ? null : _handleShare,
         ),
     ],
     ```
  8. Implement `_handleShare`:
     ```dart
     Future<void> _handleShare() async {
       setState(() => _isSharing = true);
       // Fire-and-forget audit (only if caller provided the doc identifiers)
       if (widget.documentType != null && widget.documentId != null) {
         ActivityLogService().logShared(
           documentType: widget.documentType!,
           documentId: widget.documentId!,
         );
       }
       try {
         final bytes = await _buildAndCache();
         final fileName = widget.shareFileName ??
             '${widget.title.replaceAll(' ', '_')}.pdf';
         await sharePdfBytes(bytes, fileName, widget.title);
       } catch (e) {
         if (!mounted) return;
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Couldn\'t share PDF: $e')),
         );
       } finally {
         if (mounted) setState(() => _isSharing = false);
       }
     }
     ```
  9. **Preserve backward compatibility**: existing callers at `workorder_report_screen.dart`, `add_work_order.dart`, and `payment_certificate_list_screen.dart` do NOT pass `shareFileName`/`documentId`/`documentType`. On mobile those screens will still show the share button, but without audit logging (because the identifiers are null). That is acceptable — this feature only requires audit logging on the WO export path, which we wire next in T014. Those other screens benefit from the session-preserving share path as a free side benefit and do NOT need to change.
  — Done when: (a) the file compiles, (b) on an iOS web build the share icon appears in the AppBar and the built-in printing toolbar actions are hidden, (c) on a desktop web build the share icon does NOT appear and the built-in printing toolbar is unchanged from current production, (d) the `_buildAndCache` closure is called at most once per mount when the page format is unchanged.

- [X] T014 [US2] **Modify `frontend/lib/screens/Work_Orders/work_order_home.dart`** to pass `shareFileName`, `documentId`, and `documentType` into the `PdfPreviewScreen` constructor at approximately line 1314. Exact changes:
  1. Locate the `PdfPreviewScreen(` constructor call inside `onExportPdf` (lines ~1311–1324).
  2. Add three new arguments:
     ```dart
     shareFileName: 'WO-${wo.jobNo ?? "unknown"}.pdf',
     documentId: wo.id,
     documentType: 'work_order',
     ```
  3. Do NOT touch the rest of the `onExportPdf` closure, the gating (`wo.status.toLowerCase() == 'closed'`), or the error handling — they are already correct per FR-014.
  — Done when: (a) the file compiles, (b) on an iOS web build, exporting a closed WO shows `PdfPreviewScreen` with the share icon and the shared file is named `WO-<jobNo>.pdf`, (c) the audit log receives a `shared` row with `target_type='work_order'`, `target_id=<wo.id>` when the share button is tapped.

**Checkpoint for US2**: Run rows 1, 2, 3 of [quickstart.md](quickstart.md) § "Work Order PDF export — share from the preview → Mobile path", plus rows 5–8 desktop regression. All must pass before moving to US3.

---

## Phase 5: User Story 3 — Desktop keeps the existing "Open in new tab" behaviour (Priority: P2)

**Goal**: Verify (not implement) that desktop browsers are entirely unaffected by this feature. This story is a **regression guarantee**, not new code — the form-factor gate in `canUseNativeShareControl()` already ensures desktop follows the existing path.

**Independent Test**: Run rows 5, 6, 7, 8 of [quickstart.md](quickstart.md) § "Letters V2 — Desktop regression" AND § "Work Order PDF export — Desktop regression". No mobile steps needed.

**Maps to spec sections**: [spec.md](spec.md) User Story 3, FR-005.

### Validation for User Story 3

- [ ] T015 [P] [US3] **Verify the letter viewer desktop path is unchanged**: On a desktop Chrome build, open a letter from the History tab and confirm the AppBar shows the existing `Icons.open_in_new_rounded` icon with tooltip "Open in new tab (for printing)", and tapping it still opens a new browser tab with the letter HTML. NO share icon, NO share sheet, NO new behaviour. This is a regression check — no code changes should be required. If the desktop path is broken, return to T010 and fix the `else` branch of the conditional render.
  — Done when: rows 5, 6, 7, 8 of [quickstart.md](quickstart.md) § "Letters V2 — Desktop regression" all pass.

- [ ] T016 [P] [US3] **Verify the work order PDF preview desktop path is unchanged**: On a desktop Chrome build, export a closed work order and confirm `PdfPreviewScreen` loads, the `printing` package's built-in toolbar is visible with its print/share/download buttons intact, the AppBar does NOT show a mobile share icon, and the built-in print button still opens the browser print dialog. This is a regression check — no code changes should be required. If the desktop path is broken, return to T013 and fix the `_isMobile` gating around `allowPrinting`/`allowSharing`/`actions`.
  — Done when: rows 5, 6, 7, 8 of [quickstart.md](quickstart.md) § "Work Order PDF export — Desktop regression" all pass.

**Checkpoint for US3**: Desktop has zero visible or behavioural change. SC-003 satisfied.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Full device-matrix validation, fallback path testing, audit log verification, and release hygiene.

- [ ] T017 **Fallback path testing (FR-013, SC-005)**: Following the "Fallback path — unsupported platform" section of [quickstart.md](quickstart.md), force `navigator.canShare` to return `false` via DevTools (`Object.defineProperty(navigator, 'canShare', { value: () => false });`) on one iOS device and one Android device. Re-run both the letters and work order share flows. Verify:
  - NO share sheet appears.
  - The PDF is auto-downloaded to the device's Files / Downloads.
  - A "Saved to Files" confirmation is shown (if your snackbar message differs, that is fine — but there MUST be user feedback so the user knows where the file went).
  - The user is still on the same screen inside the PWA.
  If no confirmation snackbar is shown, add one: in `_handleShare` of both screens, after `sharePdfBytes` returns successfully, check whether the share sheet was actually used vs. fallback. Since the helper does not signal which path was taken, the simplest fix is to always show a neutral "Shared" or "Saved" snackbar after `sharePdfBytes` completes without error — or, better, extend `sharePdfBytes` to return an enum `ShareOutcome { sharedViaSheet, fallbackDownloaded, cancelled }` and have the caller show an appropriate snackbar per outcome. Use your judgement; the acceptance check is "the user knows what happened".
  — Done when: fallback rows pass on at least one iOS device and one Android device, and a user visibly learns whether their PDF went to the share sheet or to Files.

- [ ] T018 **Audit log verification**: After running at least one letter share and one WO share end-to-end on a real device, query the backend activity log and confirm there is at least one row per share with the correct `target_type` (`letter` or `work_order`), `target_id` matching the document you shared, and `action='shared'`. Use the curl commands in [quickstart.md](quickstart.md) § "Audit log check" or query the Supabase table directly via the SQL editor. Cancelled share attempts should ALSO produce a row (we log intent, not completion — per [research.md](research.md) decision 6 and 7).
  — Done when: at least one `{action='shared', target_type='letter'}` row and one `{action='shared', target_type='work_order'}` row are visible in `user_activity_log`.

- [ ] T019 **Run the full [quickstart.md](quickstart.md) device matrix**: all iOS rows (1, 2, 3 — release-blocking), the Android row (4 — smoke test), and all desktop regression rows (5, 6, 7, 8). Use the sign-off checklist at the bottom of `quickstart.md` to tick each item. If ANY iOS row fails, return to US1 or US2 to debug. If an Android row fails, file a follow-up ticket but do not block the release (per Q4 clarification).
  — Done when: every iOS checkbox is ticked, every desktop regression checkbox is ticked, and Android row 4 has been smoke-tested (one share each from letters and WO).

- [ ] T020 **Version bump**: Run `bash scripts/bump_version.sh` (or the equivalent — check `scripts/` for the current name) to bump the Flutter app's patch version. Do NOT stage or commit `backend/version.json` even if the bump script modifies it — per `CLAUDE.md` / constitution Technology Constraints, that file is managed independently on the server and must never be committed from a dev machine.
  — Done when: `pubspec.yaml` version is bumped, the corresponding frontend build is deployed, and `git status` shows `backend/version.json` is NOT staged.

- [ ] T021 **Self-review against the spec**: Open [spec.md](spec.md) and walk through every `FR-001` through `FR-015` and every `SC-001` through `SC-006`. For each one, write a one-line note on how the implementation satisfies it (in a scratch buffer — this is for the reviewer, not a committed artefact). Any FR or SC that cannot be trivially mapped to implemented behaviour is a gap — return to the relevant task and fix. Pay particular attention to:
  - **FR-003** form-factor gate (not capability gate) — grep your code to confirm you did NOT call `canShare({files})` as part of the control-selection logic.
  - **FR-006** session preservation — confirmed by quickstart step 11 ("user is STILL inside the installed PWA").
  - **FR-009** no double fetch for WO — confirmed by `_cachedBytes` in `PdfPreviewScreen`.
  - **FR-010** cancellation vs. failure distinction — confirmed by the AbortError handling in `sharePdfBytes`.
  - **FR-013** fallback is auto-download, never "open in new tab" — confirmed by T004 and by `sharePdfBytes`'s fallback branch.
  - **FR-015** meaningful filenames — `letter_<8chars>.pdf`, `letter_<millis>.pdf`, `WO-<jobNo>.pdf`.
  — Done when: every FR and SC has a one-line mapping note and no gaps remain.

- [ ] T022 **Report to the reviewer**: Summarise the implementation in a short handoff note to the reviewer (parent agent). Include:
  - List of files modified with one-line description each.
  - Which tasks you completed and which (if any) you deviated from, with reasons.
  - Results of the quickstart device matrix (which rows passed, which failed, any blockers).
  - Any deviations from [contracts/activity-log-shared.md](contracts/activity-log-shared.md) (e.g., if the backend helper signature forced a shape change).
  - Any spec gaps you noticed that were not addressed by the task list.
  - Confirmation that `backend/version.json` was not committed.
  — Done when: the handoff note is written and the reviewer can pick it up without re-reading any plan artefacts.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup / reading)**: No dependencies. Start immediately.
- **Phase 2 (Foundational)**: Depends on Phase 1 being read. BLOCKS US1 and US2.
  - T003 and T004 are in the same file (`download_helper_web.dart`) — must be sequential.
  - T005, T006, T007 are three different files — can run in parallel after T003/T004 (but they do not actually depend on T003/T004 and could run in parallel with them too — marked `[P]` accordingly).
  - T008 (backend endpoint) is independent of the frontend foundation — `[P]`-able with T003–T007.
  - T009 (`logShared` client method) depends on T008 being deployed (or at least implemented) so the endpoint exists for manual curl verification, but the Dart code itself compiles regardless.
- **Phase 3 (US1)**: Depends on ALL of Phase 2. T010, T011, T012 are sequential within US1 because they build on each other (T010 defines the `onShare` parameter; T011 and T012 supply it).
- **Phase 4 (US2)**: Depends on ALL of Phase 2. Can run in parallel with Phase 3 (different files). T013 and T014 are sequential within US2 because T014 consumes the new constructor parameters added in T013.
- **Phase 5 (US3)**: Depends on Phase 3 AND Phase 4 being complete (regression checks against both flows). T015 and T016 are `[P]`-able.
- **Phase 6 (Polish)**: Depends on Phases 3, 4, 5.

### Within-Phase Dependencies

- **T003 → T004**: same file, sequential.
- **T005 → T006, T007**: T005 creates the façade that references the stub and web files, but the stub/web files do not depend on the façade existing first. Can run T005/T006/T007 in any order as long as all three exist before any consumer imports the façade.
- **T008 → T009**: T009 is the client for the endpoint in T008. Implement T008 first, verify it works with curl, then implement T009.
- **T010 → T011, T012**: T010 adds the `onShare` parameter; T011 and T012 pass it.
- **T013 → T014**: T013 adds the parameters; T014 passes them.
- **T017 → T018**: fallback testing before audit verification (so the audit log contains both sheet-opened and fallback-downloaded rows).

### Parallel Opportunities

- **Foundational**: T005, T006, T007, T008 can all run in parallel (different files).
- **US1 vs US2**: After Phase 2 completes, a single implementer can do US1 then US2 sequentially, or two implementers can split the work (one on letters, one on WO).
- **US3 verification**: T015 and T016 are independent regression checks — can run in parallel.

---

## Implementation Strategy

### MVP First (US1 only)

1. Complete **Phase 1**: Read the plan, research, and contracts.
2. Complete **Phase 2**: Build the foundation (share helper, capability gate, audit endpoint, client service method).
3. Complete **Phase 3 (US1)**: Wire the share control into the letter viewer.
4. **STOP and VALIDATE**: Run [quickstart.md](quickstart.md) rows 1–3 and 5–8 for the letter flow only.
5. If US1 passes and shipping is urgent, you could deploy here — the letter share alone delivers real iOS user value. The WO flow would follow in a second slice.

### Full delivery

1. Phase 1 → Phase 2 → Phase 3 (US1) → Phase 4 (US2) → Phase 5 (US3 regression) → Phase 6 (Polish).
2. Validate the full device matrix at the end.
3. Hand off to the reviewer with T022's summary note.

---

## Notes for the implementer agent

- **`[P]` tasks**: different files, no dependencies on incomplete tasks. Can be done in any order or in parallel if you are multi-tasking.
- **`[Story]` label**: maps the task to the user story for traceability back to [spec.md](spec.md).
- **File paths are absolute-relative** to the repo root (`C:\Development\flutter_work_order\`). Every task tells you exactly which file to edit.
- **No automated tests**: per [research.md](research.md) decision 9, this feature is validated manually via [quickstart.md](quickstart.md). Do not add widget tests or integration tests unless you find a specific reason that justifies the cost.
- **Do not refactor unrelated code**: per `CLAUDE.md` project instructions, don't add error handling for scenarios that can't happen, don't clean up surrounding code, don't add docstrings to code you didn't change. This feature is a targeted UI fix — resist the urge to tidy up neighbouring code in the same PR.
- **Do not commit `backend/version.json`**: see T020.
- **Deviations are allowed if justified**: if you find a blocker (e.g., the `printing` package version does not support `allowPrinting: false`, or the activity log helper has a different signature than expected), document the deviation in your T022 handoff note and proceed with the simplest alternative that still satisfies the FRs and SCs. Do NOT ask the reviewer for permission on each deviation — use your judgement and document.
- **The reviewer will check**:
  - The six files modified (`download_helper_web.dart`, `share_capability*.dart` × 3, `activity_log_service.dart`, `letter_html_viewer_screen.dart`, `letter_form_tab_v2.dart`, `letter_history_tab_v2.dart`, `pdf_preview_screen.dart`, `work_order_home.dart`, `backend/routers/activity_log.py`) match the intent of each task.
  - The form-factor gate is implemented correctly (not a raw capability check).
  - The fallback path is auto-download, not "open in new tab".
  - The audit log endpoint works and the client fires it fire-and-forget.
  - Desktop behaviour is unchanged (zero regression).
  - `backend/version.json` is not staged.
  - The quickstart device matrix has actually been run, not skipped.

When you are done, return to the reviewer with your T022 handoff note.
