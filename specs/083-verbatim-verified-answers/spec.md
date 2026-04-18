# Feature Specification: Verbatim Verified Answers

**Feature Branch**: `083-verbatim-verified-answers`
**Created**: 2026-04-18
**Status**: Draft
**Input**: User description: "Verbatim Verified Answers — skip LLM synthesis when a single cached answer clearly matches"

## Clarifications

### Session 2026-04-18

- Q: What does "N" count in the synthesis footer caption "Synthesized from N verified sources"? → A: Count of distinct underlying curated answers — dedupe spec-068 paraphrase variants that share a `rating_id`/`validated_qa_id` so a single source of truth counts once.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Near-instant answer for clear-match questions (Priority: P1)

A technician asks the AI assistant a question that closely matches an admin-curated verified answer already in the knowledge base (e.g., "how to backup CADAS ATS?"). Today the system takes ~10–15s to synthesize a paraphrased reply even though a curated answer already exists. With this feature, when the top verified match is strong and clearly stands apart from the second-best match, the assistant returns the curated answer **verbatim** in under two seconds, preserving the admin-authored wording.

**Why this priority**: This is the core user-facing value. It removes the single biggest latency in the verified-answer path and eliminates the honesty gap where the green "Verified Answer" badge sits on top of LLM-paraphrased prose.

**Independent Test**: Ask a question that has exactly one strong verified match in the library. Verify the response arrives in under 2 seconds, its body text is byte-identical to the stored `validated_answer`, and the green "Verified Answer" badge is shown. Can be validated end-to-end without touching synthesis-path code.

**Acceptance Scenarios**:

1. **Given** a verified Q&A exists whose top similarity to the incoming question is ≥ 0.85 and where no other match is within 0.05 of that score, **When** the user sends the question, **Then** the assistant returns the stored verified answer verbatim, the green "Verified Answer" badge is displayed, no "Synthesized from N verified sources" footer is shown, and no language-model generation call is made for this response.
2. **Given** only one verified match is returned and its similarity is ≥ 0.85, **When** the user sends the question, **Then** the assistant returns that match verbatim and the dominance-gap rule does not block the verbatim path.
3. **Given** the user gives a thumbs-up on a verbatim response, **When** the feedback is recorded, **Then** the thumbs-up count increments on the same verified-Q&A row that served the verbatim text, identical to how feedback works on synthesized responses today.

---

### User Story 2 - Honest labelling when multiple verified sources are combined (Priority: P2)

When a question doesn't have one dominant match — for example, two or three curated answers each contribute partially — the assistant continues to produce a combined answer as it does today, but now tells the user plainly that the reply was assembled from multiple verified sources rather than quoted from one.

**Why this priority**: Preserves today's behavior for ambiguous cases while closing the honesty gap introduced by User Story 1. Without this, the UI change from P1 would imply every green badge means "verbatim," which is wrong.

**Independent Test**: Ask a question with two or more comparably-scoring verified matches. Verify the green "Verified Answer" badge is shown, a subtle grey footer caption "Synthesized from N verified sources" appears below the answer body, and the answer text is a combined/paraphrased reply (behavior unchanged from today).

**Acceptance Scenarios**:

1. **Given** two verified matches within 0.05 of each other (e.g., top1 = 0.90, top2 = 0.87), **When** the user sends the question, **Then** the response is a combined reply grounded in the top matches, the green "Verified Answer" badge is shown, and a small grey caption "Synthesized from N verified sources" appears beneath the answer (N equals the number of **distinct underlying curated answers** contributing to synthesis; spec-068 paraphrase variants that share the same source answer are counted once).
2. **Given** a verified match exists but its similarity is below the verbatim floor (e.g., 0.80), **When** the user sends the question, **Then** the existing synthesis behavior runs and the "Synthesized from N verified sources" caption is shown.
3. **Given** no verified match clears the entry threshold that gates verified responses, **When** the user sends the question, **Then** neither the verbatim path nor the verified-synthesis path runs — this feature is not involved, and the non-verified answer behavior continues unchanged.

---

### User Story 3 - Post-deploy tuning visibility for operators (Priority: P3)

An operator wants to know, one week after release, what fraction of verified responses took the verbatim path vs. the synthesis path, and what the similarity-score distribution looked like, so the similarity and dominance thresholds can be tuned based on real traffic rather than guesswork.

**Why this priority**: Enables safe, data-driven adjustment of the two thresholds. Needed for ongoing operation but not for launch — the system is already correct without it.

**Independent Test**: After deployment, trigger a mix of verified responses, then query the existing user-activity log filtered to this feature's event. Verify every verified response wrote exactly one row with the mode (verbatim/synthesized) and the top-1 and top-2 similarity scores.

