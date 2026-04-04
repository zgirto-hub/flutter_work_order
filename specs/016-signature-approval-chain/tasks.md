# Tasks: Supervisor & Superintendent Signature Approval Chain

**Input**: Design documents from `/specs/016-signature-approval-chain/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api.md, quickstart.md
**Branch**: `016-signature-approval-chain`

**Delegation**: Tasks are written for another LLM (OpenAI) to implement. Claude will review each completed phase before proceeding to the next.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- All file paths are relative to repository root: `C:\Development\flutter_work_order`

---

## Phase 1: Setup (Database Migration)

**Purpose**: Schema changes that all subsequent work depends on

- [ ] T001 Create migration file `supabase/migrations/20260404_supervisor_superintendent.sql` with the following changes: (1) ALTER TABLE `users` ADD COLUMN `is_supervisor` BOOLEAN DEFAULT false, ADD COLUMN `is_superintendent` BOOLEAN DEFAULT false, ADD COLUMN `approval_level` INTEGER DEFAULT NULL with CHECK (approval_level IN (1, 2, 3)); (2) ALTER TABLE `work_orders` ADD COLUMN `signature_status` TEXT DEFAULT 'unsigned' with CHECK (signature_status IN ('unsigned', 'tech_signed', 'supervisor_approved', 'superintendent_approved', 'completed', 'rejected')); (3) ALTER TABLE `work_order_signatures` drop and recreate the `signer_role` CHECK constraint to allow ('technician', 'supervisor', 'superintendent', 'admin') — keep 'admin' for existing records; (4) Migrate multi-tech assignments: for each `work_order_id` in `work_order_assignments` with more than one row, keep the row with the earliest `assigned_at`, delete extras, and INSERT a log row into `user_activity_log` with category='admin', action='migration_single_tech', target_id=work_order_id; (5) ADD UNIQUE constraint on `work_order_assignments(work_order_id)` to enforce single-tech going forward. See `specs/016-signature-approval-chain/data-model.md` for full schema details.

**Checkpoint**: Run migration against Supabase. Verify all columns exist, CHECK constraints work, and multi-tech WOs have been cleaned up.

---

## Phase 2: Foundational (Backend Chain Helpers + Frontend Models)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T002 [P] Add three approval chain helper functions to `backend/routers/signatures.py`. (1) `_get_required_approval_level(signature_status: str) -> int` — maps 'tech_signed'->1, 'supervisor_approved'->2, 'superintendent_approved'->3, else raises ValueError. (2) `_get_approvers_for_level(level: int, department_id: str) -> list` — level 1: query `users` WHERE `is_supervisor=true` AND `id` IN (SELECT `technician_id` FROM `technician_departments` WHERE `department_id`=param); level 2: query `users` WHERE `is_superintendent=true`; level 3: return []. (3) `_advance_chain(work_order_id: str, current_status: str) -> str` — get required level from current_status, get approvers for that level, if approvers exist return current_status (wait), if none try next level, if no approvers at any remaining level AND at least one level had approvers previously return 'completed', if ALL levels missing return current_status (blocked). Log skipped levels to `user_activity_log` via `log_activity()`. See `specs/016-signature-approval-chain/data-model.md` "Approval Level Resolver" section for exact logic.

- [ ] T003 [P] Add `_get_user_approval_info(email: str) -> dict` helper to `backend/routers/signatures.py`. This function queries the `users` table for the given email and returns a dict with keys: `user_type`, `approval_level`, `is_supervisor`, `is_superintendent`, `id`, `email`. Also query `technician_departments` to get the user's department IDs and include as `department_ids: list[str]`. Return None if user not found. This helper is used by all approval endpoints.

- [ ] T004 [P] Update `frontend/lib/models/user.dart` — Add three fields to `AppUser`: `final bool isSupervisor` (default false), `final bool isSuperintendent` (default false), `final int? approvalLevel` (default null). Update `fromJson()` to parse `is_supervisor`, `is_superintendent`, `approval_level` from JSON. Update `toJson()` to include them. Update `copyWith()` to support them. Update the constructor with named parameters.

- [ ] T005 [P] Update `frontend/lib/models/work_order.dart` — (1) Add field `final String signatureStatus` (default 'unsigned'). Update `fromJson()` to parse `signature_status` from JSON (default 'unsigned'). Update `copyWith()` to support it. (2) Change `final List<TechnicianAssignment> assignedTechnicians` to `final TechnicianAssignment? assignedTechnician` (single, nullable). Update `fromJson()`: parse `work_order_assignments` as before but take only the first element (or null if empty). Update `toJson()`: send `assigned_technician_id` as single string (or null) instead of list. Update `copyWith()` accordingly.

- [ ] T006 [P] Extend `backend/routers/users.py` — Add a new Pydantic model `UpdateApprovalRoleBody` with fields: `approval_level: Optional[int] = None`, `department_ids: Optional[List[str]] = []`. Add endpoint `@router.patch("/users/{user_id}/approval-role")` with query param `admin_email: str`. Logic: (1) verify caller is admin via `_require_admin(admin_email)`; (2) verify admin is not setting their own role (compare admin user id with user_id, return 403 if same); (3) if `approval_level` is None: set `is_supervisor=false`, `is_superintendent=false`, `approval_level=null`; (4) if `approval_level=1`: set `is_supervisor=true`, `is_superintendent=false`, `approval_level=1`, then delete existing `technician_departments` rows for this user and insert new rows for each department_id; (5) if `approval_level=2`: set `is_supervisor=false`, `is_superintendent=true`, `approval_level=2`; (6) return the updated user data. Also extend the existing `GET /users` list endpoint to accept optional query params `is_supervisor: Optional[bool]`, `is_superintendent: Optional[bool]`, `department_id: Optional[str]` and filter accordingly. See `specs/016-signature-approval-chain/contracts/api.md` "PATCH /users/{user_id}/approval-role" for full contract.

- [ ] T007 Update `backend/routers/work_orders.py` — (1) Change `CreateWorkOrderBody.assigned_technician_ids: Optional[List[str]]` to `assigned_technician_id: Optional[str] = None`. (2) In the create endpoint: if the creator's `user_type` is 'technician', auto-assign them (set `assigned_technician_id` to creator's user ID). If creator is reporter/admin, leave unassigned (don't insert into `work_order_assignments`). (3) Change `UpdateWorkOrderBody.assigned_technician_ids` to `assigned_technician_id: Optional[str] = None`. (4) In the update endpoint: when `assigned_technician_id` changes, delete old assignment, insert new one. If the WO's `signature_status` is not 'unsigned', reset it to 'unsigned' and clear all non-rejected signatures from `work_order_signatures` (mark them as 'rejected' for audit), then log this to `user_activity_log`. (5) Ensure all WO GET responses include `signature_status` from the `work_orders` table in the select query.

**Checkpoint**: Foundation ready. Backend has chain helpers, approval role endpoint, single-tech assignment. Frontend models updated. Review before proceeding.

---

## Phase 3: US1 + US2 + US3 — Core Approval Chain (Priority: P1)

**Goal**: Complete the end-to-end approval chain: Technician signs -> Supervisor approves -> Superintendent approves -> Completed. Also handles rejection and re-sign.

**Independent Test**: Technician signs a WO, supervisor approves, superintendent approves. Verify signature_status progresses correctly at each step. Test rejection resets chain. Test admin gets 403.

### Implementation

- [ ] T008 [US1] Rewrite `POST /work-orders/{work_order_id}/signatures` (the `add_signature` function) in `backend/routers/signatures.py`. Changes: (1) Remove `signer_role` acceptance of 'admin' — only 'technician' is valid for signing. (2) Before creating signature, check WO `signature_status` is 'unsigned' or 'rejected'; if not, return 409 "Cannot sign at current status". (3) On re-sign after rejection (`signature_status == 'rejected'`): update all existing signatures for this WO where `status != 'rejected'` to `status='rejected'` (preserving audit trail), then reset WO `signature_status` to 'unsigned'. (4) After saving the technician signature, update WO `signature_status` to 'tech_signed'. (5) Call `_advance_chain(work_order_id, 'tech_signed')` — if it returns a status different from 'tech_signed' (meaning supervisor level was skipped), update WO accordingly. (6) Send notification via updated `dispatch_signature_notification()` (T010). (7) Log to activity log. Keep existing signature file handling (base64 decode, saved signature copy) unchanged.

- [ ] T009 [US2] [US3] Rewrite `PATCH /work-orders/{work_order_id}/signatures/{signature_id}` (the `update_signature` function) in `backend/routers/signatures.py`. Complete authorization rework per `specs/016-signature-approval-chain/contracts/api.md`: (1) Get caller info via `_get_user_approval_info(user_email)`. (2) If caller is admin (`user_type == 'admin'`), return 403 "Admin cannot approve signatures". (3) Get WO's current `signature_status`. (4) Call `_get_required_approval_level(signature_status)` to determine what level is needed. (5) If caller's `approval_level` != required level, return 403. (6) If level 1 (supervisor): verify WO's `department_id` is in caller's `department_ids`, return 403 if not. (7) Self-approval check: query the technician signature for this WO, if `signer_email` == caller email, return 403 "Cannot approve your own signature". (8) Optimistic concurrency: use UPDATE `work_orders` SET `signature_status` = new_value WHERE `id` = work_order_id AND `signature_status` = expected_value; if no rows updated, return 409 "Already approved at this level". (9) On approve: create a new signature record with `signer_role` = 'supervisor' or 'superintendent' (based on caller's level), `status='approved'`. Update WO `signature_status` to next state ('supervisor_approved' or 'superintendent_approved'). Call `_advance_chain()` to check if next level should be skipped. (10) On reject: update the signature's status to 'rejected', store rejection_reason, set WO `signature_status` to 'rejected'. (11) Send appropriate notifications. (12) Log to activity log. Return `{"status": body.status, "signature_status": new_wo_status}`.

- [ ] T010 [US1] [US2] [US3] Rewrite `dispatch_signature_notification()` in `backend/utils/notification_service.py`. Replace the existing admin-only routing with level-based routing: (1) New parameter: `kind` values expanded to include 'signature_pending_supervisor', 'signature_pending_superintendent', 'signature_approved_supervisor', 'signature_approved_superintendent'. (2) 'signature_pending_supervisor': query users WHERE `is_supervisor=true` AND `id` IN (SELECT `technician_id` FROM `technician_departments` WHERE `department_id` = wo_department_id). If none found, fall back to superintendents and add `kind='signature_pending_superintendent'`. (3) 'signature_pending_superintendent': query users WHERE `is_superintendent=true`. (4) 'signature_approved_superintendent' (chain complete): notify the technician who signed and the WO creator. (5) 'signature_rejected': notify the assigned technician and WO creator. (6) NEVER include admin users in signature notification recipients. (7) Keep existing preference cascade (`_get_preferences`, `mute_all` check, `push_enabled`/`in_app_enabled` toggles). (8) Add a new notification kind 'approval_notifications' to the preference check (alongside existing 'status_notifications'). (9) Also add `wo_department_id: str = ""` as a new parameter to support department-scoped supervisor queries.

- [ ] T011 [US1] [US2] [US3] Update `GET /signatures/bulk` endpoint in `backend/routers/signatures.py`. Change the response to include `signature_status` from `work_orders` table. For each WO ID, also query `work_orders.signature_status` and include it. Extend the per-WO status dict to include keys: `signature_status`, `supervisor_signed`, `supervisor_status`, `superintendent_signed`, `superintendent_status` (in addition to existing `technician_signed`, `technician_status`). Remove the old `admin_signed`/`admin_status` keys.

**Checkpoint**: Core chain works end-to-end. Test: tech signs -> supervisor approves -> superintendent approves -> completed. Test rejection. Test admin 403. Review before proceeding.

---

## Phase 4: US4 — Admin Manages Approval Roles (Priority: P2)

**Goal**: Admin can assign/remove supervisor and superintendent roles through the user management screen.

**Independent Test**: Admin opens user management, assigns user as supervisor with departments. Verify role saved. Change to superintendent. Verify departments cleared. Set to None. Verify role removed.

### Implementation

- [ ] T012 [P] [US4] Add approval role service methods to `frontend/lib/services/user_service.dart`. Add: (1) `Future<Map<String, dynamic>> updateApprovalRole(String userId, int? approvalLevel, List<String> departmentIds)` — calls `PATCH /users/{userId}/approval-role?admin_email=...` with JSON body `{"approval_level": approvalLevel, "department_ids": departmentIds}`. (2) `Future<List<AppUser>> getSupervisors({String? departmentId})` — calls `GET /users?is_supervisor=true&department_id=...`. (3) `Future<List<AppUser>> getSuperintendents()` — calls `GET /users?is_superintendent=true`.

- [ ] T013 [US4] Extend `frontend/lib/screens/admin/user_management_screen.dart` with an "Approval Role" section in the user edit dialog/form. Add: (1) A `DropdownButtonFormField` with options: "None", "Supervisor", "Superintendent". (2) When "Supervisor" is selected, show a department multi-select widget (reuse the existing `technician_departments` UI pattern already in this screen — look for how departments are assigned to technicians and replicate that pattern). (3) When "Superintendent" is selected, hide the department selector. (4) When "None" is selected, hide the department selector. (5) On save, call `UserService.updateApprovalRole()` with the selected level and departments. (6) If the admin is editing their own user record, disable/hide the approval role section entirely (admin cannot assign role to themselves). (7) Display current approval role in the user list/card (e.g., a small "Supervisor" or "Superintendent" chip badge).

**Checkpoint**: Admin can manage approval roles. Review before proceeding.

---

## Phase 5: US6 — Admin Excluded from Approval Chain (Priority: P2)

**Goal**: Admin sees all signature data read-only but cannot approve/reject.

**Independent Test**: Login as admin, view WO signature section. Verify no action buttons. Call PATCH approve endpoint directly — verify 403.

### Implementation

- [ ] T014 [US6] The backend 403 block for admin is already implemented in T009 (PATCH endpoint). This task covers the frontend: In `frontend/lib/screens/Work_Orders/add_work_order.dart`, in the `_buildSignatureSection()` method, add a check: if the current user's `userType == 'admin'`, render all signature steps as read-only (show status, signer name, date, signature image) but do NOT render any approve/reject/sign action buttons. Admin should see the full signature history including rejected records. This is a prerequisite for the full signature section rewrite in T018 (US7).

**Checkpoint**: Admin exclusion verified on both backend and frontend.

---

## Phase 6: US5 — Approval Status Badges on Work Order List (Priority: P2)

**Goal**: Supervisors and superintendents see contextual signature badges on WO cards.

**Independent Test**: Login as supervisor — amber badges appear on WOs in their departments with 'tech_signed' status. Login as superintendent — badges on 'supervisor_approved' WOs. Login as admin — no badges.

### Implementation

- [ ] T015 [US5] Update `frontend/lib/screens/Work_Orders/work_order_home.dart` to display signature status badges on WO cards. (1) The WO list already calls `GET /signatures/bulk` for status — use the new `signature_status` field from T011. (2) For each WO card, add a badge widget: if current user is supervisor (`approvalLevel == 1`) and WO's `signature_status == 'tech_signed'` and WO's department is in user's departments → show amber "Pending Approval" badge. If current user is superintendent (`approvalLevel == 2`) and WO's `signature_status == 'supervisor_approved'` → show amber "Pending Approval" badge. If WO's `signature_status == 'completed'` → show green "Completed" badge (visible to all). If current user is admin → do NOT show any signature action badges. (3) Use existing app theme colors from `frontend/lib/theme/app_theme.dart` for badge styling.

**Checkpoint**: Badges display correctly per role. Review before proceeding.

---

## Phase 7: US8 — Dedicated Pending Approvals Screen (Priority: P2)

**Goal**: Approvers get a dedicated screen showing only WOs awaiting their approval.

**Independent Test**: Login as supervisor — see only WOs in their departments with 'tech_signed'. Login as superintendent — see only 'supervisor_approved' WOs. User with no approval role — screen not accessible.

### Implementation

- [ ] T016 [P] [US8] Add `GET /work-orders/pending-approvals` endpoint to `backend/routers/work_orders.py`. Query param: `user_email`. Logic: (1) Get user's approval info. (2) If `approval_level` is None, return 403. (3) If level 1: query `work_orders` WHERE `signature_status = 'tech_signed'` AND `department_id` IN (user's technician_departments). (4) If level 2: query `work_orders` WHERE `signature_status = 'supervisor_approved'`. (5) Join with `work_order_assignments` and `users` to include assigned technician info. (6) Return list per contract in `specs/016-signature-approval-chain/contracts/api.md` "GET /work-orders/pending-approvals".

- [ ] T017 [US8] Create `frontend/lib/screens/approvals/pending_approvals_screen.dart`. This is a new StatefulWidget. (1) On init, call `GET /work-orders/pending-approvals?user_email=...`. (2) Display WOs as cards showing: job_no, title, department, assigned technician name, created date, signature_status. (3) Each card has "Approve" (green) and "Reject" (red) action buttons. (4) On approve: call `PATCH /work-orders/{id}/signatures/{sig_id}` with `{"status": "approved"}`, then remove the WO from the local list (setState). (5) On reject: show a dialog asking for rejection reason, then call PATCH with `{"status": "rejected", "rejection_reason": "..."}`, remove from list. (6) Empty state: show "No pending approvals" message. (7) Pull-to-refresh to reload the list. (8) Follow existing screen patterns (use `AppColors`, `GoogleFonts`, existing card styles from `work_order_home.dart`). Note: Before approve/reject, the screen needs the signature_id. Either: (a) fetch signatures for each WO to find the pending one, or (b) include signature_id in the pending-approvals endpoint response. Option (b) is simpler — extend T016 to include the latest pending signature ID in the response.

- [ ] T018 [US8] Register the Pending Approvals screen in navigation. (1) In `frontend/lib/models/nav_screen.dart`: add a new `NavScreen` entry to `NavScreenRegistry.all` list with `key: 'approvals'`, `title: 'Approvals'`, `subtitle: 'Pending approvals'`, `icon: Icons.approval_outlined`, `selectedIcon: Icons.approval_rounded`, `color: Color(0xFFD97706)` (amber), `bgColor: Color(0xFFFEF3C7)`. (2) In the `widgetForKey` switch, add `'approvals' => const PendingApprovalsScreen()`. (3) In `frontend/lib/screens/main_screen.dart`: update `_loadUserRole()` to also fetch the user's `approval_level` (add it to the `/user-role` response or make a separate call). Store it as `_approvalLevel`. (4) Update the `_canShow()` method or the nav building logic: the 'approvals' key should only be visible if `_approvalLevel != null` (user has an approval role). For admin, reporter, or technician without approval role, the "Approvals" item should not appear. (5) Also update `frontend/lib/screens/more_screen.dart` if it builds nav items from the registry — add the same `_approvalLevel != null` check for the 'approvals' key.

- [ ] T019 [US8] Update `backend/routers/users.py` — extend the `GET /user-role` endpoint response to include `approval_level`, `is_supervisor`, `is_superintendent` fields so the frontend can determine nav visibility without an extra API call.

**Checkpoint**: Pending Approvals screen works end-to-end. Review before proceeding.

---

## Phase 8: US7 — Step Progress Indicator on Work Order Detail (Priority: P3)

**Goal**: Visual step progress indicator showing the approval chain state on the WO detail screen.

**Independent Test**: View a WO at each chain stage. Verify correct steps shown as complete/pending/rejected.

### Implementation

- [ ] T020 [US7] Rewrite `_buildSignatureSection()` in `frontend/lib/screens/Work_Orders/add_work_order.dart`. This is a major rewrite of the existing signature UI (currently around lines 1250-1730). New design: (1) Define an ordered list of approval steps: `[{level: 0, role: 'technician', label: 'Technician'}, {level: 1, role: 'supervisor', label: 'Supervisor'}, {level: 2, role: 'superintendent', label: 'Superintendent'}]`. This list drives rendering — adding a future Manager level only requires adding an entry. (2) For each step, determine state from `signatureStatus` and the signatures list: if a signature record exists with matching `signer_role` and `status == 'approved'` → show as complete (green checkmark, signer name, date, signature image). If step matches the current required level → show as "current" (amber, "Awaiting [role]"). If step is after current → show as "pending" (grey). If any step has `status == 'rejected'` → show red badge with rejection reason. (3) Action buttons: only show approve/reject buttons if the current user's `approvalLevel` matches the step's level AND the WO's department is in the user's departments (for level 1). (4) For admin users: show all steps read-only, no action buttons (from T014). (5) For unassigned WOs (`assignedTechnician == null`): show "No technician assigned — contact admin" message, no signature actions. (6) Sign button for technician: only show if `signatureStatus == 'unsigned'` or `'rejected'`, and the current user is the assigned technician. (7) Use a `Stepper`-like layout or custom `Column` with connecting lines between steps. Style with existing `AppColors`.

- [ ] T021 [US7] Update single-technician assignment UI in `frontend/lib/screens/Work_Orders/add_work_order.dart`. Find the existing multi-technician checkbox UI (search for `assignedTechnicians` or checkbox-related widgets). Replace with: (1) A single `DropdownButtonFormField<String>` showing technicians filtered by the WO's department. (2) When creating a WO as a technician, auto-select the current user and disable the dropdown. (3) When creating as reporter/admin, show "Unassigned" as default with dropdown to select one technician. (4) On the edit screen, if admin changes the technician, show a confirmation dialog: "Changing the technician will reset the signature chain. Continue?" and call the backend update which handles chain reset (T007).

**Checkpoint**: Step progress indicator renders correctly at all chain stages. Single-tech UI works.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: PDF export update, documentation, and final integration

- [ ] T022 [P] Update PDF export to enforce signature_status check. In the backend PDF export endpoint (find in `backend/routers/reports.py` or `backend/routers/work_orders.py` — search for PDF/export), add a check: if WO's `signature_status != 'completed'`, return 403 "PDF export requires completed signature chain". In the PDF rendering: include signature blocks only for approval levels that have an 'approved' signature record (skip levels with no record). Each block shows signer name, date, and embedded signature image.

- [ ] T023 [P] Update the frontend PDF export button visibility. In `frontend/lib/screens/Work_Orders/add_work_order.dart`, find the export/PDF button and wrap it in a condition: only show if `signatureStatus == 'completed'`. For other statuses, either hide the button or show it disabled with tooltip "Signature chain must be completed before export".

- [ ] T024 [P] Update `AGENT.md` at repository root. Add a new section "## Approval Chain" after the existing "Notifications System" section. Document: (1) The approval chain flow: Technician -> Supervisor -> Superintendent -> Completed. (2) The `signature_status` field and valid values. (3) The `approval_level` column (1=supervisor, 2=superintendent, 3=reserved manager). (4) How to add a future Manager level (5 steps from spec). (5) Admin is excluded from the chain — 403 on approve/reject. (6) Department scoping for supervisors via `technician_departments`.

- [ ] T025 Run `specs/016-signature-approval-chain/quickstart.md` smoke test checklist. Verify all items pass. Log any failures for review.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 (migration must be applied first)
- **Phase 3 (Core Chain)**: Depends on Phase 2 — BLOCKS until helpers and models are ready
- **Phase 4 (Admin Role UI)**: Depends on Phase 2 (T006 approval-role endpoint) — can run in parallel with Phase 3
- **Phase 5 (Admin Exclusion)**: Depends on Phase 3 (T009 backend 403 already implemented)
- **Phase 6 (WO List Badges)**: Depends on Phase 3 (T011 bulk status endpoint)
- **Phase 7 (Pending Approvals)**: Depends on Phase 2 — can run in parallel with Phase 3
- **Phase 8 (Step Progress)**: Depends on Phase 3 (needs chain endpoints working)
- **Phase 9 (Polish)**: Depends on all previous phases

### User Story Dependencies

- **US1+US2+US3 (P1 Core Chain)**: Depends on Foundational only. No dependency on other stories.
- **US4 (Admin Role Management)**: Depends on Foundational (T006). Independent of US1-3.
- **US5 (WO List Badges)**: Depends on US1-3 (T011 bulk endpoint).
- **US6 (Admin Exclusion)**: Backend already in US1-3 (T009). Frontend (T014) can run after Phase 3.
- **US7 (Step Progress)**: Depends on US1-3 (chain must work to show progress).
- **US8 (Pending Approvals)**: Depends on Foundational. Can run in parallel with US1-3.

### Within Each Phase

- Tasks marked [P] can run in parallel
- Backend tasks before frontend tasks (within a story)
- Models before services before screens

### Parallel Opportunities

After Phase 2 (Foundational) completes, the following can run in parallel:
- **Stream A**: Phase 3 (Core Chain) → Phase 5 (Admin Exclusion) → Phase 6 (Badges)
- **Stream B**: Phase 4 (Admin Role UI)
- **Stream C**: Phase 7 (Pending Approvals — T016, T017, T018, T019)

Phase 8 and 9 run after streams converge.

---

## Parallel Example: Phase 2 (Foundational)

```
# These can all run in parallel (different files):
T002: Chain helpers in backend/routers/signatures.py
T003: User approval info helper in backend/routers/signatures.py  ← WAIT: same file as T002
T004: Frontend user model in frontend/lib/models/user.dart
T005: Frontend work order model in frontend/lib/models/work_order.dart
T006: Backend approval-role endpoint in backend/routers/users.py
T007: Backend single-tech assignment in backend/routers/work_orders.py

