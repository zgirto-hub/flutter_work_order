# Data Model: 016-signature-approval-chain

## Schema Changes

### Table: `users` (ALTER)

| Column | Type | Default | Constraint | Notes |
|--------|------|---------|------------|-------|
| `is_supervisor` | BOOLEAN | `false` | — | Additive flag, does not replace `user_type` |
| `is_superintendent` | BOOLEAN | `false` | — | Additive flag |
| `approval_level` | INTEGER | `NULL` | CHECK (approval_level IN (1, 2, 3)) | NULL = no approval authority, 1 = supervisor, 2 = superintendent, 3 = reserved (manager) |

**Constraints**:
- `is_supervisor = true` IFF `approval_level = 1`
- `is_superintendent = true` IFF `approval_level = 2`
- A user can have only one approval level at a time
- Enforced via application logic (backend sets all three atomically)

### Table: `work_orders` (ALTER)

| Column | Type | Default | Constraint | Notes |
|--------|------|---------|------------|-------|
| `signature_status` | TEXT | `'unsigned'` | CHECK (signature_status IN ('unsigned', 'tech_signed', 'supervisor_approved', 'superintendent_approved', 'completed', 'rejected')) | Single source of truth for chain state |

### Table: `work_order_signatures` (ALTER)

| Change | Details |
|--------|---------|
| `signer_role` CHECK | Extend to `('technician', 'supervisor', 'superintendent')`. Drop `'admin'` for new records. Existing `'admin'` records preserved. |

**Migration approach**: Drop and recreate the CHECK constraint. Existing `signer_role = 'admin'` records remain — they represent historical data from the previous workflow.

### Table: `work_order_assignments` (ALTER)

| Change | Details |
|--------|---------|
| Add UNIQUE constraint | `UNIQUE(work_order_id)` — enforces single technician per WO |
| Migration cleanup | For WOs with multiple assignments: keep earliest `assigned_at`, delete extras |

## Entity Relationships

```
users
  ├── 1:N → work_order_signatures (signer_email)
  ├── 1:N → work_order_assignments (technician_id) — NOW 1:1 per WO
  └── N:M → technician_departments (technician_id ↔ department_id)
           ↑ Reused for supervisor department scope

work_orders
  ├── 1:N → work_order_signatures (work_order_id)
  ├── 1:1 → work_order_assignments (work_order_id) — CHANGED from 1:N
  └── N:1 → departments (department_id)

work_order_signatures
  └── Each record: who signed/approved/rejected, role, image, status, reason, timestamp
      Status: 'pending' | 'approved' | 'rejected'
      Rejected records preserved for audit (never deleted)
```

## State Machine: `work_orders.signature_status`

```
                  ┌─────────────────────────────────────┐
                  │                                     │
                  ▼                                     │
 [unsigned] ──tech signs──▶ [tech_signed] ──supervisor──▶ [supervisor_approved]
     ▲                          │                              │
     │                          │ (reject)                     │ (reject)
     │                          ▼                              ▼
     │                     [rejected] ◀─────────────────  [rejected]
     │                          │
     │                     tech re-signs
     │                          │
     └──── re-assignment ───────┘
                                                               │
                                              superintendent   │
                                              approves         │
                                                               ▼
                                                        [completed]
                                                    (PDF export unlocked)
```

**Level skip logic**: If no approvers exist at a level, skip to next. If no approvers at any remaining level AND both levels are missing → block (show warning). If only one level is missing → skip and log warning.

## Approval Level Resolver

```
_get_required_approval_level(signature_status) → int:
    'tech_signed'              → 1  (needs supervisor)
    'supervisor_approved'      → 2  (needs superintendent)
    'superintendent_approved'  → 3  (needs manager — reserved, returns [] approvers)

_get_approvers_for_level(level, department_id) → List[user]:
    level 1: users WHERE is_supervisor=true AND id IN (
                SELECT technician_id FROM technician_departments WHERE department_id = ?)
    level 2: users WHERE is_superintendent=true
    level 3: [] (reserved for future)

_advance_chain(work_order_id, current_status) → new_status:
    1. Get required level from current_status
    2. Get approvers for that level
    3. If approvers exist → return current status (wait for approval)
    4. If no approvers → try next level
    5. If no approvers at any remaining level → 'completed' (if at least one level was present) OR block (if all missing)
    6. Log skipped levels to user_activity_log
```

## Frontend Model Changes

### AppUser (user.dart)

New fields:
- `bool isSupervisor` (default: false)
- `bool isSuperintendent` (default: false)
- `int? approvalLevel` (default: null)

Parse from JSON: `is_supervisor`, `is_superintendent`, `approval_level`

### WorkOrder (work_order.dart)

New fields:
- `String signatureStatus` (default: 'unsigned')

Change: `List<TechnicianAssignment> assignedTechnicians` → `TechnicianAssignment? assignedTechnician` (single)

### NavScreenRegistry (nav_screen.dart)

New entry:
- key: `'approvals'`, title: `'Approvals'`, icon: `Icons.approval_outlined`
- `widgetForKey` maps to `PendingApprovalsScreen`
- Visibility controlled by `approvalLevel != null` in `MainScreen`
