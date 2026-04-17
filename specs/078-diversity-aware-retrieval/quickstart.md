# Quickstart: 078-diversity-aware-retrieval

## What Changed

`retrieve_chunks_per_document()` in `backend/services/document_search_service.py` now applies a two-phase diversity-aware selection:

1. **Phase 1**: Fetches 20 candidate chunks (up from 10) via existing Supabase RPC
2. **Phase 2**: Groups by document, scores documents, selects top-3 winning docs + diversity floor docs, caps chunks per doc

## How to Test

```bash
# Run the full RAG quality test suite
python backend/tests/test_rag_quality.py

# Run only cross-manual synthesis tests (most sensitive to this change)
python backend/tests/test_rag_quality.py --category 3

# Run with faithfulness verification
python backend/tests/test_rag_quality.py --verify
```

## Parameters

All new parameters have defaults and are backward-compatible:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `top_docs_count` | 3 | Number of winning documents to select |
| `max_chunks_per_doc` | 3 | Max chunks from each winning document |
| `diversity_floor_threshold` | 0.60 | Minimum similarity for a floor document slot |

## Files Modified

- `backend/services/document_search_service.py` — diversity selection logic in `retrieve_chunks_per_document()`
- `backend/tests/test_rag_quality.py` — test questions for new documents (already added)
