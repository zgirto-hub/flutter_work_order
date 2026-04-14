# Tasks: Shared Systems Table

**Input**: Design documents from `/specs/056-shared-systems-table/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/systems-api.md, quickstart.md

**Tests**: No automated tests requested. Manual testing via browser and SQL editor.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Context for implementer**: This tasks.md is written for an LLM (opencode) to execute. Read the referenced design documents before starting. After implementation, Claude Code will review via superpowers code review.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `backend/routers/`, `backend/main.py`
- **Frontend**: `frontend/lib/models/`, `frontend/lib/services/`, `frontend/lib/screens/`
- **Migrations**: `supabase/migrations/`

---

## Phase 1: Setup

**Purpose**: No new setup needed — project structure already exists. Skip to Phase 2.

---

## Phase 2: Foundational (Database Migration + Backend CRUD Router)

**Purpose**: Create the `systems` table, seed data, migrate FK references, and provide the CRUD API. This phase BLOCKS all frontend work.

**⚠️ CRITICAL**: No frontend tasks can begin until this phase is complete.

**Reference docs**: Read `specs/056-shared-systems-table/data-model.md` for full schema. Read `specs/056-shared-systems-table/contracts/systems-api.md` for endpoint contracts. Read `specs/056-shared-systems-table/research.md` for design decisions.

### Database Migration (US4 — Data migration preserves all existing references)

- [X] T001 [US4] Create migration file `supabase/migrations/YYYYMMDDHHMMSS_create_systems_table.sql` (use current timestamp). The migration MUST do the following in order:

  **Step 1 — Create `systems` table**:
  ```sql
  CREATE TABLE IF NOT EXISTS systems (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      name text NOT NULL,
      category text DEFAULT NULL,
      sort_order integer NOT NULL DEFAULT 0,
      is_active boolean NOT NULL DEFAULT true,
      needs_review boolean NOT NULL DEFAULT false,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
  );
  CREATE UNIQUE INDEX idx_systems_name_lower ON systems(LOWER(name));
  CREATE INDEX idx_systems_active ON systems(is_active) WHERE is_active = true;
  CREATE INDEX idx_systems_sort ON systems(sort_order);
  ```

  **Step 2 — Seed 24 canonical systems** from the current ALLOWED_SYSTEMS list in `backend/routers/system_status.py` (lines 9–33). Use the exact order as sort_order (1-based). Auto-detect categories:
  - Names starting with "International Circuits" → category = 'International Circuits'
  - Names starting with "INDRA CCTV" → category = 'INDRA CCTV'
  - All others → category = NULL

  **Step 3 — Migrate `asset_system_links`**:
  - ADD COLUMN `system_id uuid`
  - UPDATE `asset_system_links` SET `system_id` = matching `systems.id` by case-insensitive name match (`LOWER(asset_system_links.system) = LOWER(systems.name)`)
  - For any unmatched values: INSERT into `systems` with `needs_review=true`, `is_active=true`, `sort_order` = next available number, then UPDATE the link
  - ADD FOREIGN KEY constraint on `system_id` REFERENCES `systems(id)`
  - ALTER COLUMN `system_id` SET NOT NULL
  - DROP old indexes: `idx_asset_system_links_unique` and `idx_asset_system_links_primary_standby`
  - CREATE new indexes: `UNIQUE INDEX idx_asset_system_links_unique ON asset_system_links(asset_id, system_id, role)` and `UNIQUE INDEX idx_asset_system_links_primary_standby ON asset_system_links(system_id, role) WHERE role IN ('primary', 'standby')`
  - DROP COLUMN `system` (the old text column)

  **Step 4 — Migrate `system_status_reports`**:
  - ADD COLUMN `system_id uuid`
  - UPDATE `system_status_reports` SET `system_id` = matching `systems.id` by case-insensitive name match
  - For any unmatched values: same approach as Step 3
  - ADD FOREIGN KEY constraint on `system_id` REFERENCES `systems(id)`
  - ALTER COLUMN `system_id` SET NOT NULL
  - DROP COLUMN `system_name`

### Backend CRUD Router

- [X] T002 [US1] Create `backend/routers/systems.py` — new CRUD router for systems. Follow the contract in `specs/056-shared-systems-table/contracts/systems-api.md` exactly:
  - `GET /systems` — list systems with `active_only` (default true) and `needs_review` (default false) query params. Order by `sort_order ASC`. Return `{"systems": [...]}`.
  - `POST /systems` — create a new system. Accept `name` (required), `category` (optional), `sort_order` (optional, default to max+1). Validate name uniqueness (case-insensitive) — return 409 if duplicate. Admin-only.
  - `PATCH /systems/{id}` — update name, category, and/or sort_order. Validate name uniqueness on rename. Return 404 if not found, 409 if duplicate name. Admin-only.
  - `PATCH /systems/{id}/retire` — set `is_active=false`. If system has unresolved status reports (resolved_at IS NULL), include a `warning` field in the response with the count. Return 404 if not found. Admin-only.
  - `PATCH /systems/{id}/activate` — set `is_active=true`. Return 404 if not found. Admin-only.
  - Use Pydantic models for request/response bodies. Import `supabase` from `db`.
  - Log all mutations via `backend/utils/activity.py` with category `admin` (follow existing patterns in other routers like `asset_registry.py`).

- [ ] T003 [US1] Register the systems router in `backend/main.py`. Add `from routers.systems import router as systems_router` and `app.include_router(systems_router, prefix="/api", tags=["systems"])`. Follow the existing pattern for other routers in the file.

### Modify Existing Backend Routers

- [ ] T004 [P] [US3] Modify `backend/routers/system_status.py`:
  - DELETE the `ALLOWED_SYSTEMS` list (lines 9–33).
  - Create a helper function `async def _get_active_systems()` that queries the `systems` table for `is_active=true` rows ordered by `sort_order ASC`. Return list of dicts.
  - In `get_today_status()` (line 56): replace `for name in ALLOWED_SYSTEMS` loop with iteration over `_get_active_systems()`. Build the systems list using `system["name"]` instead of bare string. The response format stays the same (`system_name`, `status`, `active_report`).
  - In `get_history()` (line 83): replace `if system_name not in ALLOWED_SYSTEMS` validation with a DB query check (`systems` table where `LOWER(name)` matches).
  - In `report_issue()` (line 106): same validation change — check against DB instead of Python list.
  - **IMPORTANT**: The `system_status_reports` table now uses `system_id` FK instead of `system_name` text. Update ALL queries that previously filtered/matched on `system_name` to JOIN with `systems` table via `system_id`. When the frontend sends `system_name` as a string, look up the corresponding `system_id` from the `systems` table first.
  - Any other function in this file that references `ALLOWED_SYSTEMS` or queries `system_name` directly must be updated similarly.

- [ ] T005 [P] [US3] Modify `backend/routers/ai_insights.py`:
  - DELETE the `ALLOWED_SYSTEMS` list (lines 18–42).
  - In `_aggregate_system_status_stats()` and any other function that references `ALLOWED_SYSTEMS`: replace with a query to the `systems` table (active, ordered by sort_order). The queries that previously matched on `system_name` text column in `system_status_reports` must now JOIN via `system_id`.

- [ ] T006 [P] [US2] Modify `backend/routers/asset_registry.py`:
  - In `get_domain_knowledge_block()`: the `asset_system_links` table no longer has a `system` text column. Update queries to JOIN `asset_system_links.system_id` → `systems.id` to get the system name. The output format should remain the same (showing system name and role).
  - Update any other queries in this file that reference `asset_system_links.system` to use `system_id` JOIN instead.

**Checkpoint**: After Phase 2, the backend is fully functional. All endpoints work with the new `systems` table. The `ALLOWED_SYSTEMS` constants are deleted from both Python files. Verify by calling `GET /api/systems` and `GET /api/system-status/today`.

---

## Phase 3: User Story 1 — Manage the canonical list of systems (Priority: P1) 🎯 MVP

**Goal**: Administrators can view, add, rename, and retire systems from a dedicated admin screen.

**Independent Test**: Navigate to admin Systems screen → verify 24 systems listed → add a new system → rename one → retire one → all changes reflected immediately.

### Implementation for User Story 1

- [ ] T007 [P] [US1] Create `frontend/lib/models/system.dart` — System model class:
  ```dart
  class System {
    final String id;
    final String name;
    final String? category;
    final int sortOrder;
    final bool isActive;
    final bool needsReview;
    final DateTime createdAt;
    final DateTime updatedAt;

    // fromJson constructor mapping from snake_case API response
    // toJson for POST/PATCH requests (only name, category, sort_order)
  }
  ```

- [ ] T008 [P] [US1] Create `frontend/lib/services/systems_service.dart` — SystemsService:
  - `Future<List<System>> fetchSystems({bool activeOnly = true, bool needsReview = false})` — GET /api/systems with query params
  - `Future<System> createSystem({required String name, String? category, int? sortOrder})` — POST /api/systems
  - `Future<System> updateSystem(String id, {String? name, String? category, int? sortOrder})` — PATCH /api/systems/{id}
  - `Future<Map<String, dynamic>> retireSystem(String id)` — PATCH /api/systems/{id}/retire (returns system + optional warning)
  - `Future<System> activateSystem(String id)` — PATCH /api/systems/{id}/activate
  - Use the existing HTTP pattern from other services (e.g., `asset_registry_service.dart`): base URL from `config.dart`, auth headers from `supabase_flutter`.

- [ ] T009 [US1] Create `frontend/lib/screens/admin/systems_screen.dart` — Admin Systems management screen:
  - **List view**: Show all systems (active + retired) fetched via `SystemsService.fetchSystems(activeOnly: false)`. Display: name, category (if present), sort_order, active/retired badge, needs_review badge (if true). Order by sort_order.
  - **Add system**: FloatingActionButton opens a dialog with fields: name (required), category (optional), sort_order (optional, defaults to next available). Calls `createSystem()`. Refresh list on success.
  - **Rename**: Tap a system row → dialog with current name pre-filled → calls `updateSystem()` with new name. Refresh on success.
  - **Retire**: Swipe or long-press → confirmation dialog. If the retire response includes a `warning`, show it in the dialog before confirming. Calls `retireSystem()`. Refresh on success.
  - **Activate**: For retired systems, show a re-activate button/action. Calls `activateSystem()`.
  - **Needs review filter**: Optional toggle to show only `needs_review=true` systems (for post-migration cleanup).
  - Follow the existing admin screen patterns (e.g., `AssetRegistryScreen` for layout, `AppTheme` for styling, `SectionLabel`/`EmptyState` from `claude_widgets.dart`).
  - Admin role check: only accessible to admin users.

- [ ] T010 [US1] Modify `frontend/lib/screens/settings_page.dart` — Add "Systems" entry to the admin section. Insert a new `SettingsRow` BETWEEN the "Asset Registry" row (line ~367) and the "Department Routing" row (line ~368):
  ```dart
  SettingsRow(
    icon: Icons.dns_outlined,
    label: 'Systems',
    subtitle: 'Manage infrastructure systems',
    showDivider: true,
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SystemsScreen(),
      ),
    ),
  ),
  ```
  Add the import for `SystemsScreen` at the top of the file.

**Checkpoint**: US1 complete. Admin can fully manage systems. Verify: open Settings → admin section → "Systems" → list shows 24 systems → add/rename/retire all work.

---

## Phase 4: User Story 2 — Unified system dropdown in Asset Registry (Priority: P2)

**Goal**: Asset Registry system selector shows all active systems from the central table instead of 4 hardcoded suggestions. No free-text entry allowed.

**Independent Test**: Edit an asset → open system selector → verify all active systems appear → search works → retired systems excluded → existing links to retired systems shown read-only.

### Implementation for User Story 2

- [ ] T011 [US2] Modify `frontend/lib/models/asset.dart` — Remove the `systemSuggestions` static constant (lines 64–69). This list is no longer needed since the system selector will fetch from the API.

- [ ] T012 [US2] Modify `frontend/lib/screens/admin/asset_edit_screen.dart` — Replace the `Autocomplete<String>` widget (lines ~191–197 that use `Asset.systemSuggestions`) with a searchable dropdown backed by `SystemsService`:
  - Fetch active systems via `SystemsService.fetchSystems(activeOnly: true)` (can cache the result for the screen's lifetime).
  - Replace the Autocomplete with a `DropdownButtonFormField<String>` or searchable dropdown that shows system names from the API response.
  - The dropdown should filter as the user types (search by name substring, case-insensitive).
  - **No free-text entry**: the user MUST select from the list. Remove any ability to type arbitrary text.
  - When the user selects a system, use the system name (same as before) for the `_service.addLink()` call — the backend `asset_registry.py` handles looking up the `system_id` from the name. **OR** if the backend expects `system_id` now, pass the system's `id` from the fetched System model instead.
  - For existing asset links that reference a retired system: show the system name as read-only text (not in a dropdown), so users can see what it was but can't re-select it.

**Checkpoint**: US2 complete. Asset Registry uses live system data. Verify: edit asset → system dropdown shows all active systems → cannot enter free text → retired systems not in dropdown but shown on existing links.

---

## Phase 5: User Story 3 — System Status screen uses shared table (Priority: P2)

**Goal**: System Status screen dynamically shows systems from the database instead of a hardcoded backend list.

**Independent Test**: Add a new system via admin screen → refresh System Status → new system appears in the grid.

### Implementation for User Story 3

- [ ] T013 [US3] Verify that the System Status screen frontend (`frontend/lib/screens/system_status_screen.dart`) already works correctly after the backend changes in T004. The frontend fetches systems from `GET /system-status/today` which now queries the DB. No frontend changes should be needed UNLESS the response format changed. If the response format is identical (it should be — T004 preserves the `system_name` key in the response), this task is just manual verification:
  - Load System Status screen → all 24 systems appear
  - Grouping by prefix (International Circuits, INDRA CCTV) still works
  - Systems appear in the correct order (by sort_order)
  - Add a new system via admin screen → refresh → new system appears

**Checkpoint**: US3 complete. System Status screen is fully dynamic. No hardcoded lists remain in the backend.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup, audit logging, and final verification.

- [ ] T014 [P] Verify audit logging: confirm that all system CRUD operations (create, rename, retire, activate) produce entries in `user_activity_log` with category `admin`. Check `backend/routers/systems.py` calls `log_activity()` from `backend/utils/activity.py`.

- [ ] T015 [P] Remove the `systemSuggestions` reference from any other file that may import it. Search the codebase for `systemSuggestions` and `Asset.systemSuggestions` — there should be zero references remaining after T011.

- [ ] T016 [P] Verify `backend/routers/asset_registry.py` `get_domain_knowledge_block()` output: the function should still produce the same format string (`"- {asset_name} ({type}, {location}): {system_name} [{role}]"`) but now gets system_name via JOIN. Run the domain knowledge endpoint and verify output looks correct.

- [ ] T017 Run the quickstart.md testing checklist (`specs/056-shared-systems-table/quickstart.md`) — go through every item and verify.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 2 (Foundational)**: No dependencies — start immediately. BLOCKS all frontend phases.
- **Phase 3 (US1 — Admin screen)**: Depends on Phase 2 (needs backend CRUD + migration)
- **Phase 4 (US2 — Asset Registry)**: Depends on Phase 2 (needs backend changes to asset_registry.py) + depends on T007, T008 from Phase 3 (System model and service)
- **Phase 5 (US3 — System Status)**: Depends on Phase 2 only (T004 backend changes). No frontend changes expected.
- **Phase 6 (Polish)**: Depends on all previous phases.

### User Story Dependencies

- **US4 (Migration)**: No dependencies — done in Phase 2 as T001
- **US1 (Admin CRUD)**: Depends on US4 (migration) + T002-T003 (backend router)
- **US2 (Asset Registry)**: Depends on US4 (migration) + T006 (backend asset_registry changes) + T007-T008 (System model/service from US1)
- **US3 (System Status)**: Depends on US4 (migration) + T004 (backend system_status changes) — frontend should work without changes

### Within Phase 2 (Backend)

- T001 (migration) MUST run first — all other Phase 2 tasks depend on it
- T002 + T003 can run together (new router + registration)
- T004, T005, T006 can all run in parallel (different files, no dependencies on each other)

### Within Phase 3 (US1 Frontend)

- T007 and T008 can run in parallel (model + service, different files)
- T009 depends on T007 + T008 (screen uses model and service)
- T010 depends on T009 (nav entry needs screen to exist)

### Parallel Opportunities

```
Phase 2 (after T001 migration):
  T002 + T003  ──┐
  T004           ├── all parallel (different files)
  T005           │
  T006          ──┘

