# Tasks: Department Auto-Assignment on File Upload

**Input**: Design documents from `/specs/094-dept-auto-assign/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: No automated tests were requested in the specification. Manual test plan is in `quickstart.md`. Test tasks are not included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `backend/routers/`, `backend/utils/`
- **Frontend**: `frontend/lib/services/`, `frontend/lib/screens/Files/`

---

## Phase 1: Setup

**Purpose**: No new project initialization needed. Existing project and dependencies suffice (no new packages per plan.md). This phase verifies the existing spec-092 infrastructure is in place.

- [x] T001 Verify spec 092 migration `20260423000000_add_department_id_to_files.sql` is applied and `files.department_id` column exists in `backend/routers/files.py` and Supabase

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Extend the `/api/departments/mine` endpoint so the frontend can obtain `is_admin` and `primary_department_id` — both non-admin UI logic and server-side substitution depend on these fields.

**⚠️ CRITICAL**: US1, US2, US3, and US4 all require the frontend to know the user's role and department before rendering the upload form. This phase must complete before any user story work begins.

- [x] T002 Extend `GET /api/departments/mine` response to include `is_admin: bool` and `primary_department_id: str | null` in `backend/routers/departments.py`
- [x] T003 [P] Update `DepartmentMineResponse` model (or dict return) to add `is_admin` and `primary_department_id` fields alongside existing `departments` and `is_global_viewer` in `backend/routers/departments.py`
- [x] T004 [P] Update `DepartmentService` / `department_service.dart` to parse and expose `is_admin` and `primary_department_id` from the `/mine` response in `frontend/lib/services/department_service.dart`

**Checkpoint**: Foundation ready — `/api/departments/mine` returns role and department info; frontend service can consume it.

---

## Phase 3: User Story 1 - Non-Admin Uploads File with Auto-Assigned Department (Priority: P1) 🎯 MVP

**Goal**: Non-admin users see no department picker and their uploads are automatically scoped to their own department.

**Independent Test**: Log in as a technician with a department, upload a file, verify `files.department_id` matches the user's `department_id` and no department field appears on the form.

### Implementation for User Story 1

- [x] T005 [US1] Modify `add_file_screen.dart` to conditionally hide the "Department (optional)" dropdown when `is_admin == false` in `frontend/lib/screens/Files/add_file_screen.dart`
- [x] T006 [US1] Modify the file upload submission in `add_file_screen.dart` to omit `department_id` from the multipart form payload when `is_admin == false` in `frontend/lib/screens/Files/add_file_screen.dart`
- [x] T007 [US1] Modify `POST /api/files/upload` handler to substitute `department_id` with the authenticated user's `users.department_id` for non-admin callers in `backend/routers/files.py`
- [x] T008 [US1] Add role check logic `is_admin = (user.user_type == "admin")` in the upload handler in `backend/routers/files.py`

**Checkpoint**: US1 complete — non-admin uploads auto-assigned to their department, no picker shown.

---

## Phase 4: User Story 2 - Admin Controls Department Assignment (Priority: P2)

**Goal**: Admin users continue to see the department dropdown, defaulting to "None (global)", and can select any department freely.

**Independent Test**: Log in as admin, verify dropdown is visible with default "None (global)", select a department, upload, verify `files.department_id` matches the selection.

### Implementation for User Story 2

- [x] T009 [US2] Conditionally show the "Department (optional)" dropdown when `is_admin == true` in `frontend/lib/screens/Files/add_file_screen.dart`
- [x] T010 [US2] Restore / preserve existing admin upload logic: admin-supplied `department_id` is passed through unchanged in `backend/routers/files.py`

**Checkpoint**: US2 complete — admin picker shown, admin uploads work identically to today.

---

## Phase 5: User Story 3 - Server Rejects Spoofed Department from Non-Admin (Priority: P3)

**Goal**: Any client-supplied `department_id` in a non-admin upload request is silently discarded and replaced by the server with the user's own department_id.

**Independent Test**: Send a crafted `POST /api/files/upload` with a spoofed `department_id` as a technician; verify the stored row uses the technician's real `department_id`.

### Implementation for User Story 3

- [x] T011 [US3] Verify and harden the server-side logic in `POST /api/files/upload` that discards any client-supplied `department_id` when `is_admin == false` and overrides it with the user's `department_id` in `backend/routers/files.py`
- [x] T012 [US3] Verify that the non-admin path in the upload handler does **not** validate or 400 on the presence of a `department_id` form field — it is silently ignored per the contract in `backend/routers/files.py`

**Checkpoint**: US3 complete — spoofed `department_id` values are silently discarded server-side.

---

## Phase 6: User Story 4 - Non-Admin Without Department Cannot Upload (Priority: P3)

**Goal**: A non-admin user with no `department_id` sees the upload button disabled with advisory text; server rejects direct API calls with a 400 error.

**Independent Test**: Log in as a technician with `department_id = null`, verify upload button is disabled and advisory message is shown; send a direct POST and verify 400 response.

### Implementation for User Story 4

- [x] T013 [US4] Add UI logic in `add_file_screen.dart` to disable the upload button and show advisory text "Contact your admin to assign a department before uploading files." when `is_admin == false && primary_department_id == null` in `frontend/lib/screens/Files/add_file_screen.dart`
- [x] T014 [US4] Add server-side guard in `POST /api/files/upload` to return HTTP 400 with `{"detail": "User has no department assigned; contact your administrator."}` when a non-admin user's `department_id` is null in `backend/routers/files.py`

**Checkpoint**: US4 complete — no-department non-admins are blocked on both frontend and server.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Cross-story validation and cleanup.

- [x] T015 Update AGENTS.md to document the new role-based upload behavior and the `departments/mine` response extension
- [ ] T016 Run the full manual test plan from `specs/094-dept-auto-assign/quickstart.md` covering all four user stories

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — verify existing schema.
- **Foundational (Phase 2)**: Depends on Setup verification — BLOCKS all user stories.
- **User Story 1 (Phase 3)**: Depends on Foundational completion.
- **User Story 2 (Phase 4)**: Depends on Foundational; modifies the same `add_file_screen.dart` file as US1 so should follow US1.
- **User Story 3 (Phase 5)**: Depends on US1 (US3 hardens the server logic introduced in US1).
- **User Story 4 (Phase 6)**: Depends on Foundational; touches same backend file as US1/US3 but can be implemented alongside US3.
- **Polish (Phase 7)**: Depends on all user stories being complete.

### User Story Dependencies

- **US1 (P1)**: Requires Foundational (T002–T004). No dependency on other stories.
- **US2 (P2)**: Requires Foundational. Modifies same UI file as US1 — apply after US1 to avoid merge conflict. Backend logic for admin pass-through is unchanged but must be verified.
- **US3 (P3)**: Requires US1 server handler (T007/T008). Hardens that same code path.
- **US4 (P3)**: Requires Foundational. Can be done in parallel with US3 (different code paths: UI guard + server 400).

### Within Each User Story

- Frontend and backend tasks within US1 can be done in parallel after Foundational is complete
- US2 primarily validates existing behavior; minimal code changes
- US3 and US4 add guards to the US1 server handler

### Parallel Opportunities

- T002 and T003 can run in parallel (endpoint logic vs. response model)
- T003 and T004 can run in parallel (backend response model vs. frontend service)
- T005 and T007 can run in parallel (frontend UI vs. backend handler) after Foundational
- T013 and T014 can run in parallel (frontend UI guard vs. server 400 guard)

---

## Parallel Example: Phase 2 (Foundational)

```
Task: "Extend /mine endpoint with is_admin and primary_department_id" (T002)
Task: "Update DepartmentMineResponse model with new fields" (T003)
Task: "Update department_service.dart to parse new /mine fields" (T004)
```

T002 and T003 can start together. T004 can start once T003's response shape is known.

## Parallel Example: Phase 3 (User Story 1)

```
Task: "Hide dropdown for non-admin" (T005) — frontend, after Foundational
Task: "Omit department_id from payload for non-admin" (T006) — frontend, after T005
Task: "Substitute department_id server-side for non-admin" (T007) — backend, after Foundational
Task: "Add role check in upload handler" (T008) — backend, after Foundational
```

T005+T006 (frontend) and T007+T008 (backend) can be developed in parallel.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Verify schema
2. Complete Phase 2: Foundational — extend `/mine` endpoint
3. Complete Phase 3: User Story 1 — hide picker, auto-assign department
4. **STOP and VALIDATE**: Test US1 independently via quickstart.md sections 2–3
5. Deploy/demo if ready — core value delivered

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add US1 → Test independently → **MVP!** (non-admin auto-assign works)
3. Add US2 → Test independently → Admin picker verified unchanged
4. Add US3 → Test independently → Spoof defense hardened
5. Add US4 → Test independently → No-department guard rail in place
6. Polish → Full manual test pass, docs update

### Notes

- No new dependencies, migrations, or schema changes required
- All modifications target existing files from spec 092
- Backend changes are confined to `backend/routers/files.py` and `backend/routers/departments.py`
- Frontend changes are confined to `frontend/lib/screens/Files/add_file_screen.dart` and `frontend/lib/services/department_service.dart`