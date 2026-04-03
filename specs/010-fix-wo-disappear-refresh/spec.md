# Feature Specification: Fix Work Order Disappears After Refresh

**Feature Branch**: `010-fix-wo-disappear-refresh`  
**Created**: 2026-04-03  
**Status**: Draft  
**Input**: User description: "when i add new Work order, it is inserted, then after refresh it disappears, what is the problem?"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Work Order Persists After Refresh (Priority: P1)

As a reporter, when I create a new work order and then refresh the work order list, the newly created work order must still appear in my list. Currently, the work order appears immediately after creation (added to the local list in the app) but vanishes on refresh because the backend fails to match the record back to the creating user.

**Why this priority**: This is the core bug. Users lose visibility of their own work orders after refresh, which breaks trust in the system and can lead to duplicate submissions.

**Independent Test**: Log in as a reporter, create a new work order, refresh the page, and verify the work order remains visible in the list.

**Acceptance Scenarios**:

1. **Given** a logged-in reporter, **When** they create a new work order and refresh the work order list, **Then** the newly created work order appears in their list.
2. **Given** a logged-in reporter whose email or auth identity may not perfectly resolve to their database user record, **When** they create a work order, **Then** the system reliably resolves their identity and stores the correct user reference on the work order.
3. **Given** a work order was just created by a reporter, **When** any user with appropriate permissions views the work order list, **Then** the work order appears with the correct creator information.

---

### User Story 2 - Consistent Department Filtering (Priority: P2)

As a user filtering work orders by department, the department filter should work correctly so that newly created work orders with a department assignment appear when filtering by that department.

**Why this priority**: A parameter naming mismatch between frontend and backend means department filtering silently fails, which can also contribute to work orders appearing to vanish when a department filter is active.

**Independent Test**: Create a work order assigned to a specific department, apply the department filter on the list page, and verify the work order appears under that department.

**Acceptance Scenarios**:

1. **Given** a work order assigned to department "Maintenance", **When** a user filters the list by "Maintenance", **Then** the work order appears in the filtered results.
2. **Given** a work order was just created with a department, **When** the user refreshes and applies a department filter, **Then** the work order is correctly included or excluded based on its department.

---

### Edge Cases

- What happens when a user's email does not exist in the users table at the time of work order creation?
- What happens when the user's auth ID cannot be resolved to a database user record?
- How does the system behave if both email-based and auth-ID-based user lookups fail?
- What happens if a work order is created while the user's department assignment changes concurrently?
- What happens if the data repair encounters a work order whose auth UUID cannot be matched to any existing user?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST reliably resolve the creating user's identity to their database user ID when saving a work order, regardless of whether the resolution is by email or auth ID.
- **FR-002**: System MUST NOT save a work order with an unresolved auth UUID as the creator reference. If identity resolution fails, the system must immediately reject the creation and display an error message to the user indicating the work order could not be saved.
- **FR-003**: System MUST return newly created work orders in subsequent list queries for the creating user without requiring any special action beyond a standard refresh.
- **FR-004**: The work order list filtering by department MUST use consistent parameter naming between the requesting client and the server so that the filter is applied correctly.
- **FR-005**: The creator reference stored on a work order MUST match the format used when querying work orders for a specific reporter, ensuring consistent round-trip behavior.
- **FR-006**: System MUST include a one-time data repair to fix existing work orders that were saved with unresolved auth UUIDs as the creator reference, resolving them to the correct database user IDs.

### Key Entities

- **Work Order**: A maintenance or service request. Key attributes include: id, title, description, status, department, and creator reference. The creator reference must consistently use the database user ID.
- **User**: A system user who has both a database user ID and an authentication identity. The system must use the database user ID for all ownership references on work orders.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of newly created work orders remain visible to their creator after page refresh.
- **SC-002**: Work orders created by any reporter are correctly attributed and retrievable in all subsequent list queries.
- **SC-003**: Department filtering returns accurate results that include all work orders matching the selected department.
- **SC-004**: Zero instances of work orders stored with unresolved authentication identifiers as the creator reference.

## Clarifications

### Session 2026-04-03

- Q: Should existing work orders saved with unresolved auth UUIDs be retroactively fixed? → A: Yes, include a one-time data migration to repair existing broken records.
- Q: What should the user experience when identity resolution fails during work order creation? → A: Immediately show an error message telling the user the work order could not be saved.

## Assumptions

- The existing user authentication and session management system is functioning correctly (users are properly logged in with valid credentials).
- The users table in the database contains records for all active users with both their database user ID and authentication identity properly linked.
- The existing work order creation UI and fields (title, description, department, status, etc.) do not need changes beyond the bug fix.
- The local list insertion behavior (showing the work order immediately after creation) is desirable and should be preserved alongside the backend fix.
