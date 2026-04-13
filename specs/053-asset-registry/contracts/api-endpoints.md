# API Contracts: Asset Registry (053)

**Date**: 2026-04-14 | **Base path**: `/api/asset-registry`

All endpoints require `user_email` query parameter. Admin-only endpoints return 403 if user is not admin.

---

## Assets

### GET /api/asset-registry/assets

List all assets with their system associations.

**Query params**: `user_email` (required)

**Response 200**:
```json
{
  "assets": [
    {
      "id": "uuid",
      "name": "WS-01",
      "type": "workstation",
      "location": "ACC Tower - Room 3",
      "notes": "Near window bay",
      "created_at": "2026-04-14T10:00:00Z",
      "updated_at": "2026-04-14T10:00:00Z",
      "system_links": [
        {"id": "uuid", "system": "CADAS-ATS", "role": "client"},
        {"id": "uuid", "system": "CADAS-IMS", "role": "client"}
      ]
    }
  ]
}
```

---

### POST /api/asset-registry/assets

Create a new asset.

**Query params**: `user_email` (required)

**Request body**:
```json
{
  "name": "WS-01",
  "type": "workstation",
  "location": "ACC Tower - Room 3",
  "notes": "Near window bay"
}
```

**Response 200**:
```json
{
  "asset": { "id": "uuid", "name": "WS-01", "type": "workstation", "location": "ACC Tower - Room 3", "notes": "Near window bay", "created_at": "...", "updated_at": "...", "system_links": [] }
}
```

**Response 409**: `{"error": "duplicate_name", "detail": "An asset with name 'WS-01' already exists"}`

**Response 400**: `{"error": "invalid_type", "detail": "Type must be one of: workstation, server, camera, router, switch, media_converter, power_adapter"}`

---

### PUT /api/asset-registry/assets/{asset_id}

Update an existing asset's fields.

**Query params**: `user_email` (required)

**Request body** (all optional):
```json
{
  "name": "WS-01-A",
  "type": "workstation",
  "location": "ACC Tower - Room 5",
  "notes": "Relocated"
}
```

**Response 200**: `{"asset": { ... updated asset with system_links ... }}`

**Response 404**: `{"error": "not_found", "detail": "Asset not found"}`

**Response 409**: `{"error": "duplicate_name", "detail": "An asset with name 'WS-01-A' already exists"}`

---

### DELETE /api/asset-registry/assets/{asset_id}

Delete an asset and all its system associations.

**Query params**: `user_email` (required)

**Response 200**: `{"deleted": true}`

**Response 404**: `{"error": "not_found", "detail": "Asset not found"}`

---

## System Links

### POST /api/asset-registry/assets/{asset_id}/links

Add a system association to an asset.

**Query params**: `user_email` (required)

**Request body**:
```json
{
  "system": "CADAS-ATS",
  "role": "primary"
}
```

**Response 200**:
```json
{
  "link": {"id": "uuid", "asset_id": "uuid", "system": "CADAS-ATS", "role": "primary", "created_at": "..."}
}
```

**Response 409 (duplicate)**: `{"error": "duplicate_link", "detail": "This asset is already linked to CADAS-ATS as primary"}`

**Response 409 (role taken)**: `{"error": "role_taken", "detail": "CADAS-ATS already has a primary server: SRV-CADAS-01"}`

**Response 400**: `{"error": "invalid_role", "detail": "Role must be one of: primary, standby, client"}`

---

### DELETE /api/asset-registry/links/{link_id}

Remove a specific system association.

**Query params**: `user_email` (required)

**Response 200**: `{"deleted": true}`

**Response 404**: `{"error": "not_found", "detail": "Link not found"}`

---

## Internal (no frontend exposure)

### GET /api/asset-registry/domain-knowledge

Returns the formatted domain knowledge text block for the extraction prompt. Used internally by `entity_extractor.py` (or called via direct function import).

**Response 200**:
```json
{
  "domain_knowledge": "DOMAIN KNOWLEDGE — Known assets and systems (from registry):\n- WS-01 (workstation, ACC Tower - Room 3): CADAS-ATS [client], CADAS-IMS [client]\n- SRV-CADAS-01 (server, Server Room A): CADAS-ATS [primary]\n..."
}
```

> **Note**: This endpoint may be implemented as a direct Python function call (`get_domain_knowledge_block()`) rather than an HTTP endpoint, since it's only consumed by the backend extraction service. The contract documents the data shape regardless of transport.
