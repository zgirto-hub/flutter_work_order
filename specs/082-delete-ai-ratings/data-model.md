# Phase 1 Data Model — Delete Review/Rating from Ask-the-AI

No schema changes. This document captures the *effective* data model of the feature — which tables it reads and writes, the invariants it preserves, and the lifecycle of the rating row through each flow.

## Tables touched

### `answer_ratings` (existing)

Source of truth for a single technician's rating on an AI answer.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | Referenced by `rating_id` on the two new endpoints. |
| `question_text` | TEXT NOT NULL | Grouping key for bulk delete (combined with `answer_text`). |
| `answer_text` | TEXT NOT NULL | Grouping key for bulk delete. |
| `rating` | TEXT NOT NULL CHECK ∈ {`positive`, `negative`} | Determines which admin surface the rating flows into. |
| `review_status` | TEXT CHECK ∈ {`pending`, `approved`, `corrected`} | `pending` = flagged for admin review. |
| `rater_email` | TEXT NOT NULL | Authorization key for technician undo. |
| `created_at` | TIMESTAMPTZ | Unchanged. |

Writes performed by this feature: **DELETE** (single row or multiple rows matched by `question_text = $1 AND answer_text = $2`). No UPDATEs. No INSERTs.

### `validated_qa` (existing)

Verified-answer cache entries, possibly linked back to the rating that first surfaced them.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | Verified cache entry. Survives rating deletion. |
| `rating_id` | UUID NULLABLE | Already nullable (spec 059). FK dropped (spec 080 follow-up migration `20260418110000`). |
| *(all other columns)* | — | Untouched by this feature. |

Writes performed by this feature: **UPDATE** `SET rating_id = NULL WHERE rating_id = $1`, applied *before* the corresponding `answer_ratings` delete. No DELETEs on `validated_qa`. No INSERTs.

### `user_activity_log` (existing)

Append-only audit log used by `backend/utils/activity.py::log_activity`.

New `(category, action)` pairs emitted by this feature:

| category | action | target_label | detail |
|---|---|---|---|
| `manual` | `unrated_answer` | `question_text[:80]` | original `rating` value |
| `manual` | `admin_deleted_rating` | `question_text[:80]` | original `rater_email` |
| `manual` | `admin_bulk_deleted_ratings` | `question_text[:80]` | `count=<int>` |

All writes are fire-and-forget (constitution VI).

### `users` (existing)

Read-only for this feature — `_admin_check(user_email)` queries `user_type = 'admin'` to authorize admin surfaces. Unchanged otherwise.

## Invariants preserved

1. **Verified cache survives rating delete**. For every matched `answer_ratings.id`, any `validated_qa.rating_id` equal to it is first NULLed. The `validated_qa` row itself is never touched.
2. **Embedding search unaffected**. `search_validated_qa` RPC uses `question_embedding`; it does not read `rating_id`. Lookup semantics are unchanged.
3. **Authorization precedes side effects**. The endpoint rejects with `403` before any `UPDATE` or `DELETE` when the caller is neither the original rater nor an admin. The orphan-then-delete sequence runs only for authorized callers.
4. **Idempotency**. Deleting an already-missing row (single or bulk with no matches) is a successful no-op. The NULLing step is also idempotent (updates zero rows when nothing is linked).
5. **Fire-and-forget audit**. `log_activity` wraps every write in a `try/except`; its failure MUST NOT cancel the primary delete.

## Row lifecycle (per rating)

```
        +-------------------+  thumbs on chat  +-----------------+
        | (no row)          | ---------------> | pending review  |
        +-------------------+                  | or positive sig |
                                                +--------+--------+
                                                         |
                               +-------------------------+-------------------------+
                               |                         |                         |
                     admin "Approve"             admin "Correct"          any actor deletes
                               |                         |                         |
                               v                         v                         v
                     inserts validated_qa      inserts validated_qa        orphan linked
                     row with                   row with corrected          validated_qa
                     rating_id = this.id        answer_text                rating_id → NULL,
                               |                         |                 then DELETE row
                               v                         v                         |
                     (rating stays;                      |                         v
                     review_status=                      |                    (row gone;
                     approved)                           |                    validated_qa
                               |                         |                    intact if it
                               |                         |                    existed)
                               v                         v
                     rating may still be deleted later — same path:
                     orphan validated_qa.rating_id → NULL, then DELETE rating row.
```

The key observation: once a rating has been approved/corrected into `validated_qa`, deleting it is still allowed (per user clarification) and the cache entry remains available via embedding lookup.

## Sequence — single rating delete (authorized)

```
caller → DELETE /manuals/ratings/{id}?user_email=X
 backend: authorize (rater==X or admin)
 backend: UPDATE validated_qa SET rating_id = NULL WHERE rating_id = {id}
 backend: DELETE FROM answer_ratings WHERE id = {id} RETURNING id
         → if 0 rows: existed=false; else existed=true
 backend: log_activity(X, 'manual', 'unrated_answer'|'admin_deleted_rating', ...)
 backend: 200 {"status": "deleted", "existed": <bool>}
frontend: remove card locally; if was rating in chat, clear _selectedRating and _ratingId
```

## Sequence — bulk delete (admin)

```
caller → POST /manuals/ratings/bulk-delete?user_email=X
         body: {"question_text": "...", "answer_text": "..."}
 backend: _admin_check(X)  → 403 if not admin
 backend: SELECT id FROM answer_ratings WHERE question_text=$q AND answer_text=$a
 backend: UPDATE validated_qa SET rating_id = NULL WHERE rating_id = ANY($ids)
 backend: DELETE FROM answer_ratings WHERE id = ANY($ids)
 backend: log_activity(X, 'manual', 'admin_bulk_deleted_ratings',
                       target_label=q[:80], detail=f"count={N}")
 backend: 200 {"deleted_count": N}
frontend: remove suggestion card locally
```

## No migration artifact produced

See plan.md "Migration gap (full-stack ownership)" for the justification. Reviewers MUST verify:
- `supabase/migrations/20260415000000_make_rating_id_nullable.sql` exists and makes `rating_id` nullable.
- `supabase/migrations/20260418110000_drop_rating_id_fk.sql` exists and drops `validated_qa_rating_id_fkey`.

If either assumption changes in the future, this feature must be revisited.
