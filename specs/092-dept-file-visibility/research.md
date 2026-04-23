# Phase 0 Research: Department-scoped File Visibility

## Decision 1 — Table names: `files` + `file_folders`

**Decision**: Use the existing `files` and `file_folders` tables.
**Rationale**: Inspection of `backend/routers/files.py` and `backend/routers/folders.py` shows the actual Supabase tables are `files` (not `documents`) and `file_folders` (not `document_folders`). The spec's provisional names were placeholders; correcting them here prevents a non-existent-table migration failure.
**Alternatives considered**: Creating new `documents`/`document_folders` tables as the spec hinted — rejected as unnecessary churn that would orphan existing data and double every routing call.

## Decision 2 — Folder scope dropped (clarification Q2, option C)

**Decision**: Only `files` gain `department_id`. `file_folders` is not modified.
**Rationale**: User chose Option C during clarification — scope is evaluated per-file only. Simplifies implementation, avoids transitive visibility logic, and keeps the existing folder-permission hierarchy untouched.
**Alternatives considered**: Folder-level scope with transitive inheritance (original FR-005 draft) — rejected as added complexity without clear operational need.

## Decision 3 — Migrate file listing from direct Supabase query to backend endpoint

**Decision**: Add `GET /api/files/list` on the backend and change `FileService.fetchFiles()` to call it instead of `_client.from('files').select(...)`.
**Rationale**: The current Flutter `FileService` performs the file-list query directly against Supabase using the anon key. A department filter applied only in Flutter would be trivially bypassable (user dev-tools, direct SDK call). Constitution III requires backend-enforced RBAC as primary (RLS is defense-in-depth only). The constitution explicitly says "Any code changes MUST comply with these principles" — so enforcement has to live on the server. Spec also forbids RLS changes ("No RLS changes in Supabase — filtering is done in FastAPI layer").
**Alternatives considered**:
- Add Supabase RLS policies — rejected; spec explicitly forbids.
- Leave the query client-side and rely on trust — rejected; violates the core security guarantee (SC-001, SC-006).
- Reuse an existing endpoint — none exists; current backend has upload/delete/share/expiration but no list endpoint.

## Decision 4 — `resource_permissions` override via query composition

**Decision**: The list query for a non-global viewer returns files matching:
```
department_id IS NULL
OR department_id IN (SELECT department_id FROM technician_departments WHERE technician_id = :user_id)
OR id IN (SELECT resource_id FROM resource_permissions WHERE resource_type = 'file' AND user_email = :user_email)
```
**Rationale**: Clarification Q1 resolved per-user shares as a bypass of department scope. The third clause re-adds explicitly shared file IDs to the visible set. The existing Flutter `FileService.fetchFiles()` already uses a similar OR of `is_private`, `uploaded_by`, and `id.in.(...)` — the new backend query inherits that logic and layers department scope on top.
**Alternatives considered**: Evaluate `resource_permissions` only after department filter — rejected; would silently break existing per-user shares to out-of-department users.

## Decision 5 — `is_global_viewer` flag on `GET /api/departments/mine`

**Decision**: The endpoint returns `{ departments: [{id, name}], is_global_viewer: bool }`. Admin/supervisor/superintendent get `is_global_viewer: true` and `departments: []` (or a full list — same effect).
**Rationale**: FR-011 asks for "a signal that identifies admin-tier viewers". An explicit boolean is clearer than overloading "empty departments list" semantics. FR-012 uses it directly to suppress the scope label on the Files screen.
**Alternatives considered**: Return all departments for global viewers — rejected; forces the client to infer "global" from list length and duplicates existing `GET /api/departments/`.

## Decision 6 — `ON DELETE SET NULL` handles department deletion

**Decision**: FK constraint `ON DELETE SET NULL` on `files.department_id` fulfils FR-015 with no application code.
**Rationale**: When a department is deleted, any scoped files flip to global visibility automatically. Zero application logic required.
**Alternatives considered**: `ON DELETE CASCADE` (would delete files — catastrophic); `ON DELETE RESTRICT` (would block dept deletion — operationally annoying).

## Decision 7 — No new dependencies

**Decision**: Ship with existing `http`, `supabase_flutter`, FastAPI, Supabase Python client.
**Rationale**: All needed functionality — form fields, JSON responses, activity log, DropdownButton, chip widgets — already exists.

## Open items deferred to implementation

- Activity-log detail payload for department-edit action: follow existing `log_activity` signature in `backend/utils/activity.py`; concrete strings decided during coding.
- Exact order of "Showing files for …" label in `files_screen.dart`: slot under the existing header bar, style per `app_theme.dart`.
- Badge color for department chip: use `AppColors` primary-container tone, per `claude_widgets.dart` conventions.
