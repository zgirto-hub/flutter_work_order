# Feature Specification: Delete User

**Feature Branch**: `093-delete-user`
**Created**: 2026-04-24
**Status**: Draft
**Input**: User description: "Delete User feature for User Management screen — adds a Delete button inside the user details dialog with two-step confirmation, self-delete prevention, and a DELETE /users/{user_id} backend endpoint that removes the user from Supabase Auth and the public.users table, with an activity-log entry."

## Clarifications

### Session 2026-04-24

- Q: Should the system prevent deletion of the last remaining active admin, to avoid total admin lockout? → A: Yes — reject any deletion that would leave zero active admins; surface a clear error, and UI may hide/disable Delete in that case.
- Q: After a user is deleted, can the email address be reused immediately to create a new account? → A: Yes — email is fully released on deletion and immediately reusable via the normal Add User flow.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin permanently deletes an obsolete user (Priority: P1)

An admin opens the User Management screen, taps a user whose account should be permanently removed (former employee, test account, duplicate), opens the user details dialog, and presses **Delete User**. The admin confirms the destructive action in a second "Are you sure?" dialog, and the user is permanently removed from both the authentication system and the application user list.

**Why this priority**: This is the core capability of the feature. Without it, admins have no way to remove users permanently — only to deactivate them — leading to long-term clutter of the users table, lingering auth records, and inability to re-use emails.

**Independent Test**: An admin can delete a non-self user end-to-end from the details dialog, confirm the two-step prompt, and verify the user disappears from the list after refresh and cannot log in again.

**Acceptance Scenarios**:

1. **Given** the admin is viewing another user's details dialog, **When** the admin taps **Delete User** and confirms in the second dialog, **Then** the user is removed from the list, cannot sign in, and a success confirmation is shown.
2. **Given** the admin taps **Delete User** and then cancels the confirmation dialog, **When** the cancel action is processed, **Then** no deletion occurs, the user remains in the list, and the details dialog state is preserved.
3. **Given** deletion succeeds on the server, **When** the UI returns to the users list, **Then** the deleted user no longer appears without a manual page reload.

---

### User Story 2 - Admin is prevented from deleting their own account (Priority: P1)

An admin opens the details dialog for their own account. The Delete User button is not shown, so there is no way to accidentally lock themselves out of the system from this screen.

**Why this priority**: Self-deletion would immediately lock the acting admin out of the product and, for a sole-admin installation, could make the system unrecoverable without backend intervention. This guard is as critical as the delete capability itself.

**Independent Test**: Log in as an admin, open your own user details, and verify the Delete button is absent; forged requests targeting the acting admin's own account are rejected by the backend.

**Acceptance Scenarios**:

1. **Given** the admin opens their own user details dialog, **When** the dialog renders, **Then** the Delete User button is not visible.
2. **Given** a delete request is made for the acting admin's own account (bypassing the UI), **When** the backend processes it, **Then** the request is rejected with an error and no deletion occurs.

---

### User Story 3 - Deletion is auditable (Priority: P2)

Every successful user deletion writes an entry to the user activity log capturing who deleted whom, so administrators can audit user removals after the fact.

**Why this priority**: Deletion is irreversible and operationally sensitive. An audit trail is required to investigate disputes, support internal controls, and recover context about why a user is missing.

**Independent Test**: After a successful deletion, the activity log contains a `user_deleted` entry naming the performing admin and the removed user, viewable via existing activity-log tooling.

**Acceptance Scenarios**:

1. **Given** a successful deletion, **When** the operation completes, **Then** a `user_deleted` activity log entry exists with the acting admin's email and the deleted user's identifying information.
2. **Given** a failed deletion, **When** the operation aborts, **Then** no `user_deleted` activity entry is written.

---

### Edge Cases

