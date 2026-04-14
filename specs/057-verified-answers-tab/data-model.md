# Data Model: Verified Answers Admin Tab

## Entities

### validated_qa (existing — no changes)

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| question_text | TEXT | NOT NULL | Editable by admin (FR-002) |
| validated_answer | TEXT | NOT NULL | Editable by admin (FR-002) |
| question_embedding | VECTOR(768) | NOT NULL | Re-generated when question_text changes (FR-003) |
| equipment_type | TEXT | nullable | Re-extracted when question_text changes (FR-003) |
| fault_code | TEXT | nullable | Re-extracted when question_text changes (FR-003) |
| procedure_ref | TEXT | nullable | |
| manual_ids | UUID[] | DEFAULT '{}' | |
| source_chunks | JSONB | NOT NULL, DEFAULT '[]' | |
| validated_by | TEXT | NOT NULL | Original validator email |
| validated_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |
| thumbs_up_count | INTEGER | NOT NULL, DEFAULT 0 | Displayed on card |
| thumbs_down_count | INTEGER | NOT NULL, DEFAULT 0 | Displayed on card |
| is_reflagged | BOOLEAN | NOT NULL, DEFAULT FALSE | |
| rating_id | UUID | NOT NULL, FK → answer_ratings(id) | Used during delete to reset review_status |
| created_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |
| updated_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() | Updated on every edit (FR-005); used for sort order |

### answer_ratings (existing — affected by delete)

| Column | Type | Relevant to this feature |
|--------|------|--------------------------|
| id | UUID | PK, referenced by validated_qa.rating_id |
| review_status | TEXT | Reset to `'pending'` when linked validated_qa is deleted (FR-013) |

## Relationships

```
answer_ratings 1 ←── 1 validated_qa (via validated_qa.rating_id FK)
```

On delete of validated_qa row:
1. Hard-delete the validated_qa row
2. UPDATE answer_ratings SET review_status = 'pending' WHERE id = <rating_id>

## No migration required

All columns and tables already exist. No schema changes.
