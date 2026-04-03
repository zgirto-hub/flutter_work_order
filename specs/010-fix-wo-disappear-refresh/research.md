# Research: Fix Work Order Disappears After Refresh

## Root Cause Analysis

### Bug 1: `created_by` Identity Resolution Failure (PRIMARY)

**Location**: `backend/routers/work_orders.py` lines 453-463

**What happens**:
1. Frontend sends `created_by` = Supabase auth UUID (`_userId`) and `created_by_email` = user's email
2. Backend tries `_get_user_id_by_email(body.created_by_email)` — if user's email not found in `users` table, returns None
3. Backend falls back to `_get_user_by_auth_id(body.created_by)` — if `auth_id` column doesn't match, returns None
4. Both fail → `resolved_created_by` remains as the raw auth UUID
5. Work order is saved with `created_by = auth_uuid` (wrong format)

**Why it disappears on refresh**:
- List endpoint (`list_work_orders`, line 360-365) filters reporter work orders by `created_by == reporter_user_id`
- `reporter_user_id` is looked up via `_get_user_id_by_email(email)` — returns the database UUID (`users.id`)
- Stored auth UUID ≠ database UUID → work order filtered out

**Decision**: Make `created_by` resolution mandatory — reject creation if resolution fails, with clear error message to user.
**Rationale**: Silent fallback to auth UUID creates invisible data corruption. Failing fast is safer.
**Alternatives considered**:
- Store auth UUID and query by both ID types → adds query complexity, masks data inconsistency
- Auto-create user record → violates Constitution III (no self-registration)

### Bug 2: Department Parameter Name Mismatch (SECONDARY)

**Location**: 
- Frontend: `frontend/lib/services/work_order_service.dart` line 50 — sends `params['department'] = department`
- Backend: `backend/routers/work_orders.py` line 316 — expects `department_id: Optional[str] = Query(None)`

**What happens**: Frontend sends `?department=X` but backend reads `department_id` query param → always None → department filter never applied.

**Decision**: Fix frontend to send `department_id` instead of `department`.
**Rationale**: Backend parameter name `department_id` is correct (matches the column name in `work_orders` table). Frontend should conform.
**Alternatives considered**:
- Change backend to accept `department` → inconsistent with data model column naming
- Accept both names → unnecessary complexity (YAGNI)

### Data Migration: Repair Existing Broken Records

**Decision**: Write a SQL migration that joins `work_orders.created_by` against `users.auth_id` and updates mismatched rows to use `users.id`.
**Rationale**: Existing broken records will remain invisible to reporters forever without repair.
**Alternatives considered**:
- Backend script instead of SQL migration → less auditable, not idempotent
- Manual repair → error-prone, doesn't scale

**Migration strategy**:
```sql
UPDATE work_orders wo
SET created_by = u.id
FROM users u
WHERE wo.created_by = u.auth_id::text
  AND wo.created_by != u.id::text;
```
This is safe because:
- Only updates rows where `created_by` matches an `auth_id` (not already a `users.id`)
- Idempotent — running twice has no effect
- Records where auth_id cannot be matched are left unchanged (logged for manual review)
