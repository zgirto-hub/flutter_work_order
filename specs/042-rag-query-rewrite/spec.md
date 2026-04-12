# Feature Specification: RAG Query Rewrite

**Feature Branch**: `042-rag-query-rewrite`  
**Created**: 2026-04-12  
**Status**: Draft  
**Input**: User description: "Query rewriting before retrieval for the manual assistant AI pipeline. Before embedding the user's question, rewrite it into a self-contained search query using the last 3 conversation turns and Gemma via Ollama. The rewrite should resolve references like 'what about the second point?' into explicit queries."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Contextual Follow-Up Questions Resolve Correctly (Priority: P1)

A technician is using the "Ask the AI" manual assistant. They ask "What is the inspection interval for the APU?" and receive an answer citing three key points. They then ask "What about the second point?" Without query rewriting, the system would embed the vague follow-up literally and retrieve irrelevant documents. With query rewriting, the system rewrites the question into something like "What are the details about [specific second point from prior answer] for the APU inspection interval?" before retrieval, returning accurate and relevant results.

**Why this priority**: This is the core value of the feature — resolving ambiguous references in follow-up questions so retrieval returns relevant documents instead of noise.

**Independent Test**: Can be tested by having a multi-turn conversation where the second question contains a pronoun or reference to a prior answer, and verifying the retrieved documents are relevant.

**Acceptance Scenarios**:

1. **Given** a user has asked "What is the inspection interval for the APU?" and received an answer, **When** they ask "Tell me more about that", **Then** the system rewrites the query to include explicit APU inspection context before retrieval, and the answer is relevant to APU inspections.
2. **Given** a user has asked about a topic and the AI listed multiple points, **When** they ask "What about the third point?", **Then** the system resolves "the third point" into the actual content of that point from the prior response and retrieves relevant documents.
3. **Given** a user asks a self-contained question with no prior context (first message), **When** the query is processed, **Then** the system uses the original question as-is (no rewrite degradation).

---

### User Story 2 - Transparent Rewriting With No Latency Perception (Priority: P2)

The query rewriting step happens automatically and invisibly. The user types their question and receives an answer without noticing any additional processing step. The rewritten query is used only internally for retrieval; the user's original question is still displayed in the conversation.

**Why this priority**: If the rewrite step adds noticeable delay or visibly alters the user's question, adoption suffers. The feature must be seamless.

**Independent Test**: Can be tested by timing the end-to-end response with and without the rewrite step and verifying the user's original question text is preserved in the conversation display.

**Acceptance Scenarios**:

1. **Given** a user submits a follow-up question, **When** the system rewrites the query, **Then** the total added latency from the rewrite step is under 2 seconds.
2. **Given** a user submits any question, **When** the conversation is displayed, **Then** the user's original question text is shown (not the rewritten version).

---

### User Story 3 - Graceful Fallback on Rewrite Failure (Priority: P3)

If the rewrite service is unavailable or returns an error, the system falls back to using the user's original query for embedding and retrieval. The user still gets an answer, though it may be less contextually accurate for ambiguous follow-ups.

**Why this priority**: Reliability is essential. The rewrite step is an enhancement, not a gate — the system must never fail entirely because the rewrite failed.

**Independent Test**: Can be tested by simulating service unavailability and verifying the pipeline still returns an answer using the raw user query.

**Acceptance Scenarios**:

1. **Given** the rewrite service is unreachable, **When** a user asks a follow-up question, **Then** the system uses the original query for retrieval and returns an answer (with no error shown to the user).
2. **Given** the rewrite service returns a malformed or empty response, **When** a user asks a question, **Then** the system falls back to the original query.

---

### Edge Cases

- What happens when the conversation has fewer than 3 prior turns? The system uses whatever turns are available (0, 1, or 2).
- What happens when the user's question is already self-contained and needs no rewriting? The rewritten query should be semantically equivalent to the original, causing no degradation in retrieval quality.
- What happens when the prior conversation context is very long? The system truncates to the last 3 turns to keep the rewrite prompt within model limits.
- What happens when the user switches topics mid-conversation (e.g., asks about APU, then asks about landing gear)? The rewrite should reflect the new topic, not force context from the old one.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST rewrite the user's question into a self-contained search query before embedding, using the last 3 conversation turns as context.
- **FR-002**: System MUST use the existing local language model integration to perform query rewriting.
- **FR-003**: System MUST preserve the user's original question text in the conversation display; only the retrieval pipeline uses the rewritten query.
- **FR-004**: System MUST fall back to the original user query if the rewrite step fails (timeout, error, empty response).
- **FR-005**: System MUST resolve pronouns and references (e.g., "it", "that", "the second point") into explicit terms based on conversation history.
- **FR-006**: System MUST pass the rewritten query (not the original) to the embedding and vector search steps.
- **FR-007**: System MUST handle first-turn questions (no prior context) without errors, using the original question directly or producing an equivalent rewrite.
- **FR-008**: System MUST limit the conversation context window to the last 3 turns (user + assistant message pairs) to bound rewrite prompt size.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Follow-up questions containing pronouns or references retrieve relevant documents at least 80% of the time (compared to baseline without rewriting).
- **SC-002**: The query rewrite step adds no more than 2 seconds of additional latency to the end-to-end response time.
- **SC-003**: First-turn (context-free) questions show no degradation in retrieval relevance compared to the current system.
- **SC-004**: The system continues to return answers 100% of the time even when the rewrite service is unavailable (graceful fallback).

## Assumptions

- The existing local language model service is available and running a model suitable for query rewriting.
- The existing conversation memory (Layer 3 from the manual assistant) already stores recent turns and can provide the last 3 turns to the rewrite step.
- The rewrite step is backend-only; no frontend changes are needed beyond what already exists.
- The ask_question endpoint is the sole integration point for this feature.
- The language model can perform query rewriting adequately with a simple system prompt and few-shot examples, without fine-tuning.
