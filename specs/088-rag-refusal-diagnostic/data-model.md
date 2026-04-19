# Phase 1 Data Model: RAG Refusal Diagnostic Logging

**Feature**: 088-rag-refusal-diagnostic | **Date**: 2026-04-19

## Scope

One new table. No changes to existing tables. Existing `user_activity_log` is written to per diagnostic entry (category `manual`, action `rag_diagnostic_logged`) as a short heartbeat for the constitutional audit trail — no schema change required there.

---

## Entity: Diagnostic Entry → table `rag_diagnostic_log`

One row per `/api/manuals/ask` request, including trivial short-circuits and pipeline errors. Written via background task; failures are never surfaced to the user.

### Columns

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| `id` | `uuid` | NOT NULL | `gen_random_uuid()` | Primary key. Used as cross-reference from `user_activity_log` heartbeat. |
| `created_at` | `timestamptz` | NOT NULL | `now()` | Request start time (server clock). |
| `user_email` | `text` | NOT NULL | — | Requester. For `source='test_suite'` this is `test@quality-check.local`; still recorded for audit. |
| `source` | `text` | NOT NULL | `'user'` | Enum: `user` \| `test_suite` \| `internal`. `CHECK (source IN (...))`. Per spec Clarification Q3. |
| `question_raw` | `text` | NOT NULL | — | Exact question body as submitted (FR-002). |
| `decision` | `text` | NOT NULL | — | `grounded` \| `ungrounded` \| `error`. `CHECK (decision IN (...))`. The final outcome the user saw. |
| `reason_code` | `text` | NOT NULL | — | One of the six closed codes (see research.md R-02). `CHECK (reason_code IN (...))`. |
| `reason_note` | `text` | NULL | NULL | Optional short human-readable elaboration attached by the classifier when helpful (e.g., `"top rerank score 0.41 below threshold 0.55"`). Never free-form from the generator; always assembled from structured dict values by the classifier. |
| `pipeline_stages` | `jsonb` | NOT NULL | `'{}'::jsonb` | Per-stage payload (shape below). This is the dict threaded through the pipeline. |
| `thresholds` | `jsonb` | NOT NULL | `'{}'::jsonb` | Numeric cutoffs in effect at request time (e.g., `{"max_chunk_distance": 0.55, "verbatim_match_min": 0.85}`). Captured from the service module constants so historical entries remain interpretable if the constants change later. |
| `latency_breakdown` | `jsonb` | NOT NULL | `'{}'::jsonb` | Mirrors the dict already produced by spec 066. Stored here so entries are self-contained — no cross-table join needed to read a diagnostic. |
| `provider_used` | `text` | NULL | NULL | Which LLM provider actually generated (e.g., `gemini`, `ollama`). Copied from the response payload. NULL when no generation ran. |

**Total columns: 11** — intentionally flat. Anything finer-grained lives inside `pipeline_stages` JSONB.

### `pipeline_stages` JSONB shape

