# Tasks: Structured Work Order Description Fields

**Input**: Design documents from `/specs/054-structured-wo-description/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/
**Target implementor**: opencode LLM — follow the plan exactly, read each referenced file before modifying it.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `backend/routers/`
- **Frontend**: `frontend/lib/screens/`, `frontend/lib/services/`, `frontend/lib/models/`

---

## Phase 1: Setup

**Purpose**: No project setup needed — existing project. Verify branch.

- [X] T001 Verify you are on branch `054-structured-wo-description` by running `git branch --show-current`. Read `specs/054-structured-wo-description/plan.md` and `specs/054-structured-wo-description/spec.md` to understand the full feature scope before starting any work.

---

## Phase 2: Foundational (Backend Changes)

**Purpose**: Backend endpoints that MUST be deployed before frontend can work. Both tasks modify different files and can run in parallel.

**CRITICAL**: No frontend work can begin until this phase is complete.

### Backend: Asset Names Endpoint

- [X] T002 [P] Add `GET /asset-registry/asset-names` endpoint in `backend/routers/asset_registry.py`. This endpoint must NOT require admin access (no `_admin_check` call). It should query the `assets` table selecting only the `name` column, ordered alphabetically, and return `{"names": ["name1", "name2", ...]}`. Place it near the existing `list_assets` endpoint (around line 115). Any authenticated user should be able to call it. Keep it minimal — no system links, no full asset objects.

### Backend: Structured Fields & Stitching

- [X] T003 [P] Extend `CreateWorkOrderBody` in `backend/routers/work_orders.py` (line 44-55) with 5 new optional fields: `asset_name: Optional[str] = None`, `fault_description: Optional[str] = None`, `action_taken: Optional[str] = None`, `outcome: Optional[str] = None`, `notes: Optional[str] = None`. Add a module-level constant `VALID_OUTCOMES = {"Resolved", "Pending Parts", "Escalated", "Monitoring"}`.

- [X] T004 Add stitching logic in the `POST /work-orders` handler in `backend/routers/work_orders.py`, just before the payload construction (around line 741). If all four structured fields (`asset_name`, `fault_description`, `action_taken`, `outcome`) are present and non-empty: (1) validate `outcome` is in `VALID_OUTCOMES` (raise 400 if not), (2) build the stitched description string in bracket-labeled format: `[Asset] <value>\n[Fault] <value>\n[Action] <value>\n[Outcome] <value>`, (3) if `notes` is non-empty, append `\n[Notes] <value>`, (4) set `payload["description"]` to this stitched string, overriding `body.description`. If structured fields are absent, use `body.description or ""` as-is (backward compatibility). Depends on T003.

**Checkpoint**: Backend is ready. Test with curl: `POST /work-orders` with structured fields should store a bracket-labeled description. `GET /asset-registry/asset-names` should return asset names without admin check.

---

## Phase 3: User Story 1 + 3 + 4 — Structured Form (Priority: P1/P2/P3) MVP

**Goal**: Replace the single description TextFormField with 4 structured sub-fields (Asset Name as plain text for now, Fault Description, Action Taken, Outcome dropdown) + optional Notes. These three user stories are inherently part of the same form change.

**Independent Test**: Open Add Work Order screen, verify 4 required fields + Notes appear instead of single description field. Fill all fields, submit, check that the saved work order has a bracket-labeled description in the database.

### Frontend Service Update

- [X] T005 [US1] Update `addWorkOrder()` in `frontend/lib/services/work_order_service.dart` (line 68-94). Add 5 new optional named parameters: `String? assetName`, `String? faultDescription`, `String? actionTaken`, `String? outcome`, `String? notes`. In the `jsonEncode` body (line 72-84), add these fields alongside existing ones: `'asset_name': assetName`, `'fault_description': faultDescription`, `'action_taken': actionTaken`, `'outcome': outcome`, `'notes': notes`. Keep the existing `'description'` field as `workOrder.description` for backward compatibility.

### Frontend Form Replacement

- [X] T006 [US1] In `frontend/lib/screens/Work_Orders/add_work_order.dart`, add new state variables and controllers. Near the existing `descriptionController` declaration (line 86) and `_descriptionFocusNode` (line 77), add: `final TextEditingController assetNameController = TextEditingController();`, `final TextEditingController faultController = TextEditingController();`, `final TextEditingController actionController = TextEditingController();`, `final TextEditingController notesController = TextEditingController();`, `String? selectedOutcome;`, and corresponding FocusNodes `_assetNameFocusNode`, `_faultFocusNode`, `_actionFocusNode`, `_notesFocusNode`. Initialize them in `initState` and dispose them in `dispose()` (following the pattern of existing controllers around lines 459-468).

- [X] T007 [US1] In the same file, replace the description `TextFormField` widget (lines 1743-1762) with 5 new form fields in this order: (1) **Asset Name**: `TextFormField` with `assetNameController`, label "Asset Name", validator that checks non-empty, `maxLines: 1`. (2) **Fault Description**: `TextFormField` with `faultController`, label "Fault Description", `maxLines: 3`, validator for non-empty. Move the existing `DictationButton` suffix from the old description field to this field (change `controller: descriptionController` to `controller: faultController` in the DictationButton). (3) **Action Taken**: `TextFormField` with `actionController`, label "Action Taken", `maxLines: 2`, validator for non-empty. (4) **Outcome**: `DropdownButtonFormField<String>` with items `["Resolved", "Pending Parts", "Escalated", "Monitoring"]`, label "Outcome", validator for non-null, `onChanged` sets `selectedOutcome`. (5) **Notes** (optional): `TextFormField` with `notesController`, label "Notes (optional)", `maxLines: 2`, `textDirection: TextDirection.rtl` support hint, no validator. Add `SizedBox(height: 16)` between each field. Depends on T006.

- [X] T008 [US1] Update the submit handler in `add_work_order.dart` (around line 1097-1115). When creating a new work order (`widget.workOrder == null`), pass the structured fields to the service call: change `await _service.addWorkOrder(newWorkOrder)` to `await _service.addWorkOrder(newWorkOrder, assetName: assetNameController.text.trim(), faultDescription: faultController.text.trim(), actionTaken: actionController.text.trim(), outcome: selectedOutcome, notes: notesController.text.trim())`. For existing work orders (edit/update path), keep using `descriptionController.text.trim()` as-is since edit is out of scope. Depends on T005 and T007.

- [X] T009 [US1] Update AI Assist integration in `add_work_order.dart` (around line 636-637). Change `descriptionController.text = response['description'];` to `faultController.text = response['description'];` so AI-generated text fills the Fault Description field instead of the removed description field. Also update the `highlighted.add('description')` on line 638 to `highlighted.add('fault_description')` (or remove if the highlight decoration doesn't apply to the new fields). Similarly, update the dictation result routing at lines 1007-1008 and 1044 to use `faultController` instead of `descriptionController`.

- [X] T010 [US1] Handle the `initState` prefill paths for existing work orders. At line 209 (`descriptionController.text = widget.workOrder!.description`), keep this line for backward compat with the edit flow. At line 235 (`descriptionController.text = widget.prefillDescription!`), route the prefill to `faultController.text = widget.prefillDescription!` instead, since prefilled descriptions from AI/templates should go to the Fault Description field. Depends on T006.

**Checkpoint**: The Add Work Order screen now shows 4 required structured fields + optional Notes. Submitting creates a work order with bracket-labeled description. The DictationButton works on Fault Description. AI Assist fills Fault Description. US1 (structured form), US3 (outcome dropdown), and US4 (notes field) are all functional.

---

## Phase 4: User Story 2 — Asset Autocomplete (Priority: P1)

**Goal**: Upgrade the plain-text Asset Name field to an autocomplete that suggests registered asset names from the Asset Registry. Free-text entry remains allowed when no match is found or the registry is unreachable.

**Independent Test**: Type 2+ characters in Asset Name field, see matching asset names appear as suggestions. Select one to populate the field. Type a non-matching name — field accepts it as free text. Disconnect network — field still works as plain text input.

### Frontend Service

- [X] T011 [P] [US2] Add `fetchAssetNames()` method to `frontend/lib/services/asset_service.dart`. It should call `GET ${AppConfig.baseUrl}/asset-registry/asset-names` (no `user_email` query param needed), parse the response JSON `names` array, and return `Future<List<String>>`. On any error (network, non-200), return an empty list (graceful degradation). Use `_headers()` for auth token.

### Frontend Autocomplete Widget

- [X] T012 [US2] In `frontend/lib/screens/Work_Orders/add_work_order.dart`, add `List<String> _assetNames = [];` to the state class. In `initState()`, after existing initialization, add an async call: `AssetService().fetchAssetNames().then((names) { if (mounted) setState(() => _assetNames = names); }).catchError((_) {});`. Import `AssetService` at the top of the file. Depends on T011.

- [X] T013 [US2] Replace the plain `TextFormField` for Asset Name (created in T007) with Flutter's `Autocomplete<String>` widget. Configure it as follows: `optionsBuilder` should filter `_assetNames` case-insensitively where the name contains the typed text, returning at most 15 results; only trigger when text length >= 2 characters (return empty iterable otherwise). `fieldViewBuilder` should return a `TextFormField` with `assetNameController`, label "Asset Name", validator for non-empty. `onSelected` should set `assetNameController.text` to the selected value. The field must still accept free-text entry (this is the default Autocomplete behavior). Depends on T006 and T012.

**Checkpoint**: Asset Name field now shows autocomplete suggestions from the registry. Typing "Gen" shows matching assets like "Generator #1". Selecting populates the field. Free text still accepted. If asset fetch fails, field works as plain text. US2 is complete.

---

## Phase 5: User Story 5 — Structured Detail View (Priority: P2)

**Goal**: When viewing a work order with a structured description, display it as visually separated labeled sub-fields instead of a single text block. Legacy descriptions display as plain text.

**Independent Test**: Create a work order with the structured form, then open it in view mode (canEdit=false). Verify Asset Name, Fault, Action, Outcome, and Notes (if present) display as separate labeled rows. Open a pre-existing work order — verify it shows plain text as before.

### Description Parser & Structured View Widget

- [X] T014 [US5] In `frontend/lib/screens/Work_Orders/add_work_order.dart`, add a static helper method `Map<String, String>? _parseStructuredDescription(String description)` to the state class. It should check if `description.startsWith('[Asset] ')`. If yes, parse each line matching the regex pattern `\[(\w+)\]\s*(.*)` and return a Map with keys like `Asset`, `Fault`, `Action`, `Outcome`, `Notes`. If the description doesn't start with `[Asset] ` or parsing fails, return `null` (legacy fallback).

- [X] T015 [US5] In the same file, modify the view mode (when `canEdit` is false). Find where the description TextFormField is rendered (the area from T007). Wrap it in a conditional: call `_parseStructuredDescription(widget.workOrder!.description)`. If it returns a non-null Map, render a `Card` with a `Column` of `ListTile`-style rows — each row has a bold label (e.g., "Asset Name", "Fault Description", "Action Taken", "Outcome") and the value as subtitle text. Omit the "Notes" row if the key is absent. If it returns null, show the existing read-only TextFormField with `descriptionController` (legacy fallback). Depends on T014.

**Checkpoint**: Structured work orders display with labeled sub-fields in view mode. Legacy work orders display as plain text. US5 is complete.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanup and edge case handling

- [X] T016 [P] Add form field change tracking for the new controllers in `add_work_order.dart`. The existing `_onFormFieldChanged` listener is added to controllers around line 513 and removed around line 795. Add the same listener to `assetNameController`, `faultController`, `actionController`, and `notesController` following the same pattern. Also add `selectedOutcome` changes to trigger `_hasChanges = true`.

- [X] T017 [P] Handle the auto-save flow for existing work orders in `add_work_order.dart` (around line 535-554). The auto-save builds a `WorkOrder` with `description: descriptionController.text.trim()`. Since edit is out of scope for structured fields, keep this as-is — the auto-save path uses the old description controller for existing work orders only.

- [X] T018 Verify the `_highlightDecoration` helper (used for AI-assist highlighted fields) works with the new field names. If the `highlighted` set contains field identifiers, update the identifiers to match the new field keys (e.g., `'fault_description'` instead of `'description'`). Check lines around 636-638 and the `_highlightDecoration` method to ensure consistency.

- [ ] T019 Run the quickstart.md validation: Start the backend, open the PWA, test the full flow: (1) Create a new work order with all structured fields filled + notes, verify bracket-labeled description in the database. (2) Create a work order without notes, verify `[Notes]` line is omitted. (3) Test autocomplete by typing partial asset names. (4) Test with no assets in registry — field should work as plain text. (5) View a structured work order — verify labeled sub-fields display. (6) View a legacy work order — verify plain text display. (7) Test validation by leaving required fields empty.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — read the plan
- **Phase 2 (Foundational/Backend)**: No dependencies on frontend. T002 and T003 are parallel. T004 depends on T003.
- **Phase 3 (US1+US3+US4)**: Depends on Phase 2 (backend must be ready). T005 is independent. T006-T010 are sequential within the form.
- **Phase 4 (US2)**: Depends on Phase 3 (Asset Name field must exist). T011 is independent of frontend. T012 depends on T011. T013 depends on T012.
- **Phase 5 (US5)**: Depends on Phase 3 (structured descriptions must exist to view). T014-T015 are sequential.
- **Phase 6 (Polish)**: Depends on all prior phases. T016-T018 are parallel.

### User Story Dependencies

- **US1+US3+US4 (P1/P2/P3)**: Can start after Phase 2 backend — no dependencies on other stories
- **US2 (P1)**: Depends on US1 (needs the Asset Name field to upgrade to autocomplete)
- **US5 (P2)**: Depends on US1 (needs structured descriptions to exist for parsing)

### Within Each Phase

- Backend: Request model (T003) → Stitching logic (T004)
- Frontend form: Controllers (T006) → Widgets (T007) → Submit handler (T008) → AI/Dictation (T009) → Prefill (T010)
- Autocomplete: Service (T011) → State loading (T012) → Widget upgrade (T013)
- Detail view: Parser (T014) → View widget (T015)

### Parallel Opportunities

- T002 and T003 can run in parallel (different files)
- T005 and T006 can run in parallel (different files)
- T011 can run in parallel with Phase 3 tasks (different file)
- T016, T017, T018 can all run in parallel

---

## Parallel Example: Phase 2 (Backend)

```
# These two tasks modify different files and can run simultaneously:
T002: Add GET /asset-registry/asset-names in backend/routers/asset_registry.py
T003: Extend CreateWorkOrderBody in backend/routers/work_orders.py
```

## Parallel Example: Phase 3 Start

```
# These two tasks modify different files and can start together:
T005: Update addWorkOrder() in frontend/lib/services/work_order_service.dart
T006: Add controllers/state in frontend/lib/screens/Work_Orders/add_work_order.dart
```

---

## Implementation Strategy

### MVP First (Phase 2 + Phase 3)

1. Complete Phase 2: Backend endpoints (T002-T004)
2. Complete Phase 3: Structured form (T005-T010)
3. **STOP and VALIDATE**: Create a work order with structured fields, verify bracket-labeled description saved correctly
4. This gives you US1 + US3 + US4 working end-to-end

### Incremental Delivery

1. Phase 2 (Backend) → Backend ready
2. Phase 3 (US1+US3+US4) → Structured form working → **Deploy/Demo (MVP!)**
3. Phase 4 (US2) → Asset autocomplete → Deploy
4. Phase 5 (US5) → Detail view → Deploy
5. Phase 6 (Polish) → Final cleanup → Deploy

---

## Notes

- **IMPORTANT**: Read each file before modifying it. The line numbers are approximate — verify by searching for the described code patterns.
- The `add_work_order.dart` file is large (~1800+ lines). Take care with line references.
- Do NOT modify the Edit Work Order flow — edit screen is explicitly out of scope.
- Do NOT modify the WorkOrder model (`work_order.dart`) — description remains a single string.
- The bracket-labeled format `[Asset] ...\n[Fault] ...` is the canonical stitching format. Do not change it.
- Preserve the existing `descriptionController` for backward compat with edit flows.
- The `DictationButton` and AI Assist must route to the Fault Description field.
- Commit after each phase checkpoint.
