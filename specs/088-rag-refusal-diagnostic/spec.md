# Feature Specification: RAG Refusal Diagnostic Logging

**Feature Branch**: `088-rag-refusal-diagnostic`
**Created**: 2026-04-19
**Status**: Draft
**Input**: User description: "Add per-stage structured logging to the AI assistant's question-answering endpoint so every refusal ('ungrounded' response) produces a forensic record showing exactly which stage of the RAG pipeline caused the refusal. No tuning changes — observability only."

## Clarifications

### Session 2026-04-19

- Q: When a refusal has multiple contributing causes (e.g., retrieval returned only weak chunks AND rerank filtered them AND the generator would have refused anyway), which reason code is recorded? → A: First-trigger-wins — record the earliest pipeline stage that would have produced a refusal on its own. Later weak stages are symptomatic, not causal.
- Q: What is the retention policy for diagnostic entries given that most diagnostic value lives in refused entries and grounded entries are bulk noise? → A: Asymmetric retention — refused and errored entries kept 30 days; grounded-success entries kept 7 days. Preserves full analysis window where it matters without carrying successful-answer volume for longer than needed.
- Q: How are test-suite runs (which fire ~87 questions back-to-back from a synthetic user) distinguished from real user traffic in the log, given that SC-002 depends on clean signal? → A: Every entry carries a `source` enum — one of `user`, `test_suite`, or `internal` (reserved for future automated agents). Admin interface supports filtering on this field. Test-suite runs set this tag explicitly, not via email pattern matching.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Classify a single refusal into its root cause (Priority: P1)

An administrator runs the RAG quality test suite and sees that the AI refused to answer "lost ats admin pw, how to reset" even though the answer is in the CADAS-ATS manual. They open the admin diagnostic screen, locate the log entry for that exact question, and see a per-stage breakdown revealing where the refusal was produced — for example, "retrieval returned 5 chunks, top rerank score 0.41 fell below threshold 0.55" or "generator refused despite 3 high-scoring chunks."

**Why this priority**: Without this capability, the team cannot tell whether the over-refusals visible in the test suite come from the rewrite stage, retrieval, reranking, or the generator. Any attempt to improve the RAG pipeline without this data is guessing. This single log view unblocks every downstream tuning decision.

**Independent Test**: Ask the AI a question that the test suite shows is refused, then open the admin diagnostic screen, find the corresponding log entry, and confirm the entry identifies which stage caused the refusal with enough detail that the reviewer can place the refusal into one of three named root-cause buckets: (a) retrieval empty or irrelevant, (b) rerank score below threshold, (c) generator refused despite valid retrieval.

**Acceptance Scenarios**:

1. **Given** the AI assistant has just responded "This information is not in the available manuals" to a user question, **When** the administrator opens the diagnostic screen, **Then** a log entry exists for that question showing the raw question, every rewritten form of the question, the top retrieved chunks with their scores and source manuals, rerank scores, and a machine-readable reason code explaining why the final answer was marked ungrounded.
2. **Given** the administrator is viewing the list of diagnostic entries, **When** they filter by outcome "refused", **Then** only entries where the AI declined to give a grounded answer are shown.
3. **Given** a diagnostic entry is open, **When** the administrator reads the reason code field, **Then** the code is one of a small, fixed set (such as `no_chunks_retrieved`, `rerank_below_threshold`, `generator_refused_with_chunks`, `rewrite_produced_empty_query`) — not free-form prose — so entries can be counted and grouped.

---

### User Story 2 — Classify a batch of refusals (Priority: P2)

