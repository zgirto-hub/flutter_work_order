# Implementation Plan: iOS PWA Native Share for Letters & Work Order PDFs

**Branch**: `038-ios-pwa-share` | **Date**: 2026-04-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/038-ios-pwa-share/spec.md`

## Summary

On iOS/mobile PWA, replace the session-breaking "Open in new tab" affordance in the Letters V2 HTML viewer and the session-breaking built-in toolbar actions of the work order PDF preview with a single **AppBar share control** that invokes the native system share sheet (AirDrop, Mail, Messages, Print, Save to Files) carrying a real PDF file. Desktop keeps its existing behaviour unchanged (form-factor gate, not capability gate). When the Web Share API with file support is unavailable on mobile, auto-download the PDF to the device's Files/Downloads location with a "Saved to Files" confirmation — never fall back to "Open in new tab" on iOS.

**Technical approach**: extend the existing `frontend/lib/services/download_helper_web.dart` (which already implements the iOS Web Share API pattern for attachment downloads) with a new `sharePdfBytes(bytes, fileName, title)` entry point that takes bytes directly instead of fetching from a URL, and change its unsupported-platform fallback from "open in new tab" (current behaviour) to anchor-download (new behaviour, FR-013). Add a small `ShareCapability` helper that exposes a form-factor gate to UI layers. Wire the two screens: (a) `LetterHtmlViewerScreen` gets a new `onShare` callback that returns `Future<Uint8List>` PDF bytes, supplied by its two callers (form tab → reuses existing server round-trip via `LetterService.generateV2/updateV2`; history tab → uses `LetterService.regenerateV2`); (b) `PdfPreviewScreen` gains an AppBar share button that caches the `buildPdf()` result and hides the `printing` package's built-in `allowPrinting`/`allowSharing` actions on mobile. Add a fire-and-forget `/activity-log/shared` backend endpoint to satisfy Principle VI (Audit Everything).

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x (frontend only, primarily web target); Python 3.10 + FastAPI (backend, minimal touch for audit endpoint)
**Primary Dependencies**: `package:web` (existing — JS interop for `navigator.share`, `navigator.canShare`, `Blob`, `File`, anchor download), `package:printing` (existing — already used for `PdfPreview`; its `allowPrinting`/`allowSharing`/`actions` params control the built-in toolbar), `package:http` (existing — activity log POST), existing `download_helper_web.dart` to be extended
**Storage**: N/A — PDF bytes are transient (built → shared/downloaded → released). No database changes. No new file storage.
**Testing**: Manual device testing across the iOS PWA test matrix (installed PWA + regular Safari, iOS 17+), macOS Safari desktop, Chrome/Edge/Firefox desktop, Android Chrome PWA (smoke test only). No new automated tests — the existing Flutter test suite does not cover web-interop share flows, and introducing a platform-stubbed test for `navigator.share` is a YAGNI violation for a two-screen change. Manual validation checklist lives in `quickstart.md`.
**Target Platform**: Flutter Web (primary). iOS Safari 15+ (installed PWA and regular tab), Android Chrome 90+ (installed PWA), desktop Chrome/Edge/Firefox/macOS Safari (unchanged behaviour)
**Project Type**: Web (existing `frontend/` + `backend/` + `supabase/` monorepo layout)
**Performance Goals**: Share sheet must open within 3 seconds of tap for documents up to 10 pages on typical iOS office hardware and Wi-Fi (SC-004). PDF generation for letters uses the existing server round-trip — same latency budget as the existing "Generate PDF" button. PDF generation for work orders reuses the bytes already fetched for the `PdfPreview` widget (no second round-trip, per FR-009).
**Constraints**: Zero regression on desktop (SC-003). Must not break the PWA session on any platform (FR-006). Must distinguish share cancellation (silent) from share failure (visible error) (FR-010). Must hide the `printing` package's built-in share/print/download actions on mobile so only one share affordance is visible (FR-002). Must reuse existing authorization gating for WO export (closed status + role) (FR-014). Must use `openInNewTab()` from `download_helper_web.dart` via conditional import — not `url_launcher` (constitution Technology Constraints).
**Scale/Scope**: 2 Flutter screens modified (`letter_html_viewer_screen.dart`, `pdf_preview_screen.dart`); 2 call sites updated (`letter_form_tab_v2.dart`, `letter_history_tab_v2.dart`); 1 existing helper extended (`download_helper_web.dart`) + 1 new thin helper (`share_capability.dart`); 1 minimal FastAPI endpoint added (`/activity-log/shared`). No new models, no migrations, no new Flutter services.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment |
|-----------|------------|
| **I. Full-Stack Ownership** | ⚠️ **Deviation with justification (see Complexity Tracking).** Feature is predominantly frontend — no migration, no new Flutter model, no new Flutter service. The minimal backend touch is an audit-log endpoint (see Principle VI below), which also delivers partial full-stack coverage. The excluded layers are documented: no DB because sharing is transient, no new model because no new entity, no new service because the two existing services (`LetterService`, `ReportService`) already return PDF bytes and no new method is needed. |
| **II. Explicit Over Automatic** | ✅ **Compliant.** The share is always explicit — user taps the share button, the native share sheet appears, the user picks a target. Nothing is auto-shared, auto-downloaded (except as a fallback when the share sheet is unavailable, which is still a direct response to an explicit user tap), or auto-routed. Cancellation is explicitly distinguished from failure (FR-010). |
| **III. Role-Based Access Control** | ✅ **Compliant.** Sharing does not introduce a new permission surface (FR-014). The letter share control follows the same visibility rules as the existing letter viewer. The work order share control follows the same gating as the existing export: closed status + the user's current role check. No new authorization logic is added. |
| **IV. Server-First File Storage** | ✅ **Compliant.** No files are persisted as a result of sharing. PDF bytes are constructed in memory (for letters: server returns bytes; for WO: server returns bytes), handed to `navigator.share`, and released. The fallback auto-download uses an anchor element to save to the user's device — still not touching server storage. |
| **V. Client-Side Computation Where Possible** | ✅ **Compliant.** Share capability detection, form-factor gating, Blob/File construction, and the anchor-download fallback all execute client-side. Nothing is routed through the backend that could be done in the browser. |
| **VI. Audit Everything** | ⚠️ **Compliance requires one small backend addition.** The constitution explicitly lists `shared` as an audit verb. The feature would otherwise be frontend-only, but to satisfy audit-everything we add a fire-and-forget `POST /activity-log/shared` endpoint that logs `{user_email, document_type: 'letter'\|'work_order', document_id, shared_at}` to `user_activity_log`. The log write is fire-and-forget (failure does not block the share action) per the constitution's guidance in Principle VI. This is the minimal viable audit surface and is not a YAGNI violation because it is directly required by Principle VI. |
| **VII. Simplicity & YAGNI** | ✅ **Compliant.** No new service abstraction, no new model, no platform interface polymorphism beyond the one already-established conditional-import pattern in `download_helper_web.dart` / `download_helper_mobile.dart`. No configuration flags. No analytics beyond the single audit log write required by Principle VI. No automated test infra for the web-interop path (manual validation via `quickstart.md`). |

**Gate result**: ✅ PASS with documented deviations (see Complexity Tracking).

### Post-Phase-1 re-check

After generating `research.md`, `data-model.md`, `contracts/activity-log-shared.md`, and `quickstart.md`, the constitution check is re-evaluated:

- **Principle I**: Still a deviation — research decision 6 (audit endpoint) adds a thin backend slice, so the feature is no longer 100% frontend, but it is still not full-stack in the classical sense (no migration, no model, no new service layer). Deviation remains documented in Complexity Tracking; no changes.
- **Principle II**: Still compliant — the research docs confirm all user actions are explicit; fallback auto-download only fires in direct response to an explicit share button tap.
- **Principle III**: Still compliant — contract `activity-log-shared.md` does not introduce any new role check; it inherits the global auth middleware.
- **Principle IV**: Still compliant — no file storage side effects; the audit row is metadata only, and the fallback anchor download writes to the user's device, not the server.
- **Principle V**: Still compliant — all detection and fallback logic is client-side.
- **Principle VI**: Now **actively satisfied** (not just justified) by the concrete contract in `contracts/activity-log-shared.md` and the client-side `ActivityLogService.logShared` method described in research decision 6.
- **Principle VII**: Still compliant — research doc 9 (no automated tests) and decision 3 (no cache for letter bytes) and the data-model doc (no classes for the transient entities) all explicitly reject additional abstraction. Manual validation via `quickstart.md`.

**Re-check result**: ✅ PASS. No new violations introduced by Phase 1 design.

## Project Structure

### Documentation (this feature)

```text
specs/038-ios-pwa-share/
├── plan.md              # This file
├── spec.md              # Feature specification (already written + clarified)
├── research.md          # Phase 0 output — decisions & unknowns resolved
├── data-model.md        # Phase 1 output — entities (transient: ShareableDocument, ShareCapability)
├── quickstart.md        # Phase 1 output — manual device test matrix & validation steps
├── contracts/
│   └── activity-log-shared.md  # Phase 1 output — backend audit endpoint contract
├── checklists/
│   └── requirements.md  # From /speckit.specify
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
frontend/
├── lib/
│   ├── services/
│   │   ├── download_helper.dart              # [EXISTING] conditional-import façade
│   │   ├── download_helper_web.dart          # [MODIFY] add sharePdfBytes(bytes, fileName, title);
│   │   │                                     #          change unsupported-platform fallback from
│   │   │                                     #          openInNewTab → anchorDownload (FR-013)
│   │   ├── download_helper_mobile.dart       # [EXISTING] native stub — no changes
│   │   └── share_capability.dart             # [NEW] form-factor gate: canUseNativeShareControl()
│   ├── screens/
│   │   ├── letters_v2/
│   │   │   ├── letter_html_viewer_screen.dart   # [MODIFY] replace "Open in new tab" with share
│   │   │   │                                    #          control on mobile; keep tab on desktop;
│   │   │   │                                    #          add onShare: Future<Uint8List> callback
│   │   │   ├── letter_form_tab_v2.dart          # [MODIFY] supply onShare that resubmits the
│   │   │   │                                    #          form via LetterService.generateV2/updateV2
│   │   │   │                                    #          (same bytes as Generate PDF)
│   │   │   └── letter_history_tab_v2.dart       # [MODIFY] supply onShare that calls
│   │   │                                        #          LetterService.regenerateV2(letterId)
│   │   └── Work_Orders/
│   │       └── work_order_home.dart             # [NO CHANGE] already passes buildPdf to
│   │                                            #              PdfPreviewScreen — the new share
│   │                                            #              control lives inside PdfPreviewScreen
│   └── widgets/
│       └── pdf_preview_screen.dart              # [MODIFY] add mobile-only AppBar share button;
│                                                #          cache buildPdf() result so share and
│                                                #          preview share the same bytes (FR-009);
│                                                #          set allowPrinting/allowSharing=false on
│                                                #          mobile to hide the printing toolbar
│                                                #          built-in actions (Q3 decision)
backend/
├── routers/
│   └── activity_log.py                          # [MODIFY] add POST /activity-log/shared
│                                                #          (fire-and-forget; writes to
│                                                #          user_activity_log via utils/activity.py)
└── utils/
    └── activity.py                              # [NO CHANGE] existing helper reused
