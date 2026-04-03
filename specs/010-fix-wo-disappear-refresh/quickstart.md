# Quickstart: Fix Work Order Disappears After Refresh

## Changes Overview

Three targeted fixes:

1. **Backend** (`backend/routers/work_orders.py`): Make `created_by` resolution mandatory — return HTTP 400 if neither email nor auth_id resolves to a database user. Currently silently falls through with auth UUID.

2. **Frontend** (`frontend/lib/services/work_order_service.dart`): Change `params['department']` to `params['department_id']` so department filtering actually works on the backend.

3. **Migration** (`supabase/migrations/20260403_fix_created_by_auth_uuid.sql`): One-time SQL to fix existing work orders stored with auth UUIDs in `created_by`.

## How to Verify

1. Log in as a reporter
2. Create a new work order
3. Refresh the page
4. Verify the work order is still visible
5. Apply a department filter — verify correct filtering

## Files to Modify

| File | Change |
|------|--------|
| `backend/routers/work_orders.py` (lines 453-463) | Add error return when resolution fails |
| `frontend/lib/services/work_order_service.dart` (line 50) | `department` → `department_id` |
| `supabase/migrations/20260403_*.sql` | New migration file for data repair |

## Risks

- Migration affects existing data — run on staging first
- If any users are missing from the `users` table entirely, their work orders cannot be auto-repaired (will need manual intervention)
