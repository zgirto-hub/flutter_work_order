# Tasks: Asset Registry

**Input**: Design documents from `/specs/053-asset-registry/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api-endpoints.md
**Branch**: `053-asset-registry`

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)

## Reference Files

Before starting, read these design documents to understand the full context:

| Document | Path | Purpose |
|----------|------|---------|
| Spec | `specs/053-asset-registry/spec.md` | User stories, requirements, acceptance criteria |
| Plan | `specs/053-asset-registry/plan.md` | Technical context, project structure, constitution |
| Data Model | `specs/053-asset-registry/data-model.md` | Table schemas, indexes, constraints, seed data |
| API Contracts | `specs/053-asset-registry/contracts/api-endpoints.md` | All endpoint signatures, request/response shapes, error codes |
| Research | `specs/053-asset-registry/research.md` | Design decisions and rationale |
| Quickstart | `specs/053-asset-registry/quickstart.md` | Setup steps and verification procedure |

## Existing Code Patterns to Follow

Study these files before implementing — they define the project conventions:

| Pattern | Example File | What to Copy |
|---------|-------------|-------------|
| Backend router | `backend/routers/patterns.py` | Router setup, `_admin_check()`, Pydantic models, `log_activity()` calls, error format |
| Frontend service | `frontend/lib/services/pattern_service.dart` | HTTP client class, `_headers()`, `AppConfig.baseUrl`, error handling |
| Frontend model | `frontend/lib/models/pattern_rule.dart` | `fromJson`, `toJson`, `copyWith` pattern |
| Frontend admin screen | `frontend/lib/screens/admin/departments_screen.dart` | StatefulWidget, `_loading`/`_error` states, `initState` → load |
| Frontend edit screen | `frontend/lib/screens/manual_assistant/rules_tab.dart` → `RuleEditScreen` | Navigator.push with bool return, form fields, save/cancel |
| Admin navigation | `frontend/lib/screens/settings_page.dart` | `SettingsRow` inside `if (widget.userRole == 'admin')` block |
| Alert card | `frontend/lib/screens/manual_assistant/widgets/alert_card.dart` | Widget structure for displaying pattern alerts |
| Migration | `supabase/migrations/20260413200000_create_pattern_engine.sql` | Table creation, indexes, CHECK constraints, seed INSERT |
| Activity logging | `backend/utils/activity.py` | `log_activity(user_email, category, action, target_label, target_id)` |

---

## Phase 1: Setup

**Purpose**: Database schema — everything else depends on this

- [X] T001 Create migration file `supabase/migrations/20260414100000_create_asset_registry.sql` with:
  - `assets` table: id (UUID PK default gen_random_uuid()), name (text NOT NULL UNIQUE), type (text NOT NULL CHECK in 7 values: 'workstation','server','camera','router','switch','media_converter','power_adapter'), location (text NOT NULL), notes (text DEFAULT ''), created_at (timestamptz NOT NULL DEFAULT now()), updated_at (timestamptz NOT NULL DEFAULT now())
  - `asset_system_links` table: id (UUID PK default gen_random_uuid()), asset_id (UUID NOT NULL FK → assets(id) ON DELETE CASCADE), system (text NOT NULL), role (text NOT NULL CHECK in 'primary','standby','client'), created_at (timestamptz NOT NULL DEFAULT now())
  - Indexes: UNIQUE on assets(name), INDEX on assets(type), UNIQUE on asset_system_links(asset_id, system, role), UNIQUE on asset_system_links(system, role) WHERE role IN ('primary','standby'), INDEX on asset_system_links(asset_id)
  - ALTER TABLE pattern_alerts ADD COLUMN IF NOT EXISTS asset_context jsonb DEFAULT NULL
  - COMMENT ON TABLE for both new tables
  - Seed data: INSERT 6 AIDA-NG international circuit assets (Bahrain, Karachi, Tehran, Doha, Damascus, Beirut) as type 'router', location 'International Circuit', and INSERT their asset_system_links to AIDA-NG with role 'client'
  - Reference the full schema in `specs/053-asset-registry/data-model.md`

**Checkpoint**: Migration ready to apply. All subsequent tasks depend on this schema.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Backend router + frontend model/service — these are needed by ALL user story screens

**CRITICAL**: No user story UI work can begin until this phase is complete.

- [X] T002 [P] Create backend router `backend/routers/asset_registry.py` with:
  - `router = APIRouter(tags=["asset-registry"])`
  - `_admin_check(user_email)` helper (same pattern as `backend/routers/patterns.py`)
  - Pydantic models: `CreateAssetBody(name, type, location, notes)`, `UpdateAssetBody(name?, type?, location?, notes?)`, `CreateLinkBody(system, role)`
  - Constants: `VALID_TYPES = ["workstation", "server", "camera", "router", "switch", "media_converter", "power_adapter"]` and `VALID_ROLES = ["primary", "standby", "client"]`
  - Helper: `_fetch_asset_with_links(asset_id)` — queries asset + joins system_links, returns dict with `system_links` array
  - Helper: `get_domain_knowledge_block()` — queries all assets with links, formats as text block (see research.md R1 for format). Returns fallback string if registry empty.
  - Endpoints per `specs/053-asset-registry/contracts/api-endpoints.md`:
    - `GET /asset-registry/assets` — list all with system_links joined
    - `POST /asset-registry/assets` — create, validate type, check unique name (409), log_activity(category="asset", action="created_asset")
    - `PUT /asset-registry/assets/{asset_id}` — update fields, check unique name if changed (409), log_activity(category="asset", action="updated_asset")
    - `DELETE /asset-registry/assets/{asset_id}` — delete with cascade, log_activity(category="asset", action="deleted_asset")
    - `POST /asset-registry/assets/{asset_id}/links` — add link, validate role, check duplicate (409), check primary/standby uniqueness per system (409 with existing holder name), log_activity(category="asset", action="added_system_link")
    - `DELETE /asset-registry/links/{link_id}` — remove link, log_activity(category="asset", action="removed_system_link")
  - Register router in `backend/main.py`: add import and `app.include_router(asset_registry.router, prefix="/api")`

- [X] T003 [P] Create frontend model `frontend/lib/models/asset.dart` with:
  - `Asset` class: id (String), name (String), type (String), location (String), notes (String), createdAt (String), updatedAt (String), systemLinks (List<AssetSystemLink>)
  - `Asset.fromJson(Map<String, dynamic>)`, `Asset.toJson()`, `Asset.copyWith(...)`
  - `AssetSystemLink` class: id (String), system (String), role (String), createdAt (String)
  - `AssetSystemLink.fromJson(Map<String, dynamic>)`, `AssetSystemLink.toJson()`
  - Static const `List<String> assetTypes = ['workstation', 'server', 'camera', 'router', 'switch', 'media_converter', 'power_adapter']`
  - Static const `List<String> systemSuggestions = ['CADAS-ATS', 'CADAS-IMS', 'AIDA-NG', 'INDRA CCTV']`
  - Static const `List<String> linkRoles = ['primary', 'standby', 'client']`

- [X] T004 [P] Create frontend service `frontend/lib/services/asset_service.dart` with:
  - `AssetService` class (follow `pattern_service.dart` pattern exactly)
  - Private `_headers()` method for auth token
  - Methods:
    - `Future<List<Asset>> fetchAssets()` — GET /api/asset-registry/assets
    - `Future<Asset> createAsset({name, type, location, notes})` — POST /api/asset-registry/assets
    - `Future<Asset> updateAsset(String assetId, {name?, type?, location?, notes?})` — PUT /api/asset-registry/assets/{id}
    - `Future<void> deleteAsset(String assetId)` — DELETE /api/asset-registry/assets/{id}
    - `Future<AssetSystemLink> addLink(String assetId, {system, role})` — POST /api/asset-registry/assets/{id}/links
    - `Future<void> removeLink(String linkId)` — DELETE /api/asset-registry/links/{id}
  - All methods pass `user_email` as query param (same as pattern_service.dart)
  - Error handling: throw typed Exception messages for 409, 404, 400, and generic failures

**Checkpoint**: Backend API operational, frontend can call all endpoints. Ready for UI work.

---

## Phase 3: User Story 1 — Admin Manages Asset Inventory (Priority: P1) MVP

**Goal**: Admin can add, edit, delete assets via a dedicated screen with type filter and name search.

**Independent Test**: Navigate to Settings > Administration > Asset Registry. Add asset "TEST-01" (workstation, "Test Location"). Edit its location. Delete it. Filter by type. Search by name.

### Implementation for User Story 1

- [X] T005 [US1] Create asset list screen `frontend/lib/screens/admin/asset_registry_screen.dart` with:
  - StatefulWidget `AssetRegistryScreen` (follow `departments_screen.dart` pattern)
  - State: `_loading`, `_assets` (List<Asset>), `_filteredAssets`, `_searchQuery` (String), `_selectedType` (String? for filter)
  - `initState` → `_loadAssets()` calling `AssetService().fetchAssets()`
  - AppBar: title "Asset Registry", search icon toggling a TextField for name search
  - Filter: DropdownButton for asset type filter (All + 7 types), placed below AppBar or as a chip row
  - Client-side filtering: combine type filter + name search on `_assets` to produce `_filteredAssets`
  - ListView.builder of asset cards showing: name (bold), type (chip/badge), location, system count
  - Each card taps → Navigator.push to `AssetEditScreen(asset: asset)` with bool return to trigger reload
  - FAB: "Add Asset" → Navigator.push to `AssetEditScreen(asset: null)` for create mode
  - Empty state: "No assets registered yet" message when list is empty
  - Error state: SnackBar on load failure with retry
  - Pull-to-refresh via RefreshIndicator

- [X] T006 [US1] Create asset add/edit screen `frontend/lib/screens/admin/asset_edit_screen.dart` with:
  - StatefulWidget `AssetEditScreen` accepting optional `Asset? asset` parameter (null = create mode, non-null = edit mode)
  - Form fields: name (TextFormField, required), type (DropdownButtonFormField from Asset.assetTypes, required), location (TextFormField, required), notes (TextFormField, multiline, optional)
  - AppBar title: "Add Asset" or "Edit Asset" based on mode
  - Save button in AppBar or bottom: calls `AssetService().createAsset(...)` or `updateAsset(...)`
  - On save success: Navigator.pop(true) to trigger list reload
  - On 409 (duplicate name): show SnackBar with the error detail message
  - On 400 (invalid type): show SnackBar with error
  - Delete button (edit mode only): AlertDialog confirmation → `AssetService().deleteAsset(asset.id)` → Navigator.pop(true)
  - Form validation: name and location non-empty

- [X] T007 [US1] Wire navigation in `frontend/lib/screens/settings_page.dart`:
  - Add import for `asset_registry_screen.dart`
  - Add a new `SettingsRow` inside the `if (widget.userRole == 'admin')` Administration section
  - Icon: `Icons.devices_other` or `Icons.inventory_2`
  - Label: "Asset Registry"
  - onTap: `Navigator.push(context, MaterialPageRoute(builder: (_) => const AssetRegistryScreen()))`

**Checkpoint**: Admin can fully manage assets (CRUD) via the Asset Registry screen. User Story 1 is independently testable.

---

## Phase 4: User Story 2 — Admin Associates Assets with Systems (Priority: P1)

**Goal**: Admin can link/unlink systems to assets with role enforcement (max one primary + one standby per system).

**Independent Test**: Open an asset, add system link "CADAS-ATS" as "client". Add another "CADAS-IMS" as "client". Remove one. Try to add a second "primary" for a system that already has one — should be blocked with descriptive error.

**Depends on**: Phase 3 (US1) for the edit screen to exist.

### Implementation for User Story 2

- [X] T008 [US2] Add system link management to `frontend/lib/screens/admin/asset_edit_screen.dart`:
  - Below the asset form fields, add a "System Associations" section (SectionLabel or divider)
  - Display existing links as a list: each row shows "SYSTEM — Role" with a delete IconButton
  - Delete link: AlertDialog confirmation → `AssetService().removeLink(link.id)` → reload asset
  - "Add System Link" button/row at bottom of the list
  - Add link flow: show a bottom sheet or inline row with:
    - System: Autocomplete TextField with `Asset.systemSuggestions` as options (also accepts free text for custom system names)
    - Role: DropdownButton with `Asset.linkRoles` ('primary', 'standby', 'client')
    - Save button → `AssetService().addLink(asset.id, system: ..., role: ...)`
  - On 409 "duplicate_link": SnackBar "This asset is already linked to [system] as [role]"
  - On 409 "role_taken": SnackBar showing which asset currently holds that role (from error detail)
  - On success: reload the asset to show updated links list
  - The system links section should only appear AFTER the asset has been saved (not during initial create — you need an asset_id first). In create mode, show a hint: "Save the asset first, then add system associations"

**Checkpoint**: Full asset + system link management working. Both P1 stories complete and independently testable.

---

## Phase 5: User Story 3 — AI Extraction Uses Dynamic Asset Context (Priority: P2)

**Goal**: Entity extraction prompt is built dynamically from the asset registry instead of hardcoded domain strings.

**Independent Test**: Add assets with system links to registry. Create a work order mentioning an asset name (e.g., "WS-01 not responding"). Run extraction. Check `work_order_entities` for correct system mapping. Then add a new asset to registry and verify next extraction includes it without code changes.

**Depends on**: Phase 2 (T002 for `get_domain_knowledge_block()`)

### Implementation for User Story 3

- [X] T009 [US3] Modify `backend/services/entity_extractor.py` to use dynamic prompt:
  - Import `get_domain_knowledge_block` from `backend/routers/asset_registry.py`
  - Replace the hardcoded `EXTRACTION_PROMPT` constant with a prompt TEMPLATE that has a `{{domain_knowledge}}` placeholder
  - The template should keep all the existing extraction instructions, field definitions, and the `system` output field (from the main branch version — check `git diff main` to see the full original prompt with domain knowledge)
  - In the `extract_entities()` function, before calling `generate()`:
    - Call `get_domain_knowledge_block()` to get the dynamic text
    - Replace `{{domain_knowledge}}` in the template with the result
  - Keep the `{{work_order_text}}` replacement as-is
  - Restore the `system` field in the extraction output and in the `work_order_entities` upsert payload (it was removed — check git diff main for the original field list)
  - If `get_domain_knowledge_block()` returns the fallback (empty registry), the prompt still works — it just won't have asset-specific context
  - IMPORTANT: Reference the main branch version of entity_extractor.py for the full prompt structure with domain knowledge, system field, and examples. The current branch has a simplified version.

**Checkpoint**: Extraction pipeline uses live registry data. New assets in registry are immediately reflected in next extraction run.

---

## Phase 6: User Story 4 — Pattern Alerts Include Asset Context (Priority: P3)

**Goal**: Pattern alerts are enriched with asset metadata (location, type, hosted systems) when equipment_id matches a registered asset.

**Independent Test**: Ensure assets exist with system links. Trigger a pattern alert for an equipment matching an asset name. Check that the alert card shows location and associated systems. Check that alerts for unknown equipment still display normally.

**Depends on**: Phase 2 (T001 for `asset_context` column on pattern_alerts)

### Implementation for User Story 4

- [X] T010 [US4] Modify `backend/services/pattern_engine.py` to enrich alerts with asset context:
  - In the `_create_alert()` function (around line 445), after building the alert dict:
    - Query `assets` table WHERE `name = equipment_id` (the alert's equipment_id field)
    - If found, query `asset_system_links` WHERE `asset_id = asset.id`
    - Build `asset_context` dict: `{"name": asset.name, "type": asset.type, "location": asset.location, "systems": [{"system": link.system, "role": link.role} for each link]}`
    - Add `"asset_context": asset_context` to the alert insert payload
  - If no matching asset found, set `asset_context` to None (column default)
  - This is a fire-and-forget enrichment — if the lookup fails, the alert is still created without context
  - Use a try/except around the enrichment query so it never breaks alert creation

- [X] T011 [US4] Update frontend model `frontend/lib/models/pattern_alert.dart`:
  - Add field: `Map<String, dynamic>? assetContext`
  - Parse in `fromJson`: `assetContext = json['asset_context']`
  - Include in `toJson` and `copyWith`

- [X] T012 [US4] Modify `frontend/lib/screens/manual_assistant/widgets/alert_card.dart` to display asset context:
  - If `alert.assetContext != null`, add a section below the existing alert message showing:
    - Location: `alert.assetContext!['location']`
    - Type: `alert.assetContext!['type']`
    - Systems: comma-joined list from `alert.assetContext!['systems']` array, formatted as "SYSTEM [role]"
  - Use subtle styling (secondary text color, smaller font) to not overwhelm the alert message
  - If `assetContext` is null, show nothing extra (existing behavior preserved)

**Checkpoint**: Alerts for registered equipment show full asset context. Alerts for unknown equipment display normally.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanup and validation

- [X] T013 [P] Verify all 6 CRUD endpoints return correct error codes (409, 404, 400) per contracts/api-endpoints.md
- [X] T014 [P] Verify all mutating operations produce `user_activity_log` entries with category "asset"
- [X] T015 Run through `specs/053-asset-registry/quickstart.md` end-to-end validation
- [X] T016 Verify the 6 AIDA-NG circuit seed assets appear correctly after migration

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Migration)
  └─→ Phase 2 (Backend router + Frontend model/service)  [T002, T003, T004 parallel]
        ├─→ Phase 3 (US1: Asset CRUD screen)              [T005, T006, T007]
        │     └─→ Phase 4 (US2: System link management)   [T008]
        ├─→ Phase 5 (US3: Dynamic extraction prompt)       [T009]
        └─→ Phase 6 (US4: Alert enrichment)                [T010, T011, T012]
              └─→ Phase 7 (Polish)                         [T013-T016]
```