**Acceptance Scenarios**:

1. **Given** a verified response has been served, **When** the operator queries the activity log for this event type, **Then** exactly one log row exists per response, containing the mode taken and enough signal (top-1 and top-2 similarity values) to derive both the verbatim-vs-synthesis ratio and the similarity distribution.
2. **Given** the activity-log write fails transiently, **When** a verified response is served, **Then** the user still receives their answer with no user-visible delay or error — logging is fire-and-forget.

---

### Edge Cases

- **Single verified match, below floor**: No verbatim path — falls through to existing synthesis.
- **Two matches, top-1 exactly 0.85 and top-2 exactly 0.80**: Gap is 0.05, meets threshold — verbatim path runs. (Boundary is inclusive.)
- **Two matches, top-1 = 0.85 and top-2 = 0.83**: Top-1 meets floor but gap is 0.02 — synthesis runs.
- **Curated answer contains markdown / code blocks / line breaks**: Verbatim path must preserve the answer bytes exactly as stored, including formatting, whitespace, and any embedded characters.
- **Verified-Q&A rating row was deleted (spec 082)**: The verified-Q&A row itself still exists (with nullable rating reference); retrieval and verbatim/synthesis still work, and thumbs-up/down still target the correct Q&A row.
- **Short / direct-lookup questions (spec 067 fast path)**: The pre-existing direct-lookup fast path runs first and is unchanged; this feature only applies to the vector-search-driven verified paths.
- **Multiple curated variants share a single answer (spec 068)**: Any of the variant rows matching is sufficient — the stored answer is what gets returned.
- **Streaming response in verbatim mode**: The metadata event still arrives first, then the entire answer body arrives in a single chunk (there is no token-by-token stream, since no generation call happens).

## Requirements *(mandatory)*

### Functional Requirements

#### Verbatim short-circuit

- **FR-001**: System MUST return the stored curated answer verbatim — with no paraphrasing, trimming, re-formatting, or wrapping — whenever the top verified match's similarity is ≥ 0.85 AND the difference between the top match and the second-best match is ≥ 0.05.
- **FR-002**: System MUST treat the single-match case as eligible for the verbatim path as long as the sole match's similarity is ≥ 0.85 (the dominance-gap rule cannot disqualify a single match).
- **FR-003**: System MUST NOT invoke any language-model generation call on the verbatim path. The verbatim path must produce zero generation latency.
- **FR-004**: System MUST continue to use today's synthesis behavior (language-model generation grounded in the top matches) whenever the verbatim trigger is not met but the verified-response entry threshold is still cleared.
- **FR-005**: The verbatim-trigger decision logic MUST live in a single shared rule so that all four existing verified-answer code paths (streaming and non-streaming, before and after query-rewrite) apply identical behavior.
- **FR-006**: The two thresholds (minimum-similarity for verbatim, and dominance-gap) MUST be declared in a single shared location so any future adjustment changes behavior uniformly across all verified-answer paths without requiring edits at individual call sites.

#### Response contract

- **FR-007**: Every verified response MUST carry a new explicit mode indicator on the backend response identifying whether the response was served verbatim or synthesized.
- **FR-008**: The existing verified-response fields — the boolean `is_verified`, the `verified_source` object (including `validated_qa_id`), and the `source_type` value — MUST remain present and semantically unchanged on both the verbatim and synthesis responses.
- **FR-009**: In streaming mode, the new mode indicator MUST travel in the same metadata event that already carries the verified-source information; clients must not need a second event to learn which mode was taken.
- **FR-010**: On the verbatim path in streaming mode, the full answer text MUST be emitted as a single chunk immediately after the metadata event (no token-by-token stream, since no generation is happening).

#### User interface

- **FR-011**: The UI MUST continue to show the existing green "Verified Answer" badge for **both** verbatim and synthesized verified responses — the badge itself does not differentiate the two.
- **FR-012**: The UI MUST display a small grey footer caption reading "Synthesized from N verified sources" beneath the answer body **only** when the response was synthesized. No such caption MUST appear on verbatim responses. N is the count of **distinct underlying curated answers** contributing to the synthesis — paraphrase variants that share a single source of truth (same `rating_id` / `validated_qa_id` or identical stored answer text, per spec 068) MUST count as one source, not multiple.
- **FR-013**: Thumbs-up and thumbs-down controls, and the row they target when pressed, MUST behave identically to today on both the verbatim and synthesized responses (feedback targets the verified-Q&A row identified in `verified_source`).

#### Telemetry

