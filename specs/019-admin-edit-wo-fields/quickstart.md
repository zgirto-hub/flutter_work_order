# Quickstart: Admin Edit WO Metadata Fields

**Branch**: `019-admin-edit-wo-fields` | **Date**: 2026-04-05

## What This Feature Does

Allows admin users to edit three work order metadata fields that are normally immutable:
1. **Created By** — change who is listed as the work order creator
2. **Created At** — correct the creation date/time
3. **Closed At** — correct the closure date/time (only on closed work orders)

Non-admin users see these fields as read-only (unchanged behavior).

## Files to Modify

| File | Change |
|------|--------|
| `backend/routers/work_orders.py` | Add 3 optional fields to `UpdateWorkOrderBody`. Add admin-only validation logic in PUT handler. |
| `frontend/lib/services/work_order_service.dart` | Add 3 optional fields to `updateWorkOrder` payload. |
| `frontend/lib/screens/Work_Orders/add_work_order.dart` | Add admin-only editable controls for the 3 fields. |

## Files to Create

| File | Purpose |
|------|---------|
| `frontend/lib/widgets/user_selector.dart` | Searchable single-select user picker (based on `TechnicianSelector` pattern). |

## Key Patterns to Follow

1. **Backend admin check**: Use `_get_user_role(email)` to check `user_type == 'admin'` when metadata fields are present.
2. **Frontend role gating**: Use existing `_userRole == 'admin'` check to conditionally render editable vs read-only fields.
3. **User picker UI**: Follow `TechnicianSelector` pattern — bottom sheet with search, filtered list, single selection.
4. **Date picker UI**: Use `showDatePicker` + `showTimePicker` combination, pre-filled with current value.
5. **Audit logging**: Existing `log_activity` call handles it; enhance `detail` param to note metadata changes.

## Validation Summary

- `created_at` cannot be in the future
- `closed_at` must be >= `created_at`
- `closed_at` only editable when status is "Closed"
- `created_by` must be an active user UUID
- All three fields: admin-only (403 if non-admin sends them)
