# Data Model: Work Order Entity Extraction

**Date**: 2026-04-13 | **Branch**: `049-wo-entity-extraction`

## Entities

### work_order_entities

Structured data extracted from work order free text by the AI model.

| Field | Type | Constraints | Description |
| ----- | ---- | ----------- | ----------- |
| work_order_id | uuid | PK, FK → work_orders.id, ON DELETE CASCADE | Source work order |
| equipment_id | text | NOT NULL | Identifier of the equipment involved |
| equipment_type | text | nullable | Category/type of equipment (e.g., "Generator", "HVAC Unit") |
| fault_type | text | nullable | Nature of the fault (e.g., "electrical", "mechanical") |
| fault_code | text | nullable | Standardized fault code if mentioned |
| action_taken | text | nullable | Description of the corrective action |
| procedure_followed | text | nullable | Maintenance procedure or manual reference |
| parts_replaced | text[] | nullable, default '{}' | Array of part names/numbers replaced |
| outcome | text | nullable | Result of the work (e.g., "resolved", "pending parts") |
| technician_id | text | nullable | Extracted technician identifier from text |
| date | text | nullable | Date referenced in the work order text |
| embedding | vector(768) | nullable | nomic-embed-text embedding for similarity search |
| extracted_at | timestamptz | NOT NULL, default now() | When extraction first ran |
| updated_at | timestamptz | NOT NULL, default now() | When extraction last updated |

**Relationships**:
- One-to-one with `work_orders` (work_order_id is both PK and FK)
- CASCADE delete: when a work order is deleted, its entities are deleted

**Indexes**:
- PK on work_order_id (implicit)
- ivfflat index on embedding column for similarity search (future use)

---

### extraction_failures

Log of failed entity extraction attempts for debugging and retry tracking.

| Field | Type | Constraints | Description |
| ----- | ---- | ----------- | ----------- |
| id | uuid | PK, default gen_random_uuid() | Unique failure record |
| work_order_id | uuid | FK → work_orders.id, ON DELETE CASCADE | Source work order |
| error_message | text | NOT NULL | Description of what went wrong |
| raw_response | text | nullable | The raw AI model response that failed to parse |
| attempt_number | int | NOT NULL, default 1 | Which attempt this failure represents (1 or 2) |
| created_at | timestamptz | NOT NULL, default now() | When the failure occurred |

**Relationships**:
- Many-to-one with `work_orders` (a work order can have multiple failure records over time)
- CASCADE delete: when a work order is deleted, its failure logs are deleted

**Indexes**:
- PK on id (implicit)
- Index on work_order_id for lookups

---

## State Transitions

Entity extraction has no explicit state machine. The lifecycle is:

1. **No record** → work order exists but has not been processed
2. **Record exists** → extraction succeeded; record is upserted on re-extraction
3. **Failure logged** → extraction failed; failure record persists for debugging

There is no "pending" or "in-progress" state — extraction is fire-and-forget with logging.

## Validation Rules

- `equipment_id` MUST be non-empty after extraction; if the AI returns empty equipment_id, the extraction is rejected and logged as a failure
- `parts_replaced` defaults to empty array `{}` if not mentioned in the text
- All other fields are nullable — partial extractions are acceptable
- `work_order_id` must reference an existing work order
