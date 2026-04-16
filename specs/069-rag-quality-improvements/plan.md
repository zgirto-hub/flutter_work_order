# Implementation Plan: RAG Quality Improvements

**Branch**: `069-rag-quality-improvements` | **Date**: 2026-04-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/069-rag-quality-improvements/spec.md`

## Summary

Improve the validated_qa RAG flow in the "Ask the AI" knowledge base by: (1) fetching top 3 entries instead of 1, (2) adding a configurable confidence threshold to reject weak matches before calling the LLM, (3) adding a strict context-only system prompt, and (4) returning source references with every answer. All changes are backend-only in `validated_qa_service.py` and `manual_rag_service.py`.

## Technical Context

**Language/Version**: Python 3.10 (backend only)
**Primary Dependencies**: FastAPI, Supabase Python client, httpx, existing `services.ai_providers.resolver`, existing `services.ollama_embedder`, existing `services.validated_qa_service`
**Storage**: Supabase (PostgreSQL) with pgvector — existing `validated_qa` table. No schema changes.
**Testing**: Manual curl tests against `/api/manuals/ask` endpoint
**Target Platform**: Linux server (Zorin OS) behind Nginx
**Project Type**: Web service (FastAPI backend)
**Performance Goals**: N/A — existing latency profile unchanged; threshold rejection should be faster (skips LLM call)
**Constraints**: No frontend changes, no schema changes, no provider resolver changes, no .env changes
**Scale/Scope**: ~3 files modified in backend

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS (exemption) | Backend-only by design — spec FR-012 explicitly excludes frontend. No new DB tables/migrations. Frontend will consume new additive fields in a separate spec. |
| II. Explicit Over Automatic | PASS | Threshold is an explicit named constant. Confidence levels are explicitly defined with exact cutoffs. No implicit behavior. |
| III. Role-Based Access Control | N/A | No auth changes. Endpoint already accessible to all authenticated users. |
| IV. Server-First File Storage | N/A | No file storage changes. |
| V. Client-Side Computation | N/A | Backend-only changes. |
| VI. Audit Everything | PASS | Existing activity logging in the `/manuals/ask` route remains unchanged. No new user-facing actions introduced — these are quality improvements to existing responses. |
| VII. Simplicity & YAGNI | PASS | All 4 changes address concrete current problems (single-source answers, hallucination, no confidence gating, no source tracing). No speculative abstractions. |

**Gate result**: PASS — no violations.

## Project Structure

### Documentation (this feature)

```text
specs/069-rag-quality-improvements/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── services/
│   ├── validated_qa_service.py   # MODIFY: check_validated_match() → fetch top 3, return scores
│   └── manual_rag_service.py     # MODIFY: handle multi-match results, threshold, system prompt, response shape
└── routers/
    └── manuals.py                # MODIFY (minimal): pass through new response fields from RAG service
```

**Structure Decision**: Existing web application structure (backend/frontend). Changes confined to 2-3 backend Python files. No new files created.
