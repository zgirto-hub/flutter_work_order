# Tasks: Quick Status Update

**Input**: Design documents from `/specs/012-quick-status-update/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Tests**: Not requested — manual testing only.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Context for Implementation

### Key Files
- `frontend/lib/widgets/work_order_card.dart` — WorkOrderCard widget (StatefulWidget). StatusBadge is rendered at line ~156. Constructor accepts: workOrder, expanded, unreadActivityCount, onTap, onEdit, onActivity, selectionMode, isSelected, onLongPress.
- `frontend/lib/screens/Work_Orders/work_order_home.dart` — WorkOrderHome screen. WorkOrderCard instantiated at line ~692. Manages `_workOrders` list, `_selectionMode` bool, `_userRole` string (loaded via `_loadProfile()`), and `_service` (WorkOrderService instance).
- `frontend/lib/widgets/claude_widgets.dart` — StatusBadge stateless widget (lines 6-69). Takes `status` (String) and `isSmall` (bool). DO NOT MODIFY this file.
- `frontend/lib/services/work_order_service.dart` — `updateWorkOrder(WorkOrder)` (lines 97-119, PUT), `closeWorkOrder(String id, {required String closedBy, String? techNotes})` (lines 121-138, PATCH). DO NOT MODIFY this file.
- `frontend/lib/models/work_order.dart` — WorkOrder model with fields: id, status, closedBy, closedAt, techNotes, etc.

### Status Transition Map
```
Pending      → next: "In Progress"
In Progress  → next: "Resolved"
Resolved     → next: "Closed"  (uses closeWorkOrder, not updateWorkOrder)
Closed       → terminal (no transition)
```

### Existing State Available in work_order_home.dart
- `_userRole` — String, loaded from `_service.getEmployeeProfile()['user_type']`
- `_selectionMode` — bool, toggled by long-press
- `_workOrders` — `List<WorkOrder>`, the in-memory work order list
- `_service` — WorkOrderService instance
- Current user email: `Supabase.instance.client.auth.currentUser?.email`
- Current user ID: `Supabase.instance.client.auth.currentUser?.id`

---

## Phase 1: Setup

**Purpose**: No setup needed — this feature modifies existing files only. No new dependencies, no new files, no migrations.

*(Skip to Phase 2)*

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add the `onStatusTap` callback to WorkOrderCard so all user stories can use it.

- [X] T001 Add `onStatusTap` callback parameter to WorkOrderCard constructor in `frontend/lib/widgets/work_order_card.dart`. Add `final VoidCallback? onStatusTap;` field to the widget class. Add it as an optional named parameter in the constructor: `this.onStatusTap`. This is the callback that work_order_home.dart will use to trigger the bottom sheet.

- [X] T002 Wrap the existing `StatusBadge(status: widget.workOrder.status)` widget (at line ~156 in `frontend/lib/widgets/work_order_card.dart`) in a `GestureDetector`. The `onTap` should call `widget.onStatusTap?.call()` ONLY when ALL of these conditions are true: (1) `widget.onStatusTap != null`, (2) `!widget.selectionMode`, (3) `widget.workOrder.status.toLowerCase() != 'closed'`. If any condition is false, render the StatusBadge without GestureDetector wrapping (or with onTap: null). NOTE: The `selectionMode` parameter already exists on WorkOrderCard — no need to add it.

**Checkpoint**: WorkOrderCard now accepts an onStatusTap callback and gates it properly. No visible behavior change yet (callback is not passed from home screen).

---

## Phase 3: User Story 1 - Quick Status Advancement (Priority: P1) 🎯 MVP

**Goal**: Technician/admin can tap a status badge on a work order card to advance its status (Pending → In Progress, In Progress → Resolved) via a minimal bottom sheet, with in-place card update on success.

**Independent Test**: Tap the status badge on a Pending or In Progress work order. A bottom sheet appears showing the current status and a button for the next status. Tap confirm. The badge updates without page navigation.

### Implementation for User Story 1

- [X] T003 [US1] Create a helper function `_getNextStatus(String currentStatus)` in `frontend/lib/screens/Work_Orders/work_order_home.dart` that returns the next status string or null. Logic: `'pending' → 'In Progress'`, `'in progress' → 'Resolved'`, `'resolved' → 'Closed'`, `'closed' → null`. Use `currentStatus.toLowerCase()` for matching. Return null for unknown statuses. Place this as a private method in the `_WorkOrderHomeState` class.

- [X] T004 [US1] Create the `_showQuickStatusSheet(WorkOrder wo)` method in `frontend/lib/screens/Work_Orders/work_order_home.dart`. This method calls `showModalBottomSheet()` with the following bottom sheet content:
  - Use `StatefulBuilder` inside the sheet to manage a local `_isLoading` bool (starts false).
  - **Header**: Show the current status using `StatusBadge(status: wo.status)` and the work order title/jobNo for context.
  - **Action button**: A single ElevatedButton labeled with the next status text (from `_getNextStatus(wo.status)`). For this task, handle ONLY Pending → In Progress and In Progress → Resolved (NOT the close flow — that's US2).
  - **On button press**: Set `_isLoading = true` in the StatefulBuilder's setState. Create a copy of the WorkOrder with the new status (`wo.copyWith(status: nextStatus)` — or manually create a new WorkOrder if copyWith doesn't exist). Call `await _service.updateWorkOrder(updatedWo)`. On success: find the work order in `_workOrders` list by id, update its status field, call `setState(() {})` on the outer state, then `Navigator.pop(context)` to close the sheet. On error: show a `ScaffoldMessenger.of(context).showSnackBar()` with the error message, set `_isLoading = false`.
  - **Loading state**: While `_isLoading` is true, disable the button and show a CircularProgressIndicator.
  - Style the sheet with padding, rounded top corners (`RoundedRectangleBorder` with `borderRadius: BorderRadius.vertical(top: Radius.circular(16))`).

- [X] T005 [US1] Wire the `onStatusTap` callback in `frontend/lib/screens/Work_Orders/work_order_home.dart` where WorkOrderCard is instantiated (line ~692). Add: `onStatusTap: (_userRole != 'reporter' && _getNextStatus(wo.status) != null) ? () => _showQuickStatusSheet(wo) : null,`. This ensures: reporters get null (non-tappable per T002 guard), closed WOs get null (no next status), and technician/admin get the sheet.

**Checkpoint**: At this point, technicians and admins can tap the status badge on Pending and In Progress work orders to advance the status. The card updates in place. Reporters cannot tap the badge. Closed work orders show no tap interaction. This is the MVP.

---

## Phase 4: User Story 2 - Quick Close with Tech Notes (Priority: P2)

**Goal**: When tapping the badge on a "Resolved" work order, the bottom sheet includes an optional tech notes text field and calls the close endpoint instead of the regular update endpoint.

**Independent Test**: Tap the status badge on a Resolved work order. The bottom sheet shows a text field for tech notes and a "Close" button. Enter optional notes, confirm. The work order closes with the correct closer identity.

### Implementation for User Story 2

- [X] T006 [US2] Extend the `_showQuickStatusSheet` method in `frontend/lib/screens/Work_Orders/work_order_home.dart` to handle the close flow. Inside the StatefulBuilder, add a `TextEditingController` for tech notes (only created when `wo.status.toLowerCase() == 'resolved'`). In the sheet body: if the current status is "Resolved", show a `TextField` with label "Tech Notes (optional)" above the action button. Change the button label to "Close Work Order". On button press: instead of calling `updateWorkOrder()`, call `await _service.closeWorkOrder(wo.id, closedBy: Supabase.instance.client.auth.currentUser!.id, techNotes: techNotesController.text.isEmpty ? null : techNotesController.text)`. On success: update the work order in `_workOrders` — set `status = 'Closed'`, `closedBy`, `closedAt` (use `DateTime.now().toIso8601String()`), and `techNotes` if provided. Then setState and pop. On error: show snackbar, reset loading. Dispose the TextEditingController properly (use StatefulBuilder's state).

**Checkpoint**: Full status flow works: Pending → In Progress → Resolved → Closed. Close flow captures optional tech notes and records the closer.

---

## Phase 5: User Story 3 - Role-Based Access Control (Priority: P1, already handled)

**Goal**: Reporter role sees read-only badges. Already implemented in T002 (GestureDetector guard) and T005 (null callback for reporter role).

**Independent Test**: Log in as reporter, tap any status badge — nothing happens.

*(No additional tasks needed — role gating is built into T002 and T005)*

**Checkpoint**: Verified that reporter role is blocked at two levels: callback is null (T005), and GestureDetector doesn't fire without callback (T002).

---

## Phase 6: User Story 4 - Selection Mode Interaction (Priority: P2, already handled)

**Goal**: Status badge tap is disabled during selection mode. Already implemented in T002 (GestureDetector guard checks `!widget.selectionMode`).

**Independent Test**: Long-press a card to enter selection mode, then tap any status badge — nothing happens.

*(No additional tasks needed — selection mode guard is built into T002)*

**Checkpoint**: Verified that selection mode blocks badge tap via the `!widget.selectionMode` condition in T002.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and edge case handling.

- [X] T007 Verify error handling in `_showQuickStatusSheet` in `frontend/lib/screens/Work_Orders/work_order_home.dart`: wrap the API calls in try-catch blocks. Catch generic exceptions and show user-friendly error messages via SnackBar. Ensure `_isLoading` is reset to false in the catch block so the button becomes re-tappable.

- [X] T008 Verify that dismissing the bottom sheet (swipe down or tap outside) without pressing the action button has no side effects. The `showModalBottomSheet` is dismissible by default — no additional code needed, but confirm that no state mutation occurs on dismiss.

- [ ] T009 Run manual validation per `specs/012-quick-status-update/quickstart.md` testing checklist: (1) Pending → In Progress, (2) In Progress → Resolved, (3) Resolved → Closed with tech notes, (4) Reporter can't tap, (5) Selection mode blocks tap, (6) Network error shows error message.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: Skipped — no setup needed
- **Phase 2 (Foundational)**: T001 → T002 (must be sequential — T002 depends on the field added in T001)
- **Phase 3 (US1 - MVP)**: Depends on Phase 2. T003 and T004 can be done in any order, but T005 depends on both T003 and T004.
- **Phase 4 (US2 - Close)**: Depends on Phase 3 (extends the method created in T004)
- **Phase 5 (US3)**: No tasks — already covered by T002 + T005
- **Phase 6 (US4)**: No tasks — already covered by T002
- **Phase 7 (Polish)**: Depends on Phase 4

### Task Dependency Graph

```
T001 → T002 → T003 ──→ T005 → T006 → T007 → T008 → T009
                T004 ──↗
