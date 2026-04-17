# Feature Specification: RAG Pipeline Latency Optimization

**Feature Branch**: `077-rag-pipeline-parallelize`  
**Created**: 2026-04-17  
**Status**: Draft  
**Input**: User description: "Optimize RAG pipeline latency by parallelizing independent stages and adding smart skip heuristics"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Faster Answers for Simple Factual Queries (Priority: P1)

A maintenance technician opens the "Ask the AI" assistant and types a direct factual question like "what is as1-cont ip address?" or "what is the default port for AIDA-NG?". The system recognizes this is a simple lookup query, skips the unnecessary hypothetical document generation step, and returns the answer noticeably faster than before.

**Why this priority**: Simple factual lookups are the most common query type. Users currently wait ~55-60 seconds for a straightforward IP address or configuration value. Cutting this to ~30-35 seconds has the highest impact on daily user satisfaction.

**Independent Test**: Can be fully tested by asking a direct factual question (e.g. "what is cs1-ops IP address?") and measuring the total pipeline time. The response should arrive measurably faster than the current ~55s baseline, with the `hyde_ms` field showing `null` or `0` (skipped).

**Acceptance Scenarios**:

1. **Given** a user asks a direct factual question containing a specific hostname, IP address, or component name, **When** the pipeline processes the query, **Then** the HyDE stage is skipped and the query is embedded directly for vector search.
2. **Given** a user asks a direct factual question with no conversation history, **When** the pipeline processes the query, **Then** the query rewrite stage is also skipped (returns original question immediately), reducing total pipeline time by the combined rewrite + HyDE overhead.
3. **Given** a user asks a direct factual question, **When** the pipeline completes, **Then** the `latency_breakdown` in the response accurately reflects which stages were skipped (showing `null` or `0` for skipped stages).

---

### User Story 2 - Faster Answers for Complex Multi-Turn Questions (Priority: P2)

A technician is in an ongoing conversation about CADAS-ATS troubleshooting. They ask a follow-up like "what about the backup server?". The system needs both query rewrite (to resolve "the backup server" using conversation context) and HyDE (to generate a hypothetical passage for better retrieval). These two stages now run simultaneously instead of one after the other, shaving ~10-15 seconds off the total wait time.

**Why this priority**: Multi-turn conversations are the second most common usage pattern. Even when both stages are needed, parallelizing them delivers a meaningful speedup that users will notice on every follow-up question.

**Independent Test**: Can be tested by starting a conversation (e.g. "how to restart CADAS-ATS?"), then asking a follow-up ("what about the logs?") and measuring pipeline time. The combined rewrite + HyDE wall-clock time should be roughly equal to the slower of the two stages (not the sum).

**Acceptance Scenarios**:

1. **Given** a user asks a follow-up question with conversation history present, **When** the pipeline processes the query, **Then** query rewrite and HyDE generation run concurrently (in parallel).
2. **Given** both rewrite and HyDE complete successfully in parallel, **When** the pipeline continues, **Then** the rewritten query is used for system detection and validated QA checks, and the HyDE text is used for embedding — same as the current sequential behavior.
3. **Given** one of the parallel stages fails (e.g. HyDE times out but rewrite succeeds), **When** the pipeline continues, **Then** the successful result is used and the failed stage falls back gracefully (HyDE failure means direct query embedding, rewrite failure means original question used).

---

### User Story 3 - Accurate Latency Reporting (Priority: P3)

An administrator reviews the latency breakdown displayed in the AI assistant response to understand where time is spent. The breakdown correctly reflects the parallel execution — showing individual stage times that may overlap rather than summing to the total pipeline time.

**Why this priority**: Accurate diagnostics enable ongoing performance tuning. Without correct latency reporting, future optimization efforts will be misguided.

**Independent Test**: Can be tested by asking any question and inspecting the `latency_breakdown` object in the response. Stage times should be individually accurate, and the total should reflect wall-clock time (not sum of stages).

**Acceptance Scenarios**:

1. **Given** rewrite and HyDE run in parallel, **When** the response is returned, **Then** `rewrite_ms` and `hyde_ms` each reflect their own wall-clock duration, and `total_ms` reflects that they overlapped.
2. **Given** HyDE is skipped for a direct lookup query, **When** the response is returned, **Then** `hyde_ms` is `null` or `0`, clearly indicating the stage was not executed.

