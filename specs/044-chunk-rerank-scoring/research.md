# Research: Chunk Reranking by Similarity Score

**Branch**: `044-chunk-rerank-scoring` | **Date**: 2026-04-12

## R1: Distance Metric Used by pgvector RPC

**Decision**: The `search_manual_chunks` RPC returns cosine **distance** (not similarity) via the `<=>` operator. Distance ranges from 0.0 (identical) to 2.0 (opposite). The column is named `distance` in the RPC return type.

**Rationale**: Verified in `supabase/migrations/20260411000000_create_manuals.sql` — the RPC computes `(mc.embedding <=> q_embedding) AS distance` and orders by it ascending (closest first).

**Implication for threshold**: A 0.70 cosine similarity corresponds to 0.30 cosine distance. The filter condition should be `distance <= 0.30` (not `similarity >= 0.70`). Since the code already works with distance values, the constant should be expressed as a max distance threshold.

## R2: Current Filtering Behavior

**Decision**: The current code (`manual_rag_service.py:398-419`) sends **all 5** retrieved chunks to the LLM prompt, regardless of distance. A separate `MAX_SOURCE_DISTANCE = 0.45` constant controls only which chunks appear as **user-visible sources** — it does not affect the prompt content.

**Rationale**: Read from current `ask()` function. The comment at line 399 says "All 5 chunks go into the prompt (more context = better answer)".

**Implication**: The new reranking step replaces this behavior entirely: filter by distance threshold, take top N, use those for both the prompt AND source display. The old `MAX_SOURCE_DISTANCE` constant becomes redundant and should be removed.

## R3: Chunk Ordering from Database

**Decision**: The RPC already returns chunks ordered by distance ascending (best match first). No re-sorting is needed in Python after filtering.

**Rationale**: The SQL `ORDER BY mc.embedding <=> q_embedding` guarantees sorted output.

**Implication**: The Python code only needs to filter (drop chunks above max distance) and slice (take first N). The ordering requirement in FR-002 is satisfied by the database.

## R4: Threshold Value Selection

**Decision**: Use 0.30 max distance (= 0.70 similarity) as the default threshold, with top 3 chunks max.

**Rationale**: The user specified 0.70 similarity / top 3 in the feature description. For nomic-embed-text with HyDE-enhanced queries, this is a reasonable starting point. The current `MAX_SOURCE_DISTANCE = 0.45` (0.55 similarity) was already used for source display, suggesting chunks below ~0.55 similarity were considered too weak to cite. A 0.70 similarity threshold is more aggressive but appropriate when paired with HyDE.

**Alternatives considered**:
- 0.25 distance (0.75 similarity): Too aggressive, may over-filter for vague questions
- 0.40 distance (0.60 similarity): Too permissive, would not meaningfully improve over current behavior
- Dynamic threshold based on score distribution: Adds complexity (YAGNI), can be added later if static threshold proves insufficient

## R5: Observability

**Decision**: Add debug-level logging when chunks are filtered out, including the count of discarded chunks and their distance scores. No new user-facing logging or activity log entries needed.

**Rationale**: This helps operators tune the threshold during initial rollout without adding noise to the activity log. The existing `log_activity` call in the router already logs `grounded` status and source count, which indirectly reflects filtering effects.

**Alternatives considered**:
- Add filtered chunk count to the API response: Adds frontend complexity for a backend-tuning concern
- Log to `user_activity_log`: Audit overkill for an internal pipeline detail (Constitution VI applies to user-facing actions)
