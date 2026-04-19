# Phase 0 Research: Verified Answer Variants

## Overview

No true `NEEDS CLARIFICATION` items remained after `/speckit.clarify` (embedding-failure behavior and reconcile-match strategy were resolved). The research work below is small — it confirms the existing code patterns we plan to reuse so the plan accurately tracks them.

## R-1: Atomic multi-variant insert pattern

**Decision**: Reuse the "pre-compute all embeddings before any DB write" pattern already established in `backend/services/validated_qa_service.py::review_answer_multi` (lines ~629-673). Extend the same pattern to the reconcile operation.

**Rationale**: The existing code comments call out `FR-013 atomicity` — it was deliberately built so any embedding failure aborts the whole batch before the insert executes. The plan's FR-008a (atomic save on embedding failure) is already satisfied by this pattern. Using it avoids reinventing the safety invariant.

**Mechanics we will reuse**:
1. Build the target variant list.
2. For each variant needing an embedding (new or edited text), call `embed_single(text)` synchronously. If any call raises, the whole operation raises before any DB row is touched.
3. Only after all embeddings succeed, execute the DB writes (delete-then-insert batch within the same request).

**Alternatives considered**:
- Per-variant try/except with partial success — rejected: violates FR-008a (atomic save).
- Background job / async queue for embedding — rejected: adds infrastructure (worker, retry store) for a rarely-used admin operation; violates YAGNI (Principle VII).
- Postgres transaction wrapping the whole operation — nice-to-have; the Supabase Python client does not expose explicit transactions, and this operation's multi-step nature (delete + batch insert) is rare enough that last-write-wins at the HTTP level is acceptable (clarification Q-deferred).

## R-2: Reconcile algorithm for full-replace with text-based matching

**Decision**: Server-side, in-Python reconcile using normalized-text sets. No SQL UPSERT / MERGE; plain SELECT + DELETE + INSERT in the existing Supabase client style.

**Rationale**:
- Group sizes are small (1–20 rows). Python-side set ops cost microseconds and keep the code obvious.
- Consistent with how `delete_verified_answer` (cascade delete by `rating_id`) and `review_answer_multi` (batch insert) already work.
- Avoids Supabase RPC definition overhead for a low-frequency operation.

**Algorithm** (to be implemented in `validated_qa_service.reconcile_variants`):
```
fetch stored_rows = SELECT * FROM validated_qa WHERE rating_id = :rid
normalize(s) := s.strip().casefold()
submitted_norm = { normalize(t): t for t in submitted_texts }   # last-write-wins on duplicates
stored_by_norm = { normalize(r.question_text): r for r in stored_rows }

to_delete = [ r for norm, r in stored_by_norm.items() if norm not in submitted_norm ]
to_insert = [ original for norm, original in submitted_norm.items() if norm not in stored_by_norm ]
# (no "to_update" class: edits manifest as delete-old + insert-new, per clarification Q2)

# Phase 1 — compute all embeddings for to_insert (fail-fast)
embeddings = { text: await embed_single(text) for text in to_insert }

# Phase 2 — DB writes
if to_delete: DELETE WHERE id IN [r.id for r in to_delete]
if to_insert: INSERT rows with shared (rating_id, validated_answer, validated_by, manual_ids, source_chunks, validated_at)
```

**Alternatives considered**:
- Postgres `MERGE` — no dialect-portable advantage here; Supabase client doesn't abstract it.
- Supabase stored procedure (RPC) — hides the logic outside the Python service where tests live; rejected per YAGNI.

## R-3: Legacy `rating_id = NULL` backfill

**Decision**: At the top of `reconcile_variants`, if the target entry has `rating_id IS NULL`, assign a fresh synthetic UUID (`str(uuid.uuid4())`) and UPDATE that row before proceeding. Use the assigned id for all subsequent operations.

**Rationale**: Mirrors the existing pattern in `create_verified_answer` (line ~465: `synthetic_rating_id = str(_uuid.uuid4())`). The function comment there already documents the "synthetic `rating_id` groups primary + variants" design, so reusing it satisfies FR-009 with no new concept.

**Alternatives considered**:
- Blanket migration backfilling all legacy rows — rejected: unnecessary data churn; opportunistic backfill-on-edit is enough.
- Refuse to accept variants for legacy entries until migrated — rejected: breaks the admin UX for existing data.

## R-4: Frontend — visual distinction between "saved" and "new" chips in `variants_modal.dart`

**Decision**: Extend the existing `_VariantChip` with a `bool isSaved` flag (defaulted `false`). Saved chips use the current `surfaceContainerHighest` background plus a subtle leading `Icons.verified_outlined` badge (14 px, `green.shade700`). New chips use a slightly different neutral background (e.g. `surfaceContainer` with a dashed 1 px border) to signal "candidate, not yet persisted".

**Rationale**:
- Matches the UX from the brainstorm (admin at a glance can see what's in the DB vs what's a candidate).
- Reuses existing theme tokens; no new color variables.
- Keeps the "this field is editable TextField-in-chip" interaction unchanged — only the chrome differs.

**Alternatives considered**:
- Two separate widgets — rejected: duplicate code for a cosmetic difference.
- Tooltip-only distinction — rejected: not visible enough on a crowded modal.

## R-5: Paraphrase-failure notice banner

**Decision**: Reuse the existing `notice` parameter already defined on `showVariantsModal(...)` (line 8 of `variants_modal.dart`). When the paraphrase POST fails or times out, the calling code passes `notice: 'AI paraphrases are unavailable right now. You can still edit, add, or remove variants and save.'`.

**Rationale**: The notice infrastructure is already wired — orange banner with info icon at the top of the modal (lines 113-137 of `variants_modal.dart`). Zero new UI code needed.

**Alternatives considered**: A new full-screen error state — rejected: blocks the admin from performing manual variant management (User Story 3).

## R-6: Audit log payload for save

**Decision**: Single `log_activity` call per save:
- `user_email`: editor's email
- `category`: `"admin"`
- `action`: `"updated_verified_answer_variants"`
- `target_id`: the `qa_id` the admin clicked (the entry that anchored the modal)
- `target_label`: the original question text of that entry, truncated to 80 chars
- `detail`: `f"added={len(to_insert)}, removed={len(to_delete)}, final={len(final_set)}"`

**Rationale**: Matches the log-activity conventions already used for `create_verified_answer`, `delete_verified_answer`, `edited_verified_answer`. Satisfies Principle VI (Audit Everything) and spec FR-015.

**Alternatives considered**: One log entry per inserted/deleted row — rejected: noisy; the set-delta is the meaningful admin action.
