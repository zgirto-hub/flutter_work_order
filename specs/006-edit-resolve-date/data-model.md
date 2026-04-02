# Data Model: Edit Resolve Date

## Existing Entity: `system_status_reports`

No schema changes required. The existing table already has all necessary columns.

| Field | Type | Nullable | Change |
|-------|------|----------|--------|
| id | UUID | No | — |
| system_name | Text | No | — |
| report_date | Date (YYYY-MM-DD) | No | — |
| notes | Text | No | — |
| reported_by | Text | No | — |
| reported_by_name | Text | No | — |
| created_at | Timestamp | No | — |
| resolved_at | Timestamp | Yes | **Now user-editable** (was server-only) |
| resolved_by | Text | Yes | — |
| resolved_notes | Text | Yes | — |

## Validation Rules

| Rule | Enforcement |
|------|-------------|
| `resolved_at` >= `report_date` | Backend (400 error) |
| `resolved_at` <= today | Backend (400 error) |
| `resolved_at` edit only on resolved issues | Backend (400 error if `resolved_at` is null) |
| `resolved_at` cannot be cleared/set to null | Backend (ignores null value in update) |

## State Transitions

```
Unresolved Issue ──[resolve]──> Resolved Issue
                                    │
                                    ├──[edit resolved_at]──> Resolved Issue (updated date)
                                    └──[edit notes/report_date]──> Resolved Issue (updated fields)
```

No new states introduced. The `isResolved` computed property (`resolved_at != null`) remains unchanged.
