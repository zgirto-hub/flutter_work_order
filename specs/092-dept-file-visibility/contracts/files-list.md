# Contract: `GET /api/files/list`

**New endpoint.** Replaces the Flutter client's direct `supabase.from('files').select(...)` call so the visibility filter is enforceable server-side.

## Request

```
GET /api/files/list?user_email=<email>
```

- `user_email` (query, required): caller's email. Used to look up `users.id`, role, `is_supervisor`, `is_superintendent`, and membership in `technician_departments`, and to match `resource_permissions.user_email`.

## Response — 200 OK

```json
{
  "files": [
    {
      "id": "<uuid>",
      "title": "<string>",
      "file_type": "<string>",
      "file_name": "<string>",
      "file_extension": "<string>",
      "mime_type": "<string>",
      "file_path": "/files/<uuid>.<ext>",
      "is_private": false,
      "uploaded_by": "<email>",
      "folder_id": "<uuid|null>",
      "expiration_date": "<iso8601|null>",
      "file_size": 12345,
      "created_at": "<iso8601>",
      "department_id": "<uuid|null>",
      "department_name": "<string|null>"
    }
  ]
}
```

## Filter semantics

- **Global viewer** (`user_type = 'admin'` OR `is_supervisor` OR `is_superintendent`): returns all files, no filter.
- **Scoped viewer** (technician / reporter without global flags): returns only files where
  - `department_id IS NULL`, OR
  - `department_id ∈ technician_departments.department_id` for `technician_id = user.id`, OR
  - `id ∈ resource_permissions.resource_id` where `resource_type = 'file'` and `user_email = caller email`.
- The existing `is_private` + `uploaded_by` logic (from the current Supabase-direct query) is preserved: a private file is visible only to its uploader, to explicitly shared users, or to global viewers.
- `department_name` is joined from `departments.name` server-side.

## Errors

- `400` — `user_email` missing.
- `404` — no user found for that email.

## Activity log

None (listing is not logged, consistent with current behavior).

## Frontend impact

`FileService.fetchFiles()` replaces its Supabase query with an `http.get` to this endpoint. No change to card/list widgets apart from optionally rendering the new `department_name`.
