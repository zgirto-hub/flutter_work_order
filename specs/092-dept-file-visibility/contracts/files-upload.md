# Contract: `POST /api/files/upload` (modified)

Existing endpoint. Adds one optional multipart form field.

## Request (multipart form)

Existing fields unchanged:
- `file: UploadFile` (required)
- `title: str` (required)
- `file_type: str` (required)
- `is_private: bool = false`
- `uploaded_by: str` (required — caller email)
- `folder_id: str | None`
- `expiration_date: str | None`

**New field:**
- `department_id: str | None = None` — UUID. If provided, file is scoped to that department; if omitted/blank, file is global.

## Behavior

- If `department_id` is a non-empty string: validate it exists in `departments.id`; on mismatch, return `400 Bad Request`.
- If valid, include it in the `files.insert(...)` record.
- Upload remains admin-only (existing guard unchanged — currently relies on frontend gating; spec FR-014 preserves this).

## Response — 200 OK

```json
{ "status": "success", "file_url": "/files/<uuid>.<ext>" }
```

Unchanged shape.

## Errors

- `400` — invalid `department_id`.

## Activity log

Existing call:
```
log_activity(uploaded_by, "file", "uploaded",
             target_label=title, target_id=file_id, detail=file_type)
```
is extended: when `department_id` is present, include it in `detail` (e.g., `detail=f"{file_type} · dept={department_id}"`) or pass via a new dedicated key if the signature supports it. Implementer follows the existing `log_activity` utility convention.
