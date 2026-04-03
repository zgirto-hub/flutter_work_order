# Research: Quick Status Update

**Feature**: 012-quick-status-update  
**Date**: 2026-04-03

## Research Summary

No NEEDS CLARIFICATION items existed in the technical context. Research focused on verifying existing infrastructure supports the feature without new backend work.

### R1: Existing Status Update Endpoints

**Decision**: Reuse existing PUT /work-orders/{id} for status changes and PATCH /work-orders/{id}/close for closure.

**Rationale**: Both endpoints already exist, handle validation, audit logging (work_order_status_logs + system comments), and role enforcement. The PUT endpoint accepts a full WorkOrder payload including status. The PATCH close endpoint accepts closedBy (UUID) and optional techNotes.

**Alternatives considered**:
- New dedicated PATCH /work-orders/{id}/status endpoint — rejected (YAGNI; existing PUT works fine for status-only changes)

### R2: Status Transition Logic

**Decision**: Implement linear forward-only transitions client-side: Pending → In Progress → Resolved → Closed.

**Rationale**: The backend does not enforce transition ordering — it accepts any valid status value. Client-side logic determines which next status to offer in the bottom sheet. This keeps the quick flow simple (one option per state) while the full edit screen retains arbitrary status changes.

**Alternatives considered**:
- Server-side transition validation — rejected (would require backend changes; current approach is sufficient for quick flow)
- Offering multiple next statuses (e.g., Pending → In Progress OR Resolved) — rejected (spec explicitly defines linear progression)

### R3: In-Place Card Update Strategy

**Decision**: After successful API call, mutate the WorkOrder object's status field in the _workOrders list and call setState() to refresh the card. No full list reload.

**Rationale**: The API returns success/failure but the list is already in memory. Mutating the local object and triggering a rebuild is the simplest approach that avoids unnecessary network calls and maintains scroll position.

**Alternatives considered**:
- Full list reload via fetchWorkOrders() — rejected (unnecessary network call, loses scroll position, poor UX)
- Optimistic update (update UI before API call) — rejected (adds rollback complexity; spec requires update only on success)

### R4: Bottom Sheet Widget Approach

**Decision**: Use showModalBottomSheet() from work_order_home.dart with a StatefulBuilder for the close flow's loading state.

**Rationale**: Flutter's built-in modal bottom sheet provides the right UX pattern (dismissible, overlays content, doesn't navigate). StatefulBuilder allows managing loading state within the sheet without a separate widget class.

**Alternatives considered**:
- Separate StatefulWidget for the bottom sheet — rejected (YAGNI; StatefulBuilder is sufficient for a loading flag and optional text field)
- AlertDialog instead of bottom sheet — rejected (spec explicitly calls for bottom sheet; better mobile UX for action selection)

### R5: StatusBadge Tap Target

**Decision**: Wrap the existing StatusBadge widget in a GestureDetector inside work_order_card.dart, guarded by role and selection mode checks.

**Rationale**: The StatusBadge is a simple stateless widget in claude_widgets.dart. Wrapping it in a GestureDetector in the card (rather than modifying StatusBadge itself) keeps the badge reusable and avoids adding tap logic to a display-only widget.

**Alternatives considered**:
- Adding onTap to StatusBadge widget — rejected (violates single responsibility; badge is used elsewhere as display-only)
- Adding a separate "change status" icon button — rejected (spec recommends tapping the badge itself for discoverability)

### R6: Audit Logging Verification

**Decision**: No additional audit code needed. Existing endpoints handle all logging.

**Rationale**: Verified that both PUT /work-orders/{id} and PATCH /work-orders/{id}/close call _log_status_change() which writes to work_order_status_logs (old_status, new_status, changed_by) and creates a system comment in work_order_comments with type "status_change" and metadata {"from": old, "to": new}. Constitution Principle VI (Audit Everything) is satisfied without any new code.

**Alternatives considered**: None — existing behavior is sufficient.
