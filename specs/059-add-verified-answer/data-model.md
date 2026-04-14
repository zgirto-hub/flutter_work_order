# Data Model: Add Verified Answer — Manual Entry

**Date**: 2026-04-14
**Feature**: 059-add-verified-answer

## Entity: Verified Q&A Pair (`validated_qa`)

**Status**: Existing table — one schema change required.

### Schema Change

| Column      | Current          | After Migration            |
|-------------|------------------|----------------------------|
| `rating_id` | `UUID NOT NULL`  | `UUID` (nullable)          |

**Migration**: `20260415000000_make_rating_id_nullable.sql`

All other columns remain unchanged.

### Fields Used by This Feature

| Field                | Type            | Source                        | Notes                                      |
|----------------------|-----------------|-------------------------------|--------------------------------------------|
| `id`                 | UUID            | Auto-generated (DB default)   | Primary key                                |
| `question_text`      | TEXT            | Admin input (required)        | Non-empty after trim                       |
| `validated_answer`   | TEXT            | Admin input (required)        | Non-empty after trim                       |
| `question_embedding` | VECTOR(768)     | Computed via `embed_single()` | Formatted as `"[0.1,0.2,...]"` string      |
| `equipment_type`     | TEXT (nullable) | Auto-extracted from question  | Via `_extract_equipment_type()`            |
| `fault_code`         | TEXT (nullable) | Auto-extracted from question  | Via `_extract_fault_code()`                |
| `manual_ids`         | UUID[]          | Empty array `[]`              | No manual association for direct inserts   |
| `source_chunks`      | JSONB           | Empty array `[]`              | No source chunks for direct inserts        |
| `validated_by`       | TEXT            | Admin's email                 | From `editor_email` request field          |
| `rating_id`          | UUID (nullable) | `NULL`                        | No parent rating for direct inserts        |
| `validated_at`       | TIMESTAMPTZ     | DB default (`now()`)          | Auto-set                                   |
| `thumbs_up_count`    | INTEGER         | `0` (DB default)              | Auto-set                                   |
| `thumbs_down_count`  | INTEGER         | `0` (DB default)              | Auto-set                                   |
| `is_reflagged`       | BOOLEAN         | `FALSE` (DB default)          | Auto-set                                   |

### Validation Rules

- `question_text.strip()` must be non-empty
- `validated_answer.strip()` must be non-empty
- `question_embedding` must be exactly 768 dimensions
- `validated_by` must pass `_admin_check()` (existing helper)

### No State Transitions

Verified Q&A entries created via this feature have no lifecycle states. They are created as immediately active and searchable. Existing edit/delete/reflag operations apply unchanged.

### No New Relationships

The only relationship change is making `rating_id → answer_ratings(id)` optional (nullable FK). No new tables, no new foreign keys.
