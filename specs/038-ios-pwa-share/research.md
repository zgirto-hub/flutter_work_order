# Phase 0 Research — iOS PWA Native Share for Letters & Work Order PDFs

**Feature**: 038-ios-pwa-share
**Date**: 2026-04-11
**Purpose**: Resolve all unknowns in Technical Context, validate chosen approaches against existing code, document rejected alternatives.

All four spec-level ambiguities were resolved in `/speckit.clarify` (see `spec.md` § Clarifications). This document resolves implementation-level unknowns that surfaced while writing the plan.

---

## 1. Does the existing `download_helper_web.dart` already implement what we need?

**Decision**: Partially. The helper already knows how to (a) detect iOS via UA sniffing, (b) fetch bytes, (c) build a `Blob` and `File`, (d) test `navigator.canShare({files})`, (e) call `navigator.share`, (f) distinguish `AbortError` cancellation from other errors. We will **extend** it rather than write a new module. Two specific modifications are required.

**Rationale**:
- The helper is the project's canonical location for PWA file interop (per constitution Technology Constraints: "PWA URL handling MUST use `openInNewTab()` from `download_helper_web.dart` via conditional import — never `url_launcher`").
- Writing a second share helper would fragment the web-interop surface and violate Principle VII (Simplicity).
- The existing code already solves 80% of the share-sheet interaction correctly.

**Gaps to close**:

1. **Current API takes a URL, not bytes.** Its entry point `downloadFile(url, fileName)` performs a `fetch(url)` to obtain bytes. For letters and work orders, we already have `Uint8List` bytes in hand and don't want a second round-trip. → Add a new public entry point `sharePdfBytes(Uint8List bytes, String fileName, String title)` that skips the fetch step and goes straight to Blob/File/share.

2. **Current fallback is "open in new tab".** Line 83: `_openInNewTab(url);` is the dead-end path when `canShare` is false, when `navigator.share` throws a non-cancel error, or when `fetch` fails. This is the *exact* session-breaking behaviour we must eliminate per FR-013 and the Q2 clarification. → Replace the fallback on mobile with `_anchorDownload(url, fileName)` (the same anchor-click path the helper already uses for desktop/Android downloads), so the user gets the PDF saved to Files rather than getting kicked to Safari. For the new `sharePdfBytes` path, this means constructing a temporary object URL from the Blob, invoking anchor-click, and revoking the URL.

**Alternatives considered**:
- **Write a new `share_helper_web.dart` module.** Rejected: duplicates 90% of `download_helper_web.dart`, fragments conditional-import surfaces, violates constitutional Technology Constraints which names `download_helper_web.dart` as the canonical PWA URL-handling module.
- **Leave the existing `downloadFile(url, ...)` entry point alone and route through it by minting a temporary object URL first, then letting the existing code fetch that URL back.** Rejected: pointless round-trip through `fetch` for bytes we already hold, and does not fix the session-breaking fallback.
- **Use `printing` package's own `Printing.sharePdf(bytes, filename)` helper.** Rejected: on web it delegates to `navigator.share` anyway but adds a package abstraction that obscures the fallback path (which is the whole point of this feature). It also does not let us replace the fallback with anchor-download. Going direct to the existing helper is simpler and gives us full control over the fallback.

---

## 2. What form-factor detection strategy should drive the share-vs-tab gate?

**Decision**: UA-sniff for mobile form factor in a new `frontend/lib/services/share_capability.dart` helper with a single public function `bool canUseNativeShareControl()` that returns `true` on iOS (any Safari, installed PWA or tab) and Android Chrome, and `false` everywhere else. The implementation calls out to `download_helper_web.dart`'s existing UA-sniff pattern. UI layers import this helper via conditional import (`share_capability_web.dart` / `share_capability_stub.dart`) so the same call compiles on both native and web targets — even though native Flutter builds of this app are not shipped, the stub keeps type-checking clean.

