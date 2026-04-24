# Implementation Plan: Department Auto-Assignment on File Upload

**Branch**: `094-dept-auto-assign` | **Date**: 2026-04-24 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/094-dept-auto-assign/spec.md`

## Summary

Restrict the upload-form department picker to Admin users only. For Technician / Reporter / Supervisor / Superintendent, the server automatically assigns the uploader's own department (resolved from `users.department_id`) to the new file record, ignoring any client-supplied `department_id`. Non-admins who have no department assigned are blocked: the frontend disables the upload button with an advisory message, and the server rejects spoofed requests with an error. No schema changes — this builds on the `files.department_id` column added in spec 092.

**Technical approach**: Extend `GET /api/departments/mine` to also return the caller's role (`is_admin`) and their primary `department_id`. Modify `POST /api/files/upload` to override `department_id` with the authenticated user's own department when the caller is non-admin, and to 400 when such a user has no department. Hide the department dropdown in `add_file_screen.dart` for non-admins, disable the upload button (with helper text) when a non-admin has no department, and skip sending `department_id` from the client for non-admins.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client (backend, existing); `http`, `supabase_flutter`, Flutter Material, `file_picker` (frontend, existing). **No new dependencies.**
**Storage**: Supabase (PostgreSQL) — existing `files`, `users`, `departments`, `technician_departments` tables. **No schema changes, no migrations.** Relies on the `files.department_id` column added in spec 092.
**Testing**: Manual test plan in `quickstart.md`. No automated test framework wired for this area; follow existing pattern.
**Target Platform**: FastAPI on Linux server behind Nginx; Flutter web PWA + mobile.
**Project Type**: Web application (FastAPI backend + Flutter frontend).
**Performance Goals**: Upload-form open ≤300 ms p95 (one extra `/departments/mine` call already made today). Upload endpoint no extra round trips.
**Constraints**: Server is the authoritative enforcer — frontend hiding the picker is convenience, not security. Backwards compatible with existing admin uploads. No retroactive change to existing file rows.
**Scale/Scope**: Small deployment (~dozens of users). One endpoint modified, one endpoint extended, one screen modified.

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend (upload + mine endpoints), frontend model/service/screen, documentation all included. No migration needed — column exists. |
| II. Explicit Over Automatic | PARTIAL (justified) | Principle II forbids silent fallback. Here the "auto-assign" is intentional and explicit at the role level: admins pick explicitly; non-admins have zero ambiguity because they own exactly one department. The server always substitutes its authoritative value — there is no hidden cascade. See Complexity Tracking. |
| III. Role-Based Access Control | PASS | Reinforces RBAC: the department picker becomes admin-only, matching the permissions matrix. Server performs the role check via `users.user_type == 'admin'`. |
| IV. Server-First File Storage | PASS | No changes to storage path, file naming, or `StaticFiles` mount. |
| V. Client-Side Computation Where Possible | PASS | Role check and dept substitution are security boundaries — correctly server-side. |
| VI. Audit Everything | PASS | Existing upload activity-log entry continues to include `department_id`; reflects the server-substituted value for non-admins. |
| VII. Simplicity & YAGNI | PASS | One field added to `/departments/mine` response, one `if` in upload, one conditional in the form. No new tables, endpoints, or abstractions. |

## Project Structure

### Documentation (this feature)

```text
specs/094-dept-auto-assign/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (no schema changes — documents entities only)
├── quickstart.md        # Phase 1 output — manual test plan
├── contracts/
│   ├── files-upload.md          # MODIFY existing contract
│   └── departments-mine.md      # EXTEND existing contract
└── tasks.md             # /speckit.tasks output (NOT created here)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   ├── files.py              # MODIFY: substitute uploader's department_id for non-admin; 400 if non-admin has no dept
│   └── departments.py        # MODIFY: /mine response adds is_admin + primary_department_id
└── utils/
    └── file_visibility.py    # (unchanged — already exposes get_user_by_email / is_global_viewer)

frontend/lib/
├── services/
│   └── department_service.dart   # MODIFY: parse new fields from /mine (is_admin, primary_department_id)
└── screens/Files/
    └── add_file_screen.dart      # MODIFY: hide dropdown for non-admin; disable upload + advisory text when non-admin has no dept; omit department_id from multipart for non-admin

supabase/
└── migrations/
    └── (no new migration)
```

**Structure Decision**: Standard two-tier layout already in place. No new directories. No new files. All changes are in files already modified by spec 092.

## Phase 0: Outline & Research

See [research.md](./research.md). Key decisions:

- **Role source**: Use `users.user_type == 'admin'` as the single admin check. This matches `is_global_viewer()` in `backend/utils/file_visibility.py` (which also treats supervisor/superintendent as global viewers for *visibility*, but this feature restricts the picker to admin only — supervisor and superintendent are non-admin here).
- **Department source for non-admins**: `users.department_id` (the primary single-department column). `technician_departments` is NOT used here — the spec's clarifications state "Each non-admin user has exactly one department_id assigned in their profile."
- **Client-side role gate**: Reuse the existing `GET /api/departments/mine` call (added in spec 092) and extend its response with `is_admin: bool` and `primary_department_id: str | null`. This avoids a second round trip on the upload form.
- **Spoof defense**: Server substitution runs *after* form parsing but *before* the DB insert; the incoming `department_id` form field is silently discarded for non-admins.
- **No-department block**: Frontend disables the submit button and shows helper text when `is_admin == false && primary_department_id == null`. Server returns HTTP 400 with `detail = "User has no department assigned; contact your administrator."` for the same case.
- **Back-compat**: Admin upload flow is byte-identical to today. Existing rows untouched.

## Phase 1: Design & Contracts

### Data model

See [data-model.md](./data-model.md). **No schema changes.** Documents the relevant existing entities: `users.user_type`, `users.department_id`, `files.department_id`.

### Contracts

See [contracts/](./contracts/) for full shapes. Summary of changes:

- `POST /api/files/upload` — logic change only; form fields unchanged. For non-admin callers: server overrides `department_id` with `users.department_id`; returns 400 if the caller has none. For admins: unchanged behavior.
- `GET /api/departments/mine` — response extended with `is_admin: bool` and `primary_department_id: str | null`. Existing fields (`departments`, `is_global_viewer`) unchanged.

### Agent context

Run after contract files exist:

```powershell
.specify/scripts/powershell/update-agent-context.ps1 -AgentType claude
```

### Post-design Constitution re-check

No new violations. Principle II partial justification stands — the auto-assignment is deterministic and role-scoped, not a hidden cascade.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Principle II (Explicit Over Automatic) — server substitutes `department_id` for non-admins instead of requiring explicit selection | Non-admin users each belong to exactly one department; showing them a picker with a single valid option is UI noise and invites mis-scoping when the client caches a stale value. Admins remain explicit. | Keep the picker visible to all roles: rejected — current default "None (global)" causes mis-scoping in practice, and non-admin users have no legitimate cross-department upload use case. |
