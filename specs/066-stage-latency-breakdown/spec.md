# Feature Specification: Per-Stage RAG Pipeline Latency on Ask-the-AI Answer Card

**Feature Branch**: `066-stage-latency-breakdown`
**Created**: 2026-04-15
**Status**: Draft
**Input**: User description: "Per-stage RAG pipeline latency on Ask-the-AI answer card — expose embed/HyDE/rewrite/retrieval/rerank/generator/total timings so fast cloud providers visibly generate fast; observability only, additive, no pipeline changes."

## Clarifications

### Session 2026-04-15

- Q: Should the primary footer number be generator-only, total, or both shown side-by-side? → A: Both shown side-by-side — generator prominent, total secondary (e.g., `Groq (Llama 3.3 70B) · 1.2s · pipeline 22s`).
- Q: Should stage timings appear in `user_activity_log` for audit, or stay transient per-response only? → A: Transient only — not persisted to `user_activity_log` or any other store in phase 1.
- Q: Should the expandable breakdown be always-on (visible chevron) or gesture-only? → A: Always-visible chevron/toggle on the footer — discoverable, accessible, consistent across platforms.
- Q: How should a stage that did not run (HyDE disabled, greeting bypass, stage failure) be represented in the response? → A: Always include all seven keys; skipped or failed stages report explicit `null` (stable shape).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See that the active provider generates fast (Priority: P1)

A user has switched the active AI provider to Groq (or Mistral, or any fast cloud provider). They ask a question in the Ask-the-AI surface. When the answer arrives, the footer shows that the generator stage took about one second, making the provider's speed visible even though the full pipeline took roughly twenty-two seconds because of local preprocessing.

**Why this priority**: This is the entire purpose of the feature. Without it, users who configured a fast provider see the same total-time number that local Gemma produces, and the value of provider switching stays invisible.

**Independent Test**: Configure Groq as the active provider, ask any manual question, and verify the answer card footer clearly shows a short generator time (e.g., `1.2s`) alongside the provider name, distinct from the total pipeline time.

**Acceptance Scenarios**:

1. **Given** the active provider is Groq and a user asks a question, **When** the answer card renders, **Then** the footer shows the generator latency (e.g., `Groq (Llama 3.3 70B) · 1.2s`) with a secondary total (e.g., `· pipeline 22s`).
2. **Given** the active provider is local Gemma and a user asks a question, **When** the answer card renders, **Then** the footer still shows generator latency and total, and the generator value is visibly larger than what fast cloud providers produce for comparable prompts.
3. **Given** any answered question, **When** the user activates the footer, **Then** the full per-stage breakdown is revealed (embed, HyDE, rewrite, retrieval, rerank, generator, total).

---

### User Story 2 - Diagnose where time is spent (Priority: P2)

An admin or technician notices a slow answer. They expand the footer to see per-stage timings and can tell at a glance whether the bottleneck was local preprocessing (embedding, HyDE, rewrite) or remote generation.

**Why this priority**: Enables self-service triage and informs future optimization priorities without requiring server log access.

**Independent Test**: Ask a question, expand the footer detail on the answer card, and confirm each executed stage shows a formatted duration; stages that did not run are either omitted or explicitly marked as skipped.

**Acceptance Scenarios**:

1. **Given** an answered question where HyDE was enabled, **When** the user opens the breakdown, **Then** all seven values (embed, hyde, rewrite, retrieval, rerank, generator, total) are displayed.
2. **Given** an answered question where HyDE was disabled in settings, **When** the user opens the breakdown, **Then** the HyDE entry is omitted or shown as skipped — other stages still appear.
3. **Given** a greeting-bypass response (e.g., user typed "hi"), **When** the user opens the breakdown, **Then** only the total and any stages that actually executed are shown; skipped stages are not counted against the pipeline.

---

### User Story 3 - Consistent, readable formatting (Priority: P2)

A user sees timings formatted predictably regardless of scale — sub-second values never appear as raw milliseconds, and long pipelines are readable at a glance.

**Why this priority**: Formatting inconsistency ("1200ms" vs "1.2s") is the single biggest source of friction in latency displays and was explicitly called out as non-negotiable.

**Independent Test**: Inspect rendered timings for synthetic values `50ms`, `250ms`, `1200ms`, `22400ms`, `75000ms` and confirm each renders per the format rules, in both English and Arabic.

**Acceptance Scenarios**:

1. **Given** a stage took less than 100 ms, **When** displayed, **Then** it renders as `<1s`.
2. **Given** a stage took between 100 ms and 999 ms, **When** displayed, **Then** it renders as one-decimal seconds (e.g., `0.3s`).
3. **Given** a stage took between 1 s and 59.9 s, **When** displayed, **Then** it renders as one-decimal seconds (e.g., `1.2s`, `22.4s`).
4. **Given** a stage took 60 s or more, **When** displayed, **Then** it renders as minutes and seconds (e.g., `1m 15s`).
5. **Given** the interface language is Arabic, **When** timings render, **Then** they use the same format and unit conventions as English.

---

### Edge Cases

