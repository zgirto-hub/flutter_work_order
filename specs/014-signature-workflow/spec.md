# Feature Specification: Signature Workflow for Work Orders

**Feature Branch**: `014-signature-workflow`  
**Created**: 2026-04-03  
**Status**: Draft  
**Input**: User description: "Signature workflow for civil aviation work order system — saved signatures in settings, technician/admin dual-signing on closed work orders, file-based storage, bulk status fetching, authorization, and activity logging."

## Clarifications

### Session 2026-04-03

- Q: Should existing base64 signature data be migrated to files as part of this feature? → A: Out of scope — only new signatures use the file-based pattern; old data is untouched.
- Q: What status should the admin's countersignature record have? → A: Auto-approved — the admin signature record is created with status "approved" immediately (no review needed).
- Q: Should there be a maximum file size for uploaded signature images? → A: No limit — accept any file size.
- Q: How should signature status be displayed on each closed work order in the list? → A: Small icon or badge (e.g., pen icon with color indicating state: unsigned, pending review, fully signed).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Technician Signs a Closed Work Order (Priority: P1)

A technician opens a work order that has been moved to "Closed" status. If the technician has a previously saved signature, the system shows a preview with an option to use it directly or draw a new one. If no saved signature exists, a drawing canvas appears. After signing, the signature is submitted and the work order moves into a "pending admin review" state.

**Why this priority**: This is the core signing action — without it, no signature workflow exists. Every other story depends on a technician being able to sign.

**Independent Test**: Can be fully tested by closing a work order, opening it as the assigned technician, drawing/selecting a signature, and submitting. The signature record is created and visible.

**Acceptance Scenarios**:

1. **Given** a closed work order assigned to a technician who has no saved signature, **When** the technician opens the work order, **Then** a signature drawing canvas is displayed.
2. **Given** a closed work order assigned to a technician who has a saved signature, **When** the technician opens the work order, **Then** the saved signature preview is shown with a "Use Saved Signature" button and a "Draw New Instead" option.
3. **Given** a technician has drawn or selected a signature, **When** they submit the signature, **Then** the signature is saved as a file (not base64 in the database) and a signature record is created with status "pending".
4. **Given** a technician who is NOT assigned to a work order, **When** they attempt to submit a signature, **Then** the system rejects the submission with an authorization error.

---

### User Story 2 - Admin Reviews, Approves, and Countersigns (Priority: P1)

An admin opens a closed work order that has a pending technician signature. The admin sees the technician's signature, and can either approve + countersign (using their saved signature or drawing a new one) or reject with a reason. On approval, both signatures are recorded. On rejection, the technician is notified and can re-sign.

**Why this priority**: The dual-signature approval is the second half of the core workflow. Without admin review, technician signatures have no verification.

**Independent Test**: Can be tested by having a technician sign a work order, then logging in as admin, reviewing, approving with a countersignature, and verifying both signature records exist.

**Acceptance Scenarios**:

1. **Given** a closed work order with a pending technician signature, **When** an admin opens the work order details, **Then** the technician's signature is displayed for review.
2. **Given** an admin reviewing a technician signature, **When** the admin approves and provides their own signature, **Then** both signatures are stored as files, the technician signature status changes to "approved", and the admin's countersignature record is created with status "approved" immediately (no further review needed).
3. **Given** an admin reviewing a technician signature, **When** the admin rejects with a reason, **Then** the technician signature status changes to "rejected" with the reason recorded, and the technician can re-sign.
4. **Given** an admin who has a saved signature, **When** they approve a work order, **Then** they see their saved signature with an option to use it or draw a new one (same UX as technician).
5. **Given** an admin approving a signature, **When** the approval is processed, **Then** the admin's countersignature file is captured BEFORE the approval is committed (fixing the existing sequencing bug).

---

### User Story 3 - Saved Signature Management in Settings (Priority: P2)

Technicians and admins can manage their saved signature from the Settings screen. They can draw a new signature on a canvas, upload an image file, preview their current saved signature, or remove it. The saved signature is stored as a file and reused across work orders.

**Why this priority**: While not strictly required (users can always draw on the spot), pre-saving a signature significantly streamlines the signing experience and is the expected workflow for repeat users.

**Independent Test**: Can be tested entirely in the Settings screen — draw a signature, verify the preview appears, navigate away and back, verify it persists, then remove it and verify it is gone.

