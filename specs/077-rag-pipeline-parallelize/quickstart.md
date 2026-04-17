# Quickstart: RAG Pipeline Latency Optimization

**Date**: 2026-04-17  
**Feature**: 077-rag-pipeline-parallelize

## What This Feature Does

Speeds up the AI assistant's response time by running two independent preparation stages (query rewrite and hypothetical document generation) in parallel instead of sequentially, and by skipping the hypothetical document step entirely for simple factual questions like IP address lookups.

## Files Modified

- `backend/services/manual_rag_service.py` — the only file changed

## Changes at a Glance

1. **New helper function** `_is_direct_lookup(query)`: regex-based check that returns `True` for queries containing IP addresses, server hostnames, or specific component names.

2. **Parallel execution in `ask()`**: When conversation history is present (follow-up questions), `_rewrite_query()` and `_generate_hypothetical_answer()` run concurrently via `asyncio.gather()` instead of sequentially.

3. **HyDE skip**: When `_is_direct_lookup()` returns `True`, the HyDE stage is skipped entirely — the query (or rewritten query) is embedded directly for vector search.

## How to Test

1. Start the backend: `uvicorn main:app --host 0.0.0.0 --port 8000`
2. Open the AI assistant in the frontend
3. Ask a direct factual question: "what is as1-cont ip address?"
4. Check `latency_breakdown` in response — `hyde_ms` should be `null` or `0`
5. Ask a follow-up question to test parallel execution
6. Compare `total_ms` with the pre-optimization baseline (~55s)

## Rollback

Revert the single commit on `backend/services/manual_rag_service.py`. No database changes to undo.
