# Data Model: Admin Edit WO Metadata Fields

**Branch**: `019-admin-edit-wo-fields` | **Date**: 2026-04-05

## Existing Entities (No Schema Changes)

No database migrations are needed. All fields already exist in the `work_orders` table.

### Work Order (`work_orders` table)

| Field | Type | Editable by Admin | Notes |
|-------|------|-------------------|-------|
| `created_by` | UUID | Yes (new) | References `users.id` |
| `created_by_email` | text | Yes (new, auto-set) | Derived from selected user's email |
| `created_by_name` | text | Yes (new, auto-set) | Derived from selected user's full_name |
| `created_at` | timestamptz | Yes (new) | Must not be in the future |
| `closed_at` | timestamptz | Yes (new) | Must be >= created_at; only when status = "Closed" |
| `closed_by` | UUID | No change | Not part of this feature |
| `updated_at` | timestamptz | Auto-set | Updated on any modification |

### User (`users` table)

| Field | Type | Used For |
|-------|------|----------|
| `id` | UUID | Selected as new `created_by` value |
| `email` | text | Auto-populated into `created_by_email` |
| `full_name` | text | Auto-populated into `created_by_name` |
| `user_type` | text | Authorization check (must be "admin" to edit) |
| `is_active` | boolean | Filter: only active users appear in picker |

## Validation Rules

| Rule | Scope | Implementation |
|------|-------|----------------|
| `created_at <= now()` | Backend + Frontend | Reject future dates |
| `closed_at >= created_at` | Backend + Frontend | Cross-field validation |
| `created_by` must exist in `users` | Backend | UUID lookup before update |
| `created_by` user must be active | Backend | Check `is_active = true` |
| Only admin can set these fields | Backend | `user_type == 'admin'` check |

## State Transitions

No new state transitions introduced. The `closed_at` field is only editable when the work order's `status` is already "Closed". Reopening a work order (status change from Closed to another status) clears `closed_at` per existing behavior — this feature does not alter that flow.
