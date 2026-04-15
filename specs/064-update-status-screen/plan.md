# Implementation Plan: System Status — Infrastructure Compatibility

**Branch**: `064-update-status-screen` | **Date**: 2026-04-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/064-update-status-screen/spec.md`

## Summary

Clean up the System Status screen so it renders the 7 canonical systems (post-spec-061) as a flat peer grid. Remove obsolete name-based grouping, the `_ExpandableGroup` widget, the `_expandedGroups` state, the prefix-stripping display-name logic, and the hard-coded SAT badge. Preserve every existing interaction — report, resolve, edit, delete, uptime report, Recent Issues history. UI-only change; no backend, service, migration, or model changes.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x (frontend only)
**Primary Dependencies**: Flutter Material, existing `SystemStatusService`, existing `ReportIssueSheet` / `IssueDetailsSheet` / uptime-report widgets in `frontend/lib/screens/system_status_screen.dart`
**Storage**: N/A (no data-model changes; existing `system_status_reports` rows and `systems` table consumed unchanged)
**Testing**: `flutter analyze` (zero new warnings, per SC-005); manual verification against acceptance scenarios; no new unit/widget tests required (pure deletion of code paths — see Constitution Check)
**Target Platform**: Flutter Web (PWA) primary; mobile/desktop unaffected
**Project Type**: Frontend screen refactor within existing monorepo (`backend/` + `frontend/`)
**Performance Goals**: No change. Grid render stays within existing frame budget; removing group expansion removes work, not adds it.
**Constraints**: No backend/service changes (FR-007). Preserve 3-column grid and existing card `childAspectRatio: 3.0` (FR-008). Preserve all existing interactions exactly (FR-006).
**Scale/Scope**: Single file touched — `frontend/lib/screens/system_status_screen.dart`. Expected render target: 7 canonical systems post-migration, up to ~25 if pre-migration.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Notes |
|-----------|-----------|-------|
| I. Full-Stack Ownership | ✅ Documented exclusion | Frontend-only cleanup; explicitly justified — the data-model change was spec 061, and its backend + migration already shipped. No API contract change. Documented here and in spec FR-007. |
| II. Explicit Over Automatic | ✅ Pass | No change to assignment/notification/state logic. Report / resolve / edit / delete remain explicit user actions. |
| III. Role-Based Access Control | ✅ Pass | Screen visibility rules unchanged. Spec explicitly lists role-based visibility as out of scope. |
| IV. Server-First File Storage | ✅ Not applicable | No file handling. |
| V. Client-Side Computation Where Possible | ✅ Pass | Moves further toward simplicity — removes a client-side name-split grouping step. |
| VI. Audit Everything | ✅ Pass | No new user-facing actions. Existing report/resolve/edit/delete audit writes inside those flows are preserved. |
| VII. Simplicity & YAGNI | ✅ Strong pass | This spec *is* a YAGNI cleanup — it removes the now-unused `_ExpandableGroup` widget, `_expandedGroups` state, `_satSystems` set, and displayName truncation. No new abstraction added. |

**Gate verdict**: PASS. No complexity-tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/064-update-status-screen/
├── spec.md              # Feature spec (completed by /speckit.specify)
├── plan.md              # This file (/speckit.plan)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (minimal — no schema change)
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (empty — no contract change)
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
frontend/
└── lib/
    └── screens/
        └── system_status_screen.dart   # SINGLE FILE TOUCHED

# Untouched (explicit non-changes for verification):
frontend/lib/services/system_status_service.dart   # unchanged
frontend/lib/models/system_status.dart             # unchanged
backend/routers/system_status.py                   # unchanged
supabase/migrations/                               # no new migration
```

**Structure Decision**: Single-file frontend refactor inside the existing Flutter screen. All deletions; the file's public `Widget build(...)` contract and the `StatefulWidget` class name stay identical so navigation wiring, deep links, and imports elsewhere in the app need no changes.

## Phase 0 Summary

See `research.md`. Outcome: no unknowns. Four deletion targets identified (`_groupedSystems`/`_mainSystems` logic, `_ExpandableGroup` widget, `_expandedGroups` state, `_satSystems`/SAT badge, prefix-stripping in `_SystemCard`). Grid layout constants preserved. Recent Issues section and uptime report left alone.

## Phase 1 Summary

See `data-model.md` (intentionally minimal — no schema changes, entities unchanged). See `quickstart.md` for manual verification steps mapping to each SC-00x. `contracts/` directory is empty by design — the System Status API contract is unchanged by this spec and spec 061 already shipped the backend-side changes.

## Complexity Tracking

No violations. Table intentionally empty.
