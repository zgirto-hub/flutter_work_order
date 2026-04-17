# Feature Specification: Diversity-Aware Retrieval Strategy

**Feature Branch**: `078-diversity-aware-retrieval`  
**Created**: 2026-04-17  
**Status**: Draft  
**Input**: User description: "Diversity-aware retrieval strategy for search_document_chunks — two-phase retrieval with document-level scoring and diversity floor to prevent vocabulary collision and preserve cross-manual synthesis"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Single-Topic Query Returns Clean Context (Priority: P1)

A maintenance technician asks a question about a specific procedure (e.g., "How do I replace an SNL card?") that exists in multiple overlapping documents. The system retrieves focused, non-redundant context from the most relevant document instead of mixing near-duplicate chunks from competing manuals. The AI assistant produces a clear, confident answer without contradictions.

**Why this priority**: This is the core problem — duplicate documents cause the AI to receive redundant, conflicting context and produce degraded answers. Fixing this directly improves answer quality for the majority of single-topic queries.

**Independent Test**: Can be tested by querying a topic covered by overlapping documents and verifying the returned chunks are dominated by the highest-scoring document, not split across duplicates.

**Acceptance Scenarios**:

1. **Given** the knowledge base contains `frequentis_system_diagnosis` and `MHS_SystemDiagnosis` (both covering SNL replacement), **When** a user asks "How do I replace an SNL card?", **Then** the returned chunks are dominated by the single highest-scoring document (max 3 chunks from it), not 3+3 near-duplicates split across both.
2. **Given** two documents contain nearly identical procedures with minor wording differences, **When** a user queries that procedure, **Then** the top document contributes up to 3 chunks and the duplicate document contributes at most 1 chunk (via the diversity floor, if it scores above the floor threshold).
3. **Given** only one document covers a topic, **When** a user queries that topic, **Then** retrieval behavior is unchanged from the current system — up to 3 chunks from that document are returned.

---

### User Story 2 - Cross-Manual Query Preserves Multi-Document Context (Priority: P1)

A maintenance technician asks a question that requires information from multiple distinct documents (e.g., "How does CNMS monitor CADAS-ATS?"). The system retrieves chunks from both relevant documents even when one document dominates the similarity scores, ensuring the AI assistant can synthesize a complete answer.

**Why this priority**: Cross-manual synthesis is a critical differentiator of the RAG pipeline. A retrieval strategy that kills cross-document questions while solving duplication would be a net regression.

**Independent Test**: Can be tested by querying a topic that spans two documents and verifying that both documents contribute at least 1 chunk to the result set.

**Acceptance Scenarios**:

1. **Given** CNMS_Knowledge_Base covers CNMS monitoring states and CADAS-ATS Admin covers CADAS-ATS administration, **When** a user asks "How does CNMS monitor the CADAS-ATS system?", **Then** the result includes chunks from both CNMS_Knowledge_Base AND CADAS-ATS-related documents.
2. **Given** a question references two systems, **When** the primary system's document scores 0.85 and the secondary system's document scores 0.65, **Then** the secondary document still contributes at least 1 chunk because it exceeds the diversity floor threshold.
3. **Given** a question references a system whose document scores 0.45 (below diversity floor), **When** retrieval runs, **Then** that document is excluded entirely — the floor only protects genuinely relevant secondary documents, not noise.

---

### User Story 3 - Backward-Compatible Defaults (Priority: P2)

Existing code that calls the search function without new parameters continues to work identically. The new parameters have sensible defaults that improve retrieval quality out of the box without requiring callers to opt in.

**Why this priority**: The retrieval function is called from multiple places in the pipeline. Breaking existing behavior would cause regressions across the entire RAG system.

**Independent Test**: Can be tested by running the existing RAG quality test suite before and after the change and verifying no regressions in score.

**Acceptance Scenarios**:

1. **Given** existing call-sites that pass only `query_embedding` and `limit`, **When** the updated function is deployed, **Then** those calls work without modification and return results with the same structure.
2. **Given** the function is called with default parameters, **When** retrieval runs, **Then** it uses top_docs_count=3, max_chunks_per_doc=3, and diversity_floor_threshold=0.60 as defaults.

---

### Edge Cases

