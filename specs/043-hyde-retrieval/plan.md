# Implementation Plan: HyDE Retrieval for Manual Assistant

**Branch**: `043-hyde-retrieval` | **Date**: 2026-04-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/043-hyde-retrieval/spec.md`

## Summary

Add a HyDE (Hypothetical Document Embedding) step to the manual assistant RAG pipeline. After query rewriting (if applicable), the system generates a short hypothetical civil aviation manual passage via Ollama (gemma4:e2b), embeds that passage with nomic-embed-text, and uses the resulting vector for pgvector similarity search. This improves retrieval quality for vague/exploratory questions. Falls back to direct query embedding on failure.

## Technical Context

**Language/Version**: Python 3.10 (backend only)
**Primary Dependencies**: FastAPI, httpx, Supabase Python client, Ollama (gemma4:e2b for generation, nomic-embed-text for embedding) — all existing
**Storage**: N/A — no data model changes; hypothetical answer is transient/in-memory
**Testing**: Manual testing via the /manuals/ask endpoint
**Target Platform**: Linux server (Zorin OS) behind Nginx
**Project Type**: Web service (backend modification only)
**Performance Goals**: HyDE generation adds <5 seconds to pipeline
**Constraints**: 15 GB server RAM shared with Ollama model; HyDE generation must use same model already loaded for answer generation to avoid double memory usage
**Scale/Scope**: Single endpoint modification (`POST /manuals/ask`), single service file change

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Rationale |
|-----------|--------|-----------|
| I. Full-Stack Ownership | Pass (justified exclusion) | Backend-only pipeline optimization. No new endpoint, no new UI, no migration. Frontend already sends questions via existing contract — no change needed. |
| II. Explicit Over Automatic | Pass | HyDE runs deterministically on every question. Fallback is explicit and logged. |
| III. Role-Based Access Control | N/A | No new endpoints or permissions. |
| IV. Server-First File Storage | N/A | No file storage involved. |
| V. Client-Side Computation | N/A | Backend pipeline change. |
| VI. Audit Everything | Pass | Existing `log_activity` call in `ask_question` endpoint remains. HyDE step adds internal logging (success/fallback) per FR-005. |
| VII. Simplicity & YAGNI | Pass | Single new private function `_generate_hypothetical_answer()` in `manual_rag_service.py`. No new abstractions, no config UI, no toggles. |

## Project Structure

### Documentation (this feature)

```text
specs/043-hyde-retrieval/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (minimal — no data changes)
├── quickstart.md        # Phase 1 output
└── contracts/           # Phase 1 output (no contract changes)
```

### Source Code (repository root)

```text
backend/
├── services/
│   └── manual_rag_service.py   # MODIFY — add _generate_hypothetical_answer(), update ask()
├── routers/
│   └── manuals.py              # NO CHANGE — endpoint contract unchanged
└── services/
    ├── ollama_generator.py     # NO CHANGE — existing generate() used as-is
    └── ollama_embedder.py      # NO CHANGE — existing embed_single() used as-is
```

**Structure Decision**: Modification of a single existing service file. No new files, modules, or directories needed.

## Complexity Tracking

No constitution violations. Table not needed.
