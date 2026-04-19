# Quickstart: RAG Refusal Diagnostic Logging

**Feature**: 088-rag-refusal-diagnostic | **Date**: 2026-04-19

This document walks an administrator through the end-to-end experience spec 088 delivers. Intended as both an acceptance walkthrough (for the implementer to verify) and an operator handbook (for the admin doing the diagnostic session in week 2 of the plan).

---

## Prerequisites

- Backend deployed with spec 088 applied; FastAPI restarted.
- Supabase migration `20260419000000_rag_diagnostic_log.sql` applied.
- Frontend deployed with the new "RAG Logs" tab.
- You are signed in as an admin user (role check at the frontend tab guard).
- Baseline RAG quality suite result exists at `backend/tests/rag_quality_results.json` (from the 2026-04-19 run that motivated this spec: 38/87 pass, 0 hallucinations).

---

## Happy path — one diagnostic session

### Step 1 — generate a fresh batch of diagnostic entries

From the project root:

```bash
python backend/tests/test_rag_quality.py
```

The test runner now sends `source: "test_suite"` on every request. Every question therefore produces one row in `rag_diagnostic_log` tagged `source='test_suite'`, separately identifiable from any real-user traffic that happens concurrently.

Expected runtime: ~50 minutes (87 questions × ~30 s each). Wait for it to finish and confirm the summary line:

> `Score: 38/87 (43.7%)` or similar — MUST match the pre-088 baseline exactly (SC-004). Any drift is a bug in the instrumentation.

### Step 2 — open the admin screen

Navigate to the manual-assistant screen in the Flutter app. Admin sees seven tabs; the new one is labelled **"RAG Logs"** (sibling to **"Train AI"**).

### Step 3 — filter to the test run

On the RAG Logs tab:

- Source: **test_suite**
- Time range: **last 2 hours** (covers the run)
- Decision: **(all)**

The list shows ~87 rows. The summary panel at the top shows grouped counts:

| Reason code | Count |
|---|---|
| `grounded_answer` | (~26) |
| `verbatim_answer` | (~0–5) |
| `short_circuited_no_rag` | (~0) |
| `no_chunks_retrieved` | (~?) |
| `rerank_below_threshold` | (~?) |
| `generator_refused_with_chunks` | (~?) |
| `pipeline_error` | (~0) |

The actual distribution inside the three refusal buckets is the answer to the question that motivated this spec. Reading these three numbers IS the "one afternoon of reading logs" specified in SC-001 and the plan's Step 2 (Monday-morning plan).

### Step 4 — drill into a refusal

Tap any row with `decision = ungrounded`. The detail view shows:

- **Question**: the raw terse-technician input, e.g. `lost ats admin pw, how to reset`
- **Rewrite output**: what the rewriter produced, if it ran
- **HyDE hypothetical**: the synthetic passage, if generated
- **Retrieval candidates**: up to 10 chunks with vector / BM25 / hybrid scores and source manual titles
- **Rerank scores**: filtered list with the top score and the threshold in effect
- **Grounding decision + reason code**: e.g. `rerank_below_threshold — top rerank score 0.41 below threshold 0.55`
- **Latency breakdown**: `{ rewrite_ms: 480, hyde_ms: 620, retrieval_ms: 120, rerank_ms: 35, generator_ms: 0, total_ms: 1255 }` (generator_ms = 0 because it was skipped by the threshold filter)

Scroll to find the root cause. At this point the admin should be able to answer: "for this question, which stage caused the refusal?"

### Step 5 — export grouped counts

Back on the summary panel, click **Export CSV**. A file named `rag-diagnostics-summary-<from>-to-<to>.csv` downloads. Contents:

```csv
reason_code,count
grounded_answer,26
verbatim_answer,3
short_circuited_no_rag,0
no_chunks_retrieved,9
rerank_below_threshold,31
generator_refused_with_chunks,11
pipeline_error,0
```

(numbers illustrative)

This file is the input to the next tuning spec.

### Step 6 — conclude

