# Implementation Plan: Department-scoped File Visibility

**Branch**: `092-dept-file-visibility` | **Date**: 2026-04-23 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/092-dept-file-visibility/spec.md`

## Summary

Restrict the Files screen so that technicians and reporters only see files scoped to their department (via `technician_departments`) or files with no department (globals). Admin/supervisor/superintendent keep full visibility. Admins can assign a department at upload time, edit it later per-file, and see a department badge on scoped files. An explicit per-user share (`resource_permissions`) overrides department scope. Folders are NOT department-scoped in this release — scope is evaluated per-file only.

**Technical approach**: Add nullable `department_id` to the `files` table (actual table name — not `documents`). Build a new FastAPI list endpoint that applies the visibility filter server-side and is called by the frontend instead of the current direct `supabase.from('files')` query. Add a PATCH endpoint to change a single file's department. Add `GET /api/departments/mine` returning the current user's departments and a `is_global_viewer` flag. Frontend model gets a `departmentId` + `departmentName` field, upload dialog gets an optional picker, cards gain a badge, and technicians/reporters see a "Showing files for …" label.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client (backend, existing); `http`, `supabase_flutter`, Flutter Material (frontend, existing). **No new dependencies.**
**Storage**: Supabase (PostgreSQL) — existing `files`, `file_folders`, `departments`, `technician_departments`, `users`, `resource_permissions` tables. One migration adds `files.department_id UUID NULL REFERENCES departments(id) ON DELETE SET NULL` plus an index. `file_folders` is NOT modified (folder scope dropped per clarification).
**Testing**: Manual test plan in `quickstart.md`. No test framework currently wired for this area of the repo; follow existing pattern.
**Target Platform**: FastAPI on Linux server behind Nginx; Flutter web PWA + mobile.
**Project Type**: Web application (FastAPI backend + Flutter frontend).
**Performance Goals**: Files list endpoint returns in ≤300 ms p95 for typical dataset (<10k files). Filter cost dominated by an indexed lookup on `files.department_id` plus a small `IN` list from `technician_departments`.
**Constraints**: No Supabase RLS changes (FR — filtering in FastAPI layer). Backwards compatible: all existing rows have `department_id NULL` and remain globally visible. Frontend direct-Supabase listing query must migrate to the new backend endpoint, otherwise the filter is trivially bypassable.
**Scale/Scope**: Small deployment (~dozens of users, low-thousands of files). Single department per file; single-select UI.

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Migration + backend router + frontend model/service/screen updates all included. Documentation updated via `update-agent-context.ps1`. |
| II. Explicit Over Automatic | PASS | Department assignment is explicit at upload and explicit on edit. No implicit inheritance (folder scope rejected). |
| III. Role-Based Access Control | PASS | Enforces existing three-role model + supervisor/superintendent flags. Upload remains admin-only. `resource_permissions` override preserved (FR-016). **Note**: current frontend queries Supabase directly for file listing; this plan migrates listing to the backend so the RBAC rule is actually enforceable. Supabase RLS remains as defense-in-depth only. |
| IV. Server-First File Storage | PASS | No changes to storage path, UUID naming, or `StaticFiles` mount. |
| V. Client-Side Computation Where Possible | PASS | Filtering intentionally done server-side because it is a security boundary (cannot be client-side). Client still renders from a single fetched list. |
| VI. Audit Everything | PASS | Upload activity-log entry extended with `department_id` when present. Post-upload department edit writes a new activity-log entry (`file` / `updated`) with old and new department. |
| VII. Simplicity & YAGNI | PASS | Single optional `department_id` column, one list endpoint, one PATCH endpoint, one "mine" endpoint. No folder scope, no bulk re-assign, no multi-department-per-file. |

**No violations — Complexity Tracking table empty.**

## Project Structure

### Documentation (this feature)

```text
specs/092-dept-file-visibility/
├── plan.md              # This file
├── spec.md              # Feature specification (with Clarifications)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output — manual test plan
├── contracts/
│   ├── files-list.md
│   ├── files-upload.md
│   ├── files-patch-department.md
│   └── departments-mine.md
└── tasks.md             # /speckit.tasks output (NOT created here)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   ├── files.py              # MODIFY: accept department_id on upload; add list + patch-dept endpoints
│   └── departments.py        # MODIFY: add GET /mine
└── utils/
    └── file_visibility.py    # NEW (small): get_visible_file_ids(current_user) helper

