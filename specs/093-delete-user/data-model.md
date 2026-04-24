# Phase 1 Data Model: Delete User

**Feature**: 093-delete-user
**Date**: 2026-04-24

No new tables. No schema changes. No migration file. This feature only **removes** rows from existing tables and **inserts** one audit row.

## Entities Touched

### `auth.users` (Supabase Auth, managed)

- **Operation**: `DELETE` (single row, keyed by `auth_id` on the app-side user).
- **Effect**: The user can no longer sign in. JWT previously issued will still validate until expiry (standard Supabase behavior) — this is acceptable per spec FR-006 ("on the next try").
- **Skipped when**: The app-side user has no `auth_id` (FR-009 edge case).

### `public.users`

- **Operation**: `DELETE` (single row, keyed by `id`).
- **Effect**: The user disappears from all `public.users` lookups (list screens, admin dashboards).
- **Foreign-key behavior**: Existing FKs from `work_orders`, `work_order_signatures`, `work_order_assignments`, `files`, etc., point at `users.id`. These references are **not** touched — historical records retain the UUID (spec Assumptions: "references remain as historical records"). Current schema permits this because those FKs are nullable or use `ON DELETE SET NULL`; any FK configured `ON DELETE RESTRICT` would surface a DB error that propagates to the admin as HTTP 500. No change to FK policy is in scope for this feature.

### `user_activity_log`

- **Operation**: `INSERT` (single row) via `backend/utils/activity.py::log_activity()`.
- **Row shape**: follows the helper's contract — `performed_by = admin_email`, `category = "admin"`, `action = "user_deleted"`, `target_label = deleted_user.email`, `detail = "Deleted user <email> (id: <uuid>)"`, `created_at = now()`.
- **Effect**: Permanent audit trail (FR-010, SC-002). Fire-and-forget; logging failure MUST NOT cause the delete to report failure.

## Pre-Delete Read Queries

These are not mutations but they are part of the deletion flow:

1. **Target lookup**: `SELECT * FROM users WHERE id = :user_id` — used to obtain `auth_id`, `email`, `role`, and return 404 if missing.
2. **Admin guard**: `_require_admin(admin_email)` internally reads the caller's row.
3. **Last-admin count** (only when target's `role = 'admin'`):
   `SELECT count(*) FROM users WHERE role = 'admin' AND is_active = true`.
   Rejection condition: `count <= 1`.

## State Transitions

- **User (in scope)**: `exists → deleted`. Terminal; no reverse transition within the product (spec Assumptions).
- **Auth identity (in scope)**: `exists → deleted`.
- **Email address (out of band)**: immediately reusable for a new account via the existing Add User flow (spec FR-017). No reservation row is persisted.

## Validation Rules

| Rule | Enforced where | Error response |
|---|---|---|
| Caller is an active admin | `_require_admin(admin_email)` | 403 Forbidden |
| Target user exists | `_get_user_by_id(user_id)` | 404 Not Found |
| Target is not the acting admin | email equality check | 400 Bad Request — "Cannot delete your own account" |
| Deletion would not leave zero active admins | count query (admin targets only) | 400 Bad Request — "Cannot delete the last active admin" |
| Auth identity delete succeeds (if `auth_id` present) | try/except around Supabase Auth admin call | 400/500 depending on root cause |

All constraints are enforced server-side. UI guards (FR-003) are cosmetic and duplicative for UX.
