# Tasks: Auto-Suggest Asset Registry Additions

**Input**: Design documents from `/specs/055-asset-auto-suggest/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api-endpoints.md
**Branch**: `055-asset-auto-suggest`
**Target implementor**: opencode LLM — read each referenced design doc and pattern file before modifying code.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

## Reference Files

Before starting, read these design documents:

| Document | Path | Purpose |
|----------|------|---------|
| Spec | `specs/055-asset-auto-suggest/spec.md` | User stories, requirements, acceptance criteria |
| Plan | `specs/055-asset-auto-suggest/plan.md` | Technical context, project structure |
| Data Model | `specs/055-asset-auto-suggest/data-model.md` | Computed entity shape, data flow, filtering logic |
| API Contracts | `specs/055-asset-auto-suggest/contracts/api-endpoints.md` | Endpoint signatures, request/response shapes |
| Research | `specs/055-asset-auto-suggest/research.md` | Design decisions (query strategy, metadata inference, storage) |
| Quickstart | `specs/055-asset-auto-suggest/quickstart.md` | Verification procedure |

## Existing Code Patterns to Follow

Study these files before implementing:

| Pattern | Example File | What to Copy |
|---------|-------------|-------------|
| Backend router | `backend/routers/asset_registry.py` | `_admin_check()`, `log_activity()`, response format |
| Frontend service | `frontend/lib/services/asset_service.dart` | HTTP client, `_headers()`, error handling |
| Frontend admin screen | `frontend/lib/screens/admin/asset_registry_screen.dart` | StatefulWidget, loading/error states, list layout |
| Frontend edit screen | `frontend/lib/screens/admin/asset_edit_screen.dart` | Pre-filled form parameters, Navigator.push pattern |
| Settings service | `frontend/lib/services/settings_service.dart` | How system_settings key-value is read/written |

---

## Phase 1: Setup

**Purpose**: Read the plan and verify branch.

- [X] T001 Verify you are on branch `055-asset-auto-suggest` by running `git branch --show-current`. Read `specs/055-asset-auto-suggest/plan.md`, `specs/055-asset-auto-suggest/spec.md`, and `specs/055-asset-auto-suggest/contracts/api-endpoints.md` to understand the full feature scope. No code changes in this task.

---

## Phase 2: Foundational (Backend Endpoints)

**Purpose**: Backend endpoints that MUST be deployed before frontend can work.

**CRITICAL**: No frontend work can begin until this phase is complete.

- [X] T002 [P] Add `GET /asset-registry/suggestions` endpoint in `backend/routers/asset_registry.py`. This endpoint requires admin access (`_admin_check(user_email)`). Implementation per `specs/055-asset-auto-suggest/contracts/api-endpoints.md` and `specs/055-asset-auto-suggest/research.md` R1:
  1. Query all `pattern_alerts` selecting `equipment_id` and `fault_type`. Group by `equipment_id`, keep only those with count >= 2.
  2. Query all `assets` selecting `name`. Build a set of lowercase names: `{name.lower() for name in asset_names}`.
  3. Query `system_settings` for key `dismissed_asset_suggestions`. Parse the JSON array (default to empty list if not found).
  4. Filter: exclude equipment_ids where `equipment_id.lower()` is in the asset names set OR in the dismissed list (case-insensitive).
  5. For each remaining equipment_id, query `work_order_entities` selecting `equipment_type` where `equipment_id` matches. Find the most common non-null `equipment_type` (use `collections.Counter`). Set as `inferred_type` (or `None` if no consistent type).
  6. Collect distinct `fault_type` values from the alerts for each equipment_id.
  7. Return `{"suggestions": [...]}` sorted by `alert_count` descending.
  8. Add `from collections import Counter` at the top of the file.

- [X] T003 [P] Add `POST /asset-registry/suggestions/dismiss` endpoint in `backend/routers/asset_registry.py`. This endpoint requires admin access. Implementation per contracts:
  1. Accept `DismissSuggestionBody(equipment_id: str)` — add this Pydantic model near the other body models.
  2. Validate `equipment_id` is non-empty (return 400 if empty).
  3. Read `system_settings` key `dismissed_asset_suggestions`. If not found, use empty list.
  4. Parse the JSON value as a list. If `equipment_id` not already in the list, append it.
  5. Upsert to `system_settings`: key=`dismissed_asset_suggestions`, value=updated JSON array.
  6. Call `log_activity(user_email, "asset", "dismissed_suggestion", equipment_id)`.
  7. Return `{"dismissed": true}`.

**Checkpoint**: Backend ready. Test with curl:
```bash
curl -s "http://localhost:8000/api/asset-registry/suggestions?user_email=salah@admin.com" | python3 -m json.tool
curl -s -X POST "http://localhost:8000/api/asset-registry/suggestions/dismiss?user_email=salah@admin.com" -H "Content-Type: application/json" -d '{"equipment_id":"test"}' 
```

---

## Phase 3: User Story 1 — Admin Reviews Suggested Assets (Priority: P1) MVP

**Goal**: Suggestions section appears on the Asset Registry screen showing unregistered equipment with 2+ alerts.

**Independent Test**: Open Asset Registry screen. If pattern alerts exist for unregistered equipment (e.g., "MUX system"), a "Suggestions" section appears at the top with alert count and fault types. Registered assets and equipment with <2 alerts do NOT appear.

### Frontend Service

- [X] T004 [P] [US1] Add `fetchSuggestions()` method to `frontend/lib/services/asset_service.dart`. It should call `GET ${AppConfig.baseUrl}/asset-registry/suggestions?user_email=...` (same auth pattern as other methods). Parse the response JSON `suggestions` array and return `Future<List<Map<String, dynamic>>>`. On error, return empty list (graceful degradation). Each item has: `equipment_id` (String), `alert_count` (int), `fault_types` (List<String>), `inferred_type` (String?).

### Frontend UI

- [X] T005 [US1] Add suggestions state and loading to `frontend/lib/screens/admin/asset_registry_screen.dart`:
  - Add state variable: `List<Map<String, dynamic>> _suggestions = [];`
  - In the existing `_loadAssets()` method (or alongside it), also call `_service.fetchSuggestions()` and store the result in `_suggestions` via `setState`.
  - The suggestions load alongside assets — no separate loading indicator needed.

- [X] T006 [US1] Add Suggestions section widget to `frontend/lib/screens/admin/asset_registry_screen.dart`:
  - In the `build` method, above the existing asset list (and below the filter row), add a conditional section:
    - If `_suggestions.isEmpty`, show nothing (FR-010).
    - If `_suggestions.isNotEmpty`, show a section with:
      - A header: "Suggested Assets" with a subtitle like "Unregistered equipment with recurring alerts"
      - A `ListView` or `Column` of suggestion cards, each showing:
        - Equipment name (bold, truncated with ellipsis if >50 chars)
        - Alert count badge (e.g., "3 alerts")
        - Fault types as comma-separated chips or text (e.g., "network, performance")
        - Inferred type if available (e.g., "Likely: server")
        - Two action buttons: "Add" (accent color) and "Dismiss" (subtle/text button)
      - Use `Card` or `Container` with `AppColors.bgSurface2` background to visually distinguish from the main asset list.
  - Depends on T005.

**Checkpoint**: Admin sees the Suggestions section with correct data. No actions wired yet (Add/Dismiss are visual only at this point, unless you wire them in the next phases).

---

## Phase 4: User Story 2 — Admin Accepts a Suggestion (Priority: P1)

**Goal**: Tapping "Add" on a suggestion navigates to the Add Asset form with name and inferred type pre-filled.

**Independent Test**: Tap "Add" on a suggestion like "CADAS-ATS mailbox" with inferred type "server". The Add Asset form opens with name "CADAS-ATS mailbox" and type "server" pre-filled. Save the asset, return to registry — the suggestion is gone and the asset appears in the main list.

### Frontend Navigation

- [X] T007 [US2] Modify `frontend/lib/screens/admin/asset_edit_screen.dart` to accept optional pre-fill parameters. The `AssetEditScreen` constructor already accepts `Asset? asset`. Add two new optional parameters: `String? prefillName` and `String? prefillType`. In `initState`, if `asset` is null (create mode) and `prefillName` is provided, set `_nameController.text = prefillName`. If `prefillType` is provided and it's in `Asset.assetTypes`, set `_selectedType = prefillType`. These only apply in create mode (when `asset` is null).

- [X] T008 [US2] Wire the "Add" button in the suggestion card (from T006) in `frontend/lib/screens/admin/asset_registry_screen.dart`:
  - On tap, call `Navigator.push` to `AssetEditScreen(prefillName: suggestion['equipment_id'], prefillType: suggestion['inferred_type'])`.
  - Use the same `then((result) { if (result == true) _loadAssets(); })` pattern as the existing FAB and list item taps — this reloads both assets and suggestions, so the accepted suggestion disappears automatically.
  - Depends on T007.

**Checkpoint**: Full accept flow working. Tap "Add" → pre-filled form → save → suggestion gone, asset in list.

---

## Phase 5: User Story 3 — Admin Dismisses a Suggestion (Priority: P2)

**Goal**: Tapping "Dismiss" hides the suggestion permanently.

**Independent Test**: Tap "Dismiss" on a noisy suggestion. It disappears from the list. Create new alerts for the same equipment — it still doesn't reappear.

### Frontend Service

- [X] T009 [P] [US3] Add `dismissSuggestion(String equipmentId)` method to `frontend/lib/services/asset_service.dart`. It should call `POST ${AppConfig.baseUrl}/asset-registry/suggestions/dismiss?user_email=...` with JSON body `{"equipment_id": equipmentId}`. Return `Future<void>`. On error, throw Exception with message.

### Frontend UI

- [X] T010 [US3] Wire the "Dismiss" button in the suggestion card (from T006) in `frontend/lib/screens/admin/asset_registry_screen.dart`:
  - On tap, call `_service.dismissSuggestion(suggestion['equipment_id'])`.
  - On success, remove the suggestion from `_suggestions` list via `setState` and show a SnackBar: "Suggestion dismissed".
  - On error, show error SnackBar.
  - No confirmation dialog needed (dismiss is low-risk and reversible by re-checking the setting).
  - Depends on T009.

**Checkpoint**: Full dismiss flow working. Tap "Dismiss" → suggestion removed → doesn't return even after new alerts.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanup and validation

- [X] T011 [P] Verify the suggestions endpoint handles edge cases: empty alerts table, empty assets table, no dismissed setting, all equipment registered
- [X] T012 [P] Verify case-insensitive matching works: add an asset "MUX System" (capital S) and check that "MUX system" (lowercase s) alerts no longer appear as suggestions
- [X] T013 Run through `specs/055-asset-auto-suggest/quickstart.md` end-to-end validation

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup)
  └─→ Phase 2 (Backend endpoints)  [T002, T003 parallel]
        ├─→ Phase 3 (US1: Suggestions section)  [T004, T005, T006]
        │     ├─→ Phase 4 (US2: Accept flow)     [T007, T008]
        │     └─→ Phase 5 (US3: Dismiss flow)    [T009, T010]
        └─→ Phase 6 (Polish)                      [T011-T013]
```

