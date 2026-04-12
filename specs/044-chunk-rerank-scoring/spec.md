# Feature Specification: Chunk Reranking by Similarity Score

**Feature Branch**: `044-chunk-rerank-scoring`  
**Created**: 2026-04-12  
**Status**: Draft  
**Input**: User description: "Chunk reranking after retrieval using Supabase pgvector cosine similarity scores. After retrieving chunks from the vector database, filter and rerank them using the cosine similarity score already computed by pgvector — no extra Gemma calls needed. Only chunks with similarity score above 0.70 pass through, and only the top 3 are sent to Gemma for the final answer. This replaces passing all retrieved chunks blindly. Backend is FastAPI + Python. Vector search is Supabase pgvector with nomic-embed-text embeddings. The ask_question endpoint is in backend/routers/manual_assistant.py. Should work as the third step in the pipeline: query rewriting → HyDE → embed hypothetical → pgvector search WITH score → rerank by score → top 3 chunks → Gemma final answer."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Relevant answers from high-quality chunks only (Priority: P1)

A technician asks a question about a maintenance procedure. The system retrieves candidate chunks from the knowledge base, discards any with a similarity score below the quality threshold, ranks the remaining chunks by score, and sends only the top 3 to the language model for answer generation. The technician receives a more focused, accurate answer because the model is not distracted by loosely related content.

**Why this priority**: This is the core value proposition — improving answer quality by eliminating low-relevance noise before generation.

**Independent Test**: Can be tested by asking a specific technical question and verifying that only chunks scoring above the threshold are used in the answer, producing a more precise response than using all retrieved chunks.

**Acceptance Scenarios**:

1. **Given** a question with 5 retrieved chunks where 3 score above the threshold and 2 score below, **When** the system processes the retrieval results, **Then** only the 3 high-scoring chunks are sent to the language model for answer generation.
2. **Given** a question with 5 retrieved chunks where all 5 score above the threshold, **When** the system processes the retrieval results, **Then** only the top 3 chunks (by score, highest first) are sent to the language model.
3. **Given** a question with 5 retrieved chunks where only 1 scores above the threshold, **When** the system processes the retrieval results, **Then** only that 1 chunk is sent to the language model.

---

### User Story 2 - Graceful handling when no chunks pass the threshold (Priority: P2)

A technician asks a question that has no strong match in the uploaded manuals. All retrieved chunks score below the quality threshold. Instead of generating a hallucinated answer from irrelevant content, the system responds with the standard "not found" message.

**Why this priority**: Prevents misleading answers when the knowledge base genuinely lacks relevant content — critical for safety in an aviation maintenance context.

**Independent Test**: Can be tested by asking a question completely unrelated to any uploaded manual and verifying the system returns the "not in available manuals" response rather than fabricating an answer.

**Acceptance Scenarios**:

1. **Given** a question where all retrieved chunks score below the threshold, **When** the system processes the retrieval results, **Then** the system returns the standard "information not found" response without calling the language model.
2. **Given** zero qualifying chunks after filtering, **When** the response is built, **Then** the response is marked as ungrounded with an empty sources list.

---

### User Story 3 - Source attribution reflects only qualifying chunks (Priority: P3)

After receiving an answer, the technician sees source citations that correspond only to the chunks that actually contributed to the answer. Sources shown are limited to those that passed both the similarity threshold and the top-3 selection.

**Why this priority**: Improves trust and usability by ensuring displayed sources are genuinely relevant to the answer.

**Independent Test**: Can be tested by verifying that sources returned in the response correspond only to chunks that passed the threshold and were in the top 3.

**Acceptance Scenarios**:

1. **Given** an answer generated from 3 qualifying chunks, **When** the response is returned, **Then** the sources list contains only entries corresponding to those 3 chunks.
2. **Given** an answer generated from 2 qualifying chunks (only 2 passed the threshold), **When** the response is returned, **Then** the sources list contains exactly 2 entries.

---

### Edge Cases

- What happens when exactly 3 chunks tie at the threshold boundary (e.g., all score exactly at the threshold)? All 3 pass and are included.
- What happens when 4+ chunks score above the threshold with identical scores? The system takes the top 3 as returned by the database ordering (stable sort; first 3 in retrieval order).
- What happens when a chunk scores exactly at the threshold boundary? It passes the threshold (inclusive comparison).
- What happens if the threshold is set too high and no questions ever get grounded answers? The threshold is a tunable constant — administrators can lower it without code changes throughout the file.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST filter retrieved chunks, keeping only those with a similarity score at or above the configured quality threshold (default: 0.70 similarity / 0.30 distance).
- **FR-002**: System MUST rank qualifying chunks by similarity score in descending order (most similar first).
- **FR-003**: System MUST limit the chunks sent to the language model to a configurable maximum count (default: 3) after filtering and ranking.
- **FR-004**: System MUST return the "information not found" response when zero chunks pass the similarity threshold, without invoking the language model.
- **FR-005**: System MUST include only the qualifying, top-ranked chunks as sources in the response.
- **FR-006**: The similarity threshold and maximum chunk count MUST be defined as named constants that can be adjusted in a single location.
- **FR-007**: The existing pipeline steps (query rewriting, HyDE generation, embedding) MUST continue to function unchanged; reranking is inserted after retrieval and before prompt construction.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When the knowledge base contains both relevant and irrelevant content for a question, the answer references only information from the highest-scoring chunks rather than mixing in tangential content.
- **SC-002**: Questions with no relevant content in the knowledge base return the "not found" response instead of a fabricated answer at least as reliably as before (no regression).
- **SC-003**: Answer generation completes in the same or less time compared to current behavior, since fewer chunks are sent to the language model.
- **SC-004**: Sources displayed to the user correspond exactly to the chunks used for answer generation — no phantom sources from discarded chunks.

## Assumptions

- The vector search RPC already returns a distance score with each chunk (the current code references `chunk.get("distance")`). Cosine distance is used (similarity = 1 - distance), so a 0.70 similarity threshold corresponds to a 0.30 maximum distance.
- The current retrieval count of 5 chunks from the vector database is sufficient as the initial candidate pool. No increase is needed.
- The 0.70 similarity threshold and top-3 limit are starting values that may be tuned based on real-world usage but are reasonable defaults for the current embedding model.
- This change is backend-only. No frontend modifications are required.
- The HyDE-generated hypothetical answer improves embedding quality enough that the 0.70 threshold will not over-filter in normal usage.
