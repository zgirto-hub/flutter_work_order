# Feature Specification: RAG Latency Optimization

**Feature Branch**: `074-rag-latency-optimization`  
**Created**: 2026-04-16  
**Status**: Draft  
**Input**: User description: "Reduce /manuals/ask response time from ~50-100s to ~15-20s by eliminating redundant LLM calls and parallelizing independent pipeline stages"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Faster answers from the AI assistant (Priority: P1)

A technician opens the "Ask the AI" assistant and types a question about a maintenance procedure. Currently they wait 50-100 seconds for a response. After optimization, the same question returns an answer in 15-20 seconds — fast enough to be usable while standing at equipment.

**Why this priority**: The current latency makes the assistant impractical for field use. Cutting response time by 3-5x is the core goal of this spec.

**Independent Test**: Ask a question that hits the full document-search pipeline (not validated_qa cache). Measure wall-clock time from request to response. Must be under 25 seconds consistently.

**Acceptance Scenarios**:

1. **Given** a question that requires document retrieval across multiple manuals, **When** the user submits the question, **Then** the response arrives in under 25 seconds
2. **Given** a question that matches chunks from 5+ documents, **When** the pipeline runs, **Then** the system feeds all qualifying chunks into a single generation call instead of generating per-document sub-answers
3. **Given** the latency breakdown in the response, **When** compared to pre-optimization baselines, **Then** total time is reduced by at least 60%

---

### User Story 2 - Overlap LLM and non-LLM stages (Priority: P2)

The system overlaps LLM calls with non-LLM work (embedding, database queries) rather than running everything sequentially. Since Ollama serializes LLM requests on the server's single GPU, true parallel LLM inference is not feasible — but LLM generation can overlap with embedding computation and DB retrieval.

**Why this priority**: Stacks on top of the sub-answer removal for additional latency savings by reducing idle wait between stages. Independent of Story 1.

**Independent Test**: Submit a follow-up question that triggers query rewrite. Verify via latency breakdown that non-LLM stages (embedding, retrieval) overlap with LLM stages rather than waiting sequentially.

**Acceptance Scenarios**:

1. **Given** a follow-up question with conversation history, **When** the pipeline runs, **Then** LLM work (rewrite, HyDE) is sequenced but non-LLM work (embedding, DB retrieval) overlaps where possible
2. **Given** a first question (no history), **When** the pipeline runs, **Then** query rewrite is skipped entirely and only HyDE runs (no wasted LLM call)
3. **Given** one stage fails, **When** another succeeds, **Then** the pipeline continues gracefully using available results

---

### User Story 3 - Simple queries skip unnecessary stages (Priority: P3)

For straightforward questions without conversation history or with high-confidence validated QA matches, the system skips expensive pipeline stages that add no value.

**Why this priority**: Incremental optimization that reduces average latency further. Already partially implemented (validated QA fast-path exists); this extends the pattern.

**Independent Test**: Submit a standalone question (no history) and verify query rewrite is not invoked. Submit a question with a validated QA match above threshold and verify the full retrieval pipeline is bypassed.

**Acceptance Scenarios**:

1. **Given** a question with no conversation history, **When** the pipeline runs, **Then** the query rewrite stage is skipped (rewrite timing is null/zero in breakdown)
2. **Given** a high-confidence validated QA match, **When** the fast-path triggers, **Then** no HyDE, retrieval, or generation stages execute

---

### Edge Cases

- What happens when all retrieved document chunks are from a single document? The system should still use the direct-to-generation path (no synthesis needed for a single source).
- How does the system handle a question that retrieves chunks from 8+ documents? Chunks are capped and the top-ranked chunks are fed into the single generation call.
- What if the single combined prompt exceeds the model's context window? The system truncates lower-ranked chunks until the prompt fits within the model's context limit.
- What if HyDE fails but query rewrite succeeds (or vice versa) during parallel execution? The pipeline falls back to whichever result is available — raw query if HyDE fails, original query if rewrite fails.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST replace per-document sub-answer generation + synthesis with a single generation call that receives all qualifying chunks as context
- **FR-002**: System MUST overlap LLM stages with non-LLM stages (embedding, DB retrieval) where possible; Ollama serializes LLM requests on the single GPU, so parallel LLM calls are not expected to yield savings
- **FR-003**: System MUST skip query rewrite when no conversation history is provided (already true, must preserve)
- **FR-004**: System MUST preserve the existing latency breakdown fields in the response (embed, HyDE, rewrite, retrieval, rerank, generator, total)
- **FR-005**: System MUST maintain the same response format (answer, grounded, sources, confidence, score, source_type, etc.) — no breaking changes to the API contract
- **FR-006**: System MUST preserve source attribution in responses — each chunk's document name, section title, and page number must still appear in sources
- **FR-007**: System MUST cap the number of chunks sent to the generation prompt to avoid exceeding context limits
- **FR-008**: System MUST gracefully degrade if any parallelized stage fails — use available results and continue the pipeline
- **FR-009**: System MUST preserve the validated QA fast-path — high-confidence cached answers bypass the document pipeline entirely (no regression)
- **FR-010**: System MUST log the pipeline path taken (e.g., "direct-generation" vs "validated_qa") for observability

### Key Entities

- **Pipeline Stage**: A discrete processing step (rewrite, HyDE, embed, retrieve, generate) with its own latency measurement and failure handling
- **Chunk Context Block**: The combined text of top-ranked chunks from all qualifying documents, assembled into a single prompt for one generation call

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Average response time for document-retrieval questions drops from 50-100 seconds to under 25 seconds
- **SC-002**: Number of LLM generation calls per question drops from 3-9 (sub-answers + synthesis) to 1 (direct generation)
- **SC-003**: Answer quality (grounding, relevance, completeness) does not degrade — measured by existing RAG quality test suite
- **SC-004**: All existing latency breakdown fields continue to populate correctly in responses
- **SC-005**: Validated QA fast-path continues to work with no latency regression

## Assumptions

- The server can handle a single generation call with a larger context window (multiple document chunks combined) without running out of memory
- The current chunk distance and count thresholds are sufficient to keep the combined prompt within the model's context limits
- Answer quality from a single generation call with combined chunks is at least as good as per-document sub-answers followed by synthesis (to be validated by test suite)
- The latency breakdown timing model still works when stages overlap — each stage reports its own wall-clock time, total reflects end-to-end
- Ollama serializes LLM requests on the single GPU (no OLLAMA_NUM_PARALLEL) — parallelization gains come from overlapping LLM with non-LLM work, not from concurrent LLM inference
- No frontend changes are needed — the response schema remains identical

## Clarifications

### Session 2026-04-16

- Q: Does Ollama support parallel LLM inference on the server? → A: No — Ollama serializes requests on the single GPU. P2 reframed to overlap LLM with non-LLM stages only.
- Q: Fallback strategy if answer quality degrades after removing sub-answers? → A: No feature flag. Validate with RAG quality test suite before deploy; revert via git if quality drops in production.
