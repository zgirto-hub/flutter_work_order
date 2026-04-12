# Implementation Plan: RAG Query Rewrite

**Branch**: `042-rag-query-rewrite` | **Date**: 2026-04-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/042-rag-query-rewrite/spec.md`

## Summary

Add a query rewriting step to the manual assistant RAG pipeline. Before embedding the user's question for vector search, the system sends the question plus the last 3 conversation turns to Gemma via Ollama to produce a self-contained search query that resolves pronouns and references. The rewritten query is used for embedding/retrieval only; the original question is preserved for display and answer generation. Falls back to the original query on rewrite failure.

## Technical Context

**Language/Version**: Python 3.10 (backend only)
**Primary Dependencies**: FastAPI, httpx, Supabase Python client (all existing)
**Storage**: N/A — no persistent data changes
**Testing**: Manual integration testing (existing pattern)
**Target Platform**: Linux server (Zorin OS) behind Nginx
**Project Type**: Web service (backend API)
**Performance Goals**: Rewrite step adds <2s latency; total ask flow remains under 15s
**Constraints**: Server has 15GB RAM; Gemma e2b already loaded; rewrite must share the same Ollama instance
**Scale/Scope**: Single-user concurrent queries typical; low throughput

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | **PASS** | Backend-only change; frontend already sends `history` in `AskRequest`. No new screens, models, or migrations needed — layer exclusion justified by scope (retrieval optimization). |
| II. Explicit Over Automatic | **PASS** | Rewrite is an explicit preprocessing step in the pipeline, not an implicit side effect. Fallback behavior is deterministic. |
| III. Role-Based Access Control | **PASS** | No new endpoints or role changes. Uses existing `/manuals/ask` endpoint with existing auth. |
| IV. Server-First File Storage | **N/A** | No file storage involved. |
| V. Client-Side Computation | **N/A** | This is server-side retrieval optimization; no client-side computation change. |
| VI. Audit Everything | **PASS** | Existing activity logging in `/manuals/ask` endpoint remains unchanged. No new user-facing action type. |
| VII. Simplicity & YAGNI | **PASS** | Single function addition; reuses existing `ollama_generator.generate()`. No new abstractions or configurability beyond what the spec requires. |

**Gate result**: All principles pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/042-rag-query-rewrite/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── services/
│   ├── manual_rag_service.py    # MODIFY — add rewrite call before embed_single()
│   └── ollama_generator.py      # REUSE — generate() for rewrite prompt
└── routers/
    └── manuals.py               # NO CHANGE — history already passed through
```

**Structure Decision**: Backend-only modification. The single integration point is `manual_rag_service.ask()` which already receives `history` from the router. A new helper function `_rewrite_query()` will be added to `manual_rag_service.py` and called before `embed_single()` at line 269.

## Complexity Tracking

> No violations — table not needed.