Write a one-paragraph "next fix" recommendation based on the dominant reason code (SC-005). Example:

> "Of 51 refusals, 31 (61%) were `rerank_below_threshold` — retrieval IS finding relevant chunks but the 0.55 threshold is filtering them out for terse queries. Next spec: tune the threshold down to 0.45 and re-run the quality suite. Hallucination rate (Cat 6) is the guardrail — any drop there blocks the change."

---

## Validation against Success Criteria

| SC | Validation |
|---|---|
| SC-001 | Time the diagnostic session. It MUST be under 4 hours from opening the tab to writing the "next fix" recommendation in Step 6. |
| SC-002 | Count the `pipeline_error` + (any `other`, though there is no `other` in the vocabulary) rows in the summary. That count MUST be less than 5% of total refusals (ungrounded + error). For the ~35 over-refusals baseline, that is ≤ 1 row. |
| SC-003 | Open devtools / browser network panel. The `GET /api/admin/rag-diagnostics/summary` response MUST return in under 3 s even when the filter covers a full day of real traffic. |
| SC-004 | Compare the `rag_quality_results.json` from step 1 against the pre-spec baseline. Total pass, per-category pass, hallucination count MUST all match exactly. Any drift is a bug in spec 088's instrumentation, not in the pipeline. |
| SC-005 | Artifact: a one-paragraph "next fix" recommendation produced from step 6 without consulting server logs or source code — only the RAG Logs tab. |
| SC-006 | Compare `latency_breakdown.total_ms` distribution from a post-spec-088 user session against a matched pre-spec-088 sample. Median and p95 MUST not regress by more than 50 ms. Fire-and-forget writes should add negligible latency. |

If any SC fails, spec 088 is not yet shippable. Fix and re-run.

---

## Common operator tasks after v1 ships

### "Which refusal bucket dominates for real user traffic this week?"

- Source: `user`
- Time range: **last 7 days**
- Look at the summary panel. The largest refusal count is the bucket to target next.

### "Did the test suite and real users see the same bottleneck?"

- Open the summary twice — once with source=`test_suite`, once with source=`user`.
- Compare the relative distributions. Convergent: pick the largest shared bucket. Divergent: the test suite is stressing a phrasing pattern real users don't hit (or vice versa) — the rewrite may be hiding real-world failure modes.

### "Is logging healthy?"

- `GET /api/admin/rag-diagnostics/health` (admin-only). Check `in_process_write_failures_last_hour` == 0 and `last_successful_write_at` is recent. If not, the admin UI shows a warning banner at the top of the RAG Logs tab.

### "Retention check"

- Same health endpoint exposes `retention_job_last_run_at` and `retention_job_rows_deleted_last_run`. If `retention_job_last_run_at` is older than ~25 hours, the pruning cron has stalled; check `pg_cron` job status.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| RAG Logs tab not visible | User role is not `admin` | Check `users.role` in Supabase; no self-service. |
| Tab visible but empty | No requests have hit `/api/manuals/ask` since spec 088 deployed | Run the test suite (step 1) or ask a real question. |
| All entries classified as `pipeline_error` | Instrumentation bug — dict mutation is throwing inside the pipeline | Check FastAPI logs for the exception; temporary workaround: set the diagnostic subsystem to quiet mode via the health endpoint (NOT built in v1 — if this happens, the fix is a hotfix, not a toggle). |
| Summary endpoint slow (>3 s) | Indexes missing or stale | Re-run migration; confirm `rag_diagnostic_log_filter_idx` exists via `\d+ rag_diagnostic_log` in psql. |
| `total_requests` in summary doesn't match the number of entries returned by list view | Time range skew — summary uses server-UTC bounds, list uses user-local filter clicks | Harmonise both to UTC ISO-8601 in the client code before issuing the request. |
| RAG quality suite score diverges from pre-088 baseline | Instrumentation mutates something the pipeline reads later | FR-013 violation — revert and fix. The dict passed to `_StageTimer` must be written to, never read from, by pipeline stages after the fact. |
