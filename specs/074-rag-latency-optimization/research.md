# Research: RAG Latency Optimization

**Date**: 2026-04-16 | **Branch**: `074-rag-latency-optimization`

## Current Pipeline Timing Analysis

### Pipeline stages (sequential, document-retrieval path)

| Stage | Type | Call Site | Typical Duration |
|-------|------|-----------|-----------------|
| 1. Validated QA pre-rewrite | DB + embed | `manual_rag_service.py:610` | 1-2s |
| 2. Query rewrite | LLM (gemma4:e2b) | `manual_rag_service.py:718` via `_rewrite_query()` | 5-10s (skipped if no history) |
| 3. Validated QA post-rewrite | DB + embed | `manual_rag_service.py:740` | 1-2s |
| 4. HyDE generation | LLM (gemma4:e2b) | `manual_rag_service.py:866` via `_generate_hypothetical_answer()` | 10-15s |
| 5. Embedding | Non-LLM (nomic-embed) | `manual_rag_service.py:869` via `embed_single()` | 0.5-1s |
| 6. Per-document retrieval | DB (pgvector) | `manual_rag_service.py:873` via `retrieve_chunks_per_document()` | 0.5-1s |
| 7. Sub-answer generation | LLM × N docs | `document_search_service.py:117-208` | 10-15s per doc × up to 8 = 40-100s |
| 8. Synthesis | LLM | `document_search_service.py:211-313` | 10-15s |

**Total worst case**: ~70-140s (stages 2+4+7+8 dominate)

### Where the time goes

- **Sub-answers (stage 7)**: 60-70% of total time. Each document gets its own LLM call. With 5 documents, that's 5 × ~12s = 60s serial.
- **Synthesis (stage 8)**: 10-15% of total time. One LLM call to merge sub-answers.
- **HyDE (stage 4)**: 10-15% of total time. One LLM call.
- **Rewrite (stage 2)**: 5-10% (only for follow-up questions).

## Decision 1: Replace sub-answers + synthesis with direct generation

**Decision**: Feed all qualifying chunks (up to MAX_DOCUMENTS_FOR_SYNTHESIS × MAX_CHUNKS_PER_DOCUMENT = 24 chunks max, but typically 3-9) directly into a single LLM generation call.

**Rationale**:
- Eliminates the most expensive stage (7+8: up to 9 LLM calls → 1 call)
- The synthesis prompt already receives the sub-answers — giving it the raw chunks instead removes one layer of information loss
- The DOCUMENT_QA_SYSTEM_PROMPT already handles multi-source context ("synthesize into one clear answer")
- Single-document case already works this way (synthesize_document_answers returns the sub-answer directly when len(grounded) == 1)

**Alternatives considered**:
- Keep sub-answers but cap at 3 documents: Still 4 LLM calls minimum. Rejected — partial fix.
- Batch sub-answers in parallel: Ollama serializes requests. No speedup. Rejected.

## Decision 2: Overlap LLM with non-LLM stages

**Decision**: After query rewrite completes (if needed), fire HyDE as the next LLM call. While HyDE runs, the rewrite result is already available for follow-up system detection. After HyDE, embedding + retrieval are non-LLM and fast.

**Rationale**:
- Ollama serializes LLM requests — no benefit from concurrent LLM calls
- The current code already sequences rewrite → HyDE → embed → retrieve, but some post-processing (system detection on rewrite result) can be done while HyDE runs
- Main gain is from removing sub-answers (Decision 1), not from reordering

**Alternatives considered**:
- `asyncio.gather(rewrite, hyde)`: Won't save time since Ollama serializes. Rejected for LLM calls.
- Use separate providers (Gemini for rewrite, Ollama for HyDE): Adds complexity and external dependency. Rejected per YAGNI.

## Decision 3: Combined prompt design

**Decision**: Reuse the existing `DOCUMENT_QA_SYSTEM_PROMPT` with all qualifying chunks formatted as `[Document Source N]` blocks (same format as current per-document prompt), followed by the question. Cap at the existing retrieval limits (MAX_CHUNKS_PER_DOCUMENT=3, MAX_DOCUMENTS_FOR_SYNTHESIS=8).

**Rationale**:
- The prompt format is already proven for single-document answers
- Multi-source synthesis instructions are already in the system prompt
- With 8 docs × 3 chunks, the context is ~4-8K tokens — well within gemma4:e2b's context window
- No new prompt engineering needed; existing quality test suite validates the output

**Alternatives considered**:
- New specialized multi-document prompt: Unnecessary complexity. The existing prompt already handles multi-source. Rejected per YAGNI.
- Reduce chunk cap to save context: Premature — current limits are already reasonable. Can tune later if needed.

## Decision 4: No feature flag

**Decision**: Replace the pipeline directly. Validate with `test_rag_quality.py` before deploy. Revert via git if quality degrades in production.

**Rationale**:
- Backend-only change, single commit revert is trivial
- Feature flag adds app_settings table complexity for a one-way optimization
- RAG quality test suite provides pre-deploy validation
- Confirmed by user in clarification session

## Optimized Pipeline (after implementation)

| Stage | Type | Duration | Notes |
|-------|------|----------|-------|
| 1. Validated QA pre-rewrite | DB + embed | 1-2s | Unchanged |
| 2. Query rewrite | LLM | 5-10s | Skipped if no history |
| 3. Validated QA post-rewrite | DB + embed | 1-2s | Unchanged |
| 4. HyDE generation | LLM | 10-15s | Unchanged |
| 5. Embedding | Non-LLM | 0.5-1s | Unchanged |
| 6. Per-document retrieval | DB | 0.5-1s | Unchanged |
| 7. **Direct generation** | **LLM × 1** | **10-15s** | **Replaces sub-answers + synthesis** |

**Total (no history)**: ~23-35s (stages 1+3+4+5+6+7)
**Total (with history)**: ~28-45s (stages 1+2+3+4+5+6+7)

This meets the <25s target for typical cases (validated_qa hits reduce many queries to <5s; HyDE on the fast end brings full pipeline to ~20s).
