# Phase 0 Research: Delete User

**Feature**: 093-delete-user
**Date**: 2026-04-24

No `NEEDS CLARIFICATION` markers in Technical Context — all technology choices are dictated by existing patterns in the repository. This document records the decisions and why they were picked over alternatives.

## Decision 1 — Reuse existing admin-guard helper

- **Decision**: Use `_require_admin(admin_email)` from `backend/routers/users.py` at the top of the new `delete_user` endpoint.
- **Rationale**: The helper already enforces "active admin" semantics and is used by every other admin-only endpoint in the file (`create_user`, `deactivate_user`, `reset_user_password`, `activate_user`). Using it preserves consistency and keeps the new endpoint a drop-in alongside its siblings. Spec FR-005 explicitly calls for the same guard.
- **Alternatives considered**: A new bespoke guard with richer error codes was rejected — adds surface area for no current benefit (YAGNI).

## Decision 2 — Auth delete first, then DB row

- **Decision**: Order of operations is (1) delete Supabase Auth identity via `supabase.auth.admin.delete_user(auth_id)`, (2) delete `public.users` row via `.delete().eq("id", user_id).execute()`, (3) write `user_activity_log` entry. If the Auth call raises, stop and surface HTTP 400/500 without touching the DB row.
- **Rationale**: Spec FR-008 requires "no partial deletion" — the app row must not outlive the credential, and the credential must not outlive the app row. Deleting Auth first means a failure leaves both records intact (recoverable state). Deleting DB first would leave an orphan Auth identity that can still log in if Auth delete later fails.
- **Alternatives considered**:
  - *DB first, Auth second* — rejected: orphan Auth identity with no app row could still obtain a JWT on next login.
  - *Two-phase/transactional delete* — rejected: Supabase Auth lives outside PostgreSQL so there is no shared transaction; the sequential approach with fail-fast ordering is the pragmatic equivalent.
  - *Soft-delete (flag row deleted, retain both)* — rejected: spec explicitly requires permanent removal and email reuse.

## Decision 3 — No-auth-id edge case handled inline

- **Decision**: If the fetched user has no `auth_id` (FR-009 edge case), skip the Auth delete and proceed straight to the DB delete + activity log. Return success.
- **Rationale**: Matches the existing `reset_user_password` handler's explicit check for missing `auth_id` (lines 451–453 of `users.py`), which proves there are legitimate users in production without linked Auth rows. This is the minimal behavior that satisfies the spec without changing the data model.
- **Alternatives considered**: Hard-fail with 400 — rejected, spec explicitly requires treating this as success.

## Decision 4 — Self-delete and last-admin guards are server-authoritative

- **Decision**:
  - Self-delete: compare the target user's email with `admin_email`; if equal, raise 400 before any delete.
  - Last-admin: before deleting a user whose role is `admin`, count active admins via `supabase.table("users").select("id", count="exact").eq("role", "admin").eq("is_active", True)` and raise 400 if deleting this user would drop the count below 1.
- **Rationale**: Spec FR-003/FR-004/FR-016 require enforcement server-side, independent of UI state. The count query is O(1) at current scale and runs only on admin deletes.
- **Alternatives considered**:
  - *Rely on UI guard alone* — rejected: trivially bypassable with a raw HTTP client; spec requires defense-in-depth.
  - *Database trigger / RLS* — rejected: backend uses service-role key that bypasses RLS (constitution III); check at application layer is simpler and testable.

## Decision 5 — Activity log uses `log_activity` fire-and-forget

- **Decision**: After the DB row is gone, call
  `log_activity(admin_email, "admin", "user_deleted", target_label=deleted_email, detail=f"Deleted user {deleted_email} (id: {user_id})")`.
- **Rationale**: Matches the `user_deactivated`, `password_reset`, `user_activated` patterns already in `users.py`. Captures the acting admin (FR-010) and enough info to identify the deleted user (target email + uuid). Fire-and-forget aligns with Constitution VI (audit writes must not block primary request).
- **Alternatives considered**: Synchronous logging with its own error reporting — rejected, would contradict Constitution VI and existing convention.

## Decision 6 — Frontend variable rename (`deleting` → `deactivating`)

- **Decision**: Inside `_showUserDetailsDialog`, rename the existing local `bool deleting` (which tracks the Deactivate button's in-flight state) to `bool deactivating`, then introduce a fresh `bool deleting` for the new Delete flow.
- **Rationale**: Spec §"Rename collision fix" calls for this explicitly. The existing name is misleading (it actually gates deactivation) and would collide with the new flag.
- **Alternatives considered**: Re-use the single flag for both actions — rejected, spec explicitly forbids and the two actions are semantically distinct.

## Decision 7 — No new dependencies, no migration

- **Decision**: Implementation uses only packages already in `requirements.txt` / `pubspec.yaml`.
- **Rationale**: The Supabase Python client already exposes `auth.admin.delete_user`; Flutter's existing `http` package covers DELETE. No migration is needed because the feature stores no new data.
- **Alternatives considered**: A dedicated `deleted_users` audit table — rejected, `user_activity_log` already serves this role.

## Outstanding Questions

None. All spec clarifications from session 2026-04-24 have been folded into the decisions above.
