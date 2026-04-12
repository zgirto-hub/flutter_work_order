# Quickstart: HyDE Retrieval for Manual Assistant

**Branch**: `043-hyde-retrieval`

## What This Changes

A single file modification to `backend/services/manual_rag_service.py` that adds a HyDE (Hypothetical Document Embedding) step to the RAG pipeline.

## Pipeline Before

```
question → query_rewrite (if history) → embed(query) → pgvector search → generate answer
```

## Pipeline After

```
question → query_rewrite (if history) → HyDE generate(query) → embed(hypothetical) → pgvector search → generate answer
                                              ↓ (on failure)
                                         embed(query) [fallback]
```

## Files to Modify

| File | Change |
|------|--------|
| `backend/services/manual_rag_service.py` | Add `_generate_hypothetical_answer()` function; update `ask()` to call it before embedding |

## New Function Signature

```python
async def _generate_hypothetical_answer(query: str) -> str | None:
    """Generate a hypothetical manual passage for HyDE embedding.
    Returns the hypothetical text on success, or None on failure (triggering fallback)."""
```

## Testing

1. Ensure Ollama is running with gemma4:e2b and nomic-embed-text models
2. Upload at least one manual to the corpus
3. Ask a vague question via `POST /manuals/ask`: `{"question": "what do I need to know about landing gear?", "user_email": "test@test.com"}`
4. Check server logs for `HyDE generated hypothetical answer` (success) or `HyDE generation failed` (fallback)
5. Compare answer quality with a specific question like `"What is the torque specification for AN3-7A bolts?"`

## No Migration Needed

No database changes. No new dependencies. No frontend changes.
