# Implementation Plan: RAG Latency Optimization

**Branch**: `074-rag-latency-optimization` | **Date**: 2026-04-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/074-rag-latency-optimization/spec.md`

## Summary

The `/manuals/ask` RAG pipeline currently takes 50-100s per question due to 10+ sequential Ollama calls: query rewrite → HyDE → embedding → retrieval → per-document sub-answers (up to 8 LLM calls) → synthesis (1 LLM call). This plan replaces the sub-answer + synthesis pattern with a single generation call using combined chunks as context, and reorders stages to overlap LLM work with non-LLM work where possible. Target: under 25 seconds per document-retrieval question.

## Technical Context

**Language/Version**: Python 3.10 (backend only)
**Primary Dependencies**: FastAPI, Supabase Python client, httpx, existing `services.ai_providers.resolver`, `services.ollama_embedder`, `services.ollama_generator`
**Storage**: Supabase (PostgreSQL) with pgvector — no schema changes
**Testing**: `backend/tests/test_rag_quality.py` (existing), `backend/tests/test_manual_rag_latency.py` (existing)
**Target Platform**: Linux server (Zorin OS), single Ollama instance (gemma4:e2b, 15GB RAM)
**Project Type**: Web service (FastAPI backend)
**Performance Goals**: < 25s per document-retrieval question (down from 50-100s)
**Constraints**: Single GPU, Ollama serializes LLM requests (no parallel inference). 15GB RAM limits context window size.
**Scale/Scope**: ~70-page PDF manuals, up to 8 documents with 3 chunks each in retrieval

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | **PASS (exemption)** | Backend-only change — no frontend, migration, or model changes. Spec explicitly documents this. Response schema is identical. |
| II. Explicit Over Automatic | **PASS** | No implicit state transitions or assignments affected. Pipeline path is logged (FR-010). |
| III. Role-Based Access Control | **PASS** | No endpoint or permission changes. |
| IV. Server-First File Storage | **N/A** | No file storage changes. |
| V. Client-Side Computation | **N/A** | Backend pipeline change only. |
| VI. Audit Everything | **PASS** | Existing activity logging untouched. Pipeline path logged for observability. |
| VII. Simplicity & YAGNI | **PASS** | Removes complexity (sub-answer + synthesis) rather than adding it. No feature flags, no new abstractions. |

No violations. Gate passes.

## Project Structure

### Documentation (this feature)

```text
specs/074-rag-latency-optimization/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (minimal — no schema changes)
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (files to modify)

```text
backend/
├── services/
│   ├── manual_rag_service.py      # Main ask() function — reorder stages, replace sub-answer flow
│   └── document_search_service.py # Remove generate_document_sub_answers, synthesize_document_answers;
│                                  # add build_direct_generation_prompt()
└── tests/
    ├── test_rag_quality.py        # Validate answer quality before/after
    └── test_manual_rag_latency.py # Validate latency improvement
```

**Structure Decision**: Backend-only modification of 2 existing service files. No new files, no new directories, no migrations.
