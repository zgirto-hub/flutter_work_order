# Implementation Plan: Document Registry V2 UI Refactor

**Branch**: `041-registry-v2-refactor` | **Date**: 2026-04-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/041-registry-v2-refactor/spec.md`

## Summary

Refactor the Document Registry screen from a combined form-and-list layout to the Letters v2 pattern: a main screen with expandable card list + ClaudeFAB, with a pushed full-screen form for create/edit. All existing backend integration (DocumentRegistryService) and data model (RegistryEntry) remain unchanged. This is a frontend-only refactor touching one screen file (`document_registry_screen.dart`), reusing shared widgets (ClaudeFAB, EmptyState) and replicating the expandable card + pushed form patterns from `letter_generator_screen_v2.dart` and `letter_history_tab_v2.dart`.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x  
**Primary Dependencies**: Flutter Material, existing shared widgets (ClaudeFAB, EmptyState, ValidatedTextField, SectionLabel from `claude_widgets.dart`), existing DocumentRegistryService, existing RegistryEntry model  
**Storage**: N/A — no data model or backend changes  
**Testing**: Manual visual/interaction testing (PWA in browser)  
**Target Platform**: Web (PWA), primarily  
**Project Type**: Mobile/web app (Flutter)  
**Performance Goals**: Smooth 240ms card animations with no frame drops  
**Constraints**: Must visually match Letters v2 design tokens exactly; must preserve 100% of existing backend integration  
**Scale/Scope**: Single screen refactor; ~1 file rewritten, 0 new backend endpoints, 0 migrations

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
| --------- | ------ | ----- |
| I. Full-Stack Ownership | **Justified exclusion** | Frontend-only UI refactor. Backend endpoints, migration, model, and service already exist and are unchanged. No new data flows introduced — only the presentation layer changes. Documented in spec Assumptions section. |
| II. Explicit Over Automatic | **Pass** | No state transitions or assignment logic changes. Replied toggle remains explicit user action. |
| III. Role-Based Access Control | **Pass** | No role or permission changes. Screen access governed by existing NavScreenRegistry wiring (unchanged). |
| IV. Server-First File Storage | **Pass** | Existing file upload/download paths preserved exactly. No new file storage introduced. |
| V. Client-Side Computation | **Pass** | Search filtering remains client-side from the full dataset (existing pattern preserved). |
| VI. Audit Everything | **Pass** | No new user-facing actions introduced. All existing CRUD operations flow through the same backend endpoints which already produce audit entries. |
| VII. Simplicity & YAGNI | **Pass** | Replicating a proven, existing pattern (Letters v2). No new abstractions, configurability, or future-proofing added. |

**Gate result**: PASS — all principles satisfied or justified.

## Project Structure

### Documentation (this feature)

```text
specs/041-registry-v2-refactor/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
frontend/lib/
├── screens/document_registry/
│   └── document_registry_screen.dart   # REWRITE — main screen + pushed form + expandable card
├── models/
│   └── registry_entry.dart             # UNCHANGED — existing data model
├── services/
│   └── document_registry_service.dart  # UNCHANGED — existing backend service
├── widgets/
│   └── claude_widgets.dart             # UNCHANGED — provides ClaudeFAB, EmptyState
└── theme/
    └── app_theme.dart                  # UNCHANGED — provides AppColors
```

**Structure Decision**: Single-file rewrite of `document_registry_screen.dart`. The file will contain three widgets: the main screen (list view + FAB), the pushed form screen (create/edit), and the expandable entry card (stateful, animated). This mirrors the Letters v2 pattern where `letter_generator_screen_v2.dart` contains `_LetterFormScreen` as a private widget, and `letter_history_tab_v2.dart` contains `_LetterCard`. Given the Document Registry is simpler (fewer fields, no tabs), all three widgets fit naturally in one file.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Frontend-only (no backend/migration) | Pure UI refactor — identical data flows, only presentation changes | Full-stack would add unnecessary no-op changes to backend/DB for a screen-level reskin |
