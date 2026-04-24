# Implementation Plan: Delete User

**Branch**: `093-delete-user` | **Date**: 2026-04-24 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/093-delete-user/spec.md`

## Summary

Add a permanent **Delete User** capability to the admin User Management screen. From inside the existing user details dialog, an admin can tap a Delete button (hidden when viewing their own account) and confirm a two-step dialog. The backend exposes `DELETE /users/{user_id}` which verifies the caller is an active admin, blocks self-deletion, blocks deletion that would leave zero active admins, removes the Supabase Auth identity (if any), removes the `public.users` row, and writes a `user_deleted` entry to `user_activity_log`. No migrations, no new dependencies.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x (frontend); Python 3.10 (backend)
**Primary Dependencies**: FastAPI, Supabase Python client (backend, existing); `http`, `supabase_flutter`, Flutter Material (frontend, existing). **No new dependencies.**
**Storage**: Supabase (PostgreSQL) — existing `users`, `user_activity_log` tables. No schema changes, no migrations. Supabase Auth (`auth.users`) via admin client.
**Testing**: Manual E2E via quickstart (backend restart + Flutter hot reload on web).
**Target Platform**: Flutter Web (PWA) + FastAPI on Linux server.
**Project Type**: Web application (backend + frontend).
**Performance Goals**: Single user deletion completes in < 5 s wall-clock (Auth + DB + activity log).
**Constraints**: Must follow exact pattern of existing `deactivate_user` / `reset_user_password` endpoints (admin guard, `admin_email` query param, `_errorDetail` client handling, `_loadData()` refresh, SnackBar feedback). Deletion is irreversible.
**Scale/Scope**: Single-action admin tool — < 1 call/minute. ~30 lines of Python, ~80 lines of Dart.

## Constitution Check

Evaluated against `.specify/memory/constitution.md` v1.0.0.

| Principle | Compliance |
|---|---|
| I. Full-Stack Ownership | PASS. Backend route + frontend service + screen all touched. No migration needed (no schema change). AGENT.md + Architecture.md will be updated post-implementation. |
| II. Explicit Over Automatic | PASS. Two-step confirmation dialog; no auto-delete. `user_deleted` activity entry written at deletion time, not inferred. |
| III. Role-Based Access Control | PASS. Admin-only endpoint via existing `_require_admin(admin_email)` guard. Self-delete block + last-admin block enforced server-side (defense-in-depth over UI guard). |
| IV. Server-First File Storage | N/A. No file storage involved. |
| V. Client-Side Computation | N/A. Single-record mutation. |
| VI. Audit Everything | PASS. `log_activity(admin_email, "admin", "user_deleted", target_label=user["email"], detail=...)` on success. Fire-and-forget, matches existing pattern. |
| VII. Simplicity & YAGNI | PASS. Reuses existing admin-guard helper, existing activity-log util, existing SnackBar/dialog widgets. No new abstraction, no new config. |

**Gate**: PASS. No violations. Complexity Tracking section not required.

## Project Structure

### Documentation (this feature)

```text
specs/093-delete-user/
├── plan.md              # This file
├── spec.md              # Feature spec (complete, clarifications applied)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── delete-user.http # Phase 1 output — HTTP contract for DELETE /users/{user_id}
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (/speckit.tasks, NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── users.py                         # EDIT — add @router.delete("/users/{user_id}")
└── utils/
    └── activity.py                      # unchanged — reuse log_activity()

frontend/lib/
├── screens/admin/
│   └── user_management_screen.dart      # EDIT — add Delete button inside _showUserDetailsDialog,
│                                        #        two-step confirmation, rename local `deleting`
│                                        #        to `deactivating` to avoid variable collision
├── services/
│   └── user_service.dart                # EDIT — add deleteUser(userId) method (HTTP DELETE)
└── models/
    └── user.dart                        # unchanged (per spec: do not modify AppUser)

supabase/migrations/                      # unchanged — no schema changes
```

**Structure Decision**: Web application (backend + frontend) layout, matching the existing repository. The feature edits exactly three files (one backend router, one Flutter service, one Flutter screen) and touches no migrations, models, or shared widgets. This is the minimal surface that satisfies Full-Stack Ownership while honoring YAGNI.

## Complexity Tracking

Not applicable — Constitution Check passes cleanly.
