# Phase 1 Data Model — Thumbs-Down Reason & Comment

## Scope

Exactly one table is touched: `answer_ratings`. Two nullable columns are added. No new tables. No indexes required (these columns are not filtered on at query time — the Review tab reads all flagged rows and sorts in memory). No RLS or trigger changes.

---

## Table: `answer_ratings` (existing — diff only)

Existing schema from `supabase/migrations/20260413000000_create_feedback_loop.sql`:

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `id` | UUID | NO | Primary key, `gen_random_uuid()` default |
| `question_text` | TEXT | NO | |
| `answer_text` | TEXT | NO | |
| `source_chunks` | JSONB | NO | Default `'[]'` |
| `rating` | TEXT | NO | CHECK IN (`positive`, `negative`) |
| `review_status` | TEXT | YES | CHECK IN (`pending`, `approved`, `corrected`) |
| `rater_email` | TEXT | NO | |
| `manual_id` | UUID | YES | FK → `manuals(id)` ON DELETE SET NULL |
| `model_used` | TEXT | YES | |
| `session_summary` | TEXT | YES | |
| `created_at` | TIMESTAMPTZ | NO | Default `now()` |

### Added by this feature

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `feedback_reason` | TEXT | **YES** | CHECK IN (`inaccurate`, `incomplete`, `outdated`, `wrong_source`, `unclear`). NULL for thumbs-up, for skipped thumbs-down, and for all rows existing before this migration. |
| `feedback_comment` | TEXT | **YES** | Free-form user-supplied diagnostic note. Hard-capped at 2000 characters by the API validator (no CHECK LENGTH at DB level — trusting Pydantic + app-layer enforcement keeps the migration non-destructive against any edge-case legacy data). |

### Migration

File: `supabase/migrations/20260419000000_add_rating_feedback.sql`

```sql
-- Spec 087: thumbs-down reason and comment capture.
-- Adds two nullable columns to answer_ratings. Both stay NULL for:
--   * all existing rows (no backfill)
--   * all thumbs-up ratings
--   * thumbs-down ratings where the rater skipped the feedback prompt

ALTER TABLE answer_ratings
  ADD COLUMN IF NOT EXISTS feedback_reason TEXT
    CHECK (feedback_reason IN ('inaccurate', 'incomplete', 'outdated', 'wrong_source', 'unclear')),
  ADD COLUMN IF NOT EXISTS feedback_comment TEXT;
```

### Rollback

```sql
ALTER TABLE answer_ratings
  DROP COLUMN IF EXISTS feedback_reason,
  DROP COLUMN IF EXISTS feedback_comment;
```

Rollback is safe because:
- No code other than spec-087 code reads these columns.
- No downstream pipeline (RAG retrieval, From Real Usage suggestions, verified-answer promotion, reflag threshold) consumes them.
- Dropping the CHECK constraint with the column requires no separate migration step.

---

## State Transitions

The two new fields have a very simple lifecycle, tied strictly to the parent rating's lifecycle:

```text
[row just inserted by POST /manuals/rate-answer]
feedback_reason = NULL
feedback_comment = NULL
        |
        | PATCH /manuals/ratings/{id}/feedback (Save button)
        v
feedback_reason = <one of 5 values>
feedback_comment = <string or NULL>
        |
        | [no further transitions — one-shot per clarification Q2]
        v
[row deleted via DELETE /manuals/ratings/{id} on un-rate]
(reason & comment deleted with the row)
```

Key invariants:

- **Never orphaned**: both columns live on the row; row deletion removes them automatically.
- **One-shot**: after Save, the rater has no UI path to change the values (clarification Q2). A server-side retry or admin override is out of scope; the PATCH endpoint would accept a second call, but no client flow emits one.
- **Rating polarity invariant**: if `rating = 'positive'`, both feedback columns MUST remain NULL. The server enforces this in `save_rating()` (discards incoming values) and does not expose a PATCH path for positive ratings.

---

## Entity: Rating Feedback (logical view)

Strictly a logical construct — not a separate table. Represents the two new optional attributes on a thumbs-down rating row:

| Attribute | Type | Validation | Source of truth |
|---|---|---|---|
| Reason | One of 5 enum values | DB CHECK + Pydantic enum | `answer_ratings.feedback_reason` |
| Comment | Free text, 0–2000 chars | Pydantic `max_length=2000` | `answer_ratings.feedback_comment` |

Relationship: 1:1 with a negative `answer_ratings` row (identified by `rating_id`). Shares lifecycle with parent.

---

## Indexing

No new indexes. Rationale:

- The columns are not used as WHERE predicates in any query in scope.
- The Review tab's `get_flagged_answers()` selects all pending rows and the client renders them — no filtering by reason at query time.
- If a future spec adds "show only Outdated ratings this week," a partial index on `feedback_reason WHERE review_status = 'pending'` can be added then. YAGNI for now (constitution VII).

---

## Data Volume

- Existing `answer_ratings` volume: tens to low hundreds of rows per week (per project memory).
- Expected fill rate: only negative ratings, only when user does not dismiss — estimated 30–60 % of negatives will carry a reason.
- Storage impact: negligible. Postgres stores NULLs in 1-bit bitmap; populated rows add perhaps 50–200 bytes (reason enum + comment).

No scaling concerns introduced by this spec.
