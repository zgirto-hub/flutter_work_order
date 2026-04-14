# Implementation Plan: Auto-Suggest Asset Registry Additions

**Branch**: `055-asset-auto-suggest` | **Date**: 2026-04-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/055-asset-auto-suggest/spec.md`

## Summary

Add a "Suggestions" section to the Asset Registry screen that surfaces unregistered equipment from pattern alerts. The backend computes suggestions by querying pattern_alerts for equipment_ids not in the assets table (case-insensitive, 2+ alert threshold), excluding dismissed entries stored in system_settings. The frontend displays suggestions with accept (pre-fill Add Asset form) and dismiss actions.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend)
**Storage**: Supabase (PostgreSQL) — existing `pattern_alerts`, `assets`, `work_order_entities`, `system_settings` tables. No new tables.
**Testing**: Manual testing via admin screen
**Target Platform**: Web (PWA via Flutter Web)
**Project Type**: Web application (Flutter frontend + FastAPI backend + Supabase DB)
**Performance Goals**: Suggestions endpoint < 1s for typical alert volume (~50 alerts, ~20 distinct equipment_ids)
**Constraints**: Single Linux server; no new dependencies
**Scale/Scope**: ~50 pattern alerts, ~20 distinct equipment_ids, ~200 assets max

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend endpoint + frontend UI section. No migration needed (uses existing tables). |
| II. Explicit Over Automatic | PASS | Suggestions are displayed for Admin review — no auto-creation of assets |
| III. Role-Based Access Control | PASS | Suggestions endpoint uses `_admin_check()`. Only visible on Admin-only Asset Registry screen. |
| IV. Server-First File Storage | N/A | No file storage involved |
| V. Client-Side Computation | PASS | Suggestions computed server-side (requires cross-table query), displayed as-is on frontend |
| VI. Audit Everything | PASS | Dismiss action logged via `log_activity()` |
| VII. Simplicity & YAGNI | PASS | No new tables — dismissed list stored as JSON in existing `system_settings`. No configurable threshold. |

All gates pass. No violations.

## Project Structure

### Documentation (this feature)

```text
specs/055-asset-auto-suggest/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── api-endpoints.md
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── asset_registry.py        # MODIFIED — add suggestions + dismiss endpoints

frontend/
├── lib/
│   ├── services/
│   │   └── asset_service.dart   # MODIFIED — add fetchSuggestions() + dismissSuggestion()
│   └── screens/
│       └── admin/
│           └── asset_registry_screen.dart  # MODIFIED — add Suggestions section
│           └── asset_edit_screen.dart      # MODIFIED — accept pre-filled name/type from suggestion
```

**Structure Decision**: No new files. All changes modify existing files from spec 053. The feature adds 2 backend endpoints and a UI section to the existing Asset Registry screen.

## Complexity Tracking

> No violations. Table not needed.
