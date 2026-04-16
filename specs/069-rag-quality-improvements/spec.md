# Feature Specification: RAG Quality Improvements

**Feature Branch**: `069-rag-quality-improvements`  
**Created**: 2026-04-16  
**Status**: Draft  
**Input**: User description: "RAG Quality Improvements — 4 fixes: multi-chunk retrieval, confidence threshold, strict system prompt, source references"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Accurate Answers from Multiple Knowledge Base Sources (Priority: P1)

A maintenance technician asks the AI assistant a question about a procedure. The system retrieves the top 3 most relevant validated Q&A entries from the knowledge base and uses them as combined context for the LLM, producing a more comprehensive and accurate answer than a single-source lookup.

**Why this priority**: Multi-chunk retrieval is the foundation — all other improvements (threshold, sources, prompt) depend on having multiple scored results available.

**Independent Test**: Ask a question that spans multiple validated Q&A entries (e.g., a procedure with setup steps in one entry and execution steps in another). Verify the answer synthesizes information from multiple sources.

**Acceptance Scenarios**:

1. **Given** a user asks a knowledge base question, **When** the system searches validated_qa, **Then** the top 3 matching entries are retrieved and combined as context for the LLM.
2. **Given** fewer than 3 validated_qa entries exist, **When** a question is asked, **Then** the system uses however many entries are available (1 or 2) without error.
3. **Given** a question with strong matches, **When** the LLM generates an answer, **Then** it receives all 3 source texts clearly delineated (labeled Source 1, Source 2, Source 3).

---

### User Story 2 - Graceful Rejection of Unrelated Questions (Priority: P1)

A user asks a question completely outside the knowledge base domain (e.g., "what's the weather today"). Instead of producing a hallucinated or irrelevant answer, the system detects that no validated Q&A entries match with sufficient confidence and returns a helpful fallback message — without wasting an LLM API call.

**Why this priority**: Prevents hallucination and saves compute costs. Equally critical to retrieval quality.

**Independent Test**: Ask an off-topic question and verify the system returns a low-confidence fallback message without invoking the LLM.

**Acceptance Scenarios**:

1. **Given** a user asks an off-topic question, **When** the best similarity score among retrieved entries is below the confidence threshold (0.70), **Then** the system returns a fixed fallback message without calling the LLM.
2. **Given** a user asks a relevant question, **When** the best similarity score is at or above the threshold, **Then** the system proceeds to generate an LLM answer normally.
3. **Given** a borderline question, **When** the best score is exactly at the threshold boundary, **Then** the system proceeds to the LLM (threshold is inclusive: >= 0.70 passes).

---

### User Story 3 - Context-Only Answers Without Hallucination (Priority: P2)

A supervisor asks the AI assistant a technical question. The system's LLM is constrained by a strict system prompt to answer exclusively from the provided validated Q&A context, never from its general training knowledge. If the context doesn't contain the answer, the LLM explicitly says so.

**Why this priority**: Reduces risk of incorrect or fabricated technical answers in a safety-critical aviation maintenance environment.

**Independent Test**: Ask a question where the retrieved context is tangentially related but doesn't contain the exact answer. Verify the LLM responds with "I don't have that information in the knowledge base" rather than guessing.

**Acceptance Scenarios**:

1. **Given** the LLM receives retrieved context and a question, **When** generating an answer, **Then** the system prompt enforces context-only answering with explicit rules against hallucination.
2. **Given** the context contains the answer, **When** the LLM responds, **Then** it references the source (e.g., "According to source 1...").
3. **Given** the context does not contain the answer, **When** the LLM responds, **Then** it states it doesn't have the information rather than guessing.

---

### User Story 4 - Source References in Every Answer (Priority: P2)

A user receives an answer from the AI assistant. The response includes not just the answer text, but also the source entries used — each with an identifier, the original question text, and a relevance score. This lets users judge answer quality and trace the information back to its validated source.

**Why this priority**: Builds user trust and enables verification of AI-generated answers against known sources.

**Independent Test**: Ask a well-matched question and verify the API response includes a `sources` array with entry IDs, question text, and rounded similarity scores alongside a confidence level.

**Acceptance Scenarios**:

