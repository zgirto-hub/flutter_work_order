# Contract: `GET /api/departments/mine`

**New endpoint.** Returns the caller's department scope for display on the Files screen and supplies the `is_global_viewer` flag (FR-011, FR-012).

## Request

```
GET /api/departments/mine?user_email=<email>
```

## Response — 200 OK

```json
{
  "departments": [
    { "id": "<uuid>", "name": "<string>" }
  ],
  "is_global_viewer": false
}
```

### Semantics

- **Global viewer** (`user_type = 'admin'` OR `is_supervisor` OR `is_superintendent`):
  - `is_global_viewer: true`
  - `departments`: empty array `[]`. Client MUST NOT render the scope label for these users (FR-012).
- **Scoped viewer** (technician / reporter without global flags):
  - `is_global_viewer: false`
  - `departments`: list of `{id, name}` rows joined from `technician_departments` → `departments`, for `technician_id = user.id`.
  - Empty list is valid (user not assigned to any department); client still renders the label (e.g., "Showing files for none") or suppresses it — implementer's call, follow existing UI patterns.

## Errors

- `400` — `user_email` missing.
- `404` — no user found.

## Client usage

`files_screen.dart` fetches once on screen init (alongside or in parallel with `FileService.fetchFiles()`) and uses the response to decide:

1. Whether to show the "Showing files for …" label (only when `is_global_viewer == false`).
2. What department names to list in the label.