- **User with no auth identity**: If the target user has no linked authentication record (legacy or partially-created row), deletion still removes the application-side user row and succeeds.
- **Auth deletion fails**: If the authentication system rejects the delete (network error, permission issue), the application user row is NOT deleted and the admin sees an error; state remains consistent.
- **Concurrent deletion**: If the user was already deleted by another admin between list load and action, the second admin sees an error and the refreshed list no longer shows the stale entry.
- **Non-admin caller**: A request from a non-admin account is rejected, matching the guard used by other admin-only user management actions.
- **Deleted user's owned content**: Content created by the deleted user (work orders, signatures, comments, etc.) is not altered; references remain as historical records.
- **Accidental tap**: The two-step confirmation prevents a single accidental tap on **Delete** from removing a user.
- **Last active admin**: If the target is the last remaining active admin, deletion is rejected with a clear error so the system cannot be left without an admin.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Admins MUST be able to permanently delete a user account from the user details dialog in the User Management screen.
- **FR-002**: The delete action MUST require a two-step confirmation: pressing Delete in the details dialog opens a dedicated confirmation dialog that the admin must explicitly approve before deletion occurs.
- **FR-003**: The system MUST hide the Delete control when the user being viewed is the currently authenticated admin, so self-deletion cannot be initiated from the UI.
- **FR-004**: The backend MUST reject any delete request whose target user is the same account as the requesting admin, even if the UI guard is bypassed.
- **FR-005**: The backend MUST restrict the delete endpoint to active admin callers, consistent with other admin-only user management endpoints.
- **FR-006**: On successful deletion, the system MUST remove the user's authentication credential so the user can no longer sign in.
- **FR-007**: On successful deletion, the system MUST remove the user's application record so the user no longer appears in user lists or lookups.
- **FR-008**: If removal of the authentication credential fails, the system MUST NOT remove the application record, and MUST surface the failure to the admin; no partial deletion may be persisted.
- **FR-009**: If the target user has no linked authentication credential, the system MUST still remove the application record and treat the deletion as successful.
- **FR-010**: Every successful deletion MUST produce an audit entry in the activity log that records the action, the acting admin, and enough identifying information about the deleted user to support later investigation.
- **FR-011**: After a successful deletion, the User Management list MUST refresh to reflect the user's absence without requiring a manual page reload.
- **FR-012**: The admin MUST receive clear success feedback after a successful deletion and a clear error message after any failure.
- **FR-013**: Canceling the confirmation dialog MUST result in no change to the user, no network call, and no log entry.
- **FR-014**: The confirmation dialog MUST clearly communicate the destructive, irreversible nature of the action and name the user who will be deleted.
- **FR-015**: The feature MUST NOT introduce alternate delete entry points (list card, swipe gesture, long-press) beyond the user details dialog.
- **FR-016**: The backend MUST reject any delete request that would result in zero active admin accounts remaining in the system, and MUST surface a clear error indicating the last-admin protection; the UI MAY additionally hide or disable the Delete control when the target is the last active admin.
- **FR-017**: After a successful deletion, the deleted user's email address MUST be immediately reusable to create a new account through the existing Add User flow; no cooldown or block is applied.

### Key Entities *(include if feature involves data)*

- **User**: The account being deleted. Has an application-side record and, usually, a linked authentication credential. After deletion, neither exists.
- **Admin (Acting User)**: The authenticated admin initiating the deletion. Must be an active admin and must not be the same account as the target.
- **Activity Log Entry**: An immutable audit record written on successful deletion, capturing the action name, the acting admin's identity, and the deleted user's identifying information.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An admin can complete a user deletion from opening the details dialog to seeing the refreshed list in under 15 seconds on a typical connection.
- **SC-002**: 100% of successful deletions produce exactly one corresponding activity log entry naming the acting admin and the deleted user.
- **SC-003**: 0% of delete attempts against the acting admin's own account succeed, whether initiated via UI or by bypassing the UI.
- **SC-004**: 0% of deletions leave the system in a partial state (authentication record removed but application record remains, or vice versa beyond the explicit "no auth credential" case).
- **SC-005**: After a successful deletion, the deleted user's sign-in attempts fail on the next try, 100% of the time.
- **SC-006**: Accidental single-tap deletion is impossible; every successful deletion involves an explicit confirmation step.
- **SC-007**: 0% of delete attempts that would leave the system with zero active admins succeed.

## Assumptions

- The existing admin authorization guard used by other user management actions (deactivate, reset password) is sufficient for the delete endpoint; no new permission model is introduced.
- Historical references to a deleted user in other records (work orders, signatures, comments, logs) are retained as-is; cascading or anonymization of historical content is out of scope.
- Deactivation remains available and is the preferred action for temporary removals; delete is reserved for permanent removal.
- The activity log is append-only and visible via existing tooling; no new log-viewing UI is introduced by this feature.
- Deletion is irreversible from within the product; recovery of a deleted user (if ever needed) requires out-of-band database/backup intervention.
- The feature targets the existing User Management screen only; no other screens expose a delete action.