**Rationale**:
- **Form factor, not raw capability** (per Q1 clarification): even if desktop Chrome/Edge support `canShare({files})`, we keep them on the legacy "Open in new tab" path. This means a pure `navigator.canShare({files: [...]})` check is *wrong* for our gate — we need an explicit mobile allow-list.
- **UA sniff is acceptable for form-factor detection** in this scope because (a) the consequence of a false negative is a user seeing "Open in new tab" on a mobile device where share would also have worked — a graceful degradation, (b) the project already UA-sniffs in `download_helper_web.dart` line 15–18, and (c) modern UA-Client-Hints are not available on iOS Safari anyway.
- A single helper function keeps UI code readable: `if (canUseNativeShareControl()) { ... } else { ... }`.

**Alternatives considered**:
- **`navigator.canShare({files: [pdfFile]})` as the gate.** Rejected: returns true on desktop Chrome 96+, which contradicts the Q1 decision to keep all desktop on the legacy path.
- **`MediaQuery.of(context).size.shortestSide < 600` (Flutter form-factor heuristic).** Rejected: doesn't distinguish iPad in landscape-with-keyboard from a desktop, and would surface the share control on iPad Pro in desktop mode where the user doesn't want it. UA-sniff is more accurate.
- **`display-mode: standalone` CSS media query** (installed PWA only). Rejected: excludes regular mobile Safari, where the session-break bug also exists and the share sheet is still useful. The Q1 edge-case note in the spec explicitly calls this out.
- **`Theme.of(context).platform == TargetPlatform.iOS` (Flutter platform detection).** Rejected: on Flutter web, `Theme.of(context).platform` reports the *host OS* for mouse/keyboard affordances, which is not reliable for "is this a mobile browser" — it returns `TargetPlatform.macOS` for macOS Safari on a desktop, which is correct here, but for Chrome on Windows it returns `TargetPlatform.android` in some Flutter versions. Too quirky to rely on; the explicit UA check in `download_helper_web.dart` is the pattern already established in the project.

---

## 3. Where do letter PDF bytes come from in each call site?

**Decision**:

| Call site | Bytes source | Filename |
|-----------|--------------|----------|
| `letter_form_tab_v2.dart` → new/edited letter preview | Resubmit the form to the server via `LetterService.generateV2()` or `LetterService.updateV2()` (same call that powers the existing "Generate PDF" button) | `letter_${DateTime.now().millisecondsSinceEpoch}.pdf` (matches the existing download filename pattern at line 502) |
| `letter_history_tab_v2.dart` → viewing a saved letter | Call `LetterService.regenerateV2(letterId)` which returns the archived letter's PDF bytes from the server | `letter_${letterId.substring(0, 8)}.pdf` (short stable identifier that survives RTL content in the title) |

**Rationale**:
- FR-008 requires the share flow to produce the *same* PDF a user would get via the existing "Generate PDF" action. Both call sites already know how to get those bytes; they just currently fire-and-forget them via a download. We expose the same bytes to the share helper by wiring a new `onShare` callback on `LetterHtmlViewerScreen` that returns `Future<Uint8List>`.
- The form tab's `onShare` callback is essentially the first ~100 lines of the existing `_generatePdf()` method without the final `_downloadPdfBytes(...)` line. Factor that into a `Future<Uint8List> _buildPdfBytesForShare()` helper and call it from both the existing "Generate PDF" button and the new share callback.
- **Arabic/RTL filenames**: letter `almawdoo` (subject) fields contain Arabic characters. Some iOS share targets (e.g., Mail) handle UTF-8 filenames correctly; others (older AirDrop versions) display them as `???`. Rather than pick an encoding, **use an ASCII-safe identifier-based filename** for history-tab shares (short letter ID prefix) and a timestamp for form-tab shares. The in-sheet title (passed as `shareData.title`, which is separate from the filename) can still contain the Arabic subject — iOS renders that UTF-8 correctly.

**Alternatives considered**:
- **Send the raw HTML to the share sheet instead of PDF.** Rejected by FR-007 (must be a real PDF) and by the UX intent: Mail/Print/Save to Files users expect a printable document.
- **Render HTML to PDF client-side via `htmltopdfwidgets`.** Rejected: the server-side WeasyPrint pipeline is the canonical renderer (spec assumptions), it already handles the letterhead, fonts, and RTL reshaping correctly, and introducing a second renderer would create divergence.
- **Cache the PDF bytes on the first "Generate PDF" tap and reuse them for share.** Rejected as premature optimisation. The form-tab cache would be invalidated on any edit, and the history tab already has the bytes available via a single `regenerateV2` call. A cache would add state and a cache-invalidation rule for one saved round-trip per share action.

