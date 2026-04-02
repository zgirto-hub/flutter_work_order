# Feature Specification: Edit Resolve Date

**Feature Branch**: `006-edit-resolve-date`  
**Created**: 2026-04-02  
**Status**: Draft  
**Input**: User description: "I want to add a feature to edit the resolve date."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Edit Resolve Date on a Resolved Issue (Priority: P1)

As a system administrator, I want to correct the resolve date of an already-resolved issue so that the uptime report accurately reflects the actual resolution timeline.

Currently, when an issue is marked as resolved, the system records the current server timestamp as the resolve date. If a user resolves an issue a day late (e.g., the camera was actually fixed yesterday but only marked resolved today), the uptime report will be inaccurate. This feature allows editing the resolve date after the fact.

**Why this priority**: This is the core feature being requested. Without it, uptime reports can be misleading when issues are not resolved in real-time.

**Independent Test**: Can be fully tested by resolving an issue, then editing its resolve date and verifying the uptime report reflects the corrected date.

**Acceptance Scenarios**:

1. **Given** a resolved issue exists, **When** the user opens the issue details and edits the resolve date to an earlier date, **Then** the resolve date is updated and the uptime report reflects the new date.
2. **Given** a resolved issue exists, **When** the user attempts to set the resolve date to before the issue's report date, **Then** the system rejects the change with a clear error message.
3. **Given** a resolved issue exists, **When** the user edits the resolve date to a future date beyond today, **Then** the system rejects the change with a clear error message.

---

### User Story 2 - Set a Custom Resolve Date During Resolution (Priority: P2)

As a system administrator, I want to optionally specify a custom resolve date when resolving an issue, so I can record the actual fix time rather than the current timestamp.

**Why this priority**: Enhances the resolve flow itself, preventing the need to edit after the fact. Secondary to the core edit capability.

**Independent Test**: Can be tested by resolving an issue with a custom date picker and verifying the stored resolve date matches the selected date.

**Acceptance Scenarios**:

1. **Given** an unresolved issue, **When** the user resolves it and selects a custom resolve date, **Then** the system stores that date instead of the current timestamp.
2. **Given** an unresolved issue, **When** the user resolves it without selecting a custom date, **Then** the system uses the current timestamp (existing behavior preserved).

---

### Edge Cases

- What happens when the resolve date is set to the same date as the report date? The system should allow this (issue reported and resolved on the same day).
- What happens when the resolve date is edited on an issue that was already used in a generated uptime report? The next report query will use the updated date automatically.
- What happens if the user tries to clear the resolve date entirely? This should not be allowed — once resolved, the issue must retain a resolve date.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow editing the resolve date of a resolved issue to any date between the issue's report date and today (inclusive).
- **FR-002**: System MUST reject a resolve date that is earlier than the issue's report date.
- **FR-003**: System MUST reject a resolve date that is in the future (after today).
- **FR-004**: System MUST allow specifying an optional custom resolve date when resolving an issue (defaults to current timestamp if not provided).
- **FR-005**: System MUST display the current resolve date when editing, pre-populated in the date picker.
- **FR-006**: System MUST update uptime calculations to use the edited resolve date.

### Key Entities

- **System Status Report**: Existing entity. The `resolved_at` field, currently set only by the server, will become user-editable after resolution and optionally settable during resolution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can edit the resolve date of any resolved issue within 3 taps/clicks from the issue detail view.
- **SC-002**: Uptime reports accurately reflect edited resolve dates immediately after the next query.
- **SC-003**: 100% of resolve date edits are validated (no invalid dates accepted — must be between report date and today).

## Assumptions

- The edit resolve date feature is available to all users who can currently resolve issues (no additional permission level required).
- The resolve date is stored as a date-time but the user selects a date only (time portion defaults to end-of-day or preserves existing time).
- The existing edit sheet UI pattern (modal bottom sheet) will be reused for consistency.
- FR-006 is already satisfied by the recent uptime calculation change that spreads downtime from report_date to resolved_at — no additional uptime logic changes are needed.