1. **Given** a successful answer is generated, **When** the API responds, **Then** it includes `answer`, `confidence` (high/medium/low), `score` (best match), and `sources` (array of up to 3 entries with id, question_text, score).
2. **Given** a low-confidence rejection, **When** the API responds, **Then** `sources` is an empty array, `confidence` is "low", and the `score` reflects the best match found.
3. **Given** multiple sources are used, **When** scores are included, **Then** all scores are rounded to 2 decimal places.
4. **Given** the existing frontend consumes the `answer` field, **When** new fields are added, **Then** the `answer` field remains in the same position and format — new fields are purely additive.

---

### Edge Cases

- What happens when the validated_qa table is empty? The system returns the fallback message (no matches = score 0.0, below threshold).
- What happens when only 1 or 2 entries exist in validated_qa? The system returns as many as available without error.
- What happens when all 3 retrieved entries have scores above 0.70 but the question is ambiguous? The LLM synthesizes from all 3 sources; the strict prompt prevents speculation beyond context.
- What happens when the embedding service is unreachable? Existing error handling applies — this spec does not change error paths.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST retrieve the top 3 matching entries from validated_qa (by cosine similarity) instead of the current top 1.
- **FR-002**: System MUST retain the similarity score for each retrieved entry for use in threshold checks and response metadata.
- **FR-003**: System MUST define a confidence threshold as a named constant (0.70) that is easy to adjust without inline code changes.
- **FR-004**: System MUST compare the highest similarity score among retrieved entries against the confidence threshold before invoking the LLM.
- **FR-005**: System MUST return a fixed fallback message when the highest score is below the threshold, without making any LLM API call.
- **FR-006**: System MUST include a strict system prompt on all RAG LLM calls that constrains the model to answer exclusively from provided context.
- **FR-007**: System MUST format the retrieved entries as clearly labeled sources (Source 1, Source 2, Source 3) in the LLM context.
- **FR-008**: System MUST return a `confidence` field in the API response: "high" (score >= 0.85), "medium" (score >= 0.70), "low" (score < 0.70).
- **FR-009**: System MUST return a `score` field (best match, rounded to 2 decimal places) in the API response.
- **FR-010**: System MUST return a `sources` array in the API response, containing up to 3 entries each with `id`, `question_text`, and `score` (rounded to 2 decimal places).
- **FR-011**: System MUST NOT break the existing `answer` field format — new response fields are additive only.
- **FR-012**: Changes MUST be limited to the backend (Python/FastAPI). No frontend (Flutter/Dart) changes.
- **FR-013**: System MUST NOT modify the AI provider resolver, Supabase schema, environment files, or non-KB AI features (letter assistant, entity extraction, etc.).

### Key Entities

- **Validated Q&A Entry**: A pre-approved question-answer pair stored with a vector embedding. Key attributes: id, question_text, validated_answer, question_embedding. Used as the knowledge base for RAG retrieval.
- **RAG Response**: The API output containing the LLM-generated answer plus metadata. Key attributes: answer, confidence, score, sources array.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every successful AI answer is generated from up to 3 knowledge base sources instead of 1, improving answer completeness.
- **SC-002**: Off-topic or unrelated questions are rejected without an LLM call when no knowledge base entry matches with >= 70% confidence.
- **SC-003**: The AI never produces answers based on general training knowledge — all answers are grounded exclusively in the provided knowledge base context.
- **SC-004**: Every API response includes source references (entry ID, original question, relevance score) so users can trace answer provenance.
- **SC-005**: The existing frontend continues to function without modification — the answer field and existing response fields are unchanged.
- **SC-006**: LLM API costs are reduced for off-topic queries by short-circuiting before the generation step.

## Assumptions

- The validated_qa table already has vector embeddings indexed for cosine similarity search (pgvector).
- The existing `search_validated_qa` RPC supports a `match_count` parameter that can be set to 3.
- The AI provider resolver already accepts a system prompt parameter and passes it through to all providers (Ollama, Gemini, Mistral, Groq).
- A confidence threshold of 0.70 is a reasonable starting point — this can be tuned later based on production query patterns.
- The validated_qa shortcut flow (returning cached validated answers before the full RAG pipeline) is the target of these changes, not the manual-chunks RAG pipeline.
- The frontend will be updated in a separate task to display the new `sources`, `confidence`, and `score` fields.
