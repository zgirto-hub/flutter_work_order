# Quickstart: 016-signature-approval-chain

## Prerequisites

- Backend running (`uvicorn main:app`)
- Supabase instance accessible
- At least 3 test users: 1 technician, 1 admin, and 2 users to be assigned as supervisor/superintendent

## Implementation Order

### Phase 1: Database Migration
1. Apply `supabase/migrations/20260404_supervisor_superintendent.sql`
2. Verify: `users` table has `is_supervisor`, `is_superintendent`, `approval_level` columns
3. Verify: `work_orders` table has `signature_status` column (all existing = 'unsigned')
4. Verify: `work_order_assignments` has UNIQUE constraint on `work_order_id`
5. Verify: Multi-tech WOs migrated to single-tech (check migration log)

### Phase 2: Backend — Approval Role Management
1. Add `PATCH /users/{id}/approval-role` endpoint to `users.py`
2. Extend `GET /users` with `is_supervisor`, `is_superintendent`, `department_id` filters
3. Test: Admin assigns supervisor with departments, superintendent without
4. Test: Admin cannot assign role to themselves

### Phase 3: Backend — Chain Logic in Signatures Router
1. Add `_get_required_approval_level()`, `_get_approvers_for_level()`, `_advance_chain()` helpers
2. Modify `POST /work-orders/{id}/signatures` — set `signature_status` on tech sign
3. Modify `PATCH /work-orders/{id}/signatures/{sig_id}` — level-based auth, chain advancement
4. Block admin from approve/reject (return 403)
5. Handle rejection: set status to 'rejected', preserve record
6. Handle re-sign: clear non-rejected sigs, reset to 'tech_signed'
7. Add optimistic concurrency: check `signature_status` before advancing
8. Test: Full chain flow (tech → supervisor → superintendent → completed)

### Phase 4: Backend — Single-Technician Assignment
1. Modify `POST /work-orders` and `PATCH /work-orders/{id}` to accept single tech ID
2. Auto-assign technician when creator is technician
3. On re-assignment: reset signature chain
4. Extend `GET /signatures/bulk` to include `signature_status`
5. Add `GET /work-orders/pending-approvals` endpoint

### Phase 5: Backend — Notifications
1. Extend `dispatch_signature_notification()` for level-based routing
2. Tech signs → notify supervisors for department (or superintendents if no supervisor)
3. Supervisor approves → notify superintendents (or complete if none)
4. Any rejection → notify technician + WO creator
5. Exclude admin from all signature notifications

### Phase 6: Frontend — Models
1. Add `isSupervisor`, `isSuperintendent`, `approvalLevel` to `AppUser`
2. Add `signatureStatus` to `WorkOrder`
3. Change `assignedTechnicians` (List) to `assignedTechnician` (single, nullable)

### Phase 7: Frontend — Admin Role Management UI
1. Extend `user_management_screen.dart` with Approval Role section
2. Dropdown: None / Supervisor / Superintendent
3. Department multi-select when Supervisor is selected
4. Prevent admin from assigning role to themselves

### Phase 8: Frontend — Signature Section & Single-Tech
1. Rewrite `_buildSignatureSection()` in `add_work_order.dart`
2. Step progress indicator driven by `signatureStatus`
3. Action buttons visible only when user's approval level matches required step
4. Admin sees read-only view (no action buttons)
5. Replace multi-tech checkboxes with single-tech dropdown

### Phase 9: Frontend — Pending Approvals Screen & Navigation
1. Create `pending_approvals_screen.dart`
2. Register in `NavScreenRegistry`
3. Add conditional nav item in `MainScreen` (visible only when `approvalLevel != null`)
4. Add signature badges to WO list cards

### Phase 10: PDF Export Update
1. Modify PDF generation to check `signature_status == 'completed'`
2. Include only participating approval levels in signature blocks
3. Backend returns 403 if status != 'completed'

## Smoke Test Checklist

- [ ] Admin assigns user as supervisor for Department A
- [ ] Admin assigns another user as superintendent
- [ ] Technician creates WO in Department A (auto-assigned)
- [ ] Technician signs → status = 'tech_signed', supervisor notified
- [ ] Supervisor approves → status = 'supervisor_approved', superintendent notified
- [ ] Superintendent approves → status = 'completed', PDF export available
- [ ] Admin tries to approve → gets 403
- [ ] Supervisor rejects → technician notified, status = 'rejected'
- [ ] Technician re-signs → chain restarts, old sigs preserved
- [ ] Pending Approvals screen shows correct WOs per role
- [ ] WO list badges show correct status per role
