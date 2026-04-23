# Contract: `PATCH /api/files/{file_id}/department`

**New endpoint.** Lets admin change a single existing file's department association (FR-017).

## Request

```
PATCH /api/files/<file_id>/department?user_email=<email>
Content-Type: application/json

{ "department_id": "<uuid|null>" }
```

- `user_email` (query, required): caller email; must resolve to a user with `user_type = 'admin'`.
- `department_id` (body): UUID or `null`. `null` / absent clears scope back to global.

## Behavior

- Lookup caller; if not admin, return `403`.
- If `department_id` is non-null, validate it exists in `departments`; otherwise `400`.
- Update `files.department_id` for `file_id`; if no such file, `404`.
- Read old `department_id` before the update for audit purposes.
- Fire `log_activity(user_email, "file", "updated", target_label=<file title>, target_id=<file_id>, detail=f"dept: {old} → {new}")`.

## Response — 200 OK

```json
{
  "status": "success",
  "file": {
    "id": "<uuid>",
    "department_id": "<uuid|null>",
    "department_name": "<string|null>"
  }
}
```

## Errors

- `400` — invalid `department_id`.
- `403` — caller is not admin.
- `404` — file not found.
