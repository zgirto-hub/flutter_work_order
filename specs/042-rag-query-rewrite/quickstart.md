# Quickstart: RAG Query Rewrite

**Feature**: 042-rag-query-rewrite | **Date**: 2026-04-12

## What This Feature Does

Adds a query rewriting step to the "Ask the AI" manual assistant pipeline. When a user asks a follow-up question like "What about the second point?", the system first rewrites it into a self-contained query (e.g., "What are the details about [specific topic] from the APU inspection manual?") before searching for relevant document chunks. This improves retrieval accuracy for conversational follow-ups.

## Files Modified

| File | Change |
|------|--------|
| `backend/services/manual_rag_service.py` | Add `_rewrite_query()` function; call it before `embed_single()` in `ask()` |

## How It Works

1. User sends a question + conversation history to `/manuals/ask`
2. **NEW**: `_rewrite_query(question, history[-3:])` calls Gemma via Ollama to produce a self-contained search query
3. The rewritten query is embedded via `embed_single()`
4. Vector search retrieves chunks using the rewritten embedding
5. Answer generation uses the **original** question (not the rewritten one) + retrieved chunks + history

## Fallback Behavior

If the rewrite fails (Ollama timeout, error, empty result), the original user question is used for embedding — same as current production behavior.

## Testing

1. Start a conversation in "Ask the AI"
2. Ask a topic question (e.g., "What is the APU inspection interval?")
3. Ask a follow-up with a reference (e.g., "Tell me more about that" or "What about the second point?")
4. Verify the answer is relevant to the original topic (not generic/unrelated)
5. Test with a first-turn question (no history) — should work identically to current behavior
