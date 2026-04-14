# API Contract: Systems

**Base path**: `/api`

---

## GET /systems

List systems, optionally filtered by active status.

**Query parameters**:

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| active_only | boolean | true | If true, return only `is_active=true` systems |
| needs_review | boolean | false | If true, return only `needs_review=true` systems |

**Response 200**:
```json
{
  "systems": [
    {
      "id": "uuid",
      "name": "CADAS-ATS",
      "category": null,
      "sort_order": 2,
      "is_active": true,
      "needs_review": false,
      "created_at": "2026-04-14T00:00:00Z",
      "updated_at": "2026-04-14T00:00:00Z"
    }
  ]
}
```

Ordered by `sort_order ASC`.

---

## POST /systems

Create a new system. **Admin only**.

**Request body**:
```json
{
  "name": "New System Name",
  "category": "Optional Category",
  "sort_order": 25
}
```

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| name | string | yes | Non-empty, unique (case-insensitive) |
| category | string | no | Free text |
| sort_order | integer | no | Defaults to max(sort_order) + 1 |

**Response 201**: Created system object.

**Response 409**: `{ "detail": "System name already exists" }`

---

## PATCH /systems/{id}

Update a system (rename, recategorize, reorder). **Admin only**.

**Request body** (all fields optional):
```json
{
  "name": "Renamed System",
  "category": "New Category",
  "sort_order": 5
}
```

**Response 200**: Updated system object.

**Response 404**: `{ "detail": "System not found" }`

**Response 409**: `{ "detail": "System name already exists" }` (if renaming to a duplicate)

---

## PATCH /systems/{id}/retire

Retire (soft-delete) a system. **Admin only**.

Sets `is_active = false`.

**Request body**: None.

**Response 200**:
```json
{
  "system": { "...updated system object..." },
  "warning": "System has 3 unresolved status reports"
}
```

The `warning` field is present only if the system has active (unresolved) status reports. The retirement proceeds regardless.

**Response 404**: `{ "detail": "System not found" }`

---

## PATCH /systems/{id}/activate

Re-activate a previously retired system. **Admin only**.

Sets `is_active = true`.

**Response 200**: Updated system object.

---

## Notes

- All mutation endpoints (POST, PATCH) require admin role.
- GET is available to all authenticated users.
- The `system_status.py` router's `get_today_status()` switches from iterating `ALLOWED_SYSTEMS` to querying `GET /systems?active_only=true` (or direct DB query internally).
- The `ai_insights.py` router's `_aggregate_system_status_stats()` similarly switches to DB query.