Top-level keys, each optional (absent when the stage didn't run):

```json
{
  "rewrite": {
    "ran": true,
    "output_query": "CADAS-ATS administrator password recovery procedure",
    "input_turns": 0
  },
  "hyde": {
    "ran": true,
    "output_doc": "To recover a lost CADAS-ATS administrator password, the system administrator must ...",
    "failed": false
  },
  "retrieval": {
    "candidates": [
      {
        "chunk_id": "uuid-or-string",
        "manual_title": "CADAS-ATS Administrator Manual",
        "document_name": "cadas-ats-admin.pdf",
        "score_vector": 0.72,
        "score_bm25": 4.2,
        "score_hybrid": 0.58,
        "preview": "first 120 chars of chunk content…"
      }
    ],
    "k": 10
  },
  "rerank": {
    "scored": [
      { "chunk_id": "...", "rerank_score": 0.61 },
      { "chunk_id": "...", "rerank_score": 0.48 }
    ],
    "top_score": 0.61,
    "threshold_applied": 0.55
  },
  "grounding": {
    "verbatim_match": false,
    "verbatim_top_similarity": 0.62,
    "sentinel_phrase_detected": false,
    "sentinel_match": null
  },
  "generator": {
    "produced_answer": true,
    "answer_length_chars": 412,
    "refused_by_sentinel": false
  }
}
```

**Size bound**: ≤ 20 KB per row. Retrieval candidate count is capped at 10 (current pipeline default); chunk previews are capped at 120 chars; generator answer not stored here (it's represented only by length, to avoid doubling storage and because the answer itself is already persisted or derivable from other logs for successful flows). Per R-08 this keeps 30-day steady-state volume under ~100 MB.

### Constraints

- `CHECK (source IN ('user', 'test_suite', 'internal'))`
- `CHECK (decision IN ('grounded', 'ungrounded', 'error'))`
- `CHECK (reason_code IN ('grounded_answer', 'verbatim_answer', 'no_chunks_retrieved', 'rerank_below_threshold', 'generator_refused_with_chunks', 'pipeline_error', 'short_circuited_no_rag'))`
- `CHECK ((decision = 'grounded') = (reason_code IN ('grounded_answer', 'verbatim_answer', 'short_circuited_no_rag')))` — the decision and the reason code agree on groundedness; catches classifier bugs at write time.

### Indexes

- `rag_diagnostic_log_filter_idx` on `(source, decision, reason_code, created_at DESC)` — main filtered list query.
- `rag_diagnostic_log_created_at_idx` on `(created_at)` — retention pruning + time-range scans without source/decision filter.

### Row-Level Security

- `RLS ENABLE`.
- Policy `rag_diagnostic_log_admin_select`: `USING (auth.jwt() ->> 'role' = 'admin')` for `SELECT`.
- No `INSERT` policy — writes happen via backend using the Supabase service role key, bypassing RLS.
- No `UPDATE` or `DELETE` policies for end users — pruning is done by a service-role job; entries are immutable once written.

### Retention

Implemented via `pg_cron` (or equivalent nightly job) that runs the following statement:

```sql
DELETE FROM rag_diagnostic_log
WHERE (decision IN ('ungrounded', 'error') AND created_at < now() - INTERVAL '30 days')
   OR (decision = 'grounded'                AND created_at < now() - INTERVAL '7 days');
```

Per spec Clarification Q2 (asymmetric retention). Idempotent; safe to re-run.

---

## Transient shape: in-request `diagnostic` dict

Not a persisted entity — but documented here because it is the authoritative source of truth during the request and determines what gets persisted.

The dict is allocated fresh inside `ask_question` in `backend/routers/manuals.py`, passed by reference into `run_agentic_loop`, and mutated by `_StageTimer`-style context managers in `services/manual_rag_service.py`. Its shape matches `pipeline_stages` above — stages write their subtree of the dict; absent stages leave the subtree unset.

At end of request, a pure function in the new `services/rag_diagnostic_service.py`:

1. Applies the first-trigger-wins reason-code classifier against the dict.
2. Composes the full row payload (raw question, decision, reason code, stages, thresholds, latency).
3. Hands the payload to a background task that writes to `rag_diagnostic_log` and emits the `user_activity_log` heartbeat.

The response to the user is returned before the background task completes (FR-014, R-09).

---

## Migration file

Path: `supabase/migrations/20260419000000_rag_diagnostic_log.sql`

Content outline (generated fully in tasks.md):

```sql
CREATE TABLE rag_diagnostic_log ( ... );
CREATE INDEX rag_diagnostic_log_filter_idx ON rag_diagnostic_log (...);
CREATE INDEX rag_diagnostic_log_created_at_idx ON rag_diagnostic_log (created_at);
ALTER TABLE rag_diagnostic_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY rag_diagnostic_log_admin_select ON rag_diagnostic_log FOR SELECT ...;
SELECT cron.schedule('rag-diagnostic-prune', '15 3 * * *', $$DELETE FROM rag_diagnostic_log WHERE ...$$);
```

The `pg_cron` extension is already installed in the project's Supabase per prior specs (used for other maintenance jobs); if not, the migration creates it idempotently with `CREATE EXTENSION IF NOT EXISTS pg_cron;`.

---

## Cross-reference summary

| Spec requirement | Satisfied by |
|---|---|
| FR-001 (entry per request) | Row created in `rag_diagnostic_log` unconditionally before response returns |
| FR-002 (raw question) | `question_raw` column |
| FR-003 (reformulations) | `pipeline_stages.rewrite.output_query`, `pipeline_stages.hyde.output_doc` |
| FR-004 (chunks + scores + manuals) | `pipeline_stages.retrieval.candidates[]` and `pipeline_stages.rerank.scored[]` |
| FR-005 (machine-readable reason code) | `reason_code` column constrained to the closed enum |
| FR-006 (first-trigger-wins within fixed buckets) | Classifier logic in `rag_diagnostic_service.py`; enum enforced by CHECK |
| FR-007 (thresholds in effect) | `thresholds` JSONB column |
| FR-008 (timestamp + requester) | `created_at` + `user_email` |
| FR-008a (source tag) | `source` column + CHECK constraint |
| FR-012 (admin-only access) | RLS policy + backend admin router guard |
| FR-014 (logging failure survivable) | Background-task write; in-process failure counter on health endpoint |
| FR-015 (retention, 30d / 7d) | `pg_cron` daily delete statement (R-08) |
