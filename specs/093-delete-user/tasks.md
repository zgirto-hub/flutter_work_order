# Tasks: Delete User

**Feature**: 093-delete-user
**Branch**: `093-delete-user`
**Input design docs**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/delete-user.http](contracts/delete-user.http), [quickstart.md](quickstart.md)

**Tests**: Not requested in the spec or by the user. No automated test tasks are generated. Manual validation uses [quickstart.md](quickstart.md).

**Stack**: Python 3.10 + FastAPI + Supabase Python client (backend); Dart 3.x + Flutter 3.x + Material + `http` + `supabase_flutter` (frontend). **No new dependencies. No migrations.**

---

## Phase 1: Setup

No setup tasks required. Feature reuses the existing web-app layout, existing admin-guard helper, existing activity-log util, and existing user details dialog. No new packages, no new directories, no new config.

---

## Phase 2: Foundational (Blocking Prerequisites)

The frontend has a pre-existing variable name collision that blocks the new Delete flow. Fix before implementing any user story.

- [x] T001 Rename local variable `bool deleting` to `bool deactivating` inside `_showUserDetailsDialog` in [frontend/lib/screens/admin/user_management_screen.dart](../../frontend/lib/screens/admin/user_management_screen.dart); update **all** references inside that dialog (the Deactivate/Activate button's loading state and its `setState` callers). Do not touch any other variable. Verify the file still compiles with no other behavior change.

---

## Phase 3: User Story 1 — Admin permanently deletes an obsolete user (P1) 🎯 MVP

**Goal**: Admin can tap Delete in a non-self user's details dialog, confirm a second dialog, and the user is permanently removed from Supabase Auth and `public.users`, the list refreshes, and an audit entry is written.

**Independent Test**: Per [quickstart.md](quickstart.md) §"Happy Path — Delete a non-admin user" and §"Cancel Path". Log in as admin, delete a non-admin test user, confirm deletion and list refresh; repeat and cancel — verify nothing deleted.

### Backend (US1)

- [x] T002 [US1] Add `DELETE /users/{user_id}` handler `delete_user(user_id: str, admin_email: str = Query(...))` to [backend/routers/users.py](../../backend/routers/users.py), implementing this exact flow in order:
  1. `_require_admin(admin_email)` (admin guard).
  2. `user = _get_user_by_id(user_id)`; if falsy → `HTTPException(404, "User not found")`.
  3. If `user["email"] == admin_email` → `HTTPException(400, "Cannot delete your own account")`.
  4. (Skip last-admin guard here — added in US2.)
  5. `auth_id = user.get("auth_id")`; if present, `try: supabase.auth.admin.delete_user(auth_id)` inside a try/except that raises `HTTPException(400, f"Failed to delete user from auth: {e}")` on failure. If `auth_id` is missing, skip this step silently.
  6. `supabase.table("users").delete().eq("id", user_id).execute()`.
  7. `log_activity(admin_email, "admin", "user_deleted", target_label=user["email"], detail=f"Deleted user {user['email']} (id: {user_id})")`.
  8. `return {"message": "User deleted successfully"}`.
  Place the new handler immediately below `deactivate_user` to keep admin endpoints grouped.

### Frontend service (US1)

- [x] T003 [P] [US1] Add `Future<void> deleteUser(String userId)` to [frontend/lib/services/user_service.dart](../../frontend/lib/services/user_service.dart), mirroring the existing `deactivateUser` method but using `http.delete` against `${AppConfig.baseUrl}/users/$userId?admin_email=${Uri.encodeComponent(_email)}`. On non-200 responses, throw `Exception(_errorDetail(res, 'Failed to delete user'))`.

### Frontend screen (US1)

- [x] T004 [US1] In [frontend/lib/screens/admin/user_management_screen.dart](../../frontend/lib/screens/admin/user_management_screen.dart), inside `_showUserDetailsDialog`:
  - Declare a new `bool deleting = false` local inside the dialog's `StatefulBuilder` state (separate from the renamed `deactivating` from T001).
  - Compute `isSelf = user.email == Supabase.instance.client.auth.currentUser?.email` using the same pattern already used for the Approval Role read-only guard in this dialog.
  - Add a **Delete User** `TextButton.icon` as the **leftmost** entry in the dialog's `actions:` list, rendered only when `!isSelf`. Icon = `Icons.delete_outline`, label = `'Delete User'`, `foregroundColor: AppColors.dangerText`. Disable it while `deleting || deactivating` is true.
  - On press, show a second `AlertDialog` (the two-step confirmation):
    - Title: `'Delete User?'`
    - Content: `Text('This will permanently delete ${user.fullName ?? user.email} and cannot be undone.')`
    - Actions: `TextButton('Cancel')` returning `false`; `ElevatedButton('Delete')` with `style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerText, foregroundColor: Colors.white)` returning `true`.
  - If the confirmation returns `true`:
    1. `setState(() => deleting = true);`
    2. `try { await _userService.deleteUser(user.id); }` — on success: `Navigator.pop(ctx)` (close details dialog), `await _loadData()`, show success SnackBar `'User deleted successfully'` with `backgroundColor: AppColors.dangerText`.
    3. On exception: `setState(() => deleting = false);` and show an error SnackBar `'Error: $e'` with `backgroundColor: AppColors.dangerText`.
  - Do not modify the order of any other action buttons beyond inserting Delete as the leftmost one.

**Checkpoint (US1 complete)**: Manually run quickstart §"Happy Path" and §"Cancel Path". Deletion of a non-admin user works end-to-end; cancel does nothing. MVP ready.

---

## Phase 4: User Story 2 — Admin prevented from deleting their own account (P1)

**Goal**: Self-deletion is impossible from both the UI (button hidden) and the backend (rejected even if UI is bypassed), including last-admin protection per clarification.

**Independent Test**: Per [quickstart.md](quickstart.md) §"Self-Delete Blocked — UI guard", §"Self-Delete Blocked — Backend guard", and §"Last-Admin Blocked".

**Note**: The UI self-hide is already delivered by T004 (via `isSelf`). The backend self-delete guard is already delivered by T002 step 3. This phase adds the **last-admin protection** (FR-016) — the remaining server-side guard required by the clarifications.

- [x] T005 [US2] In `delete_user` in [backend/routers/users.py](../../backend/routers/users.py), insert the last-admin guard **between step 3 (self-delete check) and step 5 (Auth delete)** from T002:
  - If `user["role"] == "admin"`, count active admins:
    ```python
    resp = (
        supabase.table("users")
        .select("id", count="exact")
        .eq("role", "admin")
        .eq("is_active", True)
        .execute()
    )
    active_admin_count = resp.count or 0
    if active_admin_count <= 1:
        raise HTTPException(status_code=400, detail="Cannot delete the last active admin")
    ```
  - This guard runs only when the target is an admin, so non-admin deletes incur zero extra cost.

**Checkpoint (US2 complete)**: Run quickstart §"Self-Delete Blocked — Backend guard" (curl) and §"Last-Admin Blocked". Self-delete returns 400; last-admin delete returns 400; neither writes a log entry.

---

## Phase 5: User Story 3 — Deletion is auditable (P2)

**Goal**: Every successful deletion produces exactly one `user_deleted` activity log entry naming the acting admin and the deleted user; failed deletions produce none.

**Independent Test**: Per [quickstart.md](quickstart.md) §"Happy Path" step 9 and §"Auth-Delete Failure — consistency check".

**Note**: The `log_activity(...)` call is already delivered by T002 step 7, placed **after** the DB delete succeeds, so failures before that point correctly produce no entry. No code change needed beyond verification.

- [x] T006 [US3] Manual verification — run quickstart §"Happy Path" and confirm via Supabase SQL editor (or the existing activity log UI) that exactly one fresh row exists with `action = 'user_deleted'`, `performed_by` equal to the acting admin's email, and `target_label` equal to the deleted user's email. Then force an Auth-delete failure per quickstart §"Auth-Delete Failure" and confirm no new `user_deleted` row was written. If either check fails, file a follow-up task against `backend/routers/users.py`; do not edit the spec or plan.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T007 [P] Update [AGENT.md](../../AGENT.md) and [Architecture.md](../../Architecture.md) (if present) to mention the new `DELETE /users/{user_id}` admin endpoint and the self-delete + last-admin guards, following the same brief style used for the other admin user endpoints already documented there. Keep the entry to one or two lines.
- [ ] T008 Deploy checklist — after merging: `pip install -r requirements.txt` is **not** required (no new deps). `sudo systemctl restart document_server.service` on the Zorin server **is** required so FastAPI picks up the new route. Deploy the frontend via the standard `scripts/deploy_frontend.sh`. Do not commit `backend/version.json`.
- [ ] T009 Run the full [quickstart.md](quickstart.md) end-to-end against the deployed backend as a final acceptance gate before closing the branch.

---

## Dependencies

```text
T001 (foundational rename)
  └─► T002 (backend endpoint, US1) ─┐
  └─► T004 (frontend dialog, US1) ──┼─► T005 (last-admin guard, US2) ─► T006 (US3 verification)
  T003 (frontend service, US1) ─────┘
                                                                       └─► T007, T008, T009 (polish)
```

- **T001** must complete before **T004** (rename unblocks new `deleting` variable in the same dialog).
- **T002** must complete before **T004** calls `_userService.deleteUser` (frontend calls the endpoint).
- **T003** is independent of T001 and T002 at the code level but its end-to-end correctness depends on T002 existing at call time. Safe to implement in parallel with T002.
- **T005** depends on **T002** (it inserts logic into the same handler).
- **T006** depends on **T002**, **T004**, **T005** (verifies the full flow).
- **T007–T009** depend on everything above.

## Parallel Execution Opportunities

- **Round 1 (after T001)**: T002 (backend) and T003 (frontend service) can be developed in parallel — they touch different files and share no code.
- **Round 2**: T004 sequences behind T001, T002, T003.
- **Round 3**: T005 sequences behind T002.
- **Round 4 (polish)**: T007 is `[P]` with T008 and T009.

## Implementation Strategy

### MVP (stop-ship-worthy increment)

Complete Phase 2 + Phase 3: **T001 → T002 → T003 → T004**. At this point an admin can delete any non-self user end-to-end with a two-step confirmation, the audit log is written, and the list refreshes. This delivers the spec's primary user story (US1, P1) in isolation.

### Full feature

Add Phase 4 (T005) to enforce the last-admin protection clarification, then Phase 5 (T006) for audit verification, then Phase 6 (T007–T009) for documentation and deployment.

### Incremental delivery

Each phase is independently mergeable. Phase 3 alone is a valid release (US1 MVP); Phase 4 is a hardening follow-up; Phase 5 is a manual audit verification; Phase 6 is housekeeping.

---

## Task Count Summary

- **Setup**: 0
- **Foundational**: 1 (T001)
- **US1 (P1 — MVP)**: 3 (T002, T003, T004)
- **US2 (P1)**: 1 (T005)
- **US3 (P2)**: 1 (T006, manual verification)
- **Polish**: 3 (T007, T008, T009)
- **Total**: 9 tasks

## Format Validation

Every task above starts with `- [ ]`, carries a sequential `TNNN` ID, includes the correct `[P]` / `[USn]` labels per the Task Generation Rules, and names an exact file path (or is explicitly a manual/deployment task where no file applies).
