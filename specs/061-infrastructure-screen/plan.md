# Implementation Plan: Infrastructure Screen (Unify Systems + Asset Registry)

**Branch**: `061-infrastructure-screen` | **Date**: 2026-04-14 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/061-infrastructure-screen/spec.md`

## Summary

Replace the separate Systems admin and Asset Registry screens with a single system-centric **Infrastructure** screen. Adds a `has_contingency` flag to systems and a `site` (production/contingency) column to asset-system links, so one detail page can show every system's deployment topology grouped by site and role. Includes a one-time data migration that converts the 10 INDRA CCTV "Camera N" systems into camera assets, removes the 6 International Circuit systems (repointing their asset links and `system_status_reports` to AIDA-NG with conflict-demotion to `client`), and sets the correct `has_contingency` value for the 7 real systems.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client (backend); `http`, `supabase_flutter`, Flutter Material (frontend)
**Storage**: Supabase (PostgreSQL) — existing `systems`, `assets`, `asset_system_links`, `system_status_reports` tables; no new tables
**Testing**: pytest (backend migration tests), Flutter widget tests (frontend smoke tests for detail page)
**Target Platform**: Flutter web (primary PWA target) + Linux server for backend
**Project Type**: Web application (FastAPI backend + Flutter frontend)
**Performance Goals**: Infrastructure overview loads in <500ms with 7 systems; detail page loads with grouping in <300ms for typical asset counts (≤50 links per system)
**Constraints**: Admin-only screen (JWT + admin user_type check); migration must be idempotent and complete in a single SQL file; no breaking change to System Status feature
**Scale/Scope**: 7 real systems post-migration, up to ~100 assets total across all systems; two new Flutter screens + one bottom sheet replacing three deleted screens

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Notes |
|-----------|-----------|-------|
| I. Full-Stack Ownership | ✅ | Plan spans migration, backend endpoint updates, Flutter model/service/screens, navigation wiring, and docs |
| II. Explicit Over Automatic | ✅ | Site moves on `has_contingency` toggle require explicit admin confirmation (no silent data changes); migration's demote-to-client is documented and deterministic |
| III. Role-Based Access Control | ✅ | Admin-only endpoints preserved (existing `_admin_check`); no RLS changes |
| IV. Server-First File Storage | ✅ | No file storage involved |
| V. Client-Side Computation Where Possible | ✅ | Overview filters (Show Retired, Needs Review, Category) executed client-side on loaded system list; backend provides raw data |
| VI. Audit Everything | ✅ | `log_activity` already called for system CRUD and asset link changes; migration logs one summary activity entry |
| VII. Simplicity & YAGNI | ✅ | Two column additions (no new tables), reuses existing CRUD endpoints, one new detail endpoint only |

**Gate result: PASS.** No violations requiring Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/061-infrastructure-screen/
├── plan.md              # This file
├── spec.md              # Feature specification (ready)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (API contracts)
│   └── systems-detail.md
├── checklists/
│   └── requirements.md  # From /speckit.specify
└── tasks.md             # /speckit.tasks output (not created here)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── systems.py              # MODIFIED: add GET /systems/{id}/detail; accept has_contingency on PATCH
├── routers/
│   └── asset_registry.py       # MODIFIED: accept `site` on POST /assets/{id}/links; add PATCH /links/{id}
└── (no new files)

supabase/
└── migrations/
    └── 20260414150000_infrastructure_refactor.sql   # NEW: add columns, transform seed data, update constraints

frontend/
└── lib/
    ├── models/
    │   ├── system.dart          # MODIFIED: add hasContingency
    │   └── asset.dart           # MODIFIED: AssetSystemLink gains `site`
    ├── services/
    │   ├── systems_service.dart # MODIFIED: fetchSystemDetail(id); updateHasContingency
    │   └── asset_service.dart   # MODIFIED: addLink accepts site; updateLinkSite/updateLinkRole
    ├── screens/
    │   └── admin/
    │       ├── infrastructure_screen.dart          # NEW: replaces systems_screen.dart (overview)
    │       ├── system_detail_screen.dart           # NEW: detail page with Production/Contingency sections
    │       └── widgets/
    │           └── add_asset_to_system_sheet.dart  # NEW: bottom sheet for adding/creating a linked asset
    └── screens/
        └── settings_page.dart    # MODIFIED: single "Infrastructure" entry replacing Systems + Asset Registry

frontend/lib/screens/admin/systems_screen.dart        # DELETED
frontend/lib/screens/admin/asset_registry_screen.dart # DELETED
frontend/lib/screens/admin/asset_edit_screen.dart     # DELETED
```

**Structure Decision**: Web application layout (Option 2). Backend (`backend/`) and frontend (`frontend/`) are separate trees as in the rest of the project; Supabase migrations live under `supabase/migrations/`. The feature touches all three.

## Complexity Tracking

No violations; table omitted.
