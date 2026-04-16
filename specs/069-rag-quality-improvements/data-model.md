# Data Model: RAG Quality Improvements

**Branch**: `069-rag-quality-improvements` | **Date**: 2026-04-16

## No Schema Changes

This feature makes **no database schema changes**. All modifications are in Python service code.

## Existing Entities Referenced

### validated_qa (read-only, no changes)

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| question_text | TEXT | Original question |
| validated_answer | TEXT | Expert-validated answer |
| question_embedding | VECTOR(768) | pgvector embedding for cosine search |
| equipment_type | TEXT | Optional equipment category |
| source_chunks | JSONB | Original source chunk references |
| validated_by | TEXT | Email of validator |
| validated_at | TIMESTAMPTZ | Validation timestamp |
| thumbs_up_count | INTEGER | Positive feedback count |
| thumbs_down_count | INTEGER | Negative feedback count |
| is_reflagged | BOOLEAN | Excluded from search when true |

### search_validated_qa RPC (existing, no changes)

- **Input**: `q_embedding VECTOR(768)`, `match_count INT DEFAULT 5`
- **Output**: Table of validated_qa rows + `distance FLOAT` (cosine distance via `<=>`)
- **Current usage**: Called with `match_count: 1`
- **New usage**: Called with `match_count: 3`

## New Runtime Data Structures (Python only)

### RAG Response Fields (additive to existing response dict)

| Field | Type | Condition |
|-------|------|-----------|
| confidence | string ("high"/"medium"/"low") | Always present on validated_qa path |
| score | float (2 decimal places) | Best match similarity score |
| sources | list[dict] | Up to 3 entries: `{id, question_text, score}` |

### Confidence Constants

| Constant | Value | Meaning |
|----------|-------|---------|
| RAG_CONFIDENCE_THRESHOLD | 0.70 | Minimum similarity to proceed to LLM |
| HIGH_CONFIDENCE | 0.85 | Score >= this → confidence: "high" |
