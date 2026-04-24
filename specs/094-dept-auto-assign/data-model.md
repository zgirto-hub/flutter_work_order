# Data Model — 094-dept-auto-assign

**No schema changes.** This document describes the existing entities this feature relies on.

## Entities (existing, unchanged)

### `users`

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID (PK) | Supabase auth user id |
| `email` | text | Used as the current-user lookup key on all endpoints |
| `user_type` | text | One of `admin`, `technician`, `reporter`. **Admin check reads this field.** |
| `is_supervisor` | boolean | Defense-in-depth global-viewer flag (spec 092) — NOT used as an admin substitute here |
| `is_superintendent` | boolean | Defense-in-depth global-viewer flag (spec 092) — NOT used as an admin substitute here |
| `department_id` | UUID NULL | Primary single-department assignment. **Source of auto-assigned department for non-admin uploads.** |

### `departments`

Unchanged. Referenced via FK from `files.department_id`.

### `files`

| Field | Type | Notes |
|-------|------|-------|
| `department_id` | UUID NULL (FK → departments.id, ON DELETE SET NULL) | Added in spec 092. This spec sets it server-side for non-admin uploads. |

No new columns, no new indexes, no migrations.

## Derived values

### `is_admin` (computed server-side)

```python
is_admin = user.get("user_type") == "admin"
```

### `primary_department_id` (computed server-side)

```python
primary_department_id = user.get("department_id")   # may be None
```

## State transitions

None. A file's `department_id` is set once at upload; only admins may change it later via `PATCH /api/files/{file_id}/department` (spec 092, unchanged).

## Validation rules (server)

1. If `is_admin == false`:
   - Discard any client-supplied `department_id` form field.
   - Require `primary_department_id != None`; otherwise return HTTP 400.
   - Insert `files.department_id = primary_department_id`.
2. If `is_admin == true`:
   - Use client-supplied `department_id` as today (validate existence in `departments`; null → global).
