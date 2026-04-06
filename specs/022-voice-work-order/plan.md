# Implementation Plan: Voice-to-Work-Order Dictation

**Branch**: `022-voice-work-order` | **Date**: 2026-04-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/022-voice-work-order/spec.md`

## Summary

Add speech-to-text dictation to the work order title and description fields on the Add/Edit Work Order screen. A microphone button next to each field lets field technicians dictate hands-free. Transcription happens in real-time client-side using the Web Speech API (via `speech_to_text` Flutter package). Supports English and Arabic with language auto-detection based on a per-widget toggle (matching the pattern used by AI Insights). No backend changes required.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x (frontend only)  
**Primary Dependencies**: `speech_to_text` (NEW — Flutter package wrapping Web Speech API for PWA), Flutter Material (existing)  
**Storage**: N/A — no persistent data; voice is transcribed to text in-memory  
**Testing**: Manual testing on Chrome/Safari mobile PWA; widget tests for mic button state  
**Target Platform**: Mobile browsers (Chrome Android, Safari iOS) via Flutter Web PWA  
**Project Type**: Mobile-first PWA (Flutter Web)  
**Performance Goals**: Real-time transcription feedback within 1 second of speech  
**Constraints**: Client-side only; requires network connectivity for Web Speech API; no backend changes  
**Scale/Scope**: 2 text fields (title, description) on 1 screen (AddWorkOrderScreen handles both add and edit modes)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS (justified exclusion) | Frontend-only feature. No backend endpoint, migration, or model needed — speech processing is entirely client-side. Exclusion documented here. |
| II. Explicit Over Automatic | PASS | Language selection is explicit (user chooses EN/AR via toggle chip). Dictation start/stop is explicit (tap mic button). No implicit behavior. |
| III. Role-Based Access Control | PASS | Dictation is available to all roles that can edit work orders. Existing `canEdit` gate on the form fields already controls editability. |
| IV. Server-First File Storage | N/A | No files are uploaded or stored. Audio is processed in real-time and discarded. |
| V. Client-Side Computation | PASS | Speech recognition runs entirely client-side in the browser, consistent with this principle. |
| VI. Audit Everything | N/A | Dictation is a UI input method — the resulting text is saved via existing work order create/update flows which already have audit logging. |
| VII. Simplicity & YAGNI | PASS | Minimal scope: 2 fields, 1 screen, 1 new dependency. No abstractions beyond a reusable dictation button widget. |

**Technology Constraints Check**:
- Frontend is Flutter (Dart) targeting web — PASS
- No `url_launcher` usage — PASS (no URLs involved)
- No `backend/version.json` changes — PASS

**All gates pass. No violations to justify.**

## Project Structure

### Documentation (this feature)

```text
specs/022-voice-work-order/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
frontend/
├── lib/
│   ├── screens/Work_Orders/
│   │   └── add_work_order.dart        # Modified: add mic buttons to title & description fields
│   ├── widgets/
│   │   └── dictation_button.dart      # NEW: reusable mic button widget with recording state
│   └── services/
│       └── dictation_service.dart     # NEW: wrapper around speech_to_text for language config & lifecycle
├── pubspec.yaml                       # Modified: add speech_to_text dependency
└── web/
    └── index.html                     # May need: microphone permission meta tags (if not already present)
```

**Structure Decision**: Frontend-only changes. A reusable `DictationButton` widget encapsulates the mic button UI and recording state. A `DictationService` wraps `speech_to_text` initialization, language selection, and lifecycle management. Both are consumed by `AddWorkOrderScreen`.

## Complexity Tracking

> No constitution violations — table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| (none)    | —          | —                                   |