```

**Structure Decision**: Existing web-app monorepo layout (`frontend/` Flutter + `backend/` FastAPI + `supabase/`). This feature touches two frontend screens, one shared widget, one shared helper (extended), one new thin helper, and one backend router (minimal audit endpoint). No `supabase/migrations/` changes — the existing `user_activity_log` schema already accepts `shared` as a verb per Principle VI. No new tests directory — manual validation only (see `quickstart.md`).

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **Principle I — Full-Stack Ownership is partial** (no new Supabase migration, no new Flutter model, no new Flutter service method) | The feature is inherently a UI/UX fix for a platform-specific session-break bug on iOS. There is no new domain entity to persist, no new data to model, and no new business logic to encapsulate in a service. Forcing a full-stack footprint (e.g., a server-side share-intent table, a `SharePreference` model, a `ShareService`) would add abstraction layers with zero business value. | (a) A new backend table for share events — rejected because it duplicates the audit log write. (b) A new Flutter service `ShareService` — rejected because it would wrap a single call to `download_helper_web.dart` with no additional behaviour (three-lines-vs-abstraction rule from Principle VII). (c) A new Flutter model for "ShareableDocument" — rejected because the two callers pass in bytes and a filename directly; a model would be ceremony with no consumers. The minimal backend touch (audit endpoint from Principle VI) provides the only backend coverage the feature genuinely needs. |
| **Principle VI — Audit via new endpoint rather than extending an existing one** | There is no existing `shared` audit endpoint from the frontend side (the existing `activity_log_service.dart` only exposes `sign-in`, `sign-out`, `update-check`). A dedicated endpoint keeps the schema explicit (document type + document id) and keeps the write path identical to the existing fire-and-forget pattern. | Piggybacking on an existing generic log endpoint was rejected because there is no such generic endpoint in the frontend service surface today — creating one just for this feature would be broader scope than adding a single targeted endpoint. |