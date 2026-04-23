---
description: "Tasks for feature 092: Department-scoped File Visibility"
---

# Tasks: Department-scoped File Visibility

**Input**: Design documents from `/specs/092-dept-file-visibility/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: No automated-test tasks are included. The repo has no test framework wired for this area. Validation is manual per [quickstart.md](./quickstart.md).

**Organization**: Tasks grouped by user story so each story can land independently. Per plan.md, the Files screen currently queries Supabase directly from the client; US1 migrates listing to a new backend endpoint, which is the foundational move.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1, US2, US3, US4 (maps to spec.md user stories)
- All file paths are relative to repo root `c:\Development\flutter_work_order\`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: No project-init work needed — backend and frontend already exist. Only workspace prep.

- [x] T001 Verify the feature branch `092-dept-file-visibility` is checked out and `git status` is clean before starting.
- [x] T002 Skim [plan.md](./plan.md), [data-model.md](./data-model.md), and [contracts/](./contracts/) so every later task references the correct endpoint/table names (`files`, `file_folders`, `department_id`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Schema + shared backend helper + shared frontend model change. Every user story depends on these.

**⚠️ CRITICAL**: No user story tasks can start until this phase is complete.

- [x] T003 Create migration `supabase/migrations/20260423000000_add_department_id_to_files.sql` with: `ALTER TABLE files ADD COLUMN department_id UUID NULL REFERENCES departments(id) ON DELETE SET NULL;` + `CREATE INDEX idx_files_department_id ON files(department_id) WHERE department_id IS NOT NULL;`. Do NOT backfill existing rows.
- [x] T004 [P] Add `backend/utils/file_visibility.py` exporting `is_global_viewer(user: dict) -> bool` (returns `user_type == 'admin' OR is_supervisor OR is_superintendent`) and `get_user_department_ids(user_id: str) -> list[str]` (reads `technician_departments`). Pure helpers, no FastAPI deps.
- [x] T005 [P] Update `frontend/lib/models/file_model.dart`: add `final String? departmentId;` and `final String? departmentName;` fields; update constructor, `fromJson` (read `department_id`, `department_name`), and `toJson` accordingly. Keep all existing fields intact.

**Checkpoint**: Migration applied to Supabase (dev); backend helper importable; Flutter model compiles with the two new nullable fields.

---

## Phase 3: User Story 1 — Scoped visibility for technicians/reporters (P1) 🎯 MVP

**Goal**: A technician/reporter only sees files whose `department_id` is NULL, matches one of their departments, or where they are explicitly granted via `resource_permissions`.

**Independent Test**: Run [quickstart.md](./quickstart.md) tests T1, T2, T3, T4, T10, T12 — scoped users see only allowed files; direct-ID fetch of a hidden file returns 403; per-user share overrides scope; legacy files remain visible.

### Implementation for User Story 1

- [x] T006 [US1] In `backend/routers/files.py` add `GET /list` endpoint: `@router.get("/list")` accepting `user_email: str = Query(...)`. Look up user via `supabase.table("users").select("id, email, user_type, is_supervisor, is_superintendent").eq("email", user_email).single().execute()`. If `is_global_viewer`, `supabase.table("files").select("*, departments(name)").order("created_at", desc=True)`; else compose filter: `department_id IS NULL` OR `department_id IN (user dept ids from T004 helper)` OR `id IN (resource_permissions.resource_id where resource_type='file' AND user_email=...)`. Preserve existing `is_private`/`uploaded_by` rules from the current `FileService.fetchFiles()` logic. Shape each row per [contracts/files-list.md](./contracts/files-list.md) — flatten `departments.name` to top-level `department_name`.
- [x] T007 [US1] In `backend/routers/files.py` add `GET /files/{file_id}`: fetch the row, resolve caller; if not visible per same rule as T006, return `HTTPException(status_code=403)`. If visible, return the record with `department_name` joined. This covers SC-006 (direct-ID access denied).
- [x] T008 [US1] In `frontend/lib/services/file_service.dart` replace the body of `fetchFiles()` so it calls `GET ${kApiBaseUrl}/api/files/list?user_email=<email>` via `http.get` (see existing `department_service.dart` for the `http` pattern), parses `{"files":[...]}`, and maps each row to `FileModel`. Remove the direct `_client.from('files').select(...).or(...)` call. Keep the `SupabaseClient` import only if still used elsewhere in the file.
- [x] T009 [US1] In `frontend/lib/services/file_service.dart` add `Future<FileModel> fetchFileById(String id)` that calls `GET /api/files/{id}?user_email=<email>` and maps the response. Used by file-details flows to enforce 403.

**Checkpoint**: Log in as `tech_a@test.com`; Files list shows only globals + Electrical files. `Mechanical-SOP.pdf` is absent from the list AND its direct URL returns 403. Admin login still shows everything.

---

## Phase 4: User Story 2 — Admin upload picker + department badge (P1)

**Goal**: Admin can optionally scope a file to a department on upload, and the resulting file card shows a department badge on admin's view.

**Independent Test**: Quickstart T5, T6, T7 — upload with/without a department and verify visibility + badge behavior.

### Implementation for User Story 2

- [x] T010 [US2] Modify `POST /upload` in `backend/routers/files.py` (function `upload_file`) to accept `department_id: Optional[str] = Form(None)`. If provided and non-empty: `supabase.table("departments").select("id").eq("id", department_id).single().execute()` — on miss, raise `HTTPException(400, "Invalid department_id")`. Include `department_id` in the `record` dict passed to `supabase.table("files").insert(...)`. Extend the existing `log_activity(...)` call's `detail` to include `dept=<id>` when set.
- [x] T011 [US2] In `frontend/lib/services/department_service.dart` confirm or add `Future<List<Department>> fetchDepartments()` that calls the existing `GET /api/departments/` (or the existing project method). This is the data source for the new picker.
- [x] T012 [US2] In `frontend/lib/services/file_service.dart` update the upload method to accept an optional `String? departmentId` param and append it to the multipart form as `department_id` when non-null. Do not break existing callers — keep the param optional with default `null`.
- [x] T013 [US2] In `frontend/lib/screens/Files/add_file_screen.dart` add a `DropdownButtonFormField<Department?>` labeled "Department (optional)", populated from `DepartmentService.fetchDepartments()` on init. First item is a null "None (global)" option. Selected value is passed to the upload service call from T012. Use `app_theme.dart` for colors and `claude_widgets.dart` patterns where applicable.
- [x] T014 [US2] In `frontend/lib/screens/Files/files_screen.dart` render a small `Chip`/`Badge` on each file card when `file.departmentName != null`. No badge for `null`. Only visible to the admin viewer — check via the same role gate already used for admin-only UI in that file. Use existing theme tokens.

**Checkpoint**: Quickstart T5/T6/T7 pass. Badge visible on admin view; scoped files behave correctly for tech users.

---

## Phase 5: User Story 3 — Global viewers retain full visibility (P1)

**Goal**: Admin, supervisor, and superintendent users see every file regardless of `department_id`.

**Independent Test**: Quickstart T4 — login as `super@test.com` (supervisor) and verify all departments' files are visible.

### Implementation for User Story 3

- [x] T015 [US3] Verify the branch in `backend/routers/files.py` `GET /list` (T006) and `GET /files/{file_id}` (T007) that short-circuits when `is_global_viewer(user)` returns true skips the department filter AND the `resource_permissions` clause (a global viewer needs no grant). Add a docstring referencing FR-002 so the intent is obvious to future readers.
- [x] T016 [US3] Verify `is_global_viewer` helper from T004 returns true for `user_type == 'admin'` even when `is_supervisor`/`is_superintendent` are null (not false). Fix the helper with `bool(user.get("is_supervisor")) or bool(user.get("is_superintendent"))` if Supabase returns None. No schema change.

**Checkpoint**: Quickstart T4 passes — supervisor and admin see all 3 test files.

---

## Phase 6: User Story 4 — Scope label on Files screen (P2)

**Goal**: Technicians/reporters see "Showing files for <department names>" under the Files screen header; admin-tier users do not.

**Independent Test**: Quickstart T8 — label visible for `tech_a@test.com` (single dept) and `tech_ab@test.com` (two depts); absent for admin/supervisor.

### Implementation for User Story 4

- [x] T017 [US4] In `backend/routers/departments.py` add `GET /mine` accepting `user_email: str = Query(...)`. Look up user; if `is_global_viewer` returns true, respond `{ "departments": [], "is_global_viewer": true }`. Otherwise join `technician_departments` → `departments` and return `{ "departments": [{id, name}, ...], "is_global_viewer": false }`. Shape per [contracts/departments-mine.md](./contracts/departments-mine.md).
- [x] T018 [P] [US4] In `frontend/lib/services/department_service.dart` add `Future<({List<Department> departments, bool isGlobalViewer})> fetchMyDepartments()` hitting `GET /api/departments/mine?user_email=<email>`. Use a small inline record return type or a dedicated class — either is fine.
- [x] T019 [US4] In `frontend/lib/screens/Files/files_screen.dart` fetch "mine" on screen init alongside the files list. If `isGlobalViewer == false`, render a label beneath the header reading `"Showing files for ${departments.map((d) => d.name).join(', ')}"` in a subdued text style per `app_theme.dart`. If `isGlobalViewer == true`, render nothing.

**Checkpoint**: Quickstart T8 passes.

---

## Phase 7: Post-upload department edit (FR-017)

**Goal**: Admins can change or clear a single file's `department_id` after upload. Not tied to a lettered user story, but covered by clarification Q3 and FR-017.

**Independent Test**: Quickstart T9 — change Electrical-SOP to Mechanical and verify visibility flip + activity-log entry.

### Implementation

- [x] T020 In `backend/routers/files.py` add `PATCH /files/{file_id}/department` accepting `user_email: str = Query(...)` and body `{department_id: str | None}` (define a small Pydantic model `PatchDepartmentBody`). Verify caller is admin (`user_type == 'admin'`) else 403. Validate `department_id` exists when non-null else 400. Read old value, update the row, then call `log_activity(user_email, "file", "updated", target_label=<file title>, target_id=file_id, detail=f"dept: {old} → {new}")`. Shape per [contracts/files-patch-department.md](./contracts/files-patch-department.md).
- [x] T021 [P] In `frontend/lib/services/file_service.dart` add `Future<void> updateFileDepartment(String fileId, String? departmentId)` calling the PATCH endpoint.
- [x] T022 In `frontend/lib/screens/Files/file_details_screen.dart` add an admin-only "Change department" action (button / menu item). Opens a dialog with the same department dropdown used in `add_file_screen.dart` (T013), defaulted to the file's current `departmentId`. On save, calls T021, then refetches and pops. Show a "None (global)" option that sends `null`.

**Checkpoint**: Quickstart T9 passes. Activity log shows a `file`/`updated` row with dept change detail.

---

## Phase 8: Polish & Cross-Cutting

- [x] T023 [P] Run the migration from T003 against dev Supabase: `supabase db push` or `psql` the file. Confirm `\d files` shows `department_id` + the partial index.
- [ ] T024 [P] Restart backend: `sudo systemctl restart document_server.service` (mandatory per feedback memory — route/schema changes need restart).
- [ ] T025 Deploy frontend via `scripts/deploy_frontend.sh` and verify the build serves.
- [ ] T026 Execute the full [quickstart.md](./quickstart.md) test plan T1–T12 on the deployed build. Record any regressions.
- [x] T027 [P] Update `ARCHITECTURE.md` / `AGENT.md`: add `files.department_id` to the data-model section, and add the three new endpoints (`GET /api/files/list`, `GET /api/files/{id}`, `PATCH /api/files/{id}/department`, `GET /api/departments/mine`) to the routes section.
- [x] T028 Skim `file_service.dart` post-migration: remove any now-dead Supabase-direct code paths that were only used by the old `fetchFiles()`.
- [ ] T029 Run Dart analyzer and `flutter build web` to catch any type errors introduced by the model change (T005) or new nullable fields.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: T001–T002. Immediate.
- **Phase 2 (Foundational)**: T003–T005. T004 and T005 can run in parallel after T003 is applied locally.
- **Phase 3 (US1)**: Depends on Phase 2. T006 → T007 → T008 → T009 (T006/T007 share `files.py`, T008/T009 share `file_service.dart` → sequential within each file).
- **Phase 4 (US2)**: Depends on Phase 2 and — for end-to-end validation — on Phase 3 (to see the scoped visibility take effect). Code-wise T010–T014 can begin in parallel with US1; visibility proof requires both.
- **Phase 5 (US3)**: Depends on Phase 3 (US3 is a verification/hardening pass on US1's endpoint, plus the helper safety in T016).
- **Phase 6 (US4)**: Depends on Phase 2. Can start in parallel with US1/US2. T017 (backend) and T018/T019 (frontend) split cleanly.
- **Phase 7 (Edit-after-upload)**: Depends on Phase 2. T020 and T021 can proceed once foundational is done; T022 depends on T021 and on the dept dropdown pattern introduced by T013.
- **Phase 8 (Polish)**: After all functional phases. Deploy/test/docs.

### User Story Dependencies

- US1 → the MVP. Blocks US3 (US3 is a sanity-check phase on US1).
- US2 → independent of US1 code-wise, but end-to-end demo needs both.
- US4 → independent of all; can ship separately.
- FR-017 (Phase 7) → independent of all user stories but most useful after US2 lands.

### Within Each User Story

- Backend route/endpoint before frontend service.
- Frontend service before frontend screen.
- Screen changes last.

### Parallel Opportunities

- T004 || T005 (backend helper + Flutter model — different files).
- T014 and T019 both touch `files_screen.dart` → **sequential**.
- T010, T017, T020 are all backend endpoint adds in different routers / functions → can overlap if careful; but T006, T007, T010, T020 all edit `files.py` → serialize work in that file.
- T023 / T024 / T027 in Phase 8 are parallelizable (migration apply, service restart, docs).

---

## Parallel Example: User Story 4

```bash
# T017 backend + T018 frontend service can be done concurrently by two developers:
Dev A: Implement GET /api/departments/mine in backend/routers/departments.py (T017)
Dev B: Add fetchMyDepartments() to frontend/lib/services/department_service.dart (T018)
# T019 (files_screen label) depends on T018 being merged first.
```

---

## Implementation Strategy

### MVP scope

**User Story 1 + Story 2 + Story 3** (all P1). Delivers enforcement + authoring + the oversight-role safety net in one go. US4 (the label) can ship in the same release cycle but is the natural "P2 polish" that can be deferred if time-constrained.

### Recommended delivery order (single-developer, incremental)

1. **Foundational** — T001–T005. Apply migration to dev.
2. **US1** — T006–T009. Validate enforcement with T1/T2/T3/T4/T10/T12.
3. **US3** — T015–T016. Cheap verification pass that rolls into US1.
4. **US2** — T010–T014. Validate T5/T6/T7.
5. **Phase 7** (edit-after-upload) — T020–T022. Validate T9.
6. **US4** — T017–T019. Validate T8.
7. **Polish** — T023–T029. Deploy + full quickstart.

### Critical reminders (from project memory)

- After T010 (new routes) or schema change (T003): `sudo systemctl restart document_server.service` on the server — otherwise frontend sees generic errors.
- Do NOT commit `backend/version.json`.
- No RLS policies (spec forbids); enforcement is exclusively in FastAPI.

---

## Notes

- The spec's original names (`documents`, `document_folders`) are **not** the real table names — the code uses `files` and `file_folders`. Tasks reflect reality.
- Folder scope is explicitly OUT (clarification Q2 option C). Do not add `department_id` to `file_folders` or compute transitive folder restrictions.
- `resource_permissions` explicit shares override department scope (clarification Q1 option A; FR-016). This is handled inside the `GET /list` filter (T006), not by a separate code path.
