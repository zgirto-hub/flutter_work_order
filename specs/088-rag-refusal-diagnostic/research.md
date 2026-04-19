# Phase 0 Research: RAG Refusal Diagnostic Logging

**Feature**: 088-rag-refusal-diagnostic | **Date**: 2026-04-19

## Scope of this document

This document resolves every `NEEDS CLARIFICATION` from the plan's Technical Context and records the decisions that shape the data model and contracts in Phase 1. It also captures the architectural reasoning for reusing spec 066's `_StageTimer` pattern rather than introducing a new instrumentation mechanism.

---

## R-01 — Architectural model: extend spec 066's instrumentation dict

**Decision**: Spec 088 extends the `latency_breakdown` dict already threaded through `services.manual_rag_service` and `services.agentic_tools` by spec 066. A new dict `diagnostic` is threaded alongside it through exactly the same call chain, and a single persistence step writes the completed dict to `rag_diagnostic_log`.

**Rationale**: Spec 066 established that the pipeline already has a place where per-stage side information can be recorded without altering the pipeline's logic — the `_StageTimer` context manager wraps each stage and writes into a shared dict. Re-using that dict means spec 088 adds no new cross-cutting plumbing, preserves the contract that instrumentation is additive, and guarantees FR-013 (behaviour-preserving) by construction: the only thing that changes is that more keys are written into a dict that was already being created.

**Alternatives considered**:

- **New dedicated instrumentation subsystem** — rejected as over-engineering (violates Constitution VII). Would duplicate the threading work spec 066 already did.
- **Post-hoc log parsing of the existing `latency_breakdown` plus generator output** — rejected because the per-chunk retrieval scores and rerank scores are not in `latency_breakdown`; they're local variables inside `_run_agentic_loop`. Reconstructing them after the fact is impossible without re-running the pipeline.
- **Out-of-band side channel (e.g., a ContextVar)** — rejected because the existing threaded-dict pattern is already understood by the team and documented in spec 066.

---

## R-02 — Reason-code vocabulary

**Decision**: Six machine-readable codes, from a closed enum. Every `/api/manuals/ask` request receives exactly one.

| Code | Meaning | Outcome |
|---|---|---|
| `grounded_answer` | Pipeline answered with retrieved chunks, no refusal trigger hit | grounded = true |
| `verbatim_answer` | Validated-QA verbatim path matched (spec 083) | grounded = true |
| `no_chunks_retrieved` | Retrieval returned zero candidates after hybrid search | grounded = false |
| `rerank_below_threshold` | Retrieval returned candidates but top rerank score < `MAX_CHUNK_DISTANCE` (0.55) | grounded = false |
| `generator_refused_with_chunks` | Top candidates passed threshold but the generator emitted a sentinel refusal phrase (manuals.py:708–722) | grounded = false |
| `pipeline_error` | Uncaught exception anywhere in the agentic loop | grounded = false |
| `short_circuited_no_rag` | Greeting/thanks trivial-input path; RAG never invoked | grounded = true (canned) |

**First-trigger-wins rule** (per spec Clarification Q1): the codes are evaluated in the order shown. A request is classified with the earliest code whose condition is met — `no_chunks_retrieved` beats `rerank_below_threshold` beats `generator_refused_with_chunks`. The classifier MUST be a pure function of the already-threaded `diagnostic` dict, so it can be unit-tested without spinning up the whole pipeline.

**Rationale**: Six codes covers every path through the current pipeline with no `other` bucket needed, satisfying SC-002's "<5% other" target easily. Named codes map directly onto the three tuning stages that the follow-up spec will target.

**Alternatives considered**:

- **More granular codes** (`rewrite_produced_empty_query`, `hyde_failed_fallback_to_raw`, etc.) — rejected as YAGNI; the clarify step established that the three pipeline-stage buckets are what drive next-step tuning decisions. Finer codes can be added later if follow-up investigation needs them.
- **Free-form reason strings** — rejected because SC-002 requires counting, and free text defeats grouping (explicitly forbidden by FR-005/FR-006).

