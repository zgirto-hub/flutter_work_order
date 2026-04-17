# Research: 078-diversity-aware-retrieval

**Date**: 2026-04-17

## Key Finding: Target Function

**Decision**: The diversity-aware retrieval logic must be applied to `retrieve_chunks_per_document()` (line 12), NOT `search_document_chunks()` (line 116).

**Rationale**: `search_document_chunks` is imported in `manual_rag_service.py` but **never called**. The active RAG pipeline exclusively uses `retrieve_chunks_per_document()` (called at line 991 of `manual_rag_service.py`). Modifying only `search_document_chunks` would have zero effect on the pipeline.

**Alternatives considered**:
- Modify `search_document_chunks` only (spec's original scope) — rejected because it's dead code in the pipeline
- Modify both functions — rejected because `search_document_chunks` has no callers; adding complexity to unused code violates YAGNI
- Modify `retrieve_chunks_per_document` only — chosen, as this is the actual code path

## Current Retrieval Architecture

**File**: `backend/services/document_search_service.py`

### `retrieve_chunks_per_document()` (line 12) — ACTIVE
- Called by: `manual_rag_service.py:991`
- Current behavior:
  1. Calls Supabase RPC `search_document_chunks` with `match_count=10`, `match_threshold=0.55`
  2. Groups results by `document_id`
  3. Caps at `max_chunks_per_doc=3` per document (no scoring, just truncation)
  4. If more than `max_documents=8` docs, ranks by average distance and keeps top 8
  5. Fetches parent context for qualifying chunks
  6. Fetches document display names
- Returns: `dict[str, list[dict]]` (document_id → chunks)

### `search_document_chunks()` (line 116) — UNUSED IN PIPELINE
- Imported in `manual_rag_service.py:20` but never called
- Simple flat list return with `match_count=limit` (default 3)

### Supabase RPC `search_document_chunks` (SQL)
- Input: `query_embedding`, `match_count`, `match_threshold`
- Filters: `chunk_type='child'`, `status='ready'`, `embedding_stale=false`
- Returns: `id, document_id, parent_id, section_title, content, page_number, distance`
- Ordered by: cosine distance ascending

## Design Decisions

### Decision 1: Increase initial fetch from 10 to 20
**Rationale**: The current `match_count=10` limits the candidate pool. With 13 documents and ~260 chunks, increasing to 20 gives the diversity algorithm more candidates to work with without meaningful latency impact.

### Decision 2: Document scoring = sum of top-3 chunk similarities
**Rationale**: Sum rewards documents that have multiple relevant chunks (broad coverage) while being bounded by the per-doc cap. Max alone would favor a document with one lucky chunk. Average would penalize a document with 1 excellent + 1 mediocre chunk.

### Decision 3: Tiebreak by highest individual chunk score
**Rationale**: Per clarification session — when two documents have identical aggregate scores, the one with the single most precisely relevant chunk wins.

### Decision 4: Diversity floor at 0.60 similarity
**Rationale**: Current `match_threshold` in `retrieve_chunks_per_document` is 0.55 (cosine distance). A floor of 0.60 similarity (= 0.40 distance) is above the noise threshold but below the winning threshold, ensuring only genuinely relevant secondary documents get a guaranteed slot.

### Decision 5: Apply to `retrieve_chunks_per_document`, not `search_document_chunks`
**Rationale**: See Key Finding above. This is where the pipeline actually retrieves chunks.
