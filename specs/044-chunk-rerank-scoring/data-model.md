# Data Model: Chunk Reranking by Similarity Score

**Branch**: `044-chunk-rerank-scoring` | **Date**: 2026-04-12

## No Data Model Changes

This feature does not add, modify, or remove any database tables, columns, or RPC functions. All changes are in-memory filtering logic within the Python backend service.

### Existing Entities Referenced (read-only)

| Entity | Table | Relevant Fields | Usage |
|--------|-------|----------------|-------|
| Manual Chunk | `manual_chunks` | `id`, `manual_id`, `chunk_index`, `source_page`, `content`, `embedding` | Retrieved via `search_manual_chunks` RPC |
| Manual | `manuals` | `id`, `title` | Joined for `manual_title` in RPC results |

### Existing RPC Referenced (unchanged)

| Function | Returns | Key Column |
|----------|---------|------------|
| `search_manual_chunks(q_embedding, manual_id_filter, match_count)` | Top-k chunks with `distance` float | `distance` — cosine distance (0.0 = identical, 2.0 = opposite) |

### New Constants (in-memory, not persisted)

| Constant | Default | Meaning |
|----------|---------|---------|
| `MAX_CHUNK_DISTANCE` | 0.30 | Maximum cosine distance for a chunk to qualify (= 0.70 similarity) |
| `MAX_PROMPT_CHUNKS` | 3 | Maximum chunks sent to the language model after filtering |
