# Implementation Plan: Asset Registry

**Branch**: `053-asset-registry` | **Date**: 2026-04-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/053-asset-registry/spec.md`

## Summary

Add an Asset Registry module that models DGCA physical infrastructure (workstations, servers, cameras, etc.) with system associations. The registry is Admin-managed via a dedicated CRUD screen. The entity extraction pipeline reads from the registry at runtime to build a dynamic domain knowledge prompt block, replacing the current hardcoded system list. Pattern alerts are enriched with asset metadata (location, role, hosted systems).

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend)
**Storage**: Supabase (PostgreSQL) — new `assets` and `asset_system_links` tables
**Testing**: Manual testing via admin screen + extraction pipeline verification
**Target Platform**: Web (PWA via Flutter Web)
**Project Type**: Web application (Flutter frontend + FastAPI backend + Supabase DB)
**Performance Goals**: Admin CRUD < 30s per operation; extraction prompt generation < 500ms for 200 assets
**Constraints**: Single Linux server; no cloud storage; Gemma 4 E2B via local Ollama
**Scale/Scope**: ~200 assets, ~6-8 known systems, ~500 asset-system links max

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Feature spans all layers: migration, backend router, frontend model/service/screen, navigation wiring |
| II. Explicit Over Automatic | PASS | Admin explicitly manages assets and associations; no auto-inference |
| III. Role-Based Access Control | PASS | Admin-only screen; FR-014 enforces role gating. Backend uses `_admin_check()` pattern |
| IV. Server-First File Storage | N/A | No file uploads in this feature |
| V. Client-Side Computation | PASS | Asset list loaded once, filtered client-side (type filter, name search) |
| VI. Audit Everything | PASS | All CRUD operations will log to `user_activity_log` via `log_activity()` |
| VII. Simplicity & YAGNI | PASS | Fixed type list, no system management UI, no caching layer — simplest approach |

**Technology Constraints**:
- Frontend: Flutter (Dart) targeting web — PASS (standard StatefulWidget + service pattern)
- Backend: FastAPI on Uvicorn — PASS (standard router pattern)
- Database: Supabase PostgreSQL with timestamped migration — PASS
- `backend/version.json`: Not touched

All gates pass. No violations.

## Project Structure

### Documentation (this feature)

```text
specs/053-asset-registry/
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
│   └── asset_registry.py        # NEW — CRUD endpoints + registry query
├── services/
│   ├── entity_extractor.py      # MODIFIED — dynamic prompt from registry
│   └── pattern_engine.py        # MODIFIED — alert enrichment with asset context

frontend/
├── lib/
│   ├── models/
│   │   └── asset.dart           # NEW — Asset + AssetSystemLink models
│   ├── services/
│   │   └── asset_service.dart   # NEW — HTTP client for asset registry API
│   ├── screens/
│   │   └── admin/
│   │       ├── asset_registry_screen.dart  # NEW — main list screen
│   │       └── asset_edit_screen.dart      # NEW — add/edit form + system links
│   └── screens/
│       └── settings_page.dart   # MODIFIED — add navigation entry
│       └── manual_assistant/
│           └── widgets/
│               └── alert_card.dart  # MODIFIED — show asset context

supabase/
└── migrations/
    └── 20260414100000_create_asset_registry.sql  # NEW
```

**Structure Decision**: Follows existing web application layout. New files are placed in the established `routers/`, `models/`, `services/`, `screens/admin/` directories. Two modified backend services (entity_extractor, pattern_engine) and two modified frontend files (settings_page, alert_card).

## Complexity Tracking

> No violations. Table not needed.
