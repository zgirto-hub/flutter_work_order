# Implementation Plan: Shared Systems Table

**Branch**: `056-shared-systems-table` | **Date**: 2026-04-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/056-shared-systems-table/spec.md`

## Summary

Replace all hardcoded system name lists (ALLOWED_SYSTEMS in two Python files, systemSuggestions in Dart) and free-text system columns with a single `systems` database table. All references migrate to FK. A new admin screen allows CRUD operations on systems without code deploys. The migration preserves all existing data and seeds the table from the current 24-system canonical list.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend)  
**Storage**: Supabase (PostgreSQL) — new `systems` table; modified `asset_system_links`, `system_status_reports`  
**Testing**: Manual testing via browser (PWA) and Supabase SQL editor  
**Target Platform**: Web (PWA), Linux server (backend)  
**Project Type**: Web application (full-stack)  
**Performance Goals**: System list endpoint < 200ms (trivial — ~24 rows)  
**Constraints**: Single server, no CDN, Supabase migrations applied in timestamp order  
**Scale/Scope**: ~24 systems, ~50 existing asset_system_links, ~500 system_status_reports

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | ✅ PASS | Feature spans all layers: migration, backend router, frontend model/service/screen, navigation wiring |
| II. Explicit Over Automatic | ✅ PASS | System retirement is explicit (admin action with confirmation). No auto-assignment or implicit state changes |
| III. Role-Based Access Control | ✅ PASS | Only admin role can manage systems (POST/PATCH/retire). All authenticated users can read |
| IV. Server-First File Storage | ✅ N/A | No file storage involved |
| V. Client-Side Computation | ✅ PASS | Systems list is small (~24 items), fetched once and cached client-side for dropdown filtering |
| VI. Audit Everything | ✅ PASS | System CRUD operations will be logged via `user_activity_log` with category `admin` |
| VII. Simplicity & YAGNI | ✅ PASS | No over-engineering — simple CRUD table with FK migration. No caching layer, no event system, no complex abstractions |

**Post-Phase 1 re-check**: All gates still pass. Data model uses straightforward FK relationships. No complexity violations.

## Project Structure

### Documentation (this feature)

```text
specs/056-shared-systems-table/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── systems-api.md   # REST API contract
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   ├── systems.py              # NEW — CRUD router
│   ├── system_status.py        # MODIFY — remove ALLOWED_SYSTEMS, query DB
│   ├── ai_insights.py          # MODIFY — remove ALLOWED_SYSTEMS, query DB
│   └── asset_registry.py       # MODIFY — JOINs through system_id
└── main.py                     # MODIFY — register systems router

frontend/
├── lib/
│   ├── models/
│   │   ├── system.dart          # NEW — System model
│   │   └── asset.dart           # MODIFY — remove systemSuggestions
│   ├── services/
│   │   └── systems_service.dart # NEW — SystemsService
│   └── screens/
│       ├── admin/
│       │   ├── systems_screen.dart     # NEW — admin management screen
│       │   └── asset_edit_screen.dart  # MODIFY — use SystemsService dropdown
│       └── settings_page.dart          # MODIFY — add Systems nav entry

supabase/
└── migrations/
    └── YYYYMMDDHHMMSS_create_systems_table.sql  # NEW — table + seed + FK migration
```

**Structure Decision**: Standard full-stack layout matching existing project conventions. No new directories needed — all files slot into existing `routers/`, `models/`, `services/`, `screens/admin/` directories.

## Implementation Phases

### Phase 1 — Database Migration (P1 prerequisite)

Create the `systems` table and migrate existing FK references. See [data-model.md](data-model.md) for full schema.

**Steps**:
1. Create `systems` table with id, name, category, sort_order, is_active, needs_review, timestamps
2. Seed 24 rows from ALLOWED_SYSTEMS with correct sort_order and auto-detected categories
3. Add `system_id uuid` column to `asset_system_links`
4. Populate `system_id` by matching `asset_system_links.system` → `systems.name` (case-insensitive)
5. For unmatched values: INSERT into `systems` with `needs_review=true`, then link
6. Add `system_id uuid` column to `system_status_reports`
7. Populate `system_id` by matching `system_status_reports.system_name` → `systems.name`
8. Add FK constraints and NOT NULL to both `system_id` columns
9. Drop old indexes on text columns, create new indexes on `system_id`
10. Drop old text columns (`asset_system_links.system`, `system_status_reports.system_name`)

### Phase 2 — Backend Endpoints

New CRUD router + modify existing routers. See [contracts/systems-api.md](contracts/systems-api.md).

**New**: `backend/routers/systems.py`
- GET /api/systems — list (active_only, needs_review filters)
- POST /api/systems — create (admin only)
- PATCH /api/systems/{id} — update name/category/sort_order (admin only)
- PATCH /api/systems/{id}/retire — soft-delete (admin only, warning if open reports)
- PATCH /api/systems/{id}/activate — re-activate (admin only)

**Modify**: `backend/routers/system_status.py`
- Delete `ALLOWED_SYSTEMS` constant (lines 9–33)
- `get_today_status()`: query `systems` table (active, ordered by sort_order) instead of iterating constant
- `get_history()`: validate system_name against DB query instead of Python list
- `report_issue()`: validate system_name against DB query

**Modify**: `backend/routers/ai_insights.py`
- Delete `ALLOWED_SYSTEMS` constant (lines 18–42)
- `_aggregate_system_status_stats()`: query `systems` table instead of using constant

**Modify**: `backend/routers/asset_registry.py`
- `get_domain_knowledge_block()`: JOIN `asset_system_links` → `systems` via `system_id` to get system names

**Modify**: `backend/main.py` — register systems router

### Phase 3 — Frontend: Asset Registry Integration

Replace hardcoded suggestions with live data from the systems endpoint.

**New**: `frontend/lib/models/system.dart` — System model with fromJson
**New**: `frontend/lib/services/systems_service.dart` — fetchSystems(activeOnly: true)

**Modify**: `frontend/lib/models/asset.dart` — remove `systemSuggestions` constant
**Modify**: `frontend/lib/screens/admin/asset_edit_screen.dart` — replace `Autocomplete<String>` using `Asset.systemSuggestions` with a searchable dropdown populated from `SystemsService`. No free-text entry allowed.

### Phase 4 — Frontend: Admin Systems Screen

New standalone admin screen for managing systems.

**New**: `frontend/lib/screens/admin/systems_screen.dart`
- Paginated list showing name, category, sort_order, active badge, needs_review badge
- Add system: dialog with name, category, sort_order fields
- Rename: inline edit or dialog
- Retire: confirmation dialog with warning count of open status reports
- Activate: one-tap for retired systems

**Modify**: `frontend/lib/screens/settings_page.dart`
- Add SettingsRow for "Systems" between "Asset Registry" and "Department Routing" (after line 367)
- Icon: `Icons.dns_outlined`, Label: "Systems", Subtitle: "Manage infrastructure systems"

## Complexity Tracking

No constitution violations. No complexity justifications needed.
