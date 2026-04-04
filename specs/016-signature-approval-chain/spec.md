# Feature Specification: Supervisor & Superintendent Signature Approval Chain

**Feature Branch**: `016-signature-approval-chain`  
**Created**: 2026-04-04  
**Status**: Draft  
**Input**: User description: "Supervisor and Superintendent roles for WO signature approval chain"

## Clarifications

### Session 2026-04-04

- Q: When a reporter or admin creates a WO, how is the single technician assigned? → A: WO is created unassigned; an admin must later assign a technician before any work can begin.
- Q: How should existing multi-technician WOs be migrated to single-technician? → A: Automatically keep the first (oldest-assigned) technician, drop extras, and log which WOs were affected.
- Q: How should a skipped approval level appear in the PDF signature section? → A: Omit the skipped level's signature block entirely; PDF shows only levels that actually participated.
- Q: How should concurrent approval attempts by multiple supervisors be handled? → A: First approval wins; second attempt receives an error "Already approved at this level."
- Q: Can admin re-assign a technician on an in-progress WO? → A: Yes, at any time; re-assignment resets the entire signature chain (clears all signatures, status back to "unsigned").
- Q: Should there be a dedicated approval queue screen for supervisors/superintendents? → A: Yes, add a dedicated "Pending Approvals" screen showing only WOs awaiting the current user's approval, and also keep badges on the WO list.
- Q: Where should the Pending Approvals screen be accessible from? → A: Dedicated item in the main navigation/sidebar, visible only to users with an approval role.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Technician Signs Work Order to Start Approval Chain (Priority: P1)

A technician who has completed work on a work order signs it to initiate the approval chain. The work order's signature status advances from "unsigned" to "tech_signed," and the appropriate next-level approver (supervisor for the WO's department) is automatically notified that their review is needed.

**Why this priority**: The technician signature is the entry point for the entire approval chain. Without this, no downstream approvals can occur. This is the foundational interaction that all other stories depend on.

**Independent Test**: Can be fully tested by having a technician open a work order assigned to them, apply their signature, and verifying the WO status changes to "tech_signed" and a notification is sent to the department's supervisor.

**Acceptance Scenarios**:

1. **Given** a work order in "unsigned" status assigned to a technician, **When** the technician submits their signature, **Then** the work order's signature status updates to "tech_signed" and all supervisors for the WO's department receive a notification.
2. **Given** a work order in "unsigned" status in a department with no supervisor configured, **When** the technician submits their signature, **Then** the system skips the supervisor step, notifies superintendents instead, and logs a warning that the supervisor level was skipped.
3. **Given** a work order in "rejected" status, **When** the technician re-signs, **Then** all previous non-rejected approval signatures are cleared, the status resets to "tech_signed," and the chain restarts from the supervisor step.

---

### User Story 2 - Supervisor Approves or Rejects a Work Order Signature (Priority: P1)

A supervisor reviews work orders that have been signed by technicians in their assigned departments. They can approve (advancing the chain to superintendent review) or reject (sending it back to the technician with a reason). Supervisors only see and can act on work orders within their department scope.

**Why this priority**: The supervisor approval is the first gate in the chain and validates that department-level review is enforced. This is co-equal with P1 because the chain cannot progress without it.

**Independent Test**: Can be tested by having a supervisor view their pending approvals, approve one WO (verify status advances to "supervisor_approved" and superintendent is notified), and reject another (verify technician is notified with the rejection reason and status becomes "rejected").

**Acceptance Scenarios**:

1. **Given** a work order with status "tech_signed" in the supervisor's assigned department, **When** the supervisor approves, **Then** the status advances to "supervisor_approved" and all superintendents are notified.
2. **Given** a work order with status "tech_signed" in the supervisor's assigned department, **When** the supervisor rejects with a reason, **Then** the status changes to "rejected," the rejection reason is recorded, the technician and WO creator are notified, and the rejected signature record is preserved for audit.
3. **Given** a work order in a department NOT assigned to the supervisor, **When** the supervisor attempts to approve, **Then** the system denies access and the supervisor cannot see or act on that work order's signatures.
4. **Given** a work order with status "tech_signed" in a department with no superintendent configured, **When** the supervisor approves, **Then** the system skips the superintendent step, marks the WO as "completed," notifies the technician and creator, and logs a warning.

---

### User Story 3 - Superintendent Approves or Rejects a Work Order Signature (Priority: P1)