---

## R-03 — Admin screen placement

**Decision**: A new sibling tab inside `ManualAssistantScreen`, added to the existing admin-only TabController at [frontend/lib/screens/manual_assistant/manual_assistant_screen.dart](../../frontend/lib/screens/manual_assistant/manual_assistant_screen.dart). Tab label: **"RAG Logs"**. Visible only when `widget.userRole == 'admin'` (same guard pattern as Train AI).

**Rationale**: The Train AI tab (spec 080) serves curation of verified Q&A — a positive editorial workflow. RAG Logs serves debugging — a diagnostic workflow. Different mental models argue against nesting RAG Logs inside Train AI, but they share the same surface area (the manual-assistant admin screen) and audience (the admin investigating why the AI behaves the way it does), which argues against a new top-level admin route. A sibling tab threads the needle: same navigation context, separate concern.

**Alternatives considered**:

- **Sub-tab inside Train AI** — rejected; mental models differ.
- **New top-level admin route** — rejected; adds UI weight for what is an inspection-only tool the admin visits weekly, not daily.

---

## R-04 — Export format for grouped counts

**Decision**: CSV. Single button on the summary view emits a two-column CSV (`reason_code,count`) for the currently-applied filter. No JSON, no Markdown; CSV opens everywhere and handles the aggregation output cleanly.

**Rationale**: FR-011 requires export of the grouped counts for offline analysis. CSV is the lowest-friction format for the intended consumers (admin on a laptop opening in Excel or importing into a quick script). Deferred from Clarify because it's plan-level UX; resolving here to unblock task generation.

**Alternatives considered**:

- **JSON** — machine-friendly but the summary is a small flat table; CSV is the more natural shape.
- **Both CSV + JSON** — rejected as YAGNI for v1.

---

## R-05 — How the test suite signals `source = test_suite`

**Decision**: Extend the existing `AskRequest` Pydantic model in [backend/routers/manuals.py](../../backend/routers/manuals.py) with an optional `source: Optional[Literal['user', 'test_suite', 'internal']] = 'user'` field. The RAG quality test suite ([backend/tests/test_rag_quality.py](../../backend/tests/test_rag_quality.py:864)) sets `payload['source'] = 'test_suite'` in `run_test`. All existing callers (the real frontend) continue to send a body without the field and inherit the `user` default. Fully backward-compatible — no API version bump needed.

**Rationale**: The spec (Clarification Q3) explicitly prohibits relying on email-pattern matching; a first-class enum field is the durable answer. Pydantic's `Literal` with a default cleanly enforces the closed vocabulary at the API boundary.

**Alternatives considered**:

- **Custom HTTP header** (`X-Request-Source: test_suite`) — rejected because Pydantic validation over a body field is stronger than header parsing and matches the project's existing conventions.
- **Separate endpoint for test traffic** — rejected as a gratuitous fork of a unified code path.

---

## R-06 — Reason code for `short_circuited_no_rag`

**Decision**: Trivial-input short-circuits (greetings, thanks per the ask-the-AI greeting bypass already in `manuals.py`) produce an entry with reason code `short_circuited_no_rag` and `grounded = true` (because the canned reply is indeed grounded in the canned-reply dictionary). These entries do NOT count toward SC-002's refusal denominator — they're filtered out of "refusal" summary views by the reason code itself.

**Rationale**: FR-002 requires recording every question that enters the AI assistant's flow, and the spec's Edge Cases section explicitly addresses this. Using a reason code rather than "no entry at all" keeps the total of log entries honest — a future question ("how many trivial inputs does the system get?") becomes answerable without adding new instrumentation.

---

## R-07 — How to validate SC-004 (behaviour preservation)

**Decision**: The validation protocol for SC-004 is:

1. Before merging the implementation, run `python backend/tests/test_rag_quality.py` against the old backend. Save output as `rag_quality_pre.json`.
2. Deploy the new backend with spec 088 applied.
3. Run the test suite again against the new backend. Save as `rag_quality_post.json`.
4. Compare: total pass count, per-category pass count, hallucination count, per-question pass/fail must all be identical.