**Acceptance Scenarios**:

1. **Given** a technician or admin on the Settings screen with no saved signature, **When** they view the "My Signature" section, **Then** they see options to "Draw Signature" or "Upload Image" but no preview.
2. **Given** a user drawing a signature on the canvas in Settings, **When** they save it, **Then** a signature file is created and a preview is displayed.
3. **Given** a user uploading an image file (PNG or JPG), **When** they save it, **Then** the image is stored as the saved signature and a preview is displayed.
4. **Given** a user with an existing saved signature, **When** they draw or upload a new one, **Then** the old file is replaced and the preview updates.
5. **Given** a user with an existing saved signature, **When** they click "Remove Signature" and confirm, **Then** the signature file and reference are deleted and the preview disappears.
6. **Given** a reporter (non-technician, non-admin) on the Settings screen, **When** they view Settings, **Then** no "My Signature" section is displayed.

---

### User Story 4 - Bulk Signature Status on Work Order List (Priority: P2)

When viewing the work order list, the system fetches signature status for all visible work orders in a single request rather than one request per work order. This ensures the list loads efficiently regardless of the number of work orders displayed.

**Why this priority**: This fixes a known performance problem (N+1 queries). While the feature works without this fix, it degrades noticeably with larger work order lists.

**Independent Test**: Can be tested by loading the work order list with multiple closed work orders and verifying only one network request is made to fetch signature statuses (not one per work order).

**Acceptance Scenarios**:

1. **Given** a work order list with 50 closed work orders, **When** the list loads, **Then** signature status for all work orders is retrieved in a single request and each closed work order displays a small icon/badge indicating its signature state (unsigned, pending review, or fully signed).
2. **Given** a work order list with no closed work orders, **When** the list loads, **Then** no signature status request is made and no signature badges are shown.

---

### User Story 5 - Activity Logging for All Signature Events (Priority: P3)

Every signature action — submission, approval, rejection, and saved signature update — is recorded in the activity log with appropriate category, action, and target information.

**Why this priority**: Activity logging is important for audit trails in aviation maintenance but does not affect core user-facing functionality.

**Independent Test**: Can be tested by performing each signature action and verifying corresponding log entries exist in the activity log.

**Acceptance Scenarios**:

1. **Given** a technician submits a signature on a work order, **When** the action completes, **Then** an activity log entry is created with action "signature_submitted" and the work order as target.
2. **Given** an admin approves a signature, **When** the action completes, **Then** an activity log entry is created with action "signature_approved".
3. **Given** an admin rejects a signature, **When** the action completes, **Then** an activity log entry is created with action "signature_rejected".
4. **Given** a user updates their saved signature in Settings, **When** the action completes, **Then** an activity log entry is created with action "saved_signature_updated" and the user as target.

---

### User Story 6 - Technician Re-signs After Rejection (Priority: P2)

When an admin rejects a technician's signature, the technician sees the rejection reason and can submit a new signature. The new signature replaces the rejected one and goes through the approval cycle again.

**Why this priority**: Without re-signing, a rejected signature would be a dead end requiring workarounds.

**Independent Test**: Can be tested by having an admin reject a signature with a reason, then logging in as the technician, seeing the rejection reason, drawing a new signature, and submitting it.

**Acceptance Scenarios**:

1. **Given** a work order with a rejected technician signature, **When** the assigned technician opens the work order, **Then** they see the rejection reason and a prompt to re-sign.
2. **Given** a technician re-signing after rejection, **When** they submit the new signature, **Then** a new signature record is created with status "pending" and the previous rejected record is preserved for audit.

---

### Edge Cases

