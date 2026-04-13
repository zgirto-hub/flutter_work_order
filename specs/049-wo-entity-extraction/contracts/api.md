# API Contracts: Work Order Entity Extraction

**Date**: 2026-04-13 | **Branch**: `049-wo-entity-extraction`

## Modified Endpoints

### POST /work-orders (modified)

**Change**: Adds background entity extraction after work order creation. No change to request/response schema.

**Behavior change**: After the work order is inserted and the response is sent, a background task extracts entities from the description text. The caller sees no difference.

---

### POST /work-orders/{work_order_id}/close (modified)

**Change**: Adds background entity extraction after work order closure. No change to request/response schema.

**Behavior change**: After the work order is closed and the response is sent, a background task extracts entities from the combined description + tech_notes. The caller sees no difference.

---

## New Endpoints

### POST /work-orders/extract-entities/{work_order_id}

**Auth**: Admin only  
**Description**: Manually trigger entity extraction for a specific work order.

**Path parameters**:
- `work_order_id` (uuid): The work order to extract entities from

**Query parameters**:
- `user_email` (string, required): Email of the admin user triggering extraction

**Response 200**:
```json
{
  "status": "extracted",
  "work_order_id": "uuid",
  "entities": {
    "equipment_id": "string",
    "equipment_type": "string | null",
    "fault_type": "string | null",
    "fault_code": "string | null",
    "action_taken": "string | null",
    "procedure_followed": "string | null",
    "parts_replaced": ["string"],
    "outcome": "string | null",
    "technician_id": "string | null",
    "date": "string | null"
  }
}
```

**Response 404**: `{"detail": "Work order not found"}`  
**Response 400**: `{"detail": "Extraction failed: <error details>"}`  
**Response 403**: `{"detail": "Admin access required"}`

---

### POST /work-orders/extract-entities/backfill

**Auth**: Admin only  
**Description**: Trigger bulk extraction for all work orders that have no entity records. Runs as a background task.

**Query parameters**:
- `user_email` (string, required): Email of the admin user triggering backfill

**Response 200** (immediate):
```json
{
  "status": "backfill_started",
  "total_pending": 42,
  "batch_size": 10,
  "message": "Processing 42 work orders in batches of 10"
}
```

**Response 403**: `{"detail": "Admin access required"}`

---

## Entity Extraction JSON Schema

The AI model is instructed to output this JSON structure:

```json
{
  "equipment_id": "string (required, non-empty)",
  "equipment_type": "string or null",
  "fault_type": "string or null",
  "fault_code": "string or null",
  "action_taken": "string or null",
  "procedure_followed": "string or null",
  "parts_replaced": ["string"] ,
  "outcome": "string or null",
  "technician_id": "string or null",
  "date": "string or null"
}
```

All field values MUST be in English regardless of input language.
