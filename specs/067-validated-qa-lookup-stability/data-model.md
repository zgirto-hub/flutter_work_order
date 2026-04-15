# Data Model: Validated-QA Lookup Stability

**Branch**: `067-validated-qa-lookup-stability`
**Date**: 2026-04-15

## Summary

**No new entities. No schema changes. No migrations.** This feature is a read-path change that reuses the existing `validated_qa` table and `search_validated_qa` RPC as-is.

## Existing entities referenced (unchanged)

### `validated_qa` (Supabase table)

Expert-verified question/answer pairs. Written by the thumbs-up / admin review flow (specs 048, 059). Read by this feature's new pre-rewrite lookup.

Relevant columns used by this feature (read-only):

| Column | Purpose |
|---|---|
| `id` | Primary key; returned in cache-hit response as `verified_source.validated_qa_id` |
| `question_embedding` | pgvector embedding of the validated question; used by `search_validated_qa` RPC |
| `validated_answer` | Cached answer text returned on hit |
| `validated_by`, `validated_at` | Attribution metadata returned on hit |
| `detected_system` (or equivalent scoping column) | Used by service-layer filter to reject cross-system matches |

### `search_validated_qa` (Supabase RPC)

Existing RPC performing cosine similarity search over `question_embedding`. Called by `validated_qa_service.check_validated_match`.

No changes to its signature or behavior.

## Transient data

The only new in-memory value introduced by this feature:

- **raw-question lookup result**: return value of `check_validated_match(question, detected_system=...)` on the pre-rewrite path. Same shape as the existing post-rewrite call. Not persisted.

## State transitions

None. The feature does not introduce or modify any state machine.