### User Story Dependencies

- **US1 (P1)**: Depends on Phase 2 (backend endpoints). No other story dependencies.
- **US2 (P1)**: Depends on US1 (needs suggestion cards to exist for the "Add" button).
- **US3 (P2)**: Depends on US1 (needs suggestion cards to exist for the "Dismiss" button). Can run in parallel with US2.

### Parallel Opportunities

- **Phase 2**: T002 and T003 modify the same file but different endpoints — can be done sequentially in one pass or by one agent.
- **After US1**: US2 (T007-T008) and US3 (T009-T010) are independent and can run in parallel.
- **Phase 6**: T011, T012 can run in parallel.

---

## Parallel Example: After US1

```
# US2 and US3 touch different concerns and can proceed in parallel:
Agent 1 (Accept flow):  T007 (edit screen params) → T008 (wire Add button)
Agent 2 (Dismiss flow): T009 (service method) → T010 (wire Dismiss button)
```

---

## Implementation Strategy

### MVP First (Phase 2 + Phase 3)

1. Complete Phase 2: Backend endpoints (T002-T003)
2. Complete Phase 3: Suggestions section UI (T004-T006)
3. **STOP and VALIDATE**: Open Asset Registry, verify suggestions appear with correct data
4. This gives you US1 working — Admins can see suggested assets

### Incremental Delivery

1. Phase 2 (Backend) → Endpoints ready
2. Phase 3 (US1) → Suggestions visible → **Deploy/Demo (MVP!)**
3. Phase 4 (US2) → Accept flow → Deploy
4. Phase 5 (US3) → Dismiss flow → Deploy
5. Phase 6 (Polish) → Final validation → Deploy

---

## Notes

- **No new files**: All changes modify existing files from spec 053.
- **No migration**: Uses existing tables. Dismissed list stored in `system_settings`.
- **Read the contracts**: `specs/055-asset-auto-suggest/contracts/api-endpoints.md` has exact request/response shapes.
- **Read the data model**: `specs/055-asset-auto-suggest/data-model.md` has the filtering logic diagram.
- **Case-insensitive**: All comparisons between equipment_ids and asset names must be `.lower()` on both sides.
- **Inferred type mapping**: The `inferred_type` from the suggestions endpoint may not match `Asset.assetTypes` exactly (e.g., extraction might say "server" which matches, but "display" doesn't). Only pre-fill `prefillType` if the value is in `Asset.assetTypes`.
- Commit after each phase checkpoint.
- After implementation, a superpowers code review will be run against the plan and coding standards.
