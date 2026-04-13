# Feature Specification: Cross-Manual Synthesis (Layer 4)

**Feature Branch**: `046-cross-manual-synthesis`  
**Created**: 2026-04-13  
**Status**: Draft  
**Input**: User description: "Cross-manual synthesis (Layer 4) for the manual assistant AI pipeline. Instead of retrieving chunks from one manual or all manuals as a flat pool, retrieve the top 3 chunks from EACH manual independently, generate a sub-answer per manual using Gemma via Ollama, then send all sub-answers to Gemma with a synthesis prompt that produces one coherent final answer and explicitly notes any conflicts between manuals."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Cross-Manual Answer with Conflict Detection (Priority: P1)

A technician asks a question with "All Manuals" selected. The system retrieves relevant chunks from each manual separately, generates a per-manual sub-answer, then synthesizes them into a single coherent response that names which manuals were consulted and flags any conflicting information between them.

**Why this priority**: This is the core feature — transforming the assistant from a flat-pool lookup tool into an expert that reasons across knowledge sources and surfaces contradictions.

**Independent Test**: Can be tested by asking a question that spans multiple uploaded manuals and verifying the response names consulted manuals and provides a synthesized answer rather than fragments from a single source.

**Acceptance Scenarios**:

1. **Given** multiple manuals are uploaded and the user selects "All Manuals", **When** the user asks a question that has relevant content in at least two manuals, **Then** the system retrieves chunks from each manual independently, generates sub-answers per manual, and returns a single synthesized answer that names each consulted manual.
2. **Given** multiple manuals contain contradictory information on the same topic, **When** the user asks about that topic with "All Manuals" selected, **Then** the synthesized answer explicitly flags the conflict and attributes each position to its source manual.
3. **Given** only one manual has relevant content for a question, **When** the user asks with "All Manuals" selected, **Then** the system still returns a synthesized answer attributing the information to that single manual (no error or degraded behavior).

---

### User Story 2 - Single-Manual Bypass (Priority: P1)

When a user selects a specific manual instead of "All Manuals", the existing single-manual pipeline is used without any synthesis step, preserving current behavior and performance.

**Why this priority**: Equally critical — existing users must not experience regressions or added latency when they intentionally scope their question to one manual.

**Independent Test**: Can be tested by selecting a single manual, asking a question, and verifying the response format and latency match the current behavior (no "manuals consulted" attribution, no synthesis overhead).

**Acceptance Scenarios**:

1. **Given** the user selects a specific manual, **When** they ask a question, **Then** the system uses the existing pipeline (flat chunk retrieval, single-pass answer generation) with no synthesis step.
2. **Given** the user selects a specific manual, **When** they ask a question, **Then** the response format is unchanged from the current behavior (no "manuals consulted" section, no conflict notes).

---

### User Story 3 - Source Attribution in Synthesized Answer (Priority: P2)

The synthesized answer clearly indicates which manuals contributed to the response so the technician can trace information back to authoritative sources.

**Why this priority**: Important for trust and auditability in a maintenance environment, but the core synthesis must work first.

**Independent Test**: Can be tested by asking a cross-manual question and verifying the response and/or source metadata identifies each contributing manual by name.

**Acceptance Scenarios**:

1. **Given** a synthesized answer is generated from three manuals, **When** the response is returned, **Then** the response metadata includes a list of all manuals that were consulted (manual ID and title).
2. **Given** a synthesized answer is generated, **When** the technician views the response, **Then** the answer text itself references which manual(s) each piece of information came from.

---

### Edge Cases

- What happens when only one manual exists in the corpus and "All Manuals" is selected? The system should behave identically to single-manual mode (one sub-answer, no synthesis needed).
- What happens when no manuals have relevant chunks (all chunks exceed the distance threshold)? The system returns the existing "not in the available manuals" response.
- What happens when the sub-answer generation for one manual fails (timeout/error) but others succeed? The system should still synthesize available sub-answers and note that one manual could not be consulted.
- What happens when all manuals return the "not found" sentinel for their sub-answers? The system returns the standard "not in the available manuals" response.
- How does the system handle very large numbers of manuals (e.g., 20+)? Sub-answer generation should be parallelized, but a reasonable cap on concurrent generations prevents resource exhaustion.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When "All Manuals" is selected, the system MUST retrieve the top qualifying chunks from each manual independently (per-manual retrieval) rather than from a single flat pool.
- **FR-002**: For each manual that returns qualifying chunks, the system MUST generate a sub-answer scoped to that manual's content.
- **FR-003**: The system MUST send all sub-answers to the language model with a synthesis prompt that produces one coherent final answer.
- **FR-004**: The synthesis prompt MUST instruct the model to explicitly note any conflicts or contradictions found between manuals.
- **FR-005**: The synthesized answer MUST indicate which manuals were consulted (by name).
- **FR-006**: When a specific manual is selected (not "All Manuals"), the system MUST use the existing single-manual pipeline with no synthesis overhead.
- **FR-007**: The system MUST skip synthesis when only one manual produces qualifying chunks (even in "All Manuals" mode), using the sub-answer directly.
- **FR-008**: The existing response format (answer, grounded, sources, model, duration, session_summary) MUST be preserved; any new fields (e.g., manuals_consulted) MUST be additive.
- **FR-009**: Sub-answer generation for multiple manuals MUST be parallelized to minimize added latency.
- **FR-010**: The system MUST apply the existing chunk reranking (distance threshold and max-chunks-per-manual cap) to each manual's chunks independently.

### Key Entities

- **Sub-Answer**: A per-manual intermediate response generated from one manual's chunks only. Contains the manual's identity and the answer text. Transient (not persisted).
- **Synthesis Result**: The final merged answer combining all sub-answers, with conflict annotations and source attribution. Transient (not persisted).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When multiple manuals contain relevant information, the synthesized answer references at least two distinct manual sources by name in 100% of cases.
- **SC-002**: When manuals contain contradictory information, the synthesized answer flags the conflict in at least 90% of cases.
- **SC-003**: Single-manual queries experience zero additional latency compared to the current pipeline.
- **SC-004**: Cross-manual queries complete within 3x the time of a single-manual query (sub-answer parallelization keeps overhead bounded).
- **SC-005**: The existing response format remains backward-compatible — no fields are removed or renamed.
- **SC-006**: Technicians can identify which manual contributed each piece of information in the synthesized answer.

## Assumptions

- The existing chunk reranking thresholds (distance <= 0.45, max 3 chunks per retrieval) are appropriate for per-manual retrieval and do not need re-tuning for this feature.
- The Ollama server has sufficient capacity to handle parallel sub-answer generation for up to 10 manuals concurrently (bounded by existing server RAM constraints).
- The existing `search_manual_chunks` RPC can be called once per manual or a new RPC can group results by manual — implementation will determine the best approach.
- The rolling session summary and conversation history features (specs 042-045) continue to operate at the pipeline level and feed into each sub-answer generation identically.
- Sub-answer and synthesis prompts will be in the same language as the user's question (Arabic or English), consistent with the existing behavior.
- The current "All Manuals" mode is triggered when `manual_id` is null/omitted in the request — no UI changes are needed to activate cross-manual synthesis.