Any divergence is a blocker; spec 088 has no license to alter answers.

**Rationale**: This is the only way to catch accidental behaviour change that slipped past code review. The test suite is already deterministic against the same pipeline (same Ollama/Gemini model, same manuals, same embeddings), so any drift post-spec is evidence of a bug introduced by the instrumentation itself — e.g., a timing change that alters LLM temperature seed, or a mutation of the dict that the pipeline later reads.

---

## R-08 — Storage volume & retention mechanism

**Decision**: Retention is enforced by a nightly cron-equivalent SQL that deletes stale rows. No partitioning needed at expected volume.

- Approximate row size: 10 KB JSONB payload + ~500 bytes columnar = ~10.5 KB.
- Daily volume: ~600 requests, so ~6 MB/day.
- Retention horizon: refused/errored entries keep 30 days; grounded entries keep 7 days. The mix at steady state is roughly 40% refused (current baseline) and 60% grounded.
- At full retention horizon: `30 * 0.4 * 600 * 10.5 KB + 7 * 0.6 * 600 * 10.5 KB ≈ 75 MB + 27 MB ≈ 100 MB`.

The pruning job is implemented as a simple DELETE in a migration-installed trigger OR a small admin endpoint run by cron (choice deferred to tasks.md — implementation-level, not plan-level). Whichever is chosen, it MUST run daily and MUST be idempotent.

**Alternatives considered**:

- **Supabase `pg_cron`** — viable, recommended path; keeps retention in the database layer.
- **Application-level task queue** — rejected for this scope; the project has no existing task queue and introducing one for a single pruning job violates YAGNI.

---

## R-09 — Concurrency behaviour

**Decision**: The instrumentation dict is per-request (created fresh inside `ask_question` for each call), so there is no shared mutable state across concurrent requests. Persistence to `rag_diagnostic_log` happens on a background task (`asyncio.create_task` or the same pattern `utils/activity.py` uses), so the response to the user is not blocked on the write. Failures in the write path are logged to stderr and counted by an in-process counter exposed on a lightweight `/api/admin/rag-diagnostics/health` endpoint for admin visibility (FR-014 escalation).

**Rationale**: Directly addresses FR-014 (logging failures must not block user responses) and FR-001 (entry per request) without introducing a formal queue. The instrumentation dict has per-request scope by construction, so the usual thread-safety questions don't arise.

---

## R-10 — Index design for the list/filter view

**Decision**: Compound indexes on `(source, decision, reason_code, created_at DESC)` for the main filtered-list view, plus a single-column index on `created_at` for time-range queries that don't filter by source or decision. `reason_code` is a `text` column constrained by a `CHECK` to the enum values listed in R-02 — no enum type needed (keeps migrations simple).

**Rationale**: Every expected query from the admin UI filters by at least one of `source`, `decision`, or `reason_code` before sorting by `created_at`, making the compound index effective. At ~9K rows it isn't strictly necessary for correctness, but it keeps SC-003's 3-second budget comfortable and avoids a surprise when the data grows.

---

## Summary of cross-cutting decisions

| Decision | Impact |
|---|---|
| Reuse spec 066's `_StageTimer` dict | No new plumbing; behaviour-preservation is structural not conventional |
| Six closed reason codes | Simple classifier, easily unit-tested; covers SC-002 |
| First-trigger-wins classifier | Deterministic tuning signal; matches Clarification Q1 |
| Sibling admin tab "RAG Logs" | Separates debug workflow from Train AI's curation workflow |
| CSV-only export | Lowest-friction offline analysis |
| Optional `source` body field | Backward-compatible API extension; no version bump |
| Asymmetric retention via `pg_cron` | Matches Clarification Q2 without new task queue |
| Per-request dict + background write | Directly satisfies FR-014 with no queue infrastructure |
| Compound index on filter triple + created_at | Keeps SC-003 comfortable at full retention volume |

**All `NEEDS CLARIFICATION` markers resolved. Ready for Phase 1.**
