# Quickstart: Delete User (093)

**Purpose**: Manual E2E walk-through for validating the feature after implementation and deploy. Follow top-to-bottom in a dev or staging environment before merging.

## Prerequisites

- Backend restarted after deploying `backend/routers/users.py` changes (`sudo systemctl restart document_server.service`).
- Frontend built and deployed (or running via `flutter run -d chrome` for local dev).
- Logged in to the app as an **admin** (e.g., `salah@admin.com`).
- At least **one non-admin** test user exists that you can delete.
- At least **two active admins** exist in the system (for the last-admin test) OR you are prepared to flip a test user's role temporarily.

## Happy Path — Delete a non-admin user

1. Open the User Management screen.
2. Tap a non-admin user's card to open the details dialog.
3. Confirm the Delete User button is visible (leftmost action, danger-color).
4. Tap **Delete User**. A second "Delete User?" dialog appears naming the user.
5. Tap **Delete** in the confirmation dialog.
6. **Expect**:
    - Success SnackBar: "User deleted successfully" (danger-color background).
    - Details dialog closes.
    - User Management list refreshes and the user is gone.
7. **Verify**: attempt to sign in as the deleted user → sign-in fails.
8. **Verify** (Supabase): row is gone from `public.users`; no row in `auth.users` for that email.
9. **Verify** (`user_activity_log`): one fresh row with `action = 'user_deleted'`, `performed_by = <admin email>`, `target_label = <deleted user email>`.

## Cancel Path — two-step confirmation protects

1. Repeat steps 1–4 above.
2. In the confirmation dialog, tap **Cancel**.
3. **Expect**: no network call, no change to the list, details dialog still open (or closed cleanly without effect).
4. **Verify** (`user_activity_log`): no new `user_deleted` row was written.

## Self-Delete Blocked — UI guard

1. In User Management, tap your own user card (the currently signed-in admin).
2. **Expect**: No Delete User button visible in the details dialog (FR-003).

## Self-Delete Blocked — Backend guard

Bypass the UI with a raw request:

```bash
curl -X DELETE \
  "https://<host>/users/<your-own-user-id>?admin_email=<your-own-email>"
```

**Expect**: HTTP 400 `{"detail": "Cannot delete your own account"}`. No deletion, no log entry.

## Last-Admin Blocked

1. Ensure only one active admin exists (e.g., temporarily deactivate all other admins).
2. As that admin, attempt to have another admin account delete the sole remaining active admin (sign in as a second admin that you temporarily activate for this test), or issue the DELETE request via curl using a second admin's email.
3. **Expect**: HTTP 400 `{"detail": "Cannot delete the last active admin"}`.
4. **Verify**: target admin still exists; no activity log entry.
5. Restore the original admin activation state.

## Orphan Auth (no `auth_id`) — success path

1. Find (or create) a `public.users` row whose `auth_id` is NULL.
2. Delete it from the User Management screen.
3. **Expect**: success SnackBar, row removed, activity log written.

## Auth-Delete Failure — consistency check

Harder to trigger in production, but verify behavior by forcing a failure (e.g., point `auth_id` at a non-existent Supabase Auth id, then delete):

1. **Expect**: HTTP error surfaced to UI as "Error: Failed to delete user from auth: …".
2. **Verify**: `public.users` row is **still present**; no activity log entry.

## Email Reuse

1. After a successful delete, open the Add User flow and create a new user with the **same email** as the just-deleted user.
2. **Expect**: account creates cleanly; new user can sign in (FR-017).

## Post-Run Cleanup

- Re-activate any admins you temporarily deactivated for the last-admin test.
- Remove test users you created.
- Confirm the activity log contains only the expected `user_deleted` entries (one per successful run of the Happy Path and Orphan Auth scenarios).
