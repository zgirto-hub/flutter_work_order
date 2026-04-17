# Implementation Plan: Diversity-Aware Retrieval Strategy

**Branch**: `078-diversity-aware-retrieval` | **Date**: 2026-04-17 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/078-diversity-aware-retrieval/spec.md`

## Summary

Add document-level scoring and diversity-aware chunk selection to the RAG retrieval pipeline. The target function is `retrieve_chunks_per_document()` in `document_search_service.py` (NOT `search_document_chunks()` which is unused in the pipeline). The change fetches more candidate chunks (20 instead of 10), scores documents by aggregate similarity, selects top-K winning documents, and applies a diversity floor to preserve cross-manual synthesis.

## Technical Context

**Language/Version**: Python 3.10  
**Primary Dependencies**: FastAPI, Supabase Python client (existing — no new deps)  
**Storage**: Supabase (PostgreSQL) with pgvector — no schema changes  
**Testing**: RAG quality test suite (`backend/tests/test_rag_quality.py`)  
**Target Platform**: Linux server (Zorin OS behind Nginx)  
**Project Type**: Backend service (document search module)  
**Performance Goals**: Sub-millisecond post-processing on 20 chunks (negligible vs. vector search latency)  
**Constraints**: No external dependencies; backward-compatible function signature  
**Scale/Scope**: 13 documents, ~260 chunks currently; designed to scale to 50+ documents

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend-only change; no frontend/migration layers needed — documented in spec scope |
| II. Explicit Over Automatic | PASS | All selection parameters are explicit with documented defaults |
| III. Role-Based Access Control | N/A | No access control changes |
| IV. Server-First File Storage | N/A | No file storage changes |
| V. Client-Side Computation | N/A | This is server-side retrieval logic |
| VI. Audit Everything | PASS | FR-010 requires INFO-level logging of document scoring decisions |
| VII. Simplicity & YAGNI | PASS | Pure Python post-processing; no new abstractions, no new dependencies |

All gates pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/078-diversity-aware-retrieval/
├── plan.md              # This file
├── research.md          # Phase 0 output — key finding: target is retrieve_chunks_per_document
├── data-model.md        # Phase 1 output — in-memory entities only, no schema changes
├── quickstart.md        # Phase 1 output — testing and parameter reference
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
backend/
├── services/
│   └── document_search_service.py   # MODIFY: retrieve_chunks_per_document()
└── tests/
    └── test_rag_quality.py          # ALREADY UPDATED: new test questions for 13 documents
```

**Structure Decision**: Single file modification. The diversity selection logic is added as a private helper function `_diversity_select()` within `document_search_service.py`, called by `retrieve_chunks_per_document()` after the initial RPC fetch. No new files or modules.

## Complexity Tracking

No constitution violations. Table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| (none)    | —          | —                                   |