### User Story Dependencies

- **US1 (P1)**: Depends on Phase 2 only — can start as soon as router + model + service exist
- **US2 (P1)**: Depends on US1 (needs the edit screen to add link management to)
- **US3 (P2)**: Depends on Phase 2 only (uses `get_domain_knowledge_block()` from router) — can run in parallel with US1/US2
- **US4 (P3)**: Depends on Phase 2 only (uses migration column + backend enrichment) — can run in parallel with US1/US2/US3

### Parallel Opportunities

**Within Phase 2**: T002, T003, T004 are independent files — all three can run in parallel.

**After Phase 2**: US3 (T009) and US4 (T010-T012) are backend-only changes that don't touch the frontend screens, so they can run in parallel with US1/US2 frontend work.

**Within US4**: T011 and T012 are different files (model vs widget) and can run in parallel after T010.

---

## Parallel Example: Phase 2

```
# All three tasks touch different files — run in parallel:
Agent 1: T002 — backend/routers/asset_registry.py + backend/main.py
Agent 2: T003 — frontend/lib/models/asset.dart
Agent 3: T004 — frontend/lib/services/asset_service.dart
```

## Parallel Example: After Phase 2

```
# Frontend and backend work can proceed in parallel:
Agent 1 (frontend): T005 → T006 → T007 → T008 (US1 + US2 screens)
Agent 2 (backend):  T009 (US3 extraction) → T010 (US4 enrichment)
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1: Migration
2. Complete Phase 2: Router + Model + Service
3. Complete Phase 3: Asset CRUD screen (US1)
4. Complete Phase 4: System link management (US2)
5. **STOP and VALIDATE**: Full admin asset management working independently
6. Deploy/demo if ready — registry is usable even without AI integration

### Incremental Delivery

1. Migration + Foundational → API ready
2. US1 (Asset CRUD) → Admin can manage assets → **MVP!**
3. US2 (System Links) → Full asset-system model complete
4. US3 (Dynamic Extraction) → AI uses live registry data
5. US4 (Alert Enrichment) → Alerts show asset context
6. Polish → End-to-end validation

---

## Notes

- [P] tasks = different files, no dependencies between them
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable at its checkpoint
- Commit after each task or logical group
- Stop at any checkpoint to validate the story independently
- The tasks are written for an LLM implementer (opencode) — each task includes exact file paths, patterns to follow, and specific implementation details
- After implementation, a superpowers code review will be run against the plan and coding standards
