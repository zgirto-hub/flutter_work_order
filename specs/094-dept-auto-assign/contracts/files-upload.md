# Contract: `POST /api/files/upload` (modified)

## Change summary

Logic-only change. Multipart form fields are **unchanged**. Behavior diverges by caller role.

## Request (unchanged)

`multipart/form-data`:

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `file` | file | yes | |
| `title` | str | yes | |
| `file_type` | str | yes | |
| `is_private` | bool | no | default false |
| `uploaded_by` | str (email) | yes | authenticated user's email |
| `folder_id` | str (UUID) | no | |
| `expiration_date` | str (ISO date) | no | |
| `department_id` | str (UUID) | no | **For non-admin callers: ignored and overridden.** |

## Server behavior

```text
user = get_user_by_email(uploaded_by)
if user is None:
    return 404 "User not found"

is_admin = user.user_type == "admin"

if is_admin:
    # Existing logic — validate department_id if provided, else null/global.
    if department_id and department_id.strip():
        if not departments.exists(department_id): return 400 "Invalid department_id"
        record.department_id = department_id
else:
    # Non-admin — server substitutes the caller's own department.
    primary = user.department_id
    if primary is None:
        return 400 "User has no department assigned; contact your administrator."
    record.department_id = primary   # discards any client-supplied value
```

## Responses

| Status | When | Body |
|--------|------|------|
| 200 | Upload succeeds | `{ "success": true, "file_id": "<uuid>", "file_path": "/files/<name>" }` (unchanged) |
| 400 | Admin supplies invalid `department_id` | `{ "detail": "Invalid department_id" }` |
| 400 | Non-admin has no `users.department_id` | `{ "detail": "User has no department assigned; contact your administrator." }` |
| 404 | Unknown `uploaded_by` | `{ "detail": "User not found" }` |

## Activity log

Unchanged: one `file / uploaded` entry per upload. The logged `department_id` reflects the value actually persisted (i.e., the server-substituted value for non-admins).

## Back-compat

- Admin clients: byte-identical behavior.
- Non-admin clients sending `department_id` from a stale cache: value is silently ignored; no error.
- Existing rows: untouched.
