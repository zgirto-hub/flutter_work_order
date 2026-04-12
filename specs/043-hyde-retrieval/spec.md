# Feature Specification: HyDE Retrieval for Manual Assistant

**Feature Branch**: `043-hyde-retrieval`  
**Created**: 2026-04-12  
**Status**: Draft  
**Input**: User description: "HyDE (Hypothetical Document Embedding) for the manual assistant AI pipeline. Before searching the vector database, ask Gemma via Ollama to write a short hypothetical answer that would appear in a civil aviation technical manual, then embed that hypothetical answer instead of the raw user question. This dramatically improves retrieval quality for vague or exploratory questions."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Vague Question Gets Relevant Results (Priority: P1)

A technician types a vague or exploratory question like "what do I need to know about landing gear?" into the AI assistant. Instead of embedding the raw question (which produces poor vector matches), the system first generates a hypothetical manual passage that would answer the question, then uses that passage's embedding to search the vector database. The technician receives a grounded, relevant answer drawn from the actual manuals.

**Why this priority**: This is the core value proposition of HyDE. Vague and exploratory questions are the most common failure mode for the current retrieval pipeline, and this directly addresses it.

**Independent Test**: Can be fully tested by asking a vague question and verifying that the retrieved chunks are more relevant than what the current raw-embedding approach returns. Delivers immediate improvement in answer quality.

**Acceptance Scenarios**:

1. **Given** the manual corpus contains landing gear maintenance procedures, **When** a technician asks "what do I need to know about landing gear?", **Then** the system generates a hypothetical answer, embeds it, and retrieves relevant landing gear manual sections instead of generic or unrelated chunks.
2. **Given** the manual corpus contains turbine inspection checklists, **When** a technician asks "tell me about engine checks", **Then** the retrieved chunks are about turbine/engine inspection procedures rather than loosely related content.
3. **Given** the AI model is available, **When** a question is asked, **Then** the hypothetical document generation adds no more than a few seconds to the overall response time.

---

### User Story 2 - Follow-Up Question with Query Rewrite + HyDE (Priority: P2)

A technician has an ongoing conversation and asks a follow-up question like "what about the hydraulic part?" The system first rewrites the query (resolving pronouns using conversation history), then generates a hypothetical answer from the rewritten query, and finally embeds that hypothetical answer for retrieval. Both pipeline stages work in sequence without conflict.

**Why this priority**: Query rewriting already exists and must continue to work. HyDE must compose cleanly with it rather than replacing it.

**Independent Test**: Can be tested by starting a multi-turn conversation and asking a follow-up with pronouns. Verify that the rewritten query feeds into HyDE and produces relevant retrieval results.

**Acceptance Scenarios**:

1. **Given** a conversation about landing gear maintenance, **When** the technician asks "what about the hydraulic part?", **Then** the query is first rewritten to a self-contained question, and then HyDE generates a hypothetical answer from that rewritten query.
2. **Given** there is no conversation history, **When** a standalone question is asked, **Then** query rewriting is skipped and HyDE runs directly on the original question.

---

### User Story 3 - Graceful Fallback When HyDE Fails (Priority: P2)

The hypothetical document generation step fails (model timeout, model unavailable, empty response). The system falls back to the existing behavior: embedding the (possibly rewritten) query directly. The technician still gets an answer, just without the HyDE quality improvement.

**Why this priority**: Reliability is critical for a production assistant. HyDE is an optimization, not a requirement - the system must never break because of it.

**Independent Test**: Can be tested by simulating a generation failure and verifying the system still returns an answer using the fallback embedding path.

**Acceptance Scenarios**:

1. **Given** the generation model times out during HyDE, **When** a question is asked, **Then** the system logs a warning and proceeds by embedding the rewritten (or original) query directly.
2. **Given** the generation model returns an empty response, **When** a question is asked, **Then** the system falls back to embedding the query directly.

---

### Edge Cases

- What happens when the hypothetical answer is in a different language than the manuals? The generation prompt instructs the model to match the language of the question, which aligns with the manual content language.
- What happens when the question is already very specific (e.g., "What is the torque spec for bolt AN3-7A?")? HyDE may not improve results for highly specific factual queries, but should not degrade them since the hypothetical answer will contain similar specific terms.
- What happens when the generation model produces a hallucinated hypothetical answer? This is acceptable because the hypothetical answer is only used for embedding similarity, not shown to the user.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST generate a hypothetical manual passage in response to each user question before performing vector search.
- **FR-002**: System MUST embed the hypothetical passage (not the raw question) and use that embedding for vector similarity search.
- **FR-003**: The HyDE generation MUST run after query rewriting, using the rewritten query as input when conversation history is present.
- **FR-004**: System MUST fall back to embedding the query directly if hypothetical document generation fails for any reason (timeout, empty response, model error).
- **FR-005**: System MUST log the hypothetical generation step (success or fallback) for observability.
- **FR-006**: The hypothetical generation prompt MUST instruct the model to produce a short passage (1-2 paragraphs) in the style of a civil aviation technical manual, in the same language as the question.
- **FR-007**: The hypothetical answer MUST NOT be shown to the user; it is used solely for embedding-based retrieval.
- **FR-008**: The original user question (not the hypothetical answer) MUST still be used in the final answer-generation prompt sent to the LLM.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Vague or exploratory questions retrieve noticeably more relevant manual sections compared to the current approach, as verified by manual inspection of at least 5 test queries.
- **SC-002**: The HyDE step adds no more than 5 seconds to the total question-answering pipeline under normal conditions.
- **SC-003**: When HyDE generation fails, the system still returns an answer within the same timeframe as the current pipeline (no user-visible error).
- **SC-004**: The existing query rewriting feature continues to function correctly for follow-up questions in multi-turn conversations.

## Assumptions

- The server has sufficient capacity to handle an additional short generation call per question without significantly degrading overall performance.
- The same model used for final answer generation can also be used for hypothetical document generation, avoiding the need for a separate model.
- A short timeout is appropriate for the HyDE generation step since it only needs to produce 1-2 paragraphs.
- Embedding models produce better vector matches when given a passage-style input (the hypothetical answer) versus a question-style input (the raw query), which is the documented benefit of HyDE.
- The pipeline order is: raw question -> query rewrite (if history) -> HyDE generation -> embed hypothetical -> vector search -> build prompt with original question -> generate final answer.
