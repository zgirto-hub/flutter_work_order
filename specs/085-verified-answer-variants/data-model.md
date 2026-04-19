# Phase 1 Data Model: Verified Answer Variants

## Overview

**No new tables. No migrations.** This feature operates entirely on the existing `validated_qa` table and its existing shared-`rating_id` grouping (spec 068). The model section below documents the invariants this feature adds to how those existing rows are manipulated.

## Existing entity: `validated_qa` (unchanged schema)

| Column | Type | Role in this feature |
|---|---|---|
| `id` | uuid PK | Identifies one variant row. |
| `question_text` | text | The phrasing stored for this variant. Reconcile matches by `strip().casefold()` of this value. |
| `validated_answer` | text | Shared across all variants in the same `rating_id` group (INV-2 from spec 068). This feature NEVER touches this column in the reconcile operation. |
| `rating_id` | uuid nullable | Groups sibling variants. If `NULL` on the target entry, the reconcile operation assigns a freshly generated UUID before proceeding (FR-009). |
| `question_embedding` | vector(768) | Regenerated on insert of any new variant text. Reconcile delete-old + insert-new pattern means edited variants get a fresh embedding for the new text (and the old embedding is dropped with the old row). |
| `validated_by` | text | Set to the editor's email on inserted variants. |
| `validated_at` | timestamptz | Set to save time on inserted variants. |
| `manual_ids` | uuid[] | Copied from an existing sibling (they all share). Empty array if the entry was manually created and has none. |
| `source_chunks` | jsonb | Copied from an existing sibling (all share). |
| `equipment_type` | text nullable | Re-extracted per-variant from the new text using existing `_extract_equipment_type`. |
| `fault_code` | text nullable | Re-extracted per-variant from the new text using existing `_extract_fault_code`. |
| `thumbs_up_count`, `thumbs_down_count` | int | Dropped when the variant is deleted (edit = delete+insert, clarification Q2). Per-variant metrics do not carry across an edit. |
| `is_reflagged` | bool | Copied from an existing sibling. |
| `updated_at` | timestamptz | Not touched by reconcile — that column tracks `update_verified_answer` edits of question/answer body, not variant-set changes. |

## Invariants this feature must preserve

- **INV-A**: All rows sharing a `rating_id` carry the same `validated_answer` text. Reconcile NEVER mutates this column; inserted variants copy the current value from the clicked entry.
- **INV-B**: All rows sharing a `rating_id` carry the same `manual_ids`, `source_chunks`, and `is_reflagged`. Inserted variants copy these from the clicked entry's sibling set.
- **INV-C**: After a successful reconcile, the set of rows with the target `rating_id` is exactly `{trimmed, casefolded} mapping of submitted texts`, preserving the admin's originally-cased strings as `question_text` (we keep the user's casing, only normalize for matching).
- **INV-D**: No two rows sharing a `rating_id` have `strip().casefold()`-equal `question_text`. Enforced at reconcile time (deduplication of the submitted list).
- **INV-E**: The variant set is never empty — at least one row with the target `rating_id` must exist after any save (FR-010). Enforced at the endpoint boundary (rejects submitted list shorter than 1 after dedup).

## Relationships

- `answer_ratings` ← `validated_qa.rating_id` (nullable, existing). This feature may set `rating_id` on a legacy row but never touches `answer_ratings` itself.
- No new FK relationships.

## State transitions

The reconcile operation is a single-step transformation:

```text
state_before: { row[i] | row[i].rating_id = :rid }
submitted:    [text_1, text_2, ..., text_n]   (1 ≤ n, each ≤ 500 chars)
state_after:  exactly n rows with .rating_id = :rid, one per normalized submitted text
```

Intermediate states during the operation (between DELETE and INSERT) are not exposed outside the service function; a server-side error during the write phase is raised to the endpoint, which surfaces it to the client as an HTTP 500/503. Because embeddings are all computed before any DB write, the most likely failure class (embedder timeout) fails without any row change (FR-008a).
