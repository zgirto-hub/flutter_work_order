# API Contracts: Auto-Suggest Asset Registry Additions (055)

**Date**: 2026-04-14 | **Base path**: `/api/asset-registry`

All endpoints require `user_email` query parameter and admin access.

---

## GET /api/asset-registry/suggestions

Returns unregistered equipment_ids from pattern alerts that have 2+ alerts, excluding registered assets (case-insensitive) and dismissed suggestions.

**Query params**: `user_email` (required)

**Response 200**:
```json
{
  "suggestions": [
    {
      "equipment_id": "MUX system",
      "alert_count": 3,
      "fault_types": ["network", "performance"],
      "inferred_type": null
    },
    {
      "equipment_id": "CADAS-ATS mailbox",
      "alert_count": 2,
      "fault_types": ["software"],
      "inferred_type": "server"
    }
  ]
}
```

**Notes**:
- Results sorted by `alert_count` descending (most alerts first)
- `inferred_type` is the most common `equipment_type` from `work_order_entities` for that equipment_id, or `null` if no consistent type
- `fault_types` is a distinct list, not all occurrences

---

## POST /api/asset-registry/suggestions/dismiss

Dismiss an equipment_id so it no longer appears in suggestions.

**Query params**: `user_email` (required)

**Request body**:
```json
{
  "equipment_id": "AN816-12 fitting, return line section (aluminum 6061-T6, 3/4 OD)"
}
```

**Response 200**:
```json
{
  "dismissed": true
}
```

**Behavior**:
- Reads `system_settings` key `dismissed_asset_suggestions`
- If key doesn't exist, creates it with `[equipment_id]`
- If key exists, appends `equipment_id` to the JSON array (if not already present)
- Logs activity: `log_activity(user_email, "asset", "dismissed_suggestion", equipment_id)`

**Response 400**: `{"error": "missing_equipment_id", "detail": "equipment_id is required"}`
