# Quickstart: RAG Latency Optimization

**Branch**: `074-rag-latency-optimization`

## What This Changes

Replaces the per-document sub-answer + synthesis pipeline in `/manuals/ask` with a single direct generation call. Reduces response time from 50-100s to ~15-25s.

## Files to Modify

1. **`backend/services/manual_rag_service.py`** — Main `ask()` function
   - Replace the `generate_document_sub_answers()` + `synthesize_document_answers()` call sequence with a new direct generation flow
   - Build a combined prompt with all qualifying chunks from all documents
   - Single `provider_generate()` call replaces up to 9 LLM calls

2. **`backend/services/document_search_service.py`** — Search service
   - Add `build_direct_generation_prompt()` function that formats all qualifying chunks into a single prompt
   - `generate_document_sub_answers()` and `synthesize_document_answers()` become unused (remove or mark deprecated)

## How to Test

### Before changes (baseline)
```bash
cd backend
python -m pytest tests/test_rag_quality.py -v  # Record quality baseline
```

### After changes
```bash
# Quality regression check
python -m pytest tests/test_rag_quality.py -v

# Latency check
python -m pytest tests/test_manual_rag_latency.py -v
```

### Manual smoke test
Ask a question via the "Ask the AI" assistant that hits the document pipeline (not validated_qa). Verify:
- Answer arrives in < 25s
- Sources are attributed correctly (document name, page number)
- `latency_breakdown` in response shows `generator_ms` (single call) instead of multiple sub-answer timings

## Key Constants

- `MAX_CHUNKS_PER_DOCUMENT = 3` (in document_search_service.py)
- `MAX_DOCUMENTS_FOR_SYNTHESIS = 8` (in document_search_service.py)
- `MAX_CHUNK_DISTANCE = 0.55` (cosine distance ceiling)
- `DOCUMENT_QA_SYSTEM_PROMPT` (in manual_rag_service.py) — reused for direct generation
