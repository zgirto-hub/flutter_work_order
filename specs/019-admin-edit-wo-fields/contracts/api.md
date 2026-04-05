# API Contract: Admin Edit WO Metadata Fields

**Branch**: `019-admin-edit-wo-fields` | **Date**: 2026-04-05

## Modified Endpoint: PUT /work-orders/{work_order_id}

### Request Changes

Three new **optional** fields added to `UpdateWorkOrderBody`:

```json
{
  "job_no": "WO-001",
  "title": "Fix broken pipe",
  "description": "...",
  "location": "Building A",
  "mobile_number": "555-1234",
  "department_id": "uuid",
  "type": "Technical",
  "status": "Closed",
  "assigned_technician_id": "uuid",
  "created_by": "uuid",
  "created_at": "2026-03-15T10:30:00Z",
  "closed_at": "2026-04-01T14:00:00Z"
}
```

| New Field | Type | Required | Constraints |
|-----------|------|----------|-------------|
| `created_by` | string (UUID) | No | Must reference an active user. Admin-only. |
| `created_at` | string (ISO 8601) | No | Must not be in the future. Admin-only. |
| `closed_at` | string (ISO 8601) | No | Must be >= created_at. Only valid when status = "Closed". Admin-only. |

### Authorization

- If any of the three fields are present and the caller is not an admin → **403 Forbidden**
- If none of the three fields are present → existing behavior unchanged (backward compatible)

### Validation Errors

| Condition | HTTP Status | Error Detail |
|-----------|-------------|-------------|
| Non-admin sends created_by/created_at/closed_at | 403 | "Admin access required to modify metadata fields" |
| created_by UUID not found or inactive | 400 | "Selected user not found or inactive" |
| created_at is in the future | 400 | "Created date cannot be in the future" |
| closed_at < created_at | 400 | "Closed date cannot be before created date" |
| closed_at sent when status != Closed | 400 | "Closed date can only be set on closed work orders" |

### Response

No change to response format. Returns **200 OK** with updated work order data.

### Side Effects

- When `created_by` is set: `created_by_email` and `created_by_name` are auto-populated from the user record.
- `updated_at` is set to current timestamp.
- `log_activity` fires with detail indicating which metadata fields changed.

## Existing Endpoint Used: GET /users

Already exists. Used by the frontend "Created By" picker to load all active users. No changes needed.

Query parameters available: `department_id`, `is_supervisor`, `is_superintendent`.