```

### Parallel Opportunities

- T003 and T004 can be implemented in parallel (T003 is a helper function, T004 is the bottom sheet method — both in the same file but independent logic blocks)
- T007 and T008 can be validated in parallel

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001-T002: Add callback and GestureDetector to WorkOrderCard
2. Complete T003-T005: Build bottom sheet and wire it up
3. **STOP and VALIDATE**: Test status badge tap on Pending and In Progress work orders
4. Verify reporter role and selection mode blocking work

### Incremental Delivery

1. T001-T005 → MVP: Quick status for Pending/In Progress (deliverable)
2. T006 → Add close flow with tech notes (deliverable)
3. T007-T009 → Polish and validate all flows

### File Change Summary

| File | Tasks | Changes |
|------|-------|---------|
| `frontend/lib/widgets/work_order_card.dart` | T001, T002 | Add onStatusTap param, wrap StatusBadge in GestureDetector |
| `frontend/lib/screens/Work_Orders/work_order_home.dart` | T003, T004, T005, T006, T007 | Add helper function, bottom sheet method, wire callback |
| `frontend/lib/widgets/claude_widgets.dart` | None | No changes |
| `frontend/lib/services/work_order_service.dart` | None | No changes |

---

## Notes

- No [P] tasks marked because all tasks are in the same 2 files — true parallelism is limited
- T003 and T004 are logically independent but both edit work_order_home.dart — an LLM should do them sequentially to avoid merge conflicts
- The close flow (T006) uses `closeWorkOrder()` not `updateWorkOrder()` — this is critical for correct audit logging
- The `_userRole` check happens at the callback assignment level (T005), not inside the bottom sheet — this prevents the sheet from ever opening for reporters
- US3 and US4 have no dedicated tasks because their requirements are satisfied by guard conditions in T002 and T005
- Each task description is self-contained — an LLM can read a single task and implement it without needing to read other tasks
