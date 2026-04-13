# Data Model: Feedback Loop AI Assistant

**Branch**: `048-feedback-loop-ai-assistant` | **Date**: 2026-04-13

## New Tables

### `answer_ratings`

Stores every technician rating (positive and negative) on AI-generated answers.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | Primary key |
| question_text | TEXT | NOT NULL | Original question asked |
| answer_text | TEXT | NOT NULL | AI-generated answer that was rated |
| source_chunks | JSONB | DEFAULT '[]' | Source chunks used (manual_title, source_page, content preview) |
| rating | TEXT | NOT NULL, CHECK IN ('positive', 'negative') | Thumbs up or down |
| review_status | TEXT | CHECK IN ('pending', 'approved', 'corrected'), DEFAULT NULL | NULL for positive ratings; 'pending' for negative; updated on review |
| rater_email | TEXT | NOT NULL | Email of the technician who rated |
| manual_id | UUID | NULLABLE, FK → manuals(id) | Manual context if single-manual query |
| model_used | TEXT | NULLABLE | AI model that generated the answer |
| session_summary | TEXT | NULLABLE | Session summary at time of rating |
| created_at | TIMESTAMPTZ | DEFAULT now() | When the rating was submitted |

**Indexes**:
- `idx_answer_ratings_review` on `(review_status, created_at DESC)` — powers the review queue query
- `idx_answer_ratings_rater` on `(rater_email)` — for per-user rating history

### `validated_qa`

Stores expert-approved question-answer pairs with embeddings for similarity search.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | Primary key |
| question_text | TEXT | NOT NULL | Original question |
| validated_answer | TEXT | NOT NULL | Approved or corrected answer |
| question_embedding | VECTOR(768) | NOT NULL | nomic-embed-text embedding of question_text |
| equipment_type | TEXT | NULLABLE | Extracted from question (e.g., "Boeing 737") |
| fault_code | TEXT | NULLABLE | Extracted fault/ATA code if present |
| procedure_ref | TEXT | NULLABLE | Referenced procedure name |
| manual_ids | UUID[] | DEFAULT '{}' | Manual IDs used as sources |
| source_chunks | JSONB | DEFAULT '[]' | Original source chunks for provenance |
| validated_by | TEXT | NOT NULL | Email of admin who validated |
| validated_at | TIMESTAMPTZ | DEFAULT now() | When validation occurred |
| thumbs_up_count | INTEGER | DEFAULT 0 | Cumulative positive ratings when served |
| thumbs_down_count | INTEGER | DEFAULT 0 | Cumulative negative ratings when served |
| is_reflagged | BOOLEAN | DEFAULT FALSE | True when thumbs_down exceeds 30% threshold (min 3 ratings) |
| rating_id | UUID | NOT NULL, FK → answer_ratings(id) | Link back to the original rating that triggered review |
| created_at | TIMESTAMPTZ | DEFAULT now() | Row creation time |
| updated_at | TIMESTAMPTZ | DEFAULT now() | Last update (re-validation resets this) |

**Indexes**:
- IVFFlat index on `question_embedding` with cosine ops (lists=10) — for similarity search
- `idx_validated_qa_reflagged` on `(is_reflagged)` WHERE `is_reflagged = TRUE` — partial index for re-flagged items

## RPC Function

### `search_validated_qa`

```sql
CREATE OR REPLACE FUNCTION search_validated_qa(
    q_embedding VECTOR(768),
    match_count INT DEFAULT 5
)
RETURNS TABLE (
    id UUID,
    question_text TEXT,
    validated_answer TEXT,
    equipment_type TEXT,
    source_chunks JSONB,
    validated_by TEXT,
    validated_at TIMESTAMPTZ,
    thumbs_up_count INTEGER,
    thumbs_down_count INTEGER,
    distance FLOAT
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        vq.id,
        vq.question_text,
        vq.validated_answer,
        vq.equipment_type,
        vq.source_chunks,
        vq.validated_by,
        vq.validated_at,
        vq.thumbs_up_count,
        vq.thumbs_down_count,
        (vq.question_embedding <=> q_embedding) AS distance
    FROM validated_qa vq
    WHERE vq.is_reflagged = FALSE
    ORDER BY vq.question_embedding <=> q_embedding
    LIMIT match_count;
END;
$$;
```

**Note**: Distance is cosine distance (0 = identical, 2 = opposite). Similarity = 1 - distance. Threshold mapping:
- distance <= 0.10 → similarity >= 0.90 → direct return
- distance <= 0.25 → similarity >= 0.75 → high-priority context

## State Transitions

### Answer Rating Lifecycle

```
[AI Answer Generated] → (technician taps thumbs-up) → answer_ratings row (rating='positive', review_status=NULL)
[AI Answer Generated] → (technician taps thumbs-down) → answer_ratings row (rating='negative', review_status='pending')
```

### Flagged Answer Review Lifecycle

```
[pending] → (admin approves) → review_status='approved' → validated_qa row created
[pending] → (admin corrects) → review_status='corrected' → validated_qa row created with corrected answer
```

### Validated QA Re-flagging Lifecycle

```
[active] → (served & rated, thumbs_down > 30% with min 3 total) → is_reflagged=TRUE
[is_reflagged=TRUE] → (admin re-reviews) → updated in place, counts reset, is_reflagged=FALSE
```

## Relationships

```
answer_ratings.rater_email → users.email (logical, not FK — follows existing pattern)
validated_qa.rating_id → answer_ratings.id (FK)
validated_qa.manual_ids → manuals.id (logical array reference)
validated_qa.validated_by → users.email (logical, not FK)
```