- When a stage fails mid-pipeline but a fallback answer is returned, the breakdown reports the failed stage as `null` while successfully executed stages retain their measured values.
- When the greeting bypass short-circuits the pipeline, only the total (and any executed stages) appear; the breakdown must not imply a full pipeline ran.
- When the answer arrives via a fallback provider (owned by spec 065), the generator timing reflects the provider that actually produced the answer, not the originally selected one.
- When stage timing captures fail silently (clock skew, instrumentation bug), the stage value is reported as `null` rather than zero or negative.
- When the total elapsed time is less than the sum of captured stages (due to concurrency or measurement granularity), the displayed total remains the authoritative wall-clock value.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Ask-the-AI response payload MUST include a `latency_breakdown` object containing per-stage millisecond values for: embedding, HyDE, query rewrite, retrieval, rerank, generator, and total.
- **FR-002**: The breakdown MUST always include all seven keys (`embed_ms`, `hyde_ms`, `rewrite_ms`, `retrieval_ms`, `rerank_ms`, `generator_ms`, `total_ms`). Stages that did not execute (HyDE disabled, greeting bypass short-circuit, stage failure) MUST report explicit `null`; they MUST NOT report zero, negative values, or omit the key. The `total_ms` key is always non-null.
- **FR-003**: The `total` value MUST reflect the full request wall-clock duration, not the sum of stage values.
- **FR-004**: The answer card footer MUST display the generator stage latency prominently alongside the provider/model label (e.g., `Groq (Llama 3.3 70B) · 1.2s`).
- **FR-005**: The answer card footer MUST display the total pipeline duration in a visibly secondary position (e.g., `· pipeline 22s`).
- **FR-006**: Users MUST be able to reveal the full per-stage breakdown from the footer via an always-visible chevron/toggle control; the chevron MUST be reachable by both touch and keyboard and clearly labelled for assistive technology.
- **FR-007**: All displayed durations MUST follow these formatting rules: `<1s` for values below 100 ms, one-decimal seconds for 100 ms through 59.9 s, and `Xm Ys` for values ≥ 60 s.
- **FR-008**: The breakdown MUST render identically in Arabic and English (same units, same format, same precision).
- **FR-009**: The `latency_breakdown` field MUST be strictly additive to the existing response shape — existing consumers that ignore the field MUST continue to work unchanged.
- **FR-010**: Timings MUST be transient per-response only; the system MUST NOT persist per-stage latency to any audit, analytics, or activity log in phase 1.
- **FR-011**: Instrumentation MUST be scoped to the Ask-the-AI endpoint only; other AI-powered surfaces remain un-instrumented in phase 1.
- **FR-012**: Instrumentation MUST NOT change provider selection, fallback orchestration, timeout behavior, or any pipeline logic; it is observation-only.
- **FR-013**: When the answer is produced by a fallback provider, the generator latency reported MUST correspond to the provider that actually produced the answer.
- **FR-014**: Every answered question (including greeting bypass and fallback paths) MUST produce a displayable `total_ms`. If `generator_ms` is `null` (e.g., greeting bypass), the footer MUST still render the total and the provider label, omitting the generator segment gracefully without breaking layout.

### Key Entities

- **Latency Breakdown**: A transient per-response object with seven fixed keys — `embed_ms`, `hyde_ms`, `rewrite_ms`, `retrieval_ms`, `rerank_ms`, `generator_ms`, `total_ms`. Each stage key is either a non-negative integer milliseconds measurement or `null` (stage skipped/failed); `total_ms` is always non-null. Attached to the Ask-the-AI response only; never persisted.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When a user switches from local Gemma to a fast cloud provider, the generator time displayed on the answer card drops by at least 80% for identical questions, making provider speed visibly different.
- **SC-002**: 100% of Ask-the-AI answer cards (including fallback and bypass cases) display a total value in the footer, with no raw-millisecond formatting leaking through.
- **SC-003**: A user can retrieve the full stage breakdown in one gesture (single tap, hover, or toggle) without navigating away from the answer card.
- **SC-004**: Zero existing API consumers break as a result of the additive response field (verified by existing clients continuing to render answers unchanged when the field is ignored).
- **SC-005**: A user examining the breakdown can correctly identify the slowest stage in under 5 seconds of reading.

## Assumptions

- Stage boundaries in the RAG pipeline are observable points at which a timing hook can be placed without altering execution order or concurrency.
- The existing response transport to the Ask-the-AI client tolerates additive JSON fields without client-side schema rejection.
- The answer card footer has enough visual space on supported devices to accommodate two timing values (generator + total) alongside the provider label without truncation.
- The footer shows both generator latency (prominent) and total (secondary) side-by-side; generator is the number that changes when the provider switches, total is retained for context.
- Breakdown expansion uses an always-visible chevron/toggle on the footer, reachable by both touch and keyboard, with an assistive-technology label.
- Spec 065 (provider display audit) is merged to main and its response-shape changes are the baseline this spec extends.
- Stage timings are measured in the backend with monotonic clocks; network and client-render time are not attributed to any stage and are implicitly absorbed into total.
