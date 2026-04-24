# Contract: `GET /api/departments/mine` (extended)

## Change summary

Response body gains two fields. Existing fields unchanged. Frontend consumers that only read the old fields continue to work.

## Request (unchanged)

`GET /api/departments/mine?user_email=<email>`

## Response (extended)

```json
{
  "departments": [
    { "id": "8ab1…", "name": "Maintenance" }
  ],
  "is_global_viewer": false,
  "is_admin": false,
  "primary_department_id": "8ab1…"
}
```

| Field | Type | Notes |
|-------|------|-------|
| `departments` | array | Existing. Union of `users.department_id` + `technician_departments` rows. |
| `is_global_viewer` | bool | Existing. `user_type == 'admin' OR is_supervisor OR is_superintendent`. |
| `is_admin` | bool | **NEW.** `user.user_type == 'admin'`. |
| `primary_department_id` | str \| null | **NEW.** The value of `users.department_id` for the caller (may be null). |

## Errors

| Status | When | Body |
|--------|------|------|
| 404 | Unknown `user_email` | `{ "detail": "User not found" }` |

## Client usage (upload form)

```dart
if (!mine.is_admin) {
  // hide department dropdown
  if (mine.primary_department_id == null) {
    // disable upload button, show advisory text
  }
}
```