- What happens when fewer than `top_docs_count` documents have matching chunks? The system uses all available documents without error.
- What happens when a single document has all top-20 chunks? That document gets `max_chunks_per_doc` chunks; no diversity floor chunks are added since no other document scored above the floor.
- What happens when all documents score below `diversity_floor_threshold`? Only the top `top_docs_count` documents contribute, with no floor chunks added.
- What happens when the initial search returns fewer than 20 chunks? The diversity selection operates on whatever chunks are available — the 20-chunk fetch is a ceiling, not a minimum.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST fetch up to 20 candidate chunks in the initial vector search phase (increased from the current `limit` parameter).
- **FR-002**: System MUST group candidate chunks by their source document after the initial search.
- **FR-003**: System MUST compute a document relevance score as the weighted aggregate of its chunk similarity scores (sum of top-3 chunk scores per document).
- **FR-004**: System MUST rank documents by their relevance score and select the top `top_docs_count` (default: 3) winning documents. Ties in aggregate score MUST be broken by the highest individual chunk score (most precise match wins).
- **FR-005**: System MUST apply a diversity floor: any document scoring >= `diversity_floor_threshold` (default: 0.60) that is NOT in the winning set gets exactly 1 guaranteed chunk (its highest-scoring chunk) added to the result set.
- **FR-006**: From each winning document, the system MUST select up to `max_chunks_per_doc` (default: 3) best chunks sorted by similarity score.
- **FR-007**: System MUST merge winning document chunks and floor chunks, deduplicate by chunk ID, and return sorted by similarity descending.
- **FR-008**: The function signature MUST retain backward compatibility — all new parameters are keyword arguments with defaults, and the return type (list of dicts with the same fields) is unchanged.
- **FR-009**: No external dependencies may be added — the diversity logic is pure Python post-processing after the existing vector search query.
- **FR-010**: The system MUST log the document scoring and selection decisions at INFO level for debugging (document scores, which documents won, which got floor slots).

### Key Entities

- **Candidate Chunk**: A chunk returned by the initial vector search, with fields: id, document_id, display_name, section_title, content, page_number, similarity.
- **Document Score**: An aggregate relevance score computed from a document's candidate chunks' similarity scores.
- **Winning Document**: A document ranked in the top `top_docs_count` by document score — contributes up to `max_chunks_per_doc` chunks.
- **Floor Document**: A document NOT in the winning set but scoring >= `diversity_floor_threshold` — contributes exactly 1 chunk.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Single-topic queries that previously returned 3+ near-duplicate chunks from competing documents now return chunks dominated by the single most relevant document (measurable via RAG quality test suite — no score regression on Category 1-2 questions).
- **SC-002**: Cross-manual synthesis queries (Category 3 in the RAG test suite) maintain their current pass rate — no regressions caused by over-aggressive document filtering.
- **SC-003**: The overall RAG quality test suite score remains at or above the current baseline (98%) after the change.
- **SC-004**: Existing call-sites require zero code changes — the function signature is backward-compatible with default parameters.
- **SC-005**: The diversity selection adds negligible processing time on top of the existing vector search latency — pure post-processing on 20 chunks is sub-millisecond work.

## Clarifications

### Session 2026-04-17

- Q: How should ties in document relevance scores be broken? → A: Tiebreak by highest individual chunk score (most precise match wins).
- Research finding: The target function is `retrieve_chunks_per_document()` (line 12), NOT `search_document_chunks()` (line 116) — the latter is imported but never called in the pipeline. See research.md for details.

## Assumptions

- The existing Supabase RPC (`search_document_chunks`) supports a `match_count` parameter that can be increased from the current `limit` to 20 without performance concerns — pgvector similarity search on ~260 chunks is fast.
- The `document_id` field is always present and correct on every chunk returned by the RPC — this is required for grouping.
- The current `limit` parameter (default 3) represents the final number of chunks desired by callers. The new strategy fetches more candidates internally but returns approximately the same number of final chunks.
- The document relevance score formula (sum of top-3 chunk scores) is a reasonable starting point. It can be tuned later without changing the function interface.
- The diversity floor threshold of 0.60 is a reasonable default that balances inclusion of secondary documents against noise. This threshold can be adjusted based on RAG quality test results.
