# Data Model: Department-scoped File Visibility

## Schema changes

### `files` — add `department_id`

```sql
ALTER TABLE files
  ADD COLUMN department_id UUID NULL REFERENCES departments(id) ON DELETE SET NULL;

CREATE INDEX idx_files_department_id
  ON files(department_id)
  WHERE department_id IS NOT NULL;
```

- **Nullability**: `NULL` = global (visible to everyone).
- **FK behavior**: `ON DELETE SET NULL` — deleting a department reverts its files to global (FR-015).
- **Index**: partial index on non-null rows; the global case uses `IS NULL` and benefits from PG's natural null-scan.
- **No backfill**: existing rows remain `NULL` (FR-010).

### `file_folders` — **not changed**

Folder scope is out of this release (clarification Q2, option C). `file_folders` retains its current schema.

### No changes to

- `departments` (already has `id`, `name`).
- `technician_departments` (already links users to departments, used for both technicians and supervisors per spec assumption).
- `users` (already has `user_type`, `is_supervisor`, `is_superintendent`).
- `resource_permissions` (already holds per-user file grants).

## Visibility rule (logical)

```
is_global_viewer(user) :=
    user.user_type = 'admin'
  OR user.is_supervisor = TRUE
  OR user.is_superintendent = TRUE

visible_files(user) :=
    IF is_global_viewer(user) THEN
      SELECT * FROM files
    ELSE
      SELECT * FROM files f
      WHERE f.department_id IS NULL
         OR f.department_id IN (
              SELECT department_id FROM technician_departments
              WHERE technician_id = user.id
            )
         OR f.id IN (
              SELECT resource_id FROM resource_permissions
              WHERE resource_type = 'file' AND user_email = user.email
            )
```

## Entity field additions (API surface)

### File (API response)

New fields in file objects returned to the client:

- `department_id: string | null` — UUID of the assigned department or `null` for global.
- `department_name: string | null` — pre-joined human name, or `null`. Backend joins `departments.name` on list/get responses so the frontend does not have to resolve IDs.

All other existing fields are unchanged.

### DepartmentsMineResponse (new)

```
{
  "departments": [{ "id": "<uuid>", "name": "<string>" }, ...],
  "is_global_viewer": true | false
}
```

## State transitions

None. `department_id` has no lifecycle — it is either unset, set, or moved to another value / back to null by an admin edit (FR-017). No workflow states, no audit of transitions beyond the activity log.

## Validation rules

- On upload: if `department_id` is provided, it MUST exist in `departments`; otherwise 400.
- On PATCH: same validation; additionally caller MUST be admin, else 403.
- On list/get: no validation — filter is applied silently; unauthorized direct fetch returns 403.

## Invariants

- A file with `department_id = NULL` is visible to every authenticated user.
- A file with `department_id = X` is visible to: global viewers; users in department X; users to whom the file is explicitly shared via `resource_permissions`.
- Deleting department X does not delete or hide files — they revert to global.
- Upload permission is independent of department (admin-only, unchanged).
