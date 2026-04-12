# Quickstart: Chunk Reranking by Similarity Score

**Branch**: `044-chunk-rerank-scoring` | **Date**: 2026-04-12

## What This Feature Does

Adds a filtering and reranking step to the RAG question-answering pipeline. After chunks are retrieved from pgvector, only chunks with cosine distance <= 0.30 (similarity >= 0.70) pass through, and only the top 3 are sent to the language model. This replaces the current behavior of sending all 5 retrieved chunks to the prompt regardless of relevance.

## Files Changed

| File | Change |
|------|--------|
| `backend/services/manual_rag_service.py` | Add `MAX_CHUNK_DISTANCE` and `MAX_PROMPT_CHUNKS` constants; modify `ask()` to filter and slice `chunks_data` before building prompt; remove redundant `MAX_SOURCE_DISTANCE`; add debug logging for discarded chunks |

## Pipeline Flow (after change)

```
User question
  → Query rewrite (if history present)
  → HyDE hypothetical answer generation
  → Embed (hypothetical answer or query)
  → pgvector search (top 5 candidates with distance scores)
  → **NEW: Filter by MAX_CHUNK_DISTANCE (0.30)**
  → **NEW: Take top MAX_PROMPT_CHUNKS (3)**
  → Build prompt with qualifying chunks only
  → Generate answer via Ollama
  → Return answer + sources (from qualifying chunks only)
```

## How to Test

1. Start the backend: `cd backend && uvicorn main:app --reload`
2. Upload a manual with known content via the Knowledge screen
3. Ask a question with a clear answer in the manual — should get a grounded response with <= 3 sources
4. Ask an unrelated question — should get "information not found" response
5. Check backend logs for `Chunk reranking:` debug messages showing filtered/retained counts

## Configuration

Both thresholds are named constants at the top of `manual_rag_service.py`:

- `MAX_CHUNK_DISTANCE = 0.30` — increase to be more permissive, decrease to be stricter
- `MAX_PROMPT_CHUNKS = 3` — increase to give the LLM more context, decrease for faster/cheaper generation