A superintendent reviews work orders that have passed supervisor approval across all departments. They provide the final operational sign-off. Upon approval, the signature chain is complete, the WO is marked "completed," and PDF export becomes available.

**Why this priority**: The superintendent is the final approval gate. Without this step, the chain cannot reach completion and PDF export remains locked.

**Independent Test**: Can be tested by having a superintendent view WOs with "supervisor_approved" status, approve one (verify status becomes "completed" and PDF export unlocks), and reject another (verify chain restarts from technician).

**Acceptance Scenarios**:

1. **Given** a work order with status "supervisor_approved," **When** the superintendent approves, **Then** the status changes to "completed," the technician and WO creator are notified, and the PDF export button becomes available.
2. **Given** a work order with status "supervisor_approved," **When** the superintendent rejects with a reason, **Then** the status changes to "rejected," the rejection reason is recorded, the technician is notified to re-sign, and the rejected record is preserved for audit.
3. **Given** a completed work order (status "completed"), **When** any user with view access requests PDF export, **Then** the system generates the PDF with signature blocks only for approval levels that participated (skipped levels are omitted), each showing signer name, date, and signature image.

---

### User Story 4 - Admin Manages Approval Roles for Users (Priority: P2)

An administrator assigns or removes supervisor and superintendent approval roles for users through the existing user management screen. When assigning a supervisor role, the admin selects which departments that supervisor covers. Superintendents have no department restriction. The admin cannot assign an approval role to themselves.

**Why this priority**: Role assignment is essential for the chain to function, but it is a configuration task that only needs to happen once per user. The chain logic (P1) can be tested with pre-configured users.

**Independent Test**: Can be tested by an admin opening user management, assigning a user as supervisor with specific departments, verifying the role is saved, then changing them to superintendent and verifying department scope is removed.

**Acceptance Scenarios**:

1. **Given** an admin on the user management screen viewing a user, **When** the admin selects "Supervisor" as the approval role and chooses departments, **Then** the user's approval level is set to 1, their department assignments are saved, and they begin receiving approval notifications for those departments.
2. **Given** an admin on the user management screen, **When** the admin selects "Superintendent" for a user, **Then** the user's approval level is set to 2 with no department restriction, and they begin receiving notifications for all supervisor-approved WOs.
3. **Given** an admin on the user management screen, **When** the admin selects "None" for a user who was previously a supervisor, **Then** the approval level is cleared, department assignments for approval purposes are removed, and they no longer receive approval notifications.
4. **Given** an admin viewing their own user record, **When** they attempt to assign an approval role to themselves, **Then** the system prevents it.

---

### User Story 5 - Approval Status Visibility on Work Order List (Priority: P2)

Supervisors and superintendents see contextual signature badges on work order cards indicating which WOs need their attention. Supervisors see badges on WOs in their departments awaiting supervisor approval. Superintendents see badges on WOs awaiting superintendent approval. Admins do not see signature action badges.

**Why this priority**: Improves discoverability and workflow efficiency but the core approval actions function without it.

**Independent Test**: Can be tested by logging in as a supervisor and verifying amber badges appear only on WOs in their departments with "tech_signed" status, then logging in as superintendent and verifying badges appear on "supervisor_approved" WOs.

**Acceptance Scenarios**:

1. **Given** a supervisor viewing the work order list, **When** WOs in their department have status "tech_signed," **Then** those WOs display an amber "Pending Approval" badge.
2. **Given** a superintendent viewing the work order list, **When** WOs exist with status "supervisor_approved," **Then** those WOs display an amber "Pending Approval" badge.
3. **Given** an admin viewing the work order list, **Then** no signature-related action badges are displayed (admin sees WOs but no approval indicators).
4. **Given** any user viewing a work order with status "completed," **Then** a green "Completed" badge is displayed on the signature indicator.

---

### User Story 6 - Admin Excluded from Approval Chain (Priority: P2)

Administrators have full read-only visibility into all signature records for audit purposes but are explicitly blocked from approving or rejecting any signature. This enforces the separation between system administration and operational approval authority.

**Why this priority**: Security and role separation enforcement is critical but builds on the existing chain (P1). The chain must exist before exclusion enforcement matters.

**Independent Test**: Can be tested by logging in as an admin, viewing a WO's signature section (verify all steps are visible read-only), and attempting to call the approve/reject action (verify a 403 error is returned).

**Acceptance Scenarios**:

