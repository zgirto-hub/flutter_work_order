# Implementation Plan: RAG Pipeline Latency Optimization

**Branch**: `077-rag-pipeline-parallelize` | **Date**: 2026-04-17 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/077-rag-pipeline-parallelize/spec.md`

## Summary

Optimize the RAG pipeline (`/manuals/ask`) from ~55-60s to ~30-40s by: (1) parallelizing the independent query-rewrite and HyDE-generation stages using `asyncio.gather()`, and (2) adding a regex-based heuristic to skip HyDE entirely for direct factual lookups (hostnames, IPs, component names). Backend-only changes in `manual_rag_service.py`. No frontend, database, or migration changes.

## Technical Context

**Language/Version**: Python 3.10 (backend only — no Flutter/Dart changes)  
**Primary Dependencies**: FastAPI, existing `services.ollama_generator`, existing `services.ollama_embedder`, existing `services.ai_providers.resolver`  
**Storage**: N/A — no data model changes  
**Testing**: Manual testing via `/manuals/ask` endpoint; latency_breakdown comparison before/after  
**Target Platform**: Linux server (Zorin OS) behind Nginx  
**Project Type**: Web service (backend optimization)  
**Performance Goals**: Simple lookups < 40s (from ~55s); multi-turn follow-ups 8s+ faster than baseline  
**Constraints**: Ollama may serialize concurrent requests internally (single GPU); must not break existing fallback chains  
**Scale/Scope**: Single backend file change (`manual_rag_service.py`), ~50-80 lines modified

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS (justified exclusion) | Backend-only optimization. No new endpoints, models, or screens. Frontend already displays `latency_breakdown` — no changes needed. Exclusion documented: no database migration, no Flutter model/service/screen changes because this is a pure backend performance optimization with no new user-facing features. |
| II. Explicit Over Automatic | PASS | HyDE skip decision is explicit (regex heuristic), not implicit. No silent behavior changes — skipped stages are reflected in `latency_breakdown`. |
| III. Role-Based Access Control | N/A | No auth or permission changes. |
| IV. Server-First File Storage | N/A | No file storage changes. |
| V. Client-Side Computation | N/A | No client-side changes. |
| VI. Audit Everything | PASS | Existing logging in pipeline stages is preserved. Skip decisions logged via existing `logger.info` pattern. No new user-facing actions requiring `user_activity_log` entries. |
| VII. Simplicity & YAGNI | PASS | Regex heuristic is the simplest approach. No new config tables, no admin UI for pattern management, no abstraction layers. Hardcoded patterns matching known domain terms. |

All gates pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/077-rag-pipeline-parallelize/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (minimal — no data changes)
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (no new contracts)
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
backend/
└── services/
    └── manual_rag_service.py   # Primary file: parallelize rewrite+HyDE, add skip heuristic
```

**Structure Decision**: Single-file modification in the existing backend services directory. No new files, directories, or modules. The `_rewrite_query()` and `_generate_hypothetical_answer()` functions remain in place; the `ask()` function orchestration changes from sequential to parallel invocation using `asyncio.gather()`. A new `_is_direct_lookup()` helper function is added in the same file.