---

### Edge Cases

- What happens when a query looks like a direct lookup but HyDE would have improved results? The system should err on the side of speed for clear factual patterns (hostnames, IPs, specific component names) and accept a minor retrieval quality trade-off.
- How does the system handle both parallel stages timing out simultaneously? Both failures should be handled gracefully — rewrite falls back to original question, HyDE falls back to direct embedding.
- What happens when the query rewrite changes the question significantly (e.g. resolving a pronoun to a system name) but HyDE ran on the original question? HyDE should use the original question since it runs in parallel with rewrite; the embedding step after both complete should prefer the HyDE text (generated from original question) since it still produces a useful hypothetical passage.
- What happens with very short queries like "ip?" or "aida"? These should still go through the normal pipeline (HyDE not skipped) since they are ambiguous, not direct lookups.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST run query rewrite and HyDE generation concurrently when both stages are needed (conversation history is present and query is not a direct lookup).
- **FR-002**: System MUST skip the HyDE stage entirely for queries identified as direct factual lookups, proceeding directly to embedding the query (or rewritten query) for vector search.
- **FR-003**: The direct-lookup detection heuristic MUST identify queries containing specific technical identifiers: hostnames (e.g. `as1-cont`, `cs2-ops`), IP addresses (e.g. `172.31.x.x`), and component names that appear as exact terms in the knowledge base (e.g. "AIDA 1", "CISECA 2", "Mux 1").
- **FR-004**: System MUST skip query rewrite when no conversation history is present, regardless of query type (this is already the current behavior and must be preserved).
- **FR-005**: System MUST handle partial failures in parallel execution gracefully — if one stage fails and the other succeeds, the pipeline continues using the successful result and the appropriate fallback for the failed stage.
- **FR-006**: System MUST record accurate per-stage latency in the `latency_breakdown` response field, reflecting actual wall-clock time per stage (not cumulative).
- **FR-007**: System MUST preserve all existing pipeline behavior for non-optimized paths: validated QA fast-path, system detection, grounding checks, fallback generation, and source attribution.
- **FR-008**: The HyDE skip heuristic MUST NOT trigger for ambiguous or vague queries (e.g. "ip?", "server", "how to restart") — only for queries with clearly identifiable technical terms.
- **FR-009**: System MUST use the rewritten query (not original) for the post-rewrite validated QA check and system detection, even when HyDE ran in parallel on the original question.
- **FR-010**: When both stages run in parallel, the embedding step MUST wait for both to complete before proceeding, using the HyDE text for embedding if available, otherwise the rewritten query.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Simple factual queries (direct lookups with hostnames, IPs, component names) complete the full pipeline in under 40 seconds, down from the current ~55-60 seconds.
- **SC-002**: Multi-turn follow-up questions complete the full pipeline at least 8 seconds faster than the current baseline, due to parallel rewrite + HyDE execution.
- **SC-003**: No degradation in answer quality — the same questions that returned correct, grounded answers before the optimization continue to do so after.
- **SC-004**: The latency breakdown in responses accurately reflects parallel execution, with `total_ms` less than the sum of `rewrite_ms` + `hyde_ms` when both run concurrently.
- **SC-005**: Zero new failure modes introduced — all existing error handling and fallback paths continue to function correctly.

## Assumptions

- The Ollama server on the deployment machine can handle two concurrent inference requests without significant throughput degradation (rewrite and HyDE use the same model). If the server serializes requests internally, the parallelization benefit will be reduced but correctness is unaffected.
- The direct-lookup heuristic uses pattern matching (regex for IPs, hostname patterns, known component name lists) rather than an additional LLM call, so it adds negligible latency.
- The existing `_StageTimer` context manager can be used independently for each parallel stage without thread-safety issues (each stage gets its own timer instance writing to the shared `breakdown` dict with different keys).
- Frontend display of `latency_breakdown` does not assume stages are sequential — no frontend changes are needed.
- The query rewrite stage timeout (10s) and HyDE timeout (30s) remain unchanged; parallelization does not change individual stage timeouts.