1. **Given** an admin viewing a work order's signature section, **When** the WO is at any approval stage, **Then** the admin sees all signature steps and their statuses but no approve/reject action buttons are displayed.
2. **Given** an admin attempting to approve or reject a signature via direct request, **Then** the system returns a 403 "Admin cannot approve signatures" error.
3. **Given** an admin viewing the signature audit trail, **Then** the admin can see all current and historical (including rejected) signature records across all departments.

---

### User Story 7 - Step Progress Indicator on Work Order Detail (Priority: P3)

The work order detail screen displays a visual step progress indicator showing the current state of the approval chain: Technician, Supervisor, Superintendent. Each step shows the signer's name, date, signature image, and status. The indicator is rendered from an ordered list so that adding future approval levels requires no UI restructuring.

**Why this priority**: Visual improvement that enhances user understanding but the approval workflow functions without it.

**Independent Test**: Can be tested by viewing a WO at each chain stage and verifying the correct steps are marked complete, pending, or rejected with appropriate details.

**Acceptance Scenarios**:

1. **Given** a work order with status "supervisor_approved," **When** a user views the signature section, **Then** the progress indicator shows Technician as complete (with name, date, image), Supervisor as complete, and Superintendent as pending ("Awaiting Superintendent").
2. **Given** a work order with a rejected signature, **When** a user views the signature section, **Then** the rejected step displays a red badge with the rejection reason.
3. **Given** a user whose approval level matches the next required step for the WO's department, **When** they view the signature section, **Then** approve and reject action buttons are displayed for their step only.

---

### User Story 8 - Dedicated Pending Approvals Screen (Priority: P2)

Supervisors and superintendents have access to a dedicated "Pending Approvals" screen that shows only work orders awaiting their specific approval action. This provides a focused approval workflow separate from the general work order list. The screen is filtered automatically: supervisors see only WOs in their departments with status "tech_signed," superintendents see WOs with status "supervisor_approved." Future approval levels (e.g., Manager) will automatically appear in this screen based on their approval level. Admins, reporters, and technicians without approval roles do not see this screen.

**Why this priority**: Provides a streamlined approval workflow that reduces the cognitive load of scanning the full WO list. Important for productivity but the core approval actions work without it (via badges on the WO list).

**Independent Test**: Can be tested by logging in as a supervisor, navigating to the Pending Approvals screen, and verifying only WOs in their departments with "tech_signed" status are shown. Then logging in as a superintendent and verifying only "supervisor_approved" WOs appear. Verify a user with no approval role cannot access the screen.

**Acceptance Scenarios**:

1. **Given** a supervisor navigates to the Pending Approvals screen, **When** WOs exist with status "tech_signed" in their assigned departments, **Then** only those WOs are listed, each with WO details and an approve/reject action.
2. **Given** a superintendent navigates to the Pending Approvals screen, **When** WOs exist with status "supervisor_approved," **Then** only those WOs are listed with approve/reject actions.
3. **Given** a user with no approval role (reporter, technician without approval flag, or admin), **When** they attempt to access the Pending Approvals screen, **Then** the screen is not visible in navigation and direct access is denied.
4. **Given** an approver on the Pending Approvals screen approves or rejects a WO, **Then** the WO is removed from the list and the approver sees the updated queue without navigating away.

---

### Edge Cases

