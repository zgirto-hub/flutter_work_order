# Data Model: Fix Work Order Disappears After Refresh

## Entities (no schema changes — clarification of existing relationships)

### Users

| Field | Type | Notes |
|-------|------|-------|
| id | UUID (PK) | Database user ID — used for all ownership references |
| auth_id | UUID (UNIQUE) | Supabase auth UUID — used only for authentication |
| email | TEXT (UNIQUE, NOT NULL) | Normalized lowercase email |
| full_name | TEXT | Display name |
| user_type | TEXT | 'admin', 'technician', 'reporter' |
| department_id | UUID (FK → departments) | User's department |

### Work Orders

| Field | Type | Notes |
|-------|------|-------|
| id | UUID (PK) | Work order identifier |
| created_by | UUID (FK → users.id) | **MUST be `users.id`, never `users.auth_id`** |
| department_id | UUID (FK → departments.id) | Department assignment |
| status | TEXT | 'Pending', 'In Progress', 'Resolved', 'Closed' |
| ... | ... | Other fields unchanged |

## Key Relationship

```
users.id (PK)  ←──  work_orders.created_by (FK)
users.auth_id  ←──  (authentication layer only, never stored in work_orders)
```

## Data Migration

**Purpose**: Repair existing `work_orders` rows where `created_by` contains an `auth_id` instead of `users.id`.

**Affected rows**: Any `work_orders` row where `created_by` value matches a `users.auth_id` but not `users.id`.

**Migration logic**:
1. JOIN `work_orders.created_by` = `users.auth_id::text`
2. UPDATE `work_orders.created_by` = `users.id`
3. Skip rows that cannot be matched (orphaned — log for manual review)

**Safety**: Idempotent. Only updates rows with auth_id mismatch. Already-correct rows untouched.

## Validation Rules (existing, no changes)

- `created_by` MUST reference a valid `users.id`
- `department_id` MUST reference a valid, active `departments.id`
- `email` in users table is normalized to lowercase with whitespace trimmed