Phase 3 (after Phase 2):
  T007 ──┐
  T008 ──┴── T009 → T010

Phase 4 (after T007 + T008):
  T011 ──┐
  T012 ──┘ parallel (different files)

Phase 5 (after T004):
  T013 (verification only)

Phase 6 (after all):
  T014, T015, T016 parallel → T017
```

---

## Implementation Strategy

### MVP First (Phase 2 + Phase 3 = US4 + US1)

1. Complete Phase 2: Migration + Backend CRUD + Backend modifications
2. Complete Phase 3: Admin Systems screen + navigation
3. **STOP and VALIDATE**: All 24 systems visible in admin screen. Add/rename/retire works. System Status screen still works. ALLOWED_SYSTEMS deleted from both Python files.
4. This is a deployable MVP — the shared table is live and manageable.

### Incremental Delivery

1. Phase 2 → Backend complete, migration done
2. Phase 3 (US1) → Admin screen → **Deploy MVP**
3. Phase 4 (US2) → Asset Registry uses live dropdown → Deploy
4. Phase 5 (US3) → Verify System Status works (likely already works) → Deploy
5. Phase 6 → Cleanup and final verification

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- `work_order_entities.system` and `pattern_alerts.system` are explicitly OUT OF SCOPE — do not touch these columns
- The `system_status_reports` table's `system_name` column is being replaced by `system_id` FK — every backend query that used `system_name` must be updated to JOIN via `system_id`
- After implementation, Claude Code will review all changes via superpowers code review
- Commit after each task or logical group
- When in doubt, read the referenced design docs in `specs/056-shared-systems-table/`
