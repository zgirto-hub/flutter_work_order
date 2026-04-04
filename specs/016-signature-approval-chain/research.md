# Research: 016-signature-approval-chain

## R1: Current Signature Workflow Architecture

**Decision**: Extend the existing `signatures.py` router rather than creating a new router.

**Rationale**: The current router (`backend/routers/signatures.py`) already handles:
- `POST /work-orders/{id}/signatures` — technician/admin sign
- `PATCH /work-orders/{id}/signatures/{sig_id}` — admin approve/reject
- `GET /work-orders/{id}/signatures` — list signatures
- `GET /signatures/bulk` — bulk status for WO list
- `DELETE /work-orders/{id}/signatures/{sig_id}` — admin remove

The existing pattern uses `signer_role` ("technician" or "admin") and `status` ("pending", "approved", "rejected"). The new chain replaces admin approval with supervisor/superintendent approval. Extending in-place avoids duplication.

**Current flow**: Technician signs (status=pending) → Admin approves/rejects (updates status).
**New flow**: Technician signs (status=pending, WO signature_status=tech_signed) → Supervisor approves (WO signature_status=supervisor_approved) → Superintendent approves (WO signature_status=completed).

**Alternatives considered**: New `approval_chain.py` router — rejected because it would split signature logic across two files with shared helpers.

## R2: Database Schema for Approval Roles

**Decision**: Add columns to `users` table: `is_supervisor BOOLEAN DEFAULT false`, `is_superintendent BOOLEAN DEFAULT false`, `approval_level INTEGER DEFAULT NULL`.

**Rationale**: Using additive boolean flags + integer level preserves the existing `user_type` enum (reporter/technician/admin) per constitution Principle III. The integer `approval_level` drives chain ordering (1=supervisor, 2=superintendent, 3=future manager) making the chain extensible without schema changes.

**Alternatives considered**:
- New `user_roles` join table — rejected per Principle VII (YAGNI); only 2-3 levels expected.
- Add values to `user_type` enum — rejected; constitution mandates three roles and this would conflate identity with operational approval authority.

## R3: Signature Status Tracking on Work Orders

**Decision**: Add `signature_status TEXT DEFAULT 'unsigned'` to `work_orders` table with CHECK constraint.

**Rationale**: A single denormalized field on the WO avoids expensive joins to determine chain state. All UI and API logic references this one field. Values: `unsigned`, `tech_signed`, `supervisor_approved`, `superintendent_approved`, `completed`, `rejected`. Adding future levels only requires adding a CHECK value.

**Alternatives considered**: Derive status from signature records — rejected because it requires complex queries and creates race conditions.

## R4: Signer Role Extension in work_order_signatures

**Decision**: Extend `signer_role` CHECK to include `'supervisor'` and `'superintendent'`. Keep `'technician'`. Remove `'admin'` from valid signer roles since admin is excluded from the chain.

**Rationale**: Each approval action creates a new signature record with the approver's role. This preserves the audit trail showing who approved at each level.

**Migration note**: Existing admin signatures are preserved (the CHECK is modified for new inserts only; existing data with `signer_role='admin'` remains valid via migration approach — ALTER CHECK drops+recreates).

## R5: Navigation Architecture for Pending Approvals

**Decision**: Add "Approvals" to `NavScreenRegistry` in `nav_screen.dart` and conditionally show it in `main_screen.dart` based on user approval level.

**Rationale**: The app uses a `NavScreenRegistry` pattern with a bottom nav bar. Pinned screens are configurable. The Pending Approvals screen should appear as a nav item only for users with `approval_level != null`. The `MainScreen._canShow()` method and `_loadUserRole()` already fetch role info — extending to include approval level is straightforward.

**Alternatives considered**: Separate route outside the nav — rejected because it would be inconsistent with how other screens (Files, Reports, Calendar) are accessed.

## R6: Single-Technician Assignment Migration

**Decision**: Migration SQL will: (1) For each WO with multiple assignments, keep the one with the earliest `assigned_at` and delete the rest, logging affected WO IDs. (2) Add a UNIQUE constraint on `work_order_assignments(work_order_id)` to enforce single-tech going forward.

**Rationale**: The `work_order_assignments` table currently has no uniqueness constraint on `work_order_id`, allowing multiple technicians. Adding the constraint after cleanup enforces the new rule at the DB level.

**Current code references**: `WorkOrder.assignedTechnicians` is a `List<TechnicianAssignment>`. Frontend `toJson()` sends `assigned_technician_ids` as a list. Backend `CreateWorkOrderBody.assigned_technician_ids` accepts a list. All need to change to single-value.

## R7: Notification Routing by Approval Level

**Decision**: Extend `dispatch_signature_notification()` in `notification_service.py` to route by approval level instead of hardcoded "notify all admins."

**Rationale**: Current implementation queries all active admins when a technician signs. The new implementation queries users by `approval_level` and department scope. The existing preference cascade (mute_all → event toggle → channel toggle) remains unchanged.

**Key change**: Replace `supabase.table("users").eq("user_type", "admin")` with `supabase.table("users").eq("approval_level", required_level)` plus department join for level 1.

## R8: Concurrent Approval Handling

**Decision**: Use optimistic concurrency — check `signature_status` matches expected value before advancing. If mismatch, return 409 Conflict.

**Rationale**: PostgreSQL's default isolation level (Read Committed) combined with an atomic UPDATE ... WHERE signature_status = expected_value prevents two concurrent approvals from both succeeding. No explicit locking needed.
