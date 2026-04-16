# Quickstart: RAG Quality Improvements

**Branch**: `069-rag-quality-improvements` | **Date**: 2026-04-16

## What This Changes

The "Ask the AI" knowledge base endpoint (`POST /api/manuals/ask`) gets 4 improvements to the validated_qa lookup path:

1. **Multi-chunk**: Fetches top 3 validated QA matches instead of 1
2. **Threshold**: Rejects queries below 0.70 similarity without calling the LLM
3. **Strict prompt**: Forces LLM to answer only from provided context
4. **Sources**: Returns source entries with IDs, question text, and scores

## Files to Modify

| File | Change |
|------|--------|
| `backend/services/validated_qa_service.py` | `check_validated_match()`: fetch top 3, return all matches with scores |
| `backend/services/manual_rag_service.py` | Handle multi-match, threshold gate, strict system prompt, build new response shape |
| `backend/routers/manuals.py` | Pass through new fields (minimal changes) |

## Key Constants to Add

```python
RAG_CONFIDENCE_THRESHOLD = 0.70  # Minimum similarity to call LLM
RAG_HIGH_CONFIDENCE = 0.85       # Score >= this → confidence: "high"
```

## Testing

```bash
# Test 1 — Normal query (expect answer + sources + confidence)
curl -X POST http://localhost:8000/api/manuals/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "how do I retrieve incoming messages"}'

# Test 2 — Off-topic query (expect low confidence, no LLM call)
curl -X POST http://localhost:8000/api/manuals/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "what is the weather in Kuwait today"}'
```

## What NOT to Change

- Flutter/Dart frontend
- Supabase schema / migrations
- Provider resolver (`backend/services/ai_providers/resolver.py`)
- `.env` files
- Letter writing assistant or other AI features