# Parallel groups:
Group 1 (parallel): T002 + T004 + T005 + T006 + T007
Group 2 (after T002): T003
```

---

## Implementation Strategy

### MVP First (US1+US2+US3 Only)

1. Complete Phase 1: Migration
2. Complete Phase 2: Foundational
3. Complete Phase 3: Core Approval Chain
4. **STOP AND REVIEW**: Claude reviews all backend + frontend changes
5. Manually test the full chain flow
6. Deploy if ready — this alone delivers the core value

### Incremental Delivery

1. Migration + Foundational → Foundation ready
2. Core Chain (US1+2+3) → Test → Deploy (MVP!)
3. Admin Role UI (US4) → Test → Deploy
4. Admin Exclusion (US6) + Badges (US5) → Test → Deploy
5. Pending Approvals (US8) → Test → Deploy
6. Step Progress (US7) → Test → Deploy
7. Polish (PDF, docs) → Final review → Deploy

### Review Workflow (Claude reviews OpenAI's work)

After each phase:
1. OpenAI implements the tasks
2. Claude reviews: code correctness, authorization logic, constitution compliance, edge cases
3. Issues flagged → OpenAI fixes → Claude re-reviews
4. Phase approved → proceed to next phase

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story
- Every task includes exact file paths for the implementing LLM
- Backend uses `supabase` Python client (not raw SQL) — follow existing patterns in the codebase
- Frontend uses `http` package for API calls — follow existing patterns in services/
- Do NOT commit `backend/version.json` from dev machine (see memory: feedback_backend_version_json.md)
- All chain transitions must be logged to `user_activity_log` via `log_activity()` in `backend/utils/activity.py`
- Rejected signatures are NEVER deleted — mark as 'rejected' and preserve
- Admin NEVER appears in signature chain notifications
