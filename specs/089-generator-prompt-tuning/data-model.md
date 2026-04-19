# Data Model: Spec 089 — Generator Prompt Tuning

**Spec**: [spec.md](./spec.md) | **Date**: 2026-04-19

Spec 089 introduces **no new entities, no schema changes, and no migrations**. This document exists to enumerate the existing tables the spec reads from (and explicitly does not write to) so implementers can reason about data dependencies at a glance.

---

## Read-only dependencies

### `validated_qa` (spec 048 / spec 083)

**Used by**: Few-shot example sourcing (spec 089 §5.2.1) at implementation time; *not* at runtime.

**Schema** ([supabase/migrations/20260413000000_create_feedback_loop.sql](../../supabase/migrations/20260413000000_create_feedback_loop.sql)):

| Column | Type | Role for spec 089 |
|---|---|---|
| `id` | UUID PK | Provenance (record chosen IDs in PR description) |
| `question_text` | TEXT | Becomes the few-shot `Q:` line |
| `validated_answer` | TEXT | Becomes the few-shot `A:` line (verbatim) |
| `thumbs_up_count` | INT | Ordering signal for selection (prefer highest net) |
| `thumbs_down_count` | INT | Subtract from thumbs_up_count to get net score |
| `is_reflagged` | BOOLEAN | **Exclude rows where `is_reflagged = TRUE`** |
| `created_at` | TIMESTAMPTZ | Tiebreaker — prefer most recent |

**Selection query** (to run at implementation time):

```sql
SELECT id, question_text, validated_answer,
       (thumbs_up_count - thumbs_down_count) AS net_score
FROM validated_qa
WHERE is_reflagged = FALSE
  AND validated_answer NOT ILIKE 'I don''t have that information%'
  AND validated_answer NOT ILIKE 'This information is not in%'
ORDER BY net_score DESC, created_at DESC
LIMIT 20;
```

Implementer then hand-picks 3 rows covering the three target patterns (terse-procedural, partial-info, paraphrased/alias-heavy) — see spec §5.2.1.

**Write operations**: NONE. Spec 089 does not insert, update, or delete `validated_qa` rows. Curation remains a user-driven workflow via the existing Train AI tab.

---

### `rag_diagnostic_log` (spec 088)

**Used by**: SC-007 post-run verification (spec 089 §6.4).

**Relevant columns for spec 089**:

| Column | Type | Role for spec 089 |
|---|---|---|
| `source` | TEXT | Filter `= 'test_suite'` |
| `reason_code` | TEXT | Filter/group — target bucket is `generator_refused_with_chunks` |
| `decision` | TEXT | Cross-check `= 'ungrounded'` when reason_code is a refusal bucket |
| `created_at` | TIMESTAMPTZ | Filter to post-run 2-hour window |

**Post-run SC-007 query**:

```sql
SELECT reason_code, COUNT(*) AS n
FROM rag_diagnostic_log
WHERE source = 'test_suite'
  AND created_at > now() - INTERVAL '2 hours'
GROUP BY reason_code
ORDER BY n DESC;
```

**Merge gate on result**: `generator_refused_with_chunks` bucket ≤ 15 (stretch ≤ 8).

**Write operations**: NONE directly by spec 089. Writes continue to happen via spec 088's fire-and-forget instrumentation during the test suite run — spec 089 is a read-side consumer of that signal.

---

### `app_settings` (spec 063)

**Used by**: `services.ai_providers.resolver` (existing dependency of DOCUMENT_QA_SYSTEM_PROMPT consumer).

**Relevant row**: `key = 'ai_provider'`.

**Role for spec 089**: The resolver returns whichever provider this row names; spec 089's prompt is model-neutral to accommodate any value here without re-tuning. No changes to this row or to the resolver itself.

**Write operations**: NONE.

---

## Entity changes

None.

## Migration changes

None.

## RLS changes

None.

## Indexes added

None.
