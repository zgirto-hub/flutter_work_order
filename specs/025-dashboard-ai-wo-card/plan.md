# Implementation Plan: Dashboard AI Work Order Card with Draft Preview

**Branch**: `025-dashboard-ai-wo-card` | **Date**: 2026-04-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/025-dashboard-ai-wo-card/spec.md`

## Summary

Add an AI Work Order card to the Dashboard with a shared NL input widget (extracted from AddWorkOrderScreen). After AI parsing, a draft bottom sheet previews the parsed fields with "Create" (direct submission) and "Edit" (navigate to pre-filled Add WO form) actions. Frontend-only feature reusing existing AI parse endpoint (024), voice dictation (022), and work order services. No backend changes.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x (frontend only)  
**Primary Dependencies**: Flutter Material (existing), DictationButton from 022 (existing), AiAssistService from 024 (existing), WorkOrderService (existing), DepartmentService (existing), BottomSheetContainer from bottom_sheet_widgets.dart (existing)  
**Storage**: N/A — no persistent data; draft is in-memory only  
**Testing**: Manual testing on Chrome PWA  
**Target Platform**: Mobile browsers (Chrome Android, Safari iOS) via Flutter Web PWA  
**Project Type**: Mobile-first PWA (Flutter Web)  
**Performance Goals**: Draft bottom sheet appears within 10 seconds of tapping Generate  
**Constraints**: Client-side only; no backend changes; reuses existing AI parse endpoint  
**Scale/Scope**: 2 new widgets, 2 modified screens (Dashboard + AddWorkOrderScreen refactor)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS (justified exclusion) | Frontend-only feature. No backend changes needed — reuses existing `POST /ai/parse-work-order` endpoint and `WorkOrderService.addWorkOrder()`. Exclusion documented. |
| II. Explicit Over Automatic | PASS | User explicitly taps Generate, then explicitly taps Create or Edit. No auto-submission. |
| III. Role-Based Access Control | PASS | Dashboard AI card visible to all roles. Work order creation uses existing service which enforces role-based rules. |
| IV. Server-First File Storage | N/A | No files involved. |
| V. Client-Side Computation | PASS | AI parsing uses server-side LLM (existing endpoint). Client handles UI only. |
| VI. Audit Everything | PASS | Work orders created via Dashboard go through existing `WorkOrderService.addWorkOrder()` which already logs to `user_activity_log`. |
| VII. Simplicity & YAGNI | PASS | Extracts shared widget to reduce duplication. Draft bottom sheet is minimal (read-only fields + 2 buttons). No new abstractions. |

**Technology Constraints Check**:
- Frontend: Flutter (Dart) targeting web — PASS
- No `url_launcher` usage — PASS
- No `backend/version.json` changes — PASS

**All gates pass. No violations to justify.**

## Project Structure

### Documentation (this feature)

```text
specs/025-dashboard-ai-wo-card/
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
│   ├── screens/
│   │   ├── dashboard_screen.dart              # Modified: add NlInputCard + generation logic + draft sheet
│   │   └── Work_Orders/
│   │       └── add_work_order.dart            # Modified: add prefill params + use shared NlInputCard
│   └── widgets/
│       ├── nl_input_card.dart                 # NEW: shared NL input widget (text, mic, lang chips, generate)
│       ├── ai_draft_bottom_sheet.dart         # NEW: draft preview bottom sheet (read-only fields + Create/Edit)
│       ├── bottom_sheet_widgets.dart          # Reused: BottomSheetContainer, showAppBottomSheet
│       └── dictation_button.dart              # Reused: DictationButton from 022
```

**Structure Decision**: Frontend-only changes. Two new widgets (`NlInputCard`, `AiDraftBottomSheet`) and two modified screens. The NL input card is extracted from `AddWorkOrderScreen` into a shared widget. No contracts directory needed (reuses existing endpoint).

## Complexity Tracking

> No constitution violations — table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| (none)    | —          | —                                   |
