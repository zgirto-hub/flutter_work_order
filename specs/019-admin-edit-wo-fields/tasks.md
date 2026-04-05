# Tasks: Admin Edit WO Metadata Fields

**Input**: Design documents from `/specs/019-admin-edit-wo-fields/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api.md, quickstart.md
**Branch**: `019-admin-edit-wo-fields`

**Context**: These tasks are designed for an LLM agent to implement step-by-step. Each task is self-contained with exact file paths, what to change, and acceptance criteria. After all tasks are complete, the output will be reviewed.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1=Created By, US2=Created At, US3=Closed At)
- Include exact file paths in descriptions

---

## Phase 1: Setup (No tasks needed)

No new project setup required. This feature extends existing files only.

---

## Phase 2: Foundational (Backend — Admin Metadata Update Support)

**Purpose**: Extend the backend PUT endpoint to accept and validate the three new optional fields. This MUST be complete before any frontend work begins.

**⚠️ CRITICAL**: No frontend user story work can begin until this phase is complete.

- [ ] T001 Add three optional fields (`created_by`, `created_at`, `closed_at`) to the `UpdateWorkOrderBody` Pydantic model in `backend/routers/work_orders.py` (around line 47). All three fields must be `Optional` with default `None`. Use `Optional[str]` for `created_by` (UUID string) and `Optional[str]` for `created_at` and `closed_at` (ISO 8601 datetime strings).

- [ ] T002 Add admin-only authorization check in the PUT `/work-orders/{work_order_id}` handler in `backend/routers/work_orders.py` (inside the `update_work_order` function, around line 725). After the existing authorization checks, add: if any of the three metadata fields are not None, look up the caller's role using `_get_user_role(user_email)` (pattern already used in the file). If `user_type != 'admin'`, raise `HTTPException(status_code=403, detail="Admin access required to modify metadata fields")`.

- [ ] T003 Add validation logic for the three metadata fields in `backend/routers/work_orders.py`, inside the `update_work_order` function, after the admin check from T002:
  - If `created_by` is provided: query `supabase.table("users").select("id, email, full_name, is_active").eq("id", body.created_by).execute()`. If no user found or `is_active` is False, raise `HTTPException(400, "Selected user not found or inactive")`.
  - If `created_at` is provided: parse the ISO string to datetime. If it is in the future (compared to `datetime.utcnow()`), raise `HTTPException(400, "Created date cannot be in the future")`.
  - If `closed_at` is provided: check that the work order status (from `body.status` or existing record) is "Closed", else raise `HTTPException(400, "Closed date can only be set on closed work orders")`. Also compare `closed_at` against the effective `created_at` (either from `body.created_at` if provided, or from the existing record). If `closed_at < created_at`, raise `HTTPException(400, "Closed date cannot be before created date")`.

- [ ] T004 Add the metadata fields to the Supabase update dict in `backend/routers/work_orders.py`. In the non-reporter update branch (around line 791), after building the `update_data` dict, add conditionally:
  - If `body.created_by` is not None: set `update_data["created_by"] = body.created_by`, `update_data["created_by_email"] = user_record["email"]`, `update_data["created_by_name"] = user_record["full_name"]` (where `user_record` is the validated user from T003).
  - If `body.created_at` is not None: set `update_data["created_at"] = body.created_at`.
  - If `body.closed_at` is not None: set `update_data["closed_at"] = body.closed_at`.

- [ ] T005 Enhance the `log_activity` call in the update endpoint (around line 868 in `backend/routers/work_orders.py`) to include a `detail` string when metadata fields are changed. Build a list of changed metadata field names (e.g., `["created_by", "created_at"]`) and set `detail=f"Admin modified: {', '.join(changed_fields)}"` if any metadata fields were changed.

**Checkpoint**: Backend now accepts, validates, and persists the three metadata fields. Test with curl/Postman: send a PUT with `created_by`, `created_at`, or `closed_at` as an admin user — should succeed. Send as a non-admin — should get 403.

---

## Phase 3: User Story 1 — Admin Edits "Created By" (Priority: P1) 🎯 MVP

**Goal**: Admin can change who created a work order by selecting from a searchable list of all active users.

**Independent Test**: Open any work order as admin, change "Created By" to another user, save, reload — the new creator should be reflected. Log in as the new creator (if reporter) — the WO should appear in their list.

### Implementation for User Story 1

- [ ] T006 [US1] Create the `UserSelector` widget in `frontend/lib/widgets/user_selector.dart`. Base it on the existing `TechnicianSelector` pattern in `frontend/lib/widgets/technician_selector.dart`:
  - Single-select (not multi-select like TechnicianSelector)
  - Constructor takes: `List<AppUser> users`, `String? selectedUserId`, `Function(AppUser) onSelected`
  - UI: A `BottomSheet` with a search `TextField` at the top, a filtered `ListView` below showing each user as a `ListTile` with `fullName` as title, `email` as subtitle, and `userType` as trailing text
  - Filter by `fullName` or `email` case-insensitively
  - On tap, call `onSelected(user)` and close the bottom sheet
  - Import `AppUser` from `frontend/lib/models/user.dart`

- [ ] T007 [US1] Add a method to load all active users in `frontend/lib/screens/Work_Orders/add_work_order.dart`. Add a `List<AppUser> _allUsers = []` state variable and a `_loadAllUsers()` async method that calls the existing `GET /users` endpoint (similar to how `_loadEmployees` works). Parse the response into `AppUser` objects. Filter to only active users (`isActive == true`). Call `_loadAllUsers()` from `initState` (or from the existing `_loadData` method).

- [ ] T008 [US1] Make the "Created By" field editable for admins in `frontend/lib/screens/Work_Orders/add_work_order.dart`. Currently (around line 1053-1066), "Created By" is a read-only `TextFormField`. Change it so:
  - If `_userRole == 'admin'` and editing an existing WO: wrap it in a `GestureDetector` or use an `InkWell` that opens the `UserSelector` bottom sheet (via `showModalBottomSheet`) with `_allUsers` and the current `createdBy` user ID.
  - On selection, update a new state variable `_selectedCreatedByUser` (type `AppUser?`) and refresh the displayed name.
  - If not admin: keep the existing read-only `TextFormField` behavior unchanged.
  - Add a state variable `String? _overriddenCreatedBy` to track when the admin has changed the creator.

- [ ] T009 [US1] Update `updateWorkOrder` in `frontend/lib/services/work_order_service.dart` (around line 96) to include `created_by` in the JSON body when provided. Add an optional `String? createdBy` parameter. If not null, add `'created_by': createdBy` to the `jsonEncode` map.

- [ ] T010 [US1] Wire the save flow in `frontend/lib/screens/Work_Orders/add_work_order.dart`. In the save/submit method, when calling `updateWorkOrder`, pass `createdBy: _overriddenCreatedBy` (the selected user's ID from T008). Only pass it if the admin actually changed the creator.

**Checkpoint**: Admin can open a WO, tap "Created By", search/select a user, save. The backend updates `created_by`, `created_by_email`, `created_by_name`. Non-admins see the field as read-only.

---

## Phase 4: User Story 2 — Admin Edits "Created At" (Priority: P2)

**Goal**: Admin can correct the creation date/time of a work order using a date-time picker.

**Independent Test**: Open any work order as admin, change "Created At" to a past date, save, reload — the new date should be reflected. Try a future date — should show validation error.

### Implementation for User Story 2

- [ ] T011 [P] [US2] Add a "Created At" editable field in `frontend/lib/screens/Work_Orders/add_work_order.dart`. Below or near the existing "Created By" field:
  - Add a state variable `DateTime? _overriddenCreatedAt` initialized to null.
  - If `_userRole == 'admin'` and editing an existing WO: show a `ListTile` or `TextFormField` displaying the current `dateCreated` value (formatted as date + time). Wrap it in a `GestureDetector` that opens a `showDatePicker` followed by `showTimePicker`. Pre-fill with the current `dateCreated`. On selection, validate that the chosen date is not in the future. If valid, update `_overriddenCreatedAt`. If in the future, show a `SnackBar` with "Created date cannot be in the future".
  - If not admin: display the creation date as read-only text (existing behavior).

- [ ] T012 [US2] Update `updateWorkOrder` in `frontend/lib/services/work_order_service.dart` to include `created_at` in the JSON body when provided. Add an optional `String? createdAt` parameter (ISO 8601 string). If not null, add `'created_at': createdAt` to the `jsonEncode` map.

- [ ] T013 [US2] Wire the save flow in `frontend/lib/screens/Work_Orders/add_work_order.dart`. In the save/submit method, pass `createdAt: _overriddenCreatedAt?.toUtc().toIso8601String()` to `updateWorkOrder`. Only pass it if the admin actually changed the date.

**Checkpoint**: Admin can change the "Created At" date/time. Future dates are blocked. Non-admins see it as read-only.

---

## Phase 5: User Story 3 — Admin Edits "Closed At" (Priority: P3)

**Goal**: Admin can correct the closure date/time on a closed work order.

**Independent Test**: Open a closed work order as admin, change "Closed At", save, reload — the new date should be reflected. Try setting it before "Created At" — should show validation error. Open a non-closed WO — field should not appear.

### Implementation for User Story 3

- [ ] T014 [P] [US3] Add a "Closed At" editable field in `frontend/lib/screens/Work_Orders/add_work_order.dart`. Only display this field when the work order status is "Closed":
  - Add a state variable `DateTime? _overriddenClosedAt` initialized to null.
  - If `_userRole == 'admin'` and the WO status is "Closed" and editing an existing WO: show a `ListTile` or `TextFormField` displaying the current `closedAt` value (formatted as date + time). Wrap in `GestureDetector` that opens `showDatePicker` + `showTimePicker`. Pre-fill with current `closedAt`.
  - On selection, validate: if the chosen date is before `created_at` (use `_overriddenCreatedAt ?? widget.workOrder!.dateCreated`), show a `SnackBar` with "Closed date cannot be before created date" and reject.
  - If not admin or status is not "Closed": do not show this field at all.

- [ ] T015 [US3] Update `updateWorkOrder` in `frontend/lib/services/work_order_service.dart` to include `closed_at` in the JSON body when provided. Add an optional `String? closedAt` parameter (ISO 8601 string). If not null, add `'closed_at': closedAt` to the `jsonEncode` map.

- [ ] T016 [US3] Wire the save flow in `frontend/lib/screens/Work_Orders/add_work_order.dart`. In the save/submit method, pass `closedAt: _overriddenClosedAt?.toUtc().toIso8601String()` to `updateWorkOrder`. Only pass it if the admin actually changed the date and the status is "Closed".

**Checkpoint**: Admin can change the "Closed At" date on closed WOs. Date-before-created validation works. Field hidden on non-closed WOs. Non-admins cannot see or edit it.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and cleanup across all user stories.

- [ ] T017 Verify that the three new fields display correctly in the work order detail/view screens (not just edit). Check `frontend/lib/screens/Work_Orders/` for any detail view that shows Created By, Created At, or Closed At — ensure they reflect the updated values after admin edits.

- [ ] T018 Test edge case: admin changes "Created At" on a closed WO to a date after "Closed At". Backend should reject with 400. Verify the frontend also prevents this by cross-validating when both fields are present.

- [ ] T019 Verify that the `updated_at` timestamp is refreshed whenever any of the three metadata fields are changed (this should happen automatically since the backend update dict triggers Supabase's `updated_at` auto-update, but confirm).

- [ ] T020 Test the full flow end-to-end: as admin, edit all three fields on a closed WO in a single save. Verify all three persist correctly and the activity log entry includes the detail about which metadata fields changed.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: N/A — no setup needed
- **Phase 2 (Foundational/Backend)**: No dependencies — start immediately. BLOCKS all frontend work.
- **Phase 3 (US1 - Created By)**: Depends on Phase 2 completion
- **Phase 4 (US2 - Created At)**: Depends on Phase 2 completion. Can run in parallel with Phase 3.
- **Phase 5 (US3 - Closed At)**: Depends on Phase 2 completion. Can run in parallel with Phase 3 and 4.
- **Phase 6 (Polish)**: Depends on all user stories being complete.

### User Story Dependencies

- **US1 (Created By)**: Depends only on Phase 2. Independent of US2 and US3.
- **US2 (Created At)**: Depends only on Phase 2. Independent of US1 and US3.
- **US3 (Closed At)**: Depends only on Phase 2. Independent of US1 and US2. Cross-validates against Created At value.

### Within Each User Story

- Frontend widget/field creation before service wiring
- Service update before save flow wiring
- Each story can be tested independently after completion

### Parallel Opportunities

- T011 (US2 frontend field) and T014 (US3 frontend field) can be built in parallel — they modify the same file but different sections
- T009, T012, T015 (service updates) modify the same method but add independent parameters — best done sequentially to avoid merge conflicts
- All three user stories (Phases 3-5) can be started in parallel after Phase 2 is done, but since they modify the same files, sequential execution is recommended for an LLM agent

---

## Implementation Strategy

### Recommended: Sequential Step-by-Step (for LLM agent)

Since a single LLM agent will implement this, execute tasks in strict order T001 → T020:

1. **T001-T005**: Complete all backend changes first. This gives a working API.
2. **T006-T010**: Implement US1 (Created By) — the MVP. Test independently.
3. **T011-T013**: Implement US2 (Created At). Test independently.
4. **T014-T016**: Implement US3 (Closed At). Test independently.
5. **T017-T020**: Polish and end-to-end validation.

### MVP Scope

After completing Phase 2 + Phase 3 (T001-T010), you have a working MVP where admins can change the "Created By" field. This is the highest-value story and can be deployed independently.

---

## Notes

- All backend changes are in a single file: `backend/routers/work_orders.py`
- All frontend screen changes are in a single file: `frontend/lib/screens/Work_Orders/add_work_order.dart`
- The service file `frontend/lib/services/work_order_service.dart` gets three incremental parameter additions
- One new file created: `frontend/lib/widgets/user_selector.dart`
- No database migrations needed — all fields already exist
- Follow existing code patterns exactly (variable naming, error handling, UI layout)
- Commit after each phase checkpoint
