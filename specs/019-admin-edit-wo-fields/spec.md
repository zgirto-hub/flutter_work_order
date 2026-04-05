# Feature Specification: Admin Edit WO Metadata Fields

**Feature Branch**: `019-admin-edit-wo-fields`  
**Created**: 2026-04-05  
**Status**: Draft  
**Input**: User description: "Allow admin to edit WO fields: Created By, Created At, Closed At"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin Edits "Created By" on a Work Order (Priority: P1)

An admin opens an existing work order and needs to change who is listed as the creator. This may be necessary when a work order was submitted on behalf of someone else, or when the original creator was entered incorrectly. The admin selects a different user from the system's user list and saves the change.

**Why this priority**: Correcting the creator affects ownership, visibility (reporters only see their own WOs), and accountability. Incorrect creator attribution can cause a work order to be invisible to the person who should be tracking it.

**Independent Test**: Can be fully tested by opening any work order as an admin, changing the "Created By" field to another user, saving, and verifying the change persists and the work order now appears under the new creator's list.

**Acceptance Scenarios**:

1. **Given** an admin is viewing a work order edit screen, **When** they tap the "Created By" field, **Then** they see a searchable list of all active users (admins, technicians, and reporters) to select from.
2. **Given** an admin selects a new creator and saves, **When** the work order is reloaded, **Then** the "Created By" name and email reflect the newly selected user.
3. **Given** a reporter originally created a work order, **When** an admin changes "Created By" to a different user, **Then** the original reporter no longer sees that work order in their list, and the new creator does.
4. **Given** a non-admin user (technician or reporter) views the edit screen, **When** they look at the "Created By" field, **Then** it is displayed as read-only and cannot be modified.

---

### User Story 2 - Admin Edits "Created At" Date on a Work Order (Priority: P2)

An admin needs to correct the creation date of a work order. This is useful when a work order was entered late and the actual creation date differs from the system-recorded date, or when backdating is needed for record-keeping accuracy.

**Why this priority**: The creation date is important for reporting and SLA tracking but is less critical than creator ownership for day-to-day operations.

**Independent Test**: Can be fully tested by opening any work order as an admin, changing the "Created At" date/time, saving, and verifying the updated date appears everywhere the creation date is displayed.

**Acceptance Scenarios**:

1. **Given** an admin is editing a work order, **When** they tap the "Created At" field, **Then** a date-time picker appears pre-filled with the current creation date.
2. **Given** an admin selects a new date/time and saves, **When** the work order is viewed again, **Then** the creation date reflects the updated value.
3. **Given** an admin attempts to set "Created At" to a future date, **When** they try to save, **Then** the system prevents it and shows a validation message that the creation date cannot be in the future.
4. **Given** a non-admin user views the edit screen, **When** they look at the "Created At" field, **Then** it is displayed as read-only.

---

### User Story 3 - Admin Edits "Closed At" Date on a Work Order (Priority: P3)

An admin needs to correct the closure date on a work order that has been closed. This is necessary when the actual closure happened at a different time than when it was recorded in the system.

**Why this priority**: Closed date corrections are less frequent but important for accurate historical reporting and auditing.

**Independent Test**: Can be fully tested by opening a closed work order as an admin, changing the "Closed At" date/time, saving, and verifying the updated closure date persists.

**Acceptance Scenarios**:

1. **Given** a work order has status "Closed" and an admin is editing it, **When** they tap the "Closed At" field, **Then** a date-time picker appears pre-filled with the current closure date.
2. **Given** a work order is not closed (status is "Pending" or "In Progress"), **When** an admin views the edit screen, **Then** the "Closed At" field is not shown since there is no closure date to edit.
3. **Given** an admin sets a new closure date and saves, **When** the work order is viewed again, **Then** the closure date reflects the updated value.
4. **Given** an admin attempts to set "Closed At" to a date before the "Created At" date, **When** they try to save, **Then** the system prevents it and shows a validation message.
5. **Given** a non-admin user views the edit screen, **When** they look at the "Closed At" field, **Then** it is displayed as read-only.

---

### Edge Cases

- What happens when an admin changes "Created By" to a user who has been deactivated? The system should only allow selection of active users.
- What happens when "Created At" is changed to a date after the "Closed At" date on a closed work order? The system should validate that Created At is before Closed At and show an error.
- What happens if a work order is reopened after the admin edited "Closed At"? The "Closed At" field should be cleared when a work order is reopened, following existing behavior.

## Clarifications

### Session 2026-04-05

- Q: Which user types should be selectable when an admin changes "Created By"? → A: Any active user (admins, technicians, and reporters).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow admin users to change the "Created By" field on any work order by selecting from a searchable list of all active users (admins, technicians, and reporters).
- **FR-002**: System MUST update the creator user ID, creator email, and creator name together when "Created By" is changed, keeping them consistent.
- **FR-003**: System MUST allow admin users to change the "Created At" date and time on any work order.
- **FR-004**: System MUST NOT allow "Created At" to be set to a future date/time.
- **FR-005**: System MUST allow admin users to change the "Closed At" date and time on any closed work order.
- **FR-006**: System MUST only display the "Closed At" editing field when the work order has a status of "Closed".
- **FR-007**: System MUST NOT allow "Closed At" to be set to a date/time earlier than "Created At".
- **FR-008**: System MUST restrict editing of these three fields to admin users only; technicians and reporters see them as read-only.
- **FR-009**: System MUST persist all changes and reflect them immediately upon reload.
- **FR-010**: System MUST update the work order's "last modified" timestamp when any of these fields are changed.

### Key Entities

- **Work Order**: Existing entity. Affected fields: creator identity (user ID, email, name), creation timestamp, closure timestamp.
- **User**: Existing entity. Used as the source for the selectable creator list (active users only).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Admin users can update "Created By", "Created At", and "Closed At" on any applicable work order and see changes reflected immediately after saving.
- **SC-002**: Non-admin users cannot modify these three fields under any circumstances.
- **SC-003**: All date validations (no future "Created At", "Closed At" must be after "Created At") prevent invalid data 100% of the time.
- **SC-004**: Changing "Created By" correctly updates work order visibility so the new creator sees the work order in their list.

## Assumptions

- Only active users are available for selection in the "Created By" picker. Deactivated users are excluded.
- The existing work order edit screen will be extended with these fields rather than creating a new screen.
- The existing backend admin authorization pattern will be reused to protect these new edit capabilities.
- No detailed audit log is required beyond the existing "last modified" timestamp for tracking these changes.
- The "Created By" user picker follows the same UI pattern as the existing technician assignment picker.
