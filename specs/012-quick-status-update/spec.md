# Feature Specification: Quick Status Update

**Feature Branch**: `012-quick-status-update`  
**Created**: 2026-04-03  
**Status**: Draft  
**Input**: User description: "Add quick status update to work order list without opening the full edit screen."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Quick Status Advancement (Priority: P1)

A technician or admin viewing the work order list wants to advance a work order's status without navigating to the full edit screen. They tap the status badge on a card, see a minimal bottom sheet showing the next logical status, and confirm the change. The card updates in place immediately.

**Why this priority**: This is the core value proposition — reducing a 5-step navigation flow (tap card, expand, tap Edit, change dropdown, Save) to a 2-step interaction (tap badge, confirm). It covers the most common use case of moving work orders forward through the workflow.

**Independent Test**: Can be fully tested by tapping a status badge on any non-Closed work order and confirming the status change. Delivers immediate value by eliminating unnecessary navigation.

**Acceptance Scenarios**:

1. **Given** a technician is viewing the work order list with a "Pending" work order, **When** they tap the status badge on that card, **Then** a bottom sheet appears showing the current status and offering "In Progress" as the next status option.
2. **Given** a technician taps the status badge on an "In Progress" work order, **When** the bottom sheet appears, **Then** it offers "Resolved" as the next status option.
3. **Given** a technician confirms a status change in the bottom sheet, **When** the update succeeds, **Then** the card's status badge updates in place without a full list reload, and the bottom sheet closes.
4. **Given** a technician confirms a status change, **When** the update fails (network error, server error), **Then** an error message is shown and the card retains its original status.

---

### User Story 2 - Quick Close with Tech Notes (Priority: P2)

A technician or admin viewing a "Resolved" work order wants to close it quickly. They tap the status badge, see a bottom sheet with an optional tech notes field and a "Close" action. On confirm, the system records the closure with the current user's identity and optional notes.

**Why this priority**: Closing a work order has additional data requirements (tech_notes, closed_by) that must be handled correctly. This is a natural extension of the quick status flow but requires a slightly richer UI.

**Independent Test**: Can be tested by tapping the status badge on a Resolved work order, optionally entering tech notes, and confirming closure. Verifiable by checking the work order is marked Closed with correct metadata.

**Acceptance Scenarios**:

1. **Given** a technician taps the status badge on a "Resolved" work order, **When** the bottom sheet appears, **Then** it shows a "Close" action and an optional text field for tech notes.
2. **Given** a technician enters tech notes and confirms closure, **When** the close request succeeds, **Then** the card updates to "Closed" status in place, and the tech notes and closer identity are recorded.
3. **Given** a technician confirms closure without entering tech notes, **When** the close request succeeds, **Then** the work order is closed successfully with no tech notes.

---

### User Story 3 - Role-Based Access Control (Priority: P1)

A reporter viewing the work order list sees status badges as read-only indicators. They cannot tap the badge to change status, ensuring only authorized roles (technician, admin) can modify work order status.

**Why this priority**: This is a critical guardrail that must be in place from the start to prevent unauthorized status changes. Tied to P1 because it constrains the core feature.

**Independent Test**: Can be tested by logging in as a reporter and verifying that tapping a status badge does not open the status change sheet.

**Acceptance Scenarios**:

1. **Given** a reporter is viewing the work order list, **When** they tap a status badge on any work order, **Then** nothing happens — no bottom sheet appears.
2. **Given** an admin is viewing the work order list, **When** they tap a status badge, **Then** the status change bottom sheet appears (same behavior as technician).

---

### User Story 4 - Selection Mode Interaction (Priority: P2)

When the user is in selection mode (triggered by long-press), the quick status tap must be disabled to avoid conflicting interactions with the selection checkboxes.

**Why this priority**: Prevents UX conflicts between two tap-based interactions on the same card. Important for usability but secondary to the core status change flow.

**Independent Test**: Can be tested by entering selection mode via long-press and verifying that tapping a status badge does not trigger the status change sheet.

**Acceptance Scenarios**:

1. **Given** the user is in selection mode with one or more cards selected, **When** they tap a status badge on any card, **Then** no status change sheet appears.
2. **Given** the user exits selection mode, **When** they tap a status badge on a non-Closed work order, **Then** the status change sheet appears normally.

---

### Edge Cases

- What happens when the user taps the status badge on a "Closed" work order? Nothing happens — Closed is a terminal state with no further transitions.
- What happens if the work order status is changed by another user while the bottom sheet is open? The update request may fail with a conflict; an error message is shown and the user can retry.
- What happens if the network request is slow? A loading indicator is shown in the bottom sheet to prevent duplicate submissions.
- What happens if the user dismisses the bottom sheet without confirming? No changes are made; the work order retains its current status.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display a tappable status badge on each work order card for users with technician or admin roles.
- **FR-002**: System MUST show the status badge as read-only (non-tappable) for users with the reporter role.
- **FR-003**: System MUST present a bottom sheet when a tappable status badge is tapped, showing the current status and the next logical status option(s).
- **FR-004**: System MUST follow the linear status progression: Pending -> In Progress -> Resolved -> Closed.
- **FR-005**: System MUST NOT offer any status transition for work orders already in "Closed" status.
- **FR-006**: System MUST include an optional tech notes text field in the bottom sheet when transitioning to "Closed" status.
- **FR-007**: System MUST record the current user's identity as the closer when a work order is closed via the quick flow.
- **FR-008**: System MUST update the work order card in place after a successful status change without performing a full list reload.
- **FR-009**: System MUST disable the status badge tap interaction while the list is in selection mode.
- **FR-010**: System MUST show an error message if the status update or close request fails, retaining the original status on the card.
- **FR-011**: System MUST prevent duplicate submissions by disabling the confirm action while a request is in progress.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can change a work order status in 2 taps or fewer (tap badge, confirm), compared to the current 5-step flow.
- **SC-002**: Status changes made via quick update are reflected on the card within 2 seconds of confirmation.
- **SC-003**: 100% of quick status changes by reporter-role users are prevented (badge is non-interactive).
- **SC-004**: Work orders closed via the quick flow correctly record closer identity and optional tech notes in all cases.
- **SC-005**: No accidental status changes occur during selection mode interactions.

## Assumptions

- The existing status progression (Pending -> In Progress -> Resolved -> Closed) is strictly linear — no backward transitions or status skipping is needed for quick update.
- The current user's identity for the close flow can be derived from the authenticated session (no additional user input required for "closed_by").
- The existing update and close endpoints handle all validation server-side; the client only needs to call the appropriate method.
- The quick status flow supplements (does not replace) the full edit screen — users can still change status via the full edit flow.
- Only forward status transitions are offered in the quick flow; arbitrary status changes still require the full edit screen.
