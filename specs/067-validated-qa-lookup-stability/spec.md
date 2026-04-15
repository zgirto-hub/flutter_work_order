# Feature Specification: Validated-QA Lookup Stability

**Feature Branch**: `067-validated-qa-lookup-stability`
**Created**: 2026-04-15
**Status**: Draft
**Input**: User description: "Validated_qa cache lookup must return the cached answer consistently for identical repeated questions, regardless of accumulated conversation history."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Repeated Lookup Returns Cached Answer Every Time (Priority: P1)

A technician asks the AI Assistant the same question multiple times in a row during one chat session (for example, checking the recorded credentials for a system while working through a task). Each time, the assistant should return the expert-validated cached answer with the "Verified Answer" badge and a fast response time.

**Why this priority**: The validated-QA cache exists specifically to give technicians instant, authoritative answers for recurring operational questions. When the cache silently misses on a question that was previously verified, the technician sees "This information is not in the available manuals" — the opposite of what the cache was built to deliver. This erodes trust in the assistant and wastes 20+ seconds per miss running an unnecessary full RAG pipeline.

**Independent Test**: In a fresh chat session, ask a question known to have a validated-QA entry (e.g., "what is the password of AIDA NG system?"). Without clearing the session, re-ask the exact same question 4 more times in succession. All 5 responses must come from the validated-QA cache (badge + sub-2-second response).

**Acceptance Scenarios**:

1. **Given** a validated-QA entry exists for question Q with similarity threshold T, **When** the technician asks Q in a fresh session, **Then** the assistant returns the cached answer with the Verified Answer badge.
2. **Given** the technician has already asked Q once in the current session and received the cached answer, **When** they re-ask Q verbatim with the prior turn still in history, **Then** the assistant returns the same cached answer (not a full RAG response).
3. **Given** the technician has asked Q five times in a row in the same session, **When** reviewing the five responses, **Then** all five are identical cached answers (no alternation between cache hits and "not in manuals" misses).

---

### User Story 2 - Lookup Remains Stable Across Interleaved Topics (Priority: P2)

After asking a question that hits the cache, the technician asks an unrelated question, then returns to the original question (or a trivially paraphrased version). The original question should still hit the cache.

**Why this priority**: Real conversations interleave topics. If conversation history pollutes lookup after a single topic switch, the cache is effectively useless past turn one.

**Independent Test**: In one session, ask Q1 (known cache hit), then ask Q2 (unrelated), then re-ask Q1. Q1 must hit the cache both times.

**Acceptance Scenarios**:

1. **Given** Q1 returned a cached answer on the first ask and the session then handled an unrelated Q2, **When** Q1 is re-asked verbatim, **Then** Q1 still returns the cached answer.
2. **Given** Q1 returned a cached answer, **When** the technician re-asks Q1 with trivial surface variation (e.g., "what is the password of aida ng system?" vs "what's the password of aida-ng?"), **Then** the same cached answer is returned.

---

### Edge Cases

- Genuinely context-dependent questions (e.g., bare "what's the password?" after discussing a specific system) must NOT hit the raw-question lookup — they remain ambiguous on their own and should fall through to the context-aware pipeline as they do today.
- If a validated-QA entry is deleted or re-embedded, the next lookup must reflect the new state (no stale in-memory caching beyond what already exists).
- Cross-language lookup behavior (Arabic question vs English cached entry, and vice versa) must match existing behavior.
- When multiple validated-QA entries exceed the similarity threshold for the raw question, existing top-match selection logic is preserved.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST perform the validated-QA similarity lookup against the raw user question as submitted, before any query rewriting, HyDE generation, or conversation-context augmentation.
- **FR-002**: The system MUST return the cached answer immediately when the raw-question lookup exceeds the existing similarity threshold, without running any downstream RAG stages (rewrite, HyDE, retrieval, rerank, generation).
- **FR-003**: When the raw-question lookup does NOT find a match above threshold, the system MUST fall through to the existing full pipeline (rewrite → HyDE → retrieval → rerank → generate) unchanged.
- **FR-004**: The system MUST produce identical validated-QA lookup results for the same raw question regardless of how many prior turns are present in the session's conversation history.
- **FR-005**: The system MUST preserve existing behavior for questions that require conversation context to resolve (pronoun references, "the previous one", trivial follow-ups that are not self-contained) — these must continue to flow through the context-aware pipeline.
- **FR-006**: The system MUST preserve the existing "Verified Answer" badge, source attribution, and activity-log audit trail when a raw-question lookup hits the cache.
- **FR-007**: The system MUST NOT create, update, or delete any validated-QA entries as part of this change; read-path only.

### Key Entities *(include if feature involves data)*

- **Validated-QA entry**: An expert-verified question/answer pair in the `validated_qa` table with an associated question embedding and similarity threshold. Written by the existing thumbs-up / admin flow (not modified by this feature).
- **Raw user question**: The verbatim text submitted by the technician before any server-side transformation.
- **Rewritten query**: The conversation-aware reformulation produced by the query-rewrite stage. Currently used for validated-QA lookup (the bug); will no longer be used for the first-pass lookup after this change.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In the 5-identical-asks test (Story 1 independent test), 100% of responses must be cache hits. Before this fix, observed hit rate across such runs is ~50% (alternating).
- **SC-002**: When a validated-QA entry exists for a question, the end-to-end response time for that question must be under 2 seconds on every ask, regardless of conversation position. Today the miss path takes 20–25 seconds.
- **SC-003**: No regression on context-dependent follow-ups: questions that require conversation context to be meaningful (pronouns, "that one", etc.) must continue to behave as they do today. Measured by a regression test list of at least 5 known context-dependent questions — all must match the pre-fix baseline.
- **SC-004**: Activity-log "validated_qa_hit" events must increase in proportion to the improved hit rate; no decrease in recorded hits for any previously-hitting question.

## Assumptions

- The existing `validated_qa` table, embedding pipeline, and similarity threshold are correct and do not need tuning as part of this work. The bug is purely that the wrong query text is being embedded for lookup.
- Conversation history and query rewriting remain valuable for the non-cached path and will not be removed.
- The current similarity threshold was calibrated against raw-question-like inputs (since that's what users type); running the lookup against the rewritten query was an accidental layering, not a deliberate design choice.
- Running the pre-rewrite lookup adds one vector similarity query to the hot path but removes the rewrite + HyDE + retrieval + rerank + generation stages on cache hits, yielding a net latency improvement.
- Commit `b25ec13` (prevent context-dependent follow-ups from polluting validated_qa cache) fixed the write-side of this same layering problem; this spec is the read-side counterpart and does not re-address the write side.
