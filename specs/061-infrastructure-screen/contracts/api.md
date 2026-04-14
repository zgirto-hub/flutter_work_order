# API Contracts — Infrastructure Screen

All endpoints require `Authorization: Bearer <JWT>` and admin user_type (existing `_admin_check`). Query param `user_email` is deprecated in favor of JWT-derived identity but may still be accepted by existing endpoints for compatibility.

---

## NEW: `GET /api/systems/{id}/detail`

Returns a system plus its asset links already grouped by site and role.

### Request
- Path param: `id` (uuid)

### Response (200 OK)

```json
{
  "system": {
    "id": "f0a1...",
    "name": "AIDA-NG",
    "category": null,
    "sort_order": 1,
    "is_active": true,
    "needs_review": false,
    "has_contingency": true,
    "created_at": "...",
    "updated_at": "..."
  },
  "production": {
    "primary": [
      { "link_id": "...", "asset": { "id": "...", "name": "as1-prod", "type": "server", "location": "Room A-12" } }
    ],
    "standby":  [ /* zero or one */ ],
    "client":   [ /* zero or more */ ]
  },
  "contingency": {
    "primary": [ ... ],
    "standby": [ ... ],
    "client":  [ ... ]
  }
}
```

Notes:
- `contingency` key is **omitted entirely** when `system.has_contingency` is false.
- `primary` and `standby` arrays contain **0 or 1** element each.
- `client` array is unbounded.
- Asset fields returned are the minimum needed for rendering: `id`, `name`, `type`, `location`.

### Error responses
- 401 — missing/invalid auth
- 403 — not admin (`{"error":"admin_required"}`)
- 404 — system not found

---

## MODIFIED: `PATCH /api/systems/{id}`

Existing endpoint gains a new accepted field.

### Request body (all fields optional, partial update)

```json
{
  "name": "AIDA-NG",
  "category": null,
  "sort_order": 1,
  "has_contingency": true
}
```

### Notes
- When `has_contingency` is being set from `true` → `false` and the system still has any `asset_system_links` with `site='contingency'`, the backend MUST reject with 409 and body:
  ```json
  { "error": "contingency_assets_exist", "count": 3 }
  ```
  Frontend uses `count` to populate the confirmation dialog (spec Q4). To actually perform the toggle-with-move, the client calls the new endpoint below.

---

## NEW: `POST /api/systems/{id}/disable-contingency`

Toggles `has_contingency` to false, moving existing contingency links to production in a single transaction; demotes role to `client` on conflict.

### Request (no body required)

### Response (200 OK)

```json
{
  "system": { ... },
  "moved": 3,
  "demoted": 1
}
```

- `moved`: count of links whose `site` changed from contingency → production.
- `demoted`: count of moved links whose `role` was changed to `client` due to uniqueness conflict.

### Errors
- 403 — not admin
- 404 — system not found
- 409 — system already has `has_contingency = false`

---

## MODIFIED: `POST /api/asset-registry/assets/{asset_id}/links`

Existing endpoint; accepts a new `site` field.

### Request body

```json
{
  "system_id": "...",
  "role": "primary",
  "site": "contingency"
}
```

- `site` is required. Valid values: `"production"`, `"contingency"`.
- If `site="contingency"` but the target system has `has_contingency=false`, return 400 `{"error":"system_has_no_contingency"}`.
- On uniqueness violation: 409 with body `{"error":"duplicate_primary"|"duplicate_standby"|"duplicate_link", "site":"..."}`.

### Response (201 Created)

```json
{ "link": { "id": "...", "asset_id": "...", "system_id": "...", "role": "primary", "site": "contingency", "created_at": "..." } }
```

---

## NEW: `PATCH /api/asset-registry/links/{link_id}`

Change role and/or site of an existing link.

### Request body (at least one of)

```json
{
  "role": "standby",
  "site": "contingency"
}
```

### Response (200 OK)

```json
{ "link": { ... } }
```

### Errors
- 404 — link not found
- 409 — change creates a uniqueness conflict (see spec Q5). Body:
  ```json
  { "error": "duplicate_link", "conflict_with_link_id": "..." }
  ```

---

## UNCHANGED endpoints (called by the new screen but not modified)

- `GET /api/systems?active_only=&needs_review=` — list systems for overview
- `POST /api/systems` — create system (admin)
- `PATCH /api/systems/{id}/retire` — retire
- `PATCH /api/systems/{id}/activate` — reactivate
- `GET /api/asset-registry/assets` — list for picking an existing asset in the sheet
- `POST /api/asset-registry/assets` — create new asset inline from the sheet
- `DELETE /api/asset-registry/assets/{id}` — delete asset (cascades links)
- `DELETE /api/asset-registry/links/{link_id}` — unlink (remove a single link)

---

## Behavioral contracts summary

| Operation | Enforces FR | Status code on violation |
|---|---|---|
| Add link with duplicate primary/standby | FR-009a/b | 409 |
| Add link with same (asset, system, site) | FR-009c / Q2 | 409 |
| Add link with site=contingency to no-contingency system | FR-006 | 400 |
| Change link site to an already-linked (asset, system, site) | Q5 / FR-010 | 409 |
| Toggle `has_contingency` off with existing contingency links | Q4 / FR-012 | 409 on PATCH; 200 on explicit `disable-contingency` |
| Retire system with unresolved reports | existing behavior | 200 with warning (preserved) |
