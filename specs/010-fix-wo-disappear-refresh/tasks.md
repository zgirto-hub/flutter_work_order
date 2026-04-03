# Tasks: Fix Work Order Disappears After Refresh

**Input**: Design documents from `/specs/010-fix-wo-disappear-refresh/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md
**Target executor**: OpenAI o3 (5.4)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Path Conventions

- **Web app**: `backend/` (FastAPI/Python), `frontend/` (Flutter/Dart), `supabase/` (migrations)

---

## Phase 1: Setup

**Purpose**: No new project structure needed — this is a bug fix on existing code. Phase is empty.

**Checkpoint**: Proceed directly to Foundational phase.

---

## Phase 2: Foundational (Data Migration)

**Purpose**: Repair existing broken data. This MUST complete before verifying user story fixes, since existing records with auth UUIDs in `created_by` will remain invisible even after the code fix.

- [X] T001 Create Supabase migration to repair existing work orders with auth UUIDs stored in `created_by`. File: `supabase/migrations/20260403_fix_created_by_auth_uuid.sql`. The migration must:
  1. UPDATE `work_orders` SET `created_by = u.id` FROM `users u` WHERE `work_orders.created_by = u.auth_id::text` AND `work_orders.created_by != u.id::text`
  2. Be idempotent (safe to run multiple times)
  3. Not modify rows that already have correct `users.id` values
  4. Add a SQL comment at the top explaining the bug: frontend sends Supabase auth UUID as `created_by`, but the `work_orders.created_by` column is a FK to `users.id` (database UUID). When backend identity resolution fails, the auth UUID gets stored directly, causing the record to be invisible to the reporter on refresh.

**Checkpoint**: Migration ready. Existing broken records will be fixed when migration is applied.

---

## Phase 3: User Story 1 - Work Order Persists After Refresh (Priority: P1) MVP

**Goal**: Fix the backend so that `created_by` is always resolved to the correct database user ID, and reject creation with a clear error if resolution fails.

**Independent Test**: Log in as a reporter, create a new work order, refresh the page — the work order must still be visible in the list.

### Implementation for User Story 1

- [X] T002 [US1] Fix `created_by` identity resolution in `backend/routers/work_orders.py` (lines 453-463 in the `create_work_order` endpoint). Currently, if both `_get_user_id_by_email(body.created_by_email)` and `_get_user_by_auth_id(body.created_by)` fail, the raw auth UUID is silently stored as `created_by`. Change this so that after both lookups fail, the endpoint raises an `HTTPException(status_code=400, detail="Unable to resolve user identity. Work order could not be saved.")` instead of proceeding with the unresolved auth UUID. The resolution logic flow should be:
  1. Try `_get_user_id_by_email(body.created_by_email)` → if found, use as `resolved_created_by`
  2. If step 1 failed, try `_get_user_by_auth_id(body.created_by)` → if found, use `auth_user.get("id")` as `resolved_created_by`
  3. If both failed, raise HTTP 400 with the error message above — do NOT proceed to insert the work order
  4. Keep the existing success path unchanged (insert with `resolved_created_by` into the work order data)

- [X] T003 [US1] Verify the frontend error handling already displays the error properly. In `frontend/lib/screens/Work_Orders/add_work_order.dart` (lines ~755-764), the existing catch block shows a SnackBar with `'Failed to create work order: $e'`. Confirm this catch block handles HTTP 400 errors from the backend — no changes should be needed since `work_order_service.dart` `addWorkOrder()` (lines 87-89) already throws on non-200 status codes with the error detail. If the error message from backend is not user-friendly in the SnackBar, adjust the frontend catch to display a cleaner message like "Could not save work order. Please try again or contact support."

**Checkpoint**: User Story 1 complete. New work orders always have correct `created_by`. Creation fails with clear error if user identity cannot be resolved.

---

## Phase 4: User Story 2 - Consistent Department Filtering (Priority: P2)

**Goal**: Fix the frontend parameter name mismatch so department filtering actually works when fetching work orders.

**Independent Test**: Create a work order in department "Maintenance", apply the department filter on the list page, and verify the work order appears.

### Implementation for User Story 2

- [X] T004 [US2] Fix department parameter name in `frontend/lib/services/work_order_service.dart` line 50. Change `params['department'] = department;` to `params['department_id'] = department;`. The backend endpoint `list_work_orders` in `backend/routers/work_orders.py` line 316 expects the query parameter `department_id` (not `department`). The frontend sends the department ID value correctly — only the parameter key name is wrong. This single-line change fixes department filtering for all users, including reporters whose work orders are filtered by department.

**Checkpoint**: User Story 2 complete. Department filtering works correctly end-to-end.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T005 Add activity log entry for the data migration repair. In `supabase/migrations/20260403_fix_created_by_auth_uuid.sql`, after the UPDATE statement, add an INSERT into `user_activity_log` for each repaired row (category: 'work_order', action: 'migration_repaired_created_by') so there is an audit trail per Constitution Principle VI. Use a CTE or DO block to capture the updated row IDs and bulk-insert log entries. The `changed_by` should be NULL or a system identifier since this is an automated migration.

- [X] T006 Verify the fix end-to-end by reviewing `backend/routers/work_orders.py` list endpoint (lines 360-365 and 387-394). The reporter filtering at lines 360-365 compares `wo.get("created_by") == reporter_user_id`. After T002, new records will always have the correct `users.id`. After T001 migration, existing records will also be fixed. The fallback enrichment at lines 387-394 (which tries `_get_user_by_auth_id` for WOs missing creator join data) will no longer be needed for new records, but should be left in place for safety with any unmigrated edge cases. No code change needed — this is a verification task.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 2)**: No dependencies — can start immediately
- **User Story 1 (Phase 3)**: Independent of Phase 2 (code fix vs data fix) — can start in parallel
- **User Story 2 (Phase 4)**: Independent of all other phases — can start in parallel
- **Polish (Phase 5)**: T005 depends on T001. T006 depends on T002 and T004.

### User Story Dependencies

- **User Story 1 (P1)**: No dependencies on other stories. Fixes the code path.
- **User Story 2 (P2)**: No dependencies on other stories. Fixes a parameter name.

### Parallel Opportunities

- T001 (migration), T002 (backend fix), and T004 (frontend fix) can ALL run in parallel — they modify different files with no interdependencies.
- T003 is a verification of T002 and should run after T002.
- T005 depends on T001 (adds to migration file).
- T006 is verification only — run last.

---

## Parallel Example

```bash
# Launch all independent implementation tasks together:
Task T001: "Create migration in supabase/migrations/20260403_fix_created_by_auth_uuid.sql"
Task T002: "Fix created_by resolution in backend/routers/work_orders.py"
Task T004: "Fix department param in frontend/lib/services/work_order_service.dart"

# Then sequentially:
Task T003: "Verify frontend error handling (after T002)"
Task T005: "Add audit logging to migration (after T001)"
Task T006: "End-to-end verification (after T002, T004)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001 (migration) + T002 (backend fix) in parallel
2. Complete T003 (verify frontend error handling)
3. **STOP and VALIDATE**: Create work order as reporter, refresh, confirm it persists
4. Deploy if ready — this alone fixes the core bug

### Incremental Delivery

1. T001 + T002 + T003 → Core bug fixed (MVP)
2. T004 → Department filtering fixed
3. T005 + T006 → Audit trail + verification

---

## Notes

- Total tasks: 6
- This is a bug fix — no new models, screens, or services needed
- All changes are in existing files except the new migration SQL file
- The migration should be tested on staging before production
- Tasks are written with full context so an LLM executor (OpenAI o3) can implement each without additional context