- **No supervisor for department**: When a technician signs a WO in a department with no configured supervisor, the supervisor step is skipped, the superintendent is notified directly, and a warning is logged in the activity log.
- **No superintendent exists**: When a supervisor approves and no superintendent is configured, the superintendent step is skipped, the WO is marked completed, and a warning is logged.
- **Both supervisor and superintendent missing**: The WO cannot complete the signature chain. A warning banner is displayed on the WO: "No approvers configured -- contact admin." The system does not auto-complete.
- **Supervisor deactivated mid-chain**: The system looks for the next available supervisor in the department. If none exist, it escalates to the superintendent. If no superintendent exists either, a warning banner is shown.
- **User promoted to superintendent while supervisor approval pending**: The promoted user can approve at the superintendent level (level 2) but cannot approve at the supervisor level (level 1). A different supervisor must handle level 1.
- **Technician re-signs after rejection**: All previous approval signatures (except those with "rejected" status) are cleared, the status resets to "tech_signed," and level-1 approvers are re-notified. Rejected records remain for audit.
- **Self-approval prevention**: A user who is both a technician on a WO and a supervisor for that department cannot approve their own technician signature at the supervisor level.
- **Unassigned WO**: When a reporter or admin creates a WO and no technician has been assigned yet, the signature section displays "No technician assigned -- contact admin" and no signature actions are available.
- **Concurrent approval**: If multiple supervisors (or superintendents) for the same WO attempt to approve simultaneously, the first approval wins and the chain advances; subsequent attempts receive an error "Already approved at this level" and must refresh to see the updated status.
- **Technician re-assignment mid-chain**: Admin re-assigns a different technician while the chain is in progress. All non-rejected signatures are cleared, status resets to "unsigned," and the new technician must sign to restart the chain. Previous signatures are preserved with "rejected" status for audit.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST enforce an ordered approval chain: Technician sign -> Supervisor approve -> Superintendent approve -> Completed.
- **FR-002**: System MUST track approval chain progress via a single status field on the work order with values: "unsigned," "tech_signed," "supervisor_approved," "superintendent_approved," "completed," "rejected."
- **FR-003**: System MUST support approval roles as flags on user records (supervisor, superintendent) with a numeric approval level (1 = Supervisor, 2 = Superintendent) that drives chain order.
- **FR-004**: Supervisor approval scope MUST be limited to work orders in departments assigned to that supervisor via the existing department assignment mechanism.
- **FR-005**: Superintendent approval scope MUST cover all departments with no filtering.
- **FR-006**: System MUST return HTTP 403 when an admin user attempts to approve or reject any signature, with message "Admin cannot approve signatures."
- **FR-007**: Admin users MUST have read-only access to all signature records across all departments for audit purposes.
- **FR-008**: System MUST allow only admin users to assign or remove approval roles (supervisor/superintendent) for other users.
- **FR-009**: Admin users MUST NOT be able to assign an approval role to themselves.
- **FR-010**: When a signature is rejected at any level, the system MUST notify the assigned technician and the WO creator, store the rejection reason, and set the WO status to "rejected."
- **FR-011**: When a technician re-signs after rejection, the system MUST clear all previous non-rejected approval signatures, reset the status to "tech_signed," and restart the chain from the supervisor step.
- **FR-012**: Rejected signature records MUST be preserved in the database for audit (marked as "rejected," never deleted).
- **FR-013**: When no approvers exist at a given level, the system MUST skip that level, advance to the next, and log a warning in the activity log.
- **FR-014**: When no approvers exist at any remaining level in the chain, the system MUST NOT auto-complete the WO; instead it MUST display a warning to the user indicating no approvers are configured.
- **FR-015**: PDF export MUST be blocked until the work order's signature status is "completed."
- **FR-016**: The PDF export MUST include signature blocks only for approval levels that actually participated in the chain (skipped levels are omitted), showing signer name, date, and signature image for each.
- **FR-017**: All approval chain state transitions MUST be logged in the activity log with category, action, and target details.
- **FR-018**: Notifications MUST be routed to the correct approvers at each chain step: supervisors for the WO's department after tech signs, superintendents after supervisor approves.
- **FR-019**: Admin users MUST NOT receive notifications about signature chain events.
- **FR-020**: The approval chain design MUST be extensible so that adding a future approval level (e.g., Manager at level 3) requires only: adding a status value, adding level-specific resolver cases, and adding notification routing -- with no restructuring of existing chain logic or UI components.
- **FR-021**: The work order list MUST display contextual signature badges: amber for pending approval (visible only to the role whose action is needed), green for completed.
- **FR-022**: Supervisors MUST only see pending-approval badges for WOs in their assigned departments.
- **FR-023**: The signature section on the work order detail screen MUST display a step progress indicator rendered from an ordered list of approval levels, showing each step's status, signer info, and action buttons only for the current user's matching approval level.
- **FR-024**: Each work order MUST be assigned to exactly one technician (not multiple). The existing multi-technician assignment UI (checkboxes) MUST be replaced with a single-technician selector.
- **FR-025**: When a technician creates a work order, the system MUST auto-assign that technician as the sole assignee.
- **FR-026**: When a reporter or admin creates a work order, the WO MUST be created in an unassigned state. An admin MUST assign exactly one technician before the WO can proceed to signature.
- **FR-027**: The approval chain (technician signing) MUST be blocked until a technician is assigned to the WO. The system MUST display a message indicating assignment is required.
- **FR-028**: During migration from multi-technician to single-technician assignment, the system MUST automatically keep the first (oldest-assigned) technician for each WO, remove extra assignments, and log all affected WOs for audit review.
- **FR-029**: When multiple approvers at the same level attempt to approve a WO concurrently, the system MUST accept only the first approval, advance the chain, and return a conflict error to subsequent attempts indicating the level has already been approved.
- **FR-030**: Admin MUST be able to re-assign a different technician to a WO at any time. When re-assignment occurs, the system MUST clear all non-rejected signatures and reset the signature status to "unsigned," restarting the chain from scratch.
- **FR-031**: The system MUST provide a dedicated "Pending Approvals" screen accessible only to users with an approval role (supervisor or superintendent). The screen MUST show only WOs awaiting the current user's specific approval level, filtered by department scope for supervisors.
- **FR-032**: The Pending Approvals screen MUST update dynamically when a WO is approved or rejected, removing it from the queue without requiring a page refresh or navigation.
- **FR-033**: The Pending Approvals screen MUST NOT be visible in navigation or accessible to users without an approval role (reporters, technicians without approval flags, admins).
- **FR-034**: The Pending Approvals screen MUST be accessible via a dedicated item in the main navigation sidebar (e.g., "Approvals"), visible only to users with an approval role.