After running the full RAG quality test suite (or observing a day's worth of real user traffic), the administrator wants to know: "out of all refusals, what fraction were caused by each stage?" They open the diagnostic screen and see a count of refusals grouped by reason code, so they can decide which stage to invest in fixing first.

**Why this priority**: Fixing a stage that causes 5% of refusals before fixing one that causes 60% is a bad allocation of effort. Grouped counts turn the diagnostic screen from a case-by-case tool into a decision-making tool.

**Independent Test**: Run the RAG quality suite (87 questions). Open the diagnostic screen. Confirm a summary panel shows refusal counts grouped by reason code, and that the numbers sum to the total refusal count observed in the suite.

**Acceptance Scenarios**:

1. **Given** at least 20 diagnostic entries exist in the log, **When** the administrator opens the diagnostic screen, **Then** a summary section shows each reason code alongside how many entries fall into it.
2. **Given** the administrator wants to export the counts for offline analysis, **When** they use the export action, **Then** they receive a plain-text or tabular export of the grouped counts.

---

### User Story 3 — Inspect a successful answer to contrast with a refusal (Priority: P3)

The administrator is investigating why the AI answered question A correctly but refused question B (which has the same underlying information). They want to compare the per-stage breakdowns side by side to see where the two flows diverged.

**Why this priority**: Most of the diagnostic value comes from refusal entries, but being able to contrast with a nearby success is how the administrator learns the expected shape of each stage. It's not required for the first week of use, but it sharpens analysis later.

**Independent Test**: Submit two questions on the same topic — one using full technical terms (likely to be answered), one using abbreviations (likely to be refused). Open both log entries in the diagnostic screen and verify the administrator can view them at the same time.

**Acceptance Scenarios**:

1. **Given** the administrator is viewing one diagnostic entry, **When** they navigate to a different entry, **Then** they can do so without losing the context of the first entry.

---

### Edge Cases

- **Question submitted but RAG pipeline throws an exception**: A diagnostic entry MUST still be created, with the exception captured as the reason code (e.g., `pipeline_error`), so silent failures don't hide behind missing logs.
- **Question results in a grounded answer**: Entry is still recorded so successful flows are available for contrast (per User Story 3). Retention may be shorter for successes than for refusals (see Assumptions).
- **User's question is empty, a greeting ("hi"), or otherwise short-circuited before entering the RAG pipeline**: Either no entry is created, or an entry is created with reason code `short_circuited_no_rag` — but it MUST NOT be counted as a refusal caused by a pipeline stage.
- **Log volume grows large**: The diagnostic screen MUST remain responsive. The team expects on the order of hundreds of entries per day in realistic use.
- **Personally identifying or sensitive content in user questions**: Logs contain the raw question text. Access to the diagnostic screen MUST be restricted to administrative roles; it MUST NOT be exposed to regular technicians or end users.
- **Rapid succession of identical questions**: Each request creates its own entry — the diagnostic value is in seeing how the pipeline behaved that specific time, not in deduplication.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST record one diagnostic entry for every request that enters the AI assistant's question-answering flow, including requests that result in refusals, grounded answers, and pipeline errors.
- **FR-002**: Each diagnostic entry MUST capture the raw question exactly as the user submitted it.
- **FR-003**: Each diagnostic entry MUST capture every transformation of the question produced by upstream preparation stages (rewrites, hypothetical expansions, or any other reformulations fed into retrieval).
- **FR-004**: Each diagnostic entry MUST capture the set of manual chunks considered during retrieval, including a stable identifier for each chunk, the source manual's human-readable title, and every relevance or similarity score attached to the chunk by any stage (vector similarity, lexical match, hybrid combination, rerank).
- **FR-005**: Each diagnostic entry MUST capture the final decision for the request — whether the AI produced a grounded answer, refused, or errored — and MUST attach a short, machine-readable reason code from a fixed vocabulary explaining that decision.
- **FR-006**: The reason-code vocabulary MUST be sufficient to place every refusal into exactly one of the following root-cause buckets: (a) no relevant retrieval, (b) retrieval present but filtered out by scoring/reranking, (c) generator declined to answer despite acceptable retrieval, (d) an explicit pipeline error. A single "other" code is permitted but MUST apply to fewer than 5% of refusals. When more than one bucket could apply to the same refusal, the system MUST record the earliest stage that would have produced the refusal on its own (first-trigger-wins); later weak stages are treated as downstream symptoms and are not recorded as the cause.
- **FR-007**: Each diagnostic entry MUST record the numeric thresholds or cutoffs that were applied at each scoring stage, so that a reviewer can reproduce the decision by looking at the entry alone.
- **FR-008**: Each diagnostic entry MUST carry a timestamp and a reference to the requesting user, so entries can be correlated with external events.
- **FR-008a**: Each diagnostic entry MUST carry a `source` tag from a fixed vocabulary (`user`, `test_suite`, `internal`) identifying where the request originated. Automated callers (including the RAG quality test suite) MUST set this tag explicitly when invoking the endpoint; absence defaults to `user`. The distinction MUST NOT rely on email-pattern matching.
- **FR-009**: Administrators MUST be able to view diagnostic entries through a dedicated area of the existing administrative interface, without needing database or server-log access.
- **FR-010**: The diagnostic interface MUST allow filtering entries by final decision (at minimum: refused vs grounded), by reason code, by source tag, and by time range.
- **FR-011**: The diagnostic interface MUST present a summary view showing counts of refusals grouped by reason code over a selected time range.
- **FR-012**: Access to the diagnostic interface MUST be restricted to administrative roles; regular users, technicians, and supervisors MUST NOT see it.
- **FR-013**: Adding the diagnostic logging MUST NOT alter the behaviour of the AI assistant — same questions MUST produce the same answers and the same grounded/ungrounded decisions as before this feature shipped. The only observable change for end users is the new admin screen.
- **FR-014**: The system MUST tolerate failures of the logging subsystem without affecting user-facing responses. If a diagnostic entry cannot be persisted, the user's answer MUST still be returned normally and the logging failure MUST be surfaced to administrators through a separate health indicator, not through the user flow.
- **FR-015**: Entries MUST be retained long enough to support weekly review cycles. Specifically: refused and errored entries MUST be retained for at least 30 days; grounded-success entries MUST be retained for at least 7 days. Entries older than their retention window MAY be pruned automatically.

### Key Entities

- **Diagnostic Entry**: A single record describing the life cycle of one question through the AI assistant. Attributes include: identifier, timestamp, requesting user reference, `source` tag (one of `user` / `test_suite` / `internal`), raw question text, every reformulation of the question, the set of retrieval candidates (with scores and source manual titles), the set of reranked candidates (with rerank scores), the scoring thresholds in effect, the final outcome, the reason code, and a short human-readable note explaining the reason code where helpful.
- **Reason Code**: A short, fixed-vocabulary tag that classifies the outcome of a request. The set of codes is small and covers every observed path through the pipeline — no free-text reasons are permitted for refusals.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After running the current 87-question RAG quality test suite against the instrumented system, the administrator can classify every refused question into exactly one reason-code bucket within a single working afternoon (under 4 hours), without reading source code or server logs.
- **SC-002**: For the ~35 over-refusals currently produced by the quality suite, at least 95% fall into the three named pipeline-stage buckets (retrieval empty, rerank threshold, generator refused). Fewer than 5% end up in the "other" bucket.
- **SC-003**: The summary view renders refusal counts grouped by reason code in under 3 seconds for a day's worth of traffic (several hundred entries).
- **SC-004**: Adding the diagnostic does not change the AI's answers. Running the RAG quality suite before and after the feature ships produces the same pass/fail outcome for every question (same total score, same per-category counts, same hallucination count).
- **SC-005**: The administrator, given only the diagnostic interface and no other access, can decide within one session which single stage of the pipeline to tune first in the follow-up spec — measured by the administrator producing a written "next fix" recommendation after reviewing the summary view.
- **SC-006**: No user-facing response times are measurably impacted by the logging (no visible slowdown in the AI assistant's reply time from an end-user perspective).

## Assumptions

- Access control for the new administrative interface reuses the existing role model; "administrator" means the same thing here as it does in the rest of the application.
- Diagnostic entries are stored in the same data platform as other application data rather than in a separate observability system.
- Retention of diagnostic entries is asymmetric by outcome — refused/errored entries are kept at least 30 days (the full weekly review horizon), while grounded-success entries are kept at least 7 days (enough to contrast against a nearby refusal per User Story 3, without inflating storage with bulk ambient traffic).
- Storage cost for the expected volume (hundreds of entries per day) is negligible compared to the diagnostic value, so no aggressive sampling, truncation, or compression is required in v1.
- The full text of user questions is safe to store; no additional redaction or anonymisation is required beyond restricting who can view the interface. If this assumption is wrong for a future category of question, redaction will be added in a later spec.
- The administrative interface is an extension of the existing admin training screen rather than a brand-new top-level navigation area; this keeps the feature discoverable without adding UI weight.
- The existing quality test suite (`backend/tests/test_rag_quality.py`) is the primary instrument for validating Success Criteria SC-001 and SC-002. No new test suite is introduced as part of this spec.
- This spec delivers observability only. Any change to how the pipeline actually decides to refuse — including adjustments to thresholds, rewrite prompts, rerank cutoffs, or generator instructions — is explicitly out of scope and belongs to a follow-up spec that will read the data produced here.