---

## 4. Where do work order PDF bytes come from, and how do we avoid a double fetch?

**Decision**: `PdfPreviewScreen` already accepts a `buildPdf: Future<dynamic> Function()` callback. The underlying `printing` package's `PdfPreview` widget will call `buildPdf` at least once to render the viewer. We add a `Uint8List? _cachedBytes` field in `PdfPreviewScreen`'s state and wrap the existing `buildPdf` in a closure that populates `_cachedBytes` on first resolution. The AppBar share button reads from `_cachedBytes` if present, or awaits `buildPdf` if not (defensive — the share button is disabled/loading until the first render completes in practice).

**Rationale**:
- FR-009 explicitly requires "the bytes the preview displays are the bytes the share sheet receives" — no second round-trip.
- The `printing` package's `PdfPreview.build` callback is called once per page-format change, and we set `canChangePageFormat: false` (already set at line 46 of `pdf_preview_screen.dart`), so `buildPdf` is effectively called once per mount. Caching the result is safe.
- Converting `PdfPreviewScreen` from `StatelessWidget` to `StatefulWidget` is a trivial mechanical change.

**Alternatives considered**:
- **Pre-fetch PDF bytes in `work_order_home.dart` before pushing `PdfPreviewScreen`** so the bytes can be passed in as a simple `Uint8List`. Rejected: loses the incremental-load UX where the PdfPreview shows a shimmer while the PDF is fetched. Also, `PdfPreviewScreen` is also used by `workorder_report_screen.dart` and `payment_certificate_list_screen.dart` — all call sites would have to change, widening the blast radius.
- **Have the AppBar share button call `buildPdf()` a second time.** Rejected: doubles the server load on every share action, violates FR-009, and introduces the possibility of the viewer and the shared file showing different content if the source mutates between calls.

---

## 5. How do we hide the `printing` package's built-in toolbar actions on mobile?

**Decision**: The `PdfPreview` widget exposes three relevant boolean parameters — `allowPrinting`, `allowSharing`, `canDebug` — plus an `actions` list. On mobile (where `canUseNativeShareControl()` returns true), pass `allowPrinting: false` and `allowSharing: false`. On desktop, leave the current defaults (both default to true in the package). The download button is controlled by `canChangePageFormat`/`maxPageWidth` and a separate `allowPrinting` flag — confirm by reading the package source during implementation. Our AppBar share button becomes the sole share affordance on mobile.

**Rationale**:
- This is exactly what the printing package's API is designed for — there's no monkey-patching required.
- Hiding the built-in actions on mobile while leaving them on desktop matches the Q3 decision (AppBar button + hide built-in toolbar on mobile; desktop keeps full `printing` toolbar).
- Zero-cost on desktop, where the `printing` toolbar is the whole UX for PDF preview.

**Alternatives considered**:
- **Replace `PdfPreview` with a custom viewer on mobile.** Rejected by Q3 clarification — too much blast radius. The viewer body is well-tested.
- **Add our share button to `PdfPreview`'s `actions` slot.** Rejected: the slot is a toolbar-inline position that would sit *beside* the other toolbar buttons, not in the AppBar where the letter viewer's share button sits. We want visual consistency across the two screens.

---

## 6. How do we satisfy Principle VI (Audit Everything) for share actions?

**Decision**: Add a single FastAPI endpoint `POST /activity-log/shared` that accepts `{user_email: str, document_type: 'letter' | 'work_order', document_id: str}` and writes one row to `user_activity_log` via the existing `backend/utils/activity.py` helper. On the Flutter side, extend `ActivityLogService` with `logShared(String documentType, String documentId)` following the existing fire-and-forget pattern in `logSignIn` / `logSignOut` (wrapped in `try { } catch (_) {}`). Call `logShared` from the share button's press handler *before* invoking the native share sheet so the audit row exists regardless of whether the user completes or cancels the share.

