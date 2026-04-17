# Data Model: 078-diversity-aware-retrieval

**Date**: 2026-04-17

## No Schema Changes

This feature is pure Python post-processing logic. No database tables, columns, or migrations are required.

## In-Memory Entities

### Candidate Chunk (existing — no change)
```
{
  "id": str (UUID),
  "document_id": str (UUID),
  "parent_id": str (UUID) | None,
  "section_title": str | None,
  "content": str,
  "page_number": int | None,
  "distance": float,
  "similarity": float  # 1.0 - distance
}
```

### Document Score (new — transient, computed during selection)
```
{
  "document_id": str,
  "display_name": str,
  "aggregate_score": float,    # sum of top-3 chunk similarities
  "max_chunk_score": float,    # highest individual chunk similarity (tiebreak)
  "chunk_count": int,          # number of candidate chunks
  "chunks": list[Candidate Chunk]  # all candidate chunks for this doc
}
```

### Selection Result (new — transient)
```
{
  "winning_docs": list[str],   # document_ids of top-K docs
  "floor_docs": list[str],     # document_ids that got floor slots
  "selected_chunks": dict[str, list[Candidate Chunk]]  # final chunks by doc_id
}
```

## State Transitions

None — all entities are transient within a single request.