- **FR-014**: Every response that takes any of the four verified-answer code paths MUST write exactly one row to the existing `user_activity_log` table via the existing fire-and-forget helper, using:
  - `category` = `"manual"`
  - `action` = `"verified_answer_served"`
  - `target_label` = the incoming question text, truncated to 80 characters
  - `detail` = a semicolon-delimited key=value string containing `mode=<verbatim|synthesized>;top1=<score>;top2=<score>` (top-1 and top-2 similarity each formatted to three decimal places; use `top2=0.000` when only a single match was returned)
- **FR-015**: Log-write failures MUST NOT block, delay, or alter the response path. If the log write throws or times out, the user's answer must still be delivered normally.

#### Non-regression

- **FR-016**: System MUST NOT change the similarity threshold that gates whether a response is treated as verified at all (the existing verified-entry threshold remains the entry gate).
- **FR-017**: System MUST NOT change the pre-existing direct-lookup fast path for very short / direct questions.
- **FR-018**: System MUST NOT alter the behavior of non-verified (low-confidence or no-match) response paths — they continue to run language-model generation as today.
- **FR-019**: System MUST NOT introduce new backend endpoints, database tables, schema migrations, or changes to the verified-Q&A retrieval helper.

### Key Entities *(include if feature involves data)*

- **Verified answer match**: A single candidate returned from the verified-Q&A similarity search, carrying a similarity score, the stored curated answer text, and a stable identifier usable by feedback writes. Multiple matches are compared by similarity score to decide verbatim vs. synthesis.
- **Response mode indicator**: A new per-response value, one of `verbatim` or `synthesized`, that tells the UI which presentation path to use and that is logged for post-deploy analysis.
- **Verified-answer-served event**: A single row written to the existing activity log for every verified response, carrying the question, the chosen mode, and the top two similarity scores — enough signal to reconstruct the verbatim/synthesis ratio and score distribution after ship without any additional instrumentation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Questions whose top curated match is clearly dominant (top similarity ≥ 0.85, gap to next ≥ 0.05) complete in under 2 seconds end-to-end (from user submit to answer visible), compared with the ~10–15 second baseline for synthesized verified responses today.
- **SC-002**: Questions whose top matches are comparable (not dominant) continue to produce a combined answer indistinguishable from today's behavior in content and latency, with no regression in existing verified-answer test cases.
- **SC-003**: The green "Verified Answer" badge is shown on 100% of verified responses (both verbatim and synthesized); the "Synthesized from N verified sources" footer caption appears on 100% of synthesized verified responses and 0% of verbatim verified responses.
- **SC-004**: A thumbs-up on a verbatim response increments the thumbs-up count on the same curated row that served the verbatim text — verified by before/after count comparison on the identified row.
- **SC-005**: The feature ships with zero net new backend endpoints, zero schema migrations, and zero changes to the verified-Q&A retrieval helper.
- **SC-006**: Within one week of release, an operator can query the existing activity log with a single filter (action = `verified_answer_served`) to derive both the verbatim-vs-synthesis ratio and the top-1/top-2 similarity distribution, with no additional code change or instrumentation.
- **SC-007**: Verbatim-path responses contain the curated answer text byte-identical to what is stored — no inserted whitespace, no stripped formatting, no introduced characters.

## Assumptions

- The existing similarity threshold that gates whether a response is verified at all (currently 0.75) remains the entry gate for this feature; only matches that already pass that gate are candidates for the verbatim-vs-synthesis decision.
- Similarity scores returned by the existing verified-Q&A retrieval are comparable on a consistent 0-to-1 cosine scale; the verbatim-trigger thresholds (0.85 floor, 0.05 gap) are calibrated to that scale.
- Curated answers are already authored by an admin with the assumption that they can be shown to a user as-is; no per-response sanitization or rewriting is required on the verbatim path.
- Only the four existing verified-response code paths (pre-rewrite streaming, post-rewrite streaming, pre-rewrite non-streaming, post-rewrite non-streaming) need to honor the short-circuit; no other caller invokes verified-Q&A retrieval in a way that would bypass them.
- Rating-row deletion (spec 082) may leave curated Q&A rows with a null rating reference; this does not affect retrieval, verbatim delivery, or feedback targeting in this feature.
- Threshold tuning post-ship is a recompile-and-deploy operation for v1; a runtime admin UI for the two thresholds is out of scope.
- The telemetry log write uses the existing activity-log helper and schema; no new fields or tables are needed to satisfy the tuning use case.
- UI strings ("Synthesized from N verified sources") are shown in English only; the AI-assistant surface does not require Arabic localization per prior project guidance.