- What happens when a technician tries to sign a work order that is not in "Closed" status? System prevents signing — signatures are only available for closed work orders.
- What happens if the saved signature file is missing from the filesystem but the path still exists in the user record? System shows a "signature not found" message and prompts the user to draw or upload a new one.
- What happens if an admin tries to approve a signature that has already been approved? System prevents duplicate approval — the approve action is only available for pending signatures.
- What happens if two admins try to approve/reject the same signature simultaneously? The first action succeeds; the second receives a conflict error indicating the signature status has already changed.
- What happens when a work order is deleted while signatures exist? Signature records are cascade-deleted with the work order.
- What happens if the uploaded image is not a valid PNG/JPG? The system validates the file type and rejects unsupported formats with a user-friendly error message.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow technicians and admins to draw a signature on a canvas in Settings and save it as their reusable signature.
- **FR-002**: System MUST allow technicians and admins to upload a PNG or JPG image as their saved signature in Settings.
- **FR-003**: System MUST display a preview of the user's current saved signature in Settings if one exists.
- **FR-004**: System MUST allow users to remove their saved signature from Settings with a confirmation prompt.
- **FR-005**: System MUST store all signature images as files on the filesystem, not as base64 data in the database.
- **FR-006**: System MUST show the saved signature preview with a "Use Saved Signature" option when a technician with a saved signature opens a closed work order to sign.
- **FR-007**: System MUST provide a "Draw New Instead" option alongside the saved signature preview, allowing the technician to draw a fresh signature.
- **FR-008**: System MUST present a signature drawing canvas when a technician without a saved signature opens a closed work order to sign.
- **FR-009**: System MUST enforce that only the assigned technician or an admin can submit a signature for a work order.
- **FR-010**: System MUST allow admins to view the technician's submitted signature and approve with a countersignature or reject with a reason.
- **FR-011**: System MUST capture the admin's countersignature file BEFORE committing the approval (not after).
- **FR-012**: System MUST allow a technician to re-sign a work order after their signature has been rejected, showing the rejection reason.
- **FR-013**: System MUST enforce that only admins can approve or reject signatures.
- **FR-014**: System MUST fetch signature statuses for all work orders in the list using a single bulk request rather than individual requests per work order.
- **FR-018**: System MUST display a small icon or badge on each closed work order in the list indicating its signature state (unsigned, pending review, fully signed).
- **FR-015**: System MUST log all signature events (submission, approval, rejection, saved signature update) to the activity log.
- **FR-016**: System MUST restrict the "My Signature" section in Settings to technician and admin roles only — reporters do not see it.
- **FR-017**: System MUST preserve rejected signature records for audit purposes when a technician re-signs.

### Key Entities

- **User Signature (Saved)**: A pre-registered signature belonging to a technician or admin, stored as a file. One per user. Used as a convenience option when signing work orders.
- **Work Order Signature**: A signature submitted on a specific closed work order by either a technician or admin. Tracks the signer, their role, the signature file, approval status, and optional rejection reason. Two signatures per fully-signed work order (technician + admin). The admin's countersignature is auto-approved on creation; only technician signatures go through the pending/approved/rejected lifecycle.
- **Signature Status**: The lifecycle state of a work order signature — pending (submitted, awaiting admin review), approved (admin accepted and countersigned), or rejected (admin declined with reason).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Technicians can complete the work order signing process (open WO, select/draw signature, submit) in under 30 seconds when using a saved signature.
- **SC-002**: Admins can complete the review-and-countersign process (view technician signature, approve, countersign) in under 1 minute.
- **SC-003**: The work order list loads signature statuses for all visible work orders in a single network round-trip, regardless of list size.
- **SC-004**: 100% of signature submissions by unauthorized users (not assigned to the work order) are rejected by the system.
- **SC-005**: Every signature action (submit, approve, reject, saved signature update) produces a corresponding activity log entry with no gaps.
- **SC-006**: No signature image data is stored directly in the database — all signatures are stored as files and referenced by path.
- **SC-007**: The rejection-and-re-sign cycle can be completed (admin rejects, technician sees reason, re-signs) without requiring any workaround or manual intervention.

## Assumptions

- Users access the system via modern web browsers or mobile devices that support canvas-based drawing for signatures.
- The existing file upload infrastructure (multipart/form-data, UUID filenames, uploaded_files directory) is stable and will be reused for signature storage.
- The existing activity log system is available and follows the established pattern for new event types.
- A work order has at most one active (non-rejected) technician signature and one admin countersignature at any time.
- The assignment relationship between technicians and work orders already exists and can be queried to enforce authorization.
- Saved user signatures use a deterministic filename pattern so that re-uploading overwrites the previous file rather than accumulating orphaned files.
- Notification of rejection to the technician occurs within the application (e.g., visual indicator when opening the work order) — no external notification channels (email, push) are required for this feature.
- Migration of existing base64 signature data to the new file-based storage is out of scope for this feature. Only new signatures will use the file pattern.