### Key Entities

- **Approval Role**: A flag on a user indicating their position in the approval hierarchy (supervisor at level 1 or superintendent at level 2), with optional department scope for supervisors.
- **Signature Status**: A single field on a work order tracking the current position in the approval chain (unsigned, tech_signed, supervisor_approved, superintendent_approved, completed, rejected).
- **Work Order Signature**: A record capturing who signed/approved/rejected, their role, the signature image path, status, rejection reason (if any), and timestamp. Rejected records are preserved alongside active records.
- **Department Assignment (for Supervisors)**: The many-to-many relationship between a supervisor user and the departments they are authorized to approve work orders for.
- **Technician Assignment (on Work Order)**: A single-technician relationship on each work order. Replaces the previous multi-technician assignment. Auto-populated when a technician creates the WO; must be manually assigned by admin for reporter/admin-created WOs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of approval/reject attempts by admin users are blocked with a 403 response -- zero admin approvals exist in the signature records.
- **SC-002**: Supervisors can only view and act on work orders in their assigned departments -- no cross-department approvals are possible.
- **SC-003**: The full approval chain (technician sign -> supervisor approve -> superintendent approve) completes in the correct order for every work order, with no steps executed out of sequence.
- **SC-004**: When an approver level has no configured users, the system skips that level and logs a warning within the same transaction -- no manual intervention required.
- **SC-005**: After any rejection, the technician can re-sign and the chain restarts cleanly from step 1 with all previous non-rejected signatures cleared.
- **SC-006**: All rejected signature records remain accessible in the audit trail indefinitely -- zero rejected records are deleted.
- **SC-007**: PDF export is available only for work orders with "completed" signature status -- attempts to export before completion are blocked.
- **SC-008**: Adding a future Manager approval level (level 3) requires changes in 5 or fewer discrete locations with no restructuring of existing chain logic or UI.
- **SC-009**: Every chain state transition (sign, approve, reject, skip) is recorded in the activity log with sufficient detail to reconstruct the approval history.
- **SC-010**: Notifications reach the correct approvers within the existing notification delivery window at each chain step -- supervisors are notified after tech signs, superintendents after supervisor approves.

## Assumptions

- Existing signature workflow (spec 014) with `work_order_signatures` table is deployed and functional.
- Existing department assignment mechanism (`technician_departments` table) is in place and will be reused for supervisor department scoping.
- Existing notification infrastructure (OneSignal + in-app notifications) supports targeting users by role/department criteria.
- Existing activity logging (`user_activity_log`) is in place and supports new category/action entries.
- The `user_type` field on users (reporter, technician, admin) will NOT be changed; approval roles are additive flags alongside the existing user type.
- A user can hold both a `user_type` (e.g., technician) and an approval role (e.g., supervisor) simultaneously.
- Self-approval is not permitted: a technician who is also a supervisor for the same department cannot approve their own signature.
- The existing admin user management screen will be extended (not replaced) to include approval role assignment.
- PDF export (spec 015) is deployed and will be extended to enforce signature status checks and include all three signature blocks.
- Existing work orders with multiple technicians will be migrated to single-technician by retaining the oldest assignment; no manual admin intervention is required for migration.