**Rationale**:
- Constitution VI explicitly lists `shared` as an audit verb and requires all user-facing actions to produce a log entry.
- Logging **share intent** rather than **share completion** is the correct semantic: the Web Share API does not reliably distinguish "user completed a share" from "user cancelled" across platforms, and the promise resolves in both cases on most browsers. The intent is observable and meaningful; the completion is not.
- Fire-and-forget is explicitly permitted by Principle VI: "Fire-and-forget logging (via `backend/utils/activity.py`) is acceptable — audit writes MUST NOT block the primary request path."
- A single endpoint for both document types keeps the API surface small and matches the pattern of the existing sign-in/sign-out endpoints.

**Alternatives considered**:
- **Skip the audit entirely, with a deviation note in Complexity Tracking.** Rejected: the constitution is explicit, and the cost of compliance is one endpoint, one service method, and ~5 lines of caller code. Not worth a documented deviation.
- **Two separate endpoints (`/activity-log/shared-letter`, `/activity-log/shared-work-order`).** Rejected: no benefit over a single endpoint with a `document_type` discriminator, and it fragments the API surface.
- **Log on the backend automatically when the PDF bytes are fetched.** Rejected: the letter history and WO flows already call their existing endpoints for reasons unrelated to sharing, so we can't distinguish a share-intent fetch from a regular preview fetch on the server.

---

## 7. How do we distinguish cancellation from failure in the share flow?

**Decision**: Wrap the `_share(shareData).toDart` call in a try/catch. If the error's `toString()` contains `AbortError`, `cancel`, or `abort` (matching the existing pattern at lines 68–73 of `download_helper_web.dart`), treat it as silent cancellation — no snackbar, no fallback. Any other error propagates to the caller, which shows a user-visible snackbar ("Couldn't share PDF — try again"). The fallback auto-download path is triggered only when `canShare` returns `false` up-front or when the initial `fetch`/blob construction throws — never as a response to a user-cancelled share sheet.

**Rationale**:
- FR-010 requires this distinction.
- The pattern is already proven in `download_helper_web.dart` and works across iOS versions.
- Falling back to auto-download on cancellation would be confusing (user said "no" and still got the file downloaded).

**Alternatives considered**:
- **Inspect `error.name === 'AbortError'` directly via JS interop.** Rejected: requires additional interop declarations; string matching on `toString()` is already working in the codebase and is sufficiently specific (there is no ambiguity with other error types that happen to contain "abort").

---

## 8. What about Arabic RTL filenames and titles?

**Decision**: Use ASCII-safe filenames (see decision 3), and pass the UTF-8 subject (Arabic or English) as `shareData.title`. iOS and Android share sheets render `title` in the source label of the share sheet ("Letter: موضوع الرسالة") regardless of filename encoding. This gives the best receiving-app experience without fighting filesystem charset quirks.

**Rationale**: Accessibility and localization gap noted in the clarification summary — resolved here at plan level. No spec change needed.

---

## 9. What test coverage is appropriate?

**Decision**: Manual device-matrix validation only; no automated tests. The validation steps and the device matrix are captured in `quickstart.md` as the sign-off checklist.

**Rationale**:
- The feature exercises browser APIs (`navigator.share`, `navigator.canShare`, `Blob`, `File`, anchor download) that are not meaningfully testable in the Flutter unit/widget test harness without extensive JS interop mocking. Mocking `navigator.share` to return a resolved promise would test that our code awaits a promise — not that the share sheet opens on iOS.
- The project's existing test surface does not cover the `download_helper_web.dart` module, which is the precedent for this feature. Introducing test infra for one share path would be disproportionate.
- The feature's failure modes are all **observable on device** (wrong control shown; share sheet doesn't open; session gets kicked to Safari; wrong filename). A manual matrix is the faster and more trustworthy verification.

**Alternatives considered**:
- **Widget tests that verify `canUseNativeShareControl()` is called and the share button appears.** Rejected: tests the wiring but not the actual browser behaviour, which is the failure mode we care about.
- **Playwright/Cypress end-to-end test against a built PWA.** Rejected: the project has no Playwright/Cypress infra; adding it for one feature is a major scope expansion.

---

## Summary of resolutions

All Technical Context fields are now free of `NEEDS CLARIFICATION` markers. The feature is ready for Phase 1 (design & contracts).