frontend/lib/
├── models/
│   └── file_model.dart       # MODIFY: add departmentId, departmentName
├── services/
│   ├── file_service.dart     # MODIFY: switch fetchFiles() to backend endpoint; add updateDepartment()
│   └── department_service.dart # MODIFY: add fetchMyDepartments()
└── screens/Files/
    ├── files_screen.dart     # MODIFY: scope label + badge rendering
    └── add_file_screen.dart  # MODIFY: optional Department dropdown; include department_id in upload

supabase/
└── migrations/
    └── 20260423000000_add_department_id_to_files.sql  # NEW
```

**Structure Decision**: Standard two-tier layout already in place (`backend/` + `frontend/`). No new top-level directories. The files screen lives at `frontend/lib/screens/Files/` (capital F, confirmed). The files table is `files` (not `documents`) and the folders table is `file_folders` (not `document_folders`); the spec's provisional names are corrected here.

## Phase 0: Outline & Research

See [research.md](./research.md). Key decisions:

- **Table names**: Use actual `files` and `file_folders`, not the spec's provisional `documents`/`document_folders`.
- **Folder scope**: Dropped per clarification Q2 — `file_folders` is not modified.
- **Frontend listing path**: Currently `file_service.dart` calls `_client.from('files').select(...)` directly. The department filter cannot be enforced in the Flutter client (trivially bypassable). The new `GET /api/files/list` backend endpoint replaces the direct Supabase query; Flutter migrates to `http` just like `department_service.dart` already does.
- **Per-user share override (FR-016)**: The existing `resource_permissions` table holds per-file grants. The backend visibility query union-joins file IDs from `resource_permissions` where `user_email = current_user.email AND resource_type = 'file'`, so an explicitly shared file appears regardless of department. Existing sharing flow is untouched.
- **Department-delete behavior (FR-015)**: `ON DELETE SET NULL` on the new FK handles this automatically.
- **Global-viewer signal (FR-011)**: `GET /api/departments/mine` returns `{ departments: [{id, name}], is_global_viewer: bool }`. `is_global_viewer = user.user_type == 'admin' OR user.is_supervisor OR user.is_superintendent`. Client uses the flag to suppress the scope label.

## Phase 1: Design & Contracts

### Data model

See [data-model.md](./data-model.md). One new column on `files`:

```sql
ALTER TABLE files
  ADD COLUMN department_id UUID NULL REFERENCES departments(id) ON DELETE SET NULL;
CREATE INDEX idx_files_department_id ON files(department_id) WHERE department_id IS NOT NULL;
```

No changes to `file_folders`, `resource_permissions`, `users`, `departments`, or `technician_departments`.

### Contracts

See [contracts/](./contracts/) for full shapes. Summary:

- `POST /api/files/upload` — existing endpoint gains one optional form field `department_id: str | None`. Validates it exists in `departments` before insert. Activity log includes `department_id` when set.
- `GET /api/files/list` — **new**. Query param `user_email: str`. Returns all files the caller can see, applying the visibility filter (admin/supervisor/superintendent: no filter; others: `department_id IS NULL OR department_id IN (user's depts) OR id IN (shared via resource_permissions)`). Replaces direct Supabase query in `file_service.dart`.
- `GET /api/files/{file_id}` — **new** (currently no single-file endpoint; `/my-role` is the closest). Returns the file record if visible to caller; 403 otherwise.
- `PATCH /api/files/{file_id}/department` — **new**. Body: `{ department_id: str | null }`. Admin only. Writes activity log.
- `GET /api/departments/mine` — **new**. Returns `{ departments: [{id, name}], is_global_viewer: bool }` for the caller.

### Agent context

Run after contract files exist:

```powershell
.specify/scripts/powershell/update-agent-context.ps1 -AgentType claude
```

### Post-design Constitution re-check

No new violations introduced by design. `Server-First File Storage` unaffected. `Audit Everything` upheld via activity-log entries on upload (extended) and department edit (new). `Simplicity & YAGNI` upheld — no abstraction layers added; filter is a single SQL OR composition.

## Complexity Tracking

*(empty — no violations to justify)*
