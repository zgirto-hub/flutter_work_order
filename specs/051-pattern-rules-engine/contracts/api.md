# API Contracts: Pattern Rules Engine

**Date**: 2026-04-13 | **Prefix**: `/api/patterns`

All endpoints require `Authorization: Bearer <jwt>`. Admin-only endpoints return 403 for non-admin users.

---

## Rules Endpoints

### GET /api/patterns/rules

List all pattern rules.

**Response 200**:
```json
{
  "rules": [
    {
      "id": "uuid",
      "name": "Recurring fault threshold",
      "description": "Same fault on same equipment 3+ times in 6 months",
      "severity": "high",
      "detection_type": "recurring_fault",
      "threshold_count": 3,
      "threshold_days": 180,
      "target_field": "equipment_id",
      "group_by_field": null,
      "enabled": true,
      "is_built_in": true,
      "created_at": "2026-04-13T10:00:00Z",
      "updated_at": "2026-04-13T10:00:00Z"
    }
  ]
}
```

---

### POST /api/patterns/rules

Create a new pattern rule. **Admin only.**

**Request body**:
```json
{
  "name": "Custom recurring by type",
  "description": "Same fault on same equipment type 5+ times in 90 days",
  "severity": "medium",
  "detection_type": "recurring_fault",
  "threshold_count": 5,
  "threshold_days": 90,
  "target_field": "equipment_type",
  "group_by_field": null,
  "enabled": true
}
```

**Response 201**: Created rule object (same shape as GET list item).

**Response 400**: Validation error (missing name, invalid severity, invalid detection_type, threshold < 1).

**Response 403**: Non-admin user.

---

### PUT /api/patterns/rules/{rule_id}

Update an existing rule. **Admin only.**

**Request body**: Same shape as POST (all fields optional — partial update).

**Response 200**: Updated rule object.

**Response 404**: Rule not found.

---

### DELETE /api/patterns/rules/{rule_id}

Delete a rule. **Admin only.** Cascades to delete associated alerts.

**Response 200**: `{"deleted": true}`

**Response 404**: Rule not found.

---

### PATCH /api/patterns/rules/{rule_id}/toggle

Toggle rule enabled/disabled. **Admin only.**

**Response 200**: Updated rule object with toggled `enabled` field.

**Response 404**: Rule not found.

---

## Alerts Endpoints

### GET /api/patterns/alerts

List pattern alerts with optional filters. **Admin only.**

**Query parameters**:
- `status` (optional): `new`, `acknowledged`, `resolved`
- `severity` (optional): `low`, `medium`, `high`
- `page` (optional, default 1): Page number
- `page_size` (optional, default 20): Items per page

**Response 200**:
```json
{
  "alerts": [
    {
      "id": "uuid",
      "rule_id": "uuid",
      "rule_name": "Recurring fault threshold",
      "work_order_ids": ["uuid1", "uuid2", "uuid3"],
      "equipment_id": "ENG-001",
      "fault_type": "oil_leak",
      "technician_id": null,
      "severity": "high",
      "status": "new",
      "message": "Equipment ENG-001 has had 3 'oil_leak' faults in the last 180 days — replacement may be mandatory per manual rule.",
      "detected_at": "2026-04-13T14:30:00Z",
      "updated_at": "2026-04-13T14:30:00Z"
    }
  ],
  "total": 42,
  "page": 1,
  "page_size": 20
}
```

---

### PATCH /api/patterns/alerts/{alert_id}/status

Update alert status. **Admin only.** Enforces transition rules: new→acknowledged, acknowledged→resolved.

**Request body**:
```json
{
  "status": "acknowledged"
}
```

**Response 200**: Updated alert object.

**Response 400**: Invalid status transition (e.g., resolved→new, new→resolved).

**Response 404**: Alert not found.

---

## Scan Endpoint

### POST /api/patterns/scan

Trigger a full scan of all active rules against all entities. **Admin only.** Deduplicates by `rule_id + equipment_id + fault_type + YYYY-MM`.

**Response 200**:
```json
{
  "rules_evaluated": 6,
  "alerts_created": 12,
  "alerts_skipped_duplicate": 3,
  "duration_seconds": 4.2
}
```
