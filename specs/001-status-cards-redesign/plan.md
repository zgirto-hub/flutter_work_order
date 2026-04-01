# Implementation Plan: System Status Cards Redesign

**Branch**: `001-status-cards-redesign` | **Date**: 2026-04-02 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-status-cards-redesign/spec.md`

## Summary

Redesign the three card widgets on the System Status page (`_SystemCard`,
`_ExpandableGroup`, `_HistoryCard`) to reduce vertical space consumption
by 30%+ while retaining all existing information and interactions. The
change is frontend-only — a single file edit to
`frontend/lib/screens/system_status_screen.dart`.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x
**Primary Dependencies**: Flutter Material, fl_chart, supabase_flutter, app_theme
**Storage**: N/A (no data model changes)
**Testing**: Manual visual verification (no automated UI tests in project)
**Target Platform**: Flutter Web (desktop primary, mobile secondary)
**Project Type**: Mobile/web app — frontend-only UI change
**Performance Goals**: Instant render, no additional API calls
**Constraints**: Single-file change; preserve all interactions and color scheme
**Scale/Scope**: 1 file, 3 private widgets, ~200 lines modified

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | **PASS (exempted)** | This is a frontend-only UI layout change. No backend, database, or service changes needed. Exemption justified: the feature modifies visual density of existing widgets only. |
| II. Explicit Over Automatic | **PASS** | No assignment, notification, or state logic is changed. |
| III. Role-Based Access Control | **PASS** | No role logic is modified. Screen visibility unchanged. |
| IV. Server-First File Storage | **N/A** | No file operations involved. |
| V. Client-Side Computation | **PASS** | No computation logic is changed. |
| VI. Audit Everything | **N/A** | No user actions added or modified. |
| VII. Simplicity & YAGNI | **PASS** | Reducing padding/spacing is the simplest approach. No new abstractions introduced. |

All gates pass. No violations to track.

## Project Structure

### Documentation (this feature)

```text
specs/001-status-cards-redesign/
├── plan.md              # This file
├── research.md          # Phase 0 output (current layout analysis)
├── data-model.md        # Phase 1 output (N/A — no data changes)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
frontend/lib/screens/
└── system_status_screen.dart   # Single file containing all 3 widgets to modify:
                                #   _SystemCard      (lines 1151-1247)
                                #   _ExpandableGroup (lines 1004-1145)
                                #   _HistoryCard     (lines 1251-1388)
```

**Structure Decision**: Single-file modification. All three target widgets
are private classes within `system_status_screen.dart`. No new files needed.

## Complexity Tracking

> No Constitution Check violations — this section is intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
