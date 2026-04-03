# Quickstart: Quick Status Update

**Feature**: 012-quick-status-update  
**Date**: 2026-04-03

## What This Feature Does

Adds a tappable status badge on work order cards in the list view. Tapping the badge opens a minimal bottom sheet that lets technicians and admins advance a work order's status (Pending → In Progress → Resolved → Closed) without navigating to the full edit screen.

## Files to Modify

1. **`frontend/lib/widgets/work_order_card.dart`**
   - Add `onStatusTap` callback parameter (VoidCallback?)
   - Add `userRole` and `selectionMode` parameters to control badge interactivity
   - Wrap StatusBadge in GestureDetector, guarded by role != reporter, !selectionMode, and status != Closed

2. **`frontend/lib/screens/Work_Orders/work_order_home.dart`**
   - Add `_showQuickStatusSheet(WorkOrder wo)` method that displays a modal bottom sheet
   - Bottom sheet shows current status, next status button, and optional tech notes field (for close flow)
   - On confirm: call `WorkOrderService.updateWorkOrder()` or `closeWorkOrder()`, then update the WorkOrder in `_workOrders` list in place via setState()
   - Pass `onStatusTap`, `userRole`, and `selectionMode` to WorkOrderCard

## Key Implementation Notes

- **No backend changes**: Uses existing PUT /work-orders/{id} and PATCH /work-orders/{id}/close
- **No new widgets**: StatusBadge stays as-is; GestureDetector wraps it in the card
- **Close flow**: Requires `closedBy` (get from Supabase auth currentUser.id) and optional `techNotes` from text field
- **In-place update**: After successful API call, mutate `wo.status` (and closedBy/closedAt/techNotes for close) in the `_workOrders` list and call `setState()`
- **Role check**: `_userRole` already loaded in work_order_home.dart via `_loadProfile()`
- **Selection mode**: `_selectionMode` already tracked in work_order_home.dart state

## Testing

1. Log in as technician → tap status badge on Pending WO → confirm "In Progress" → verify badge updates
2. Repeat for In Progress → Resolved
3. Tap badge on Resolved WO → enter tech notes → confirm Close → verify badge shows Closed
4. Log in as reporter → tap badge → verify nothing happens
5. Long-press to enter selection mode → tap badge → verify nothing happens
6. Test error handling: disconnect network → tap badge → confirm → verify error message shown
