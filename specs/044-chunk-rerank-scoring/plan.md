# Implementation Plan: Chunk Reranking by Similarity Score

**Branch**: `044-chunk-rerank-scoring` | **Date**: 2026-04-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/044-chunk-rerank-scoring/spec.md`

## Summary

Add a filtering and reranking step to the RAG pipeline in `manual_rag_service.py`. After pgvector retrieves candidate chunks, discard those with cosine distance above 0.30 (similarity below 0.70), keep at most the top 3, and use only those for prompt construction and source attribution. When zero chunks qualify, return the "not found" response without calling the LLM.

## Technical Context

**Language/Version**: Python 3.10  
**Primary Dependencies**: FastAPI, Supabase Python client, httpx (all existing)  
**Storage**: Supabase (PostgreSQL) with pgvector — no schema changes  
**Testing**: Manual testing via `/manuals/ask` endpoint  
**Target Platform**: Linux server (Zorin OS) behind Nginx  
**Project Type**: Web service (backend only for this feature)  
**Performance Goals**: Same or faster than current (fewer chunks → less LLM processing)  
**Constraints**: 15 GB server RAM limit; Ollama gemma4:e2b for generation, nomic-embed-text for embedding  
**Scale/Scope**: Single-file change in `backend/services/manual_rag_service.py`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | **PASS** | Backend-only is justified — no new data model, no new endpoints, no new UI. The feature modifies internal pipeline logic in an existing service. |
| II. Explicit Over Automatic | **PASS** | Threshold and chunk limit are explicit named constants (`MAX_CHUNK_DISTANCE`, `MAX_PROMPT_CHUNKS`), not hidden magic numbers. |
| III. Role-Based Access Control | **N/A** | No new endpoints or screens. Existing `/manuals/ask` access control unchanged. |
| IV. Server-First File Storage | **N/A** | No file operations. |
| V. Client-Side Computation | **N/A** | This is server-side RAG pipeline logic. |
| VI. Audit Everything | **PASS** | No new user-facing action to audit. Existing `log_activity` in the router already logs `grounded` status and source count. Debug logging added for operational tuning. |
| VII. Simplicity & YAGNI | **PASS** | Two constants + a filter/slice operation. No abstraction layers, no configuration UI, no database changes. |

**Post-Phase 1 re-check**: All gates still pass. No design decisions introduced new violations.

## Project Structure

### Documentation (this feature)

```text
specs/044-chunk-rerank-scoring/
├── plan.md              # This file
├── research.md          # Phase 0 output — distance metric, threshold analysis
├── data-model.md        # Phase 1 output — no DB changes, documents constants
├── quickstart.md        # Phase 1 output — testing and configuration guide
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
└── services/
    └── manual_rag_service.py   # MODIFIED — add constants, filter/slice logic, debug logging
```

**Structure Decision**: Single file modification. No new files, directories, or modules needed.

## Implementation Details

### Step 1: Add Named Constants

Add two constants near the top of `manual_rag_service.py` (after existing module-level definitions):

```python
# Chunk reranking thresholds (see spec 044)
MAX_CHUNK_DISTANCE = 0.30    # cosine distance; 0.30 = 0.70 similarity
MAX_PROMPT_CHUNKS = 3        # max chunks sent to LLM after filtering
```

### Step 2: Modify `ask()` — Filter and Slice After Retrieval

In the `ask()` function, after the pgvector RPC returns `chunks_data` and before the prompt is built, insert the reranking step:

1. Filter `chunks_data` to keep only chunks where `distance <= MAX_CHUNK_DISTANCE`
2. Slice to `MAX_PROMPT_CHUNKS` (chunks are already sorted by distance ascending from the RPC)
3. Log the filtering result at debug level
4. If zero chunks remain after filtering, return the "not found" response immediately (skip LLM call)

### Step 3: Simplify Source Assembly

Remove the old `MAX_SOURCE_DISTANCE = 0.45` constant and the separate source-filtering logic. After reranking, all surviving chunks are both prompt material AND valid sources. The source assembly loop iterates over the filtered list directly.

### Step 4: Debug Logging

Add a single `logger.info()` after filtering that reports:
- Total chunks retrieved from pgvector
- Chunks passing the distance threshold
- Chunks sent to LLM (after top-N slice)

This aids threshold tuning during initial rollout.

## Complexity Tracking

No constitution violations to justify. This is a minimal, single-file change.
