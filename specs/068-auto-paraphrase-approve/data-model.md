# Data Model: Auto-Paraphrase on Admin Approve

**Feature**: 068-auto-paraphrase-approve
**Date**: 2026-04-16

## No schema changes

This feature deliberately introduces **no migrations**, no new tables, and no new columns. It exploits existing structure:

- `validated_qa.rating_id` is already nullable (migration `20260415000000_make_rating_id_nullable.sql`) and carries **no unique constraint** (verified in `20260413000000_create_feedback_loop.sql`). Multiple rows may share a `rating_id`.
- `validated_qa.question_embedding` is `vector(768)` and backed by an IVFFlat cosine index — each variant row populates its own vector; the index handles them independently.

## Logical entity shapes (existing tables, new usage)

### `validated_qa` row (unchanged schema, new usage pattern)

Per-variant unique fields:
- `id` (uuid, generated) — distinct per row
- `question_text` (text) — distinct per row (this is the whole point)
- `question_embedding` (vector(768)) — distinct per row (INV-1)

Shared across all variants produced from one approval session (INV-2):
- `validated_answer` (text)
- `validated_by` (text — reviewer email)
- `validated_at` (timestamptz)
- `rating_id` (uuid, nullable) — same value across all variants; this is how thumbs aggregate across phrasings without per-variant UI
- `manual_ids` (uuid[])
- `source_chunks` (jsonb)
- `equipment_type` (text, nullable) — re-extracted from the canonical question text (the original, not each variant) to keep filtering deterministic
- `fault_code` (text, nullable) — same rule as equipment_type

Per-row but initialised identically:
- `thumbs_up_count` (int, default 0)
- `thumbs_down_count` (int, default 0)
- `is_reflagged` (bool, default false)

### `answer_ratings` row (unchanged schema, unchanged usage)

- `review_status` transitions from `pending` → `approved` (or `corrected`) exactly once per approval session, regardless of how many validated_qa rows are inserted.
- No new columns.

## Invariant enforcement layer

| Invariant | Where enforced | How |
|---|---|---|
| INV-1: unique 768-dim embedding per row | `validated_qa_service.review_answer_multi` | Calls `ollama_embedder.embed_single(variant_text)` per variant; no reuse of prior embeddings |
| INV-2: one validated_answer across variants | `review_answer_multi` | Computed once from the answer_ratings row (or the corrected_answer arg) before the per-variant loop; each row's dict is deep-copied from a single base dict |
| INV-3: modal opens even on total provider failure | `/api/manuals/paraphrase-variants` endpoint | Exceptions from `resolver.generate` are caught; endpoint returns `{"variants": []}` with HTTP 200 |
| INV-4: read path untouched | `check_validated_match` | Function is not modified in this feature; direct/context similarity thresholds unchanged |
| INV-5: single-entry fallback preserved | Frontend modal + `review_answer_multi` | When variant list arrives empty or admin clears all chips except the original, Save All sends a single-element variant list → exactly one row inserted, matching pre-feature behaviour |

## State transitions

```text
answer_ratings.review_status
  pending --(approve/correct with variants)--> approved|corrected
                                                      |
                                                      v
                                     validated_qa: N rows inserted sharing rating_id
```

No re-transition path from approved → pending is introduced by this feature. Re-flag behaviour (existing spec 048) continues to operate on individual validated_qa rows via `is_reflagged`; if any variant is re-flagged, only that row flips back — other variants sharing the answer remain trusted. Admin then re-reviews that single variant row through the existing re-flag path.

## Relationships

```text
answer_ratings (1) ──── (0..N) validated_qa
                              (many rows share rating_id for variant sets)
```

Thumbs-up/thumbs-down on any variant row updates counts on every row sharing the same `rating_id` (see research.md R3). This is the shared-rating behaviour the feature requires.
