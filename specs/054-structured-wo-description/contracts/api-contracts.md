# API Contracts: Structured Work Order Description Fields

**Branch**: `054-structured-wo-description` | **Date**: 2026-04-14

## New Endpoint: GET /asset-registry/asset-names

Returns a list of all registered asset names for autocomplete. No admin restriction.

**Request**:
```
GET /asset-registry/asset-names
```

No query parameters required. Any authenticated user can call this endpoint.

**Response** (200):
```json
{
  "names": ["Generator #1", "CADAS-ATS Primary", "Router SW-3F-01", ...]
}
```

**Error responses**:
- 401: Unauthenticated

---

## Modified Endpoint: POST /work-orders

Existing endpoint, extended with optional structured fields.

**Request body** (new fields shown, existing fields unchanged):
```json
{
  "job_no": "WO-2026-001",
  "title": "Generator maintenance",
  "description": "",
  "location": "Building A",
  "department_id": "uuid",
  "type": "Technical",
  "status": "Pending",
  "created_by": "uuid",
  "created_by_email": "tech@example.com",
  "assigned_technician_id": null,

  "asset_name": "Generator #3",
  "fault_description": "Oil leak from main seal",
  "action_taken": "Replaced seal and cleaned area",
  "outcome": "Resolved",
  "notes": "Optional notes in Arabic or English"
}
```

**Behavior**:
- If `asset_name`, `fault_description`, `action_taken`, and `outcome` are all present and non-empty → backend stitches them into the `description` field using the bracket-labeled format
- If any of the four structured fields are missing → falls back to `description` field as-is (backward compatibility)
- `notes` is optional; omitted from stitched string when empty
- `outcome` must be one of: `Resolved`, `Pending Parts`, `Escalated`, `Monitoring`

**Response**: Unchanged — returns the created work order with the stitched `description`.

---

## Stitched Format Contract

The stitched description stored in `work_orders.description` follows this format:

```
[Asset] <value>
[Fault] <value>
[Action] <value>
[Outcome] <value>
[Notes] <value>
```

- `[Notes]` line is omitted when notes are empty/null
- Detection: a description is "structured" if it starts with the literal string `[Asset] `
- Parsing regex: `^\[(\w+)\]\s*(.*)$` (per line, multiline mode)
