# Implementation Plan: RAG Pipeline — Manual Knowledge Assistant

**Branch**: `058-rag-pipeline` | **Date**: 2026-04-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/058-rag-pipeline/spec.md`

## Summary

The RAG pipeline enabling the AI assistant to answer questions from uploaded technical manuals (PDF, DOCX, TXT) via local embedding, chunking, and generation is **already fully implemented** in the codebase. All six tasks described in the original technical spec map to existing, production code. No new implementation is required.

### Discovery: Feature Already Exists

Every component described in the specification has a working counterpart:

| Spec Task | Spec File | Existing Implementation | Status |
|-----------|-----------|------------------------|--------|
| TASK 1 — Embedding service | `services/embeddings.py` | `services/ollama_embedder.py` (46 lines) | Done |
| TASK 2 — Chunker service | `services/chunker.py` | `services/manual_chunker.py` (66 lines) + `services/manual_parser.py` (85 lines) | Done |
| TASK 3 — Upload endpoint | `POST /api/manuals/upload` | `routers/manuals.py:169` — `upload_manual()` | Done |
| TASK 3 — Query endpoint | `POST /api/manuals/query` | `routers/manuals.py:300` — `ask_question()` (as `/api/manuals/ask`) | Done |
| TASK 4 — Router registration | `main.py` | `main.py:31` (import) + `main.py:119` (include_router) | Done |
| TASK 5 — Requirements | `requirements.txt` | `pymupdf==1.24.10`, `python-docx==1.2.0`, `httpx==0.28.1` all present | Done |
| TASK 6 — Flutter service | `manual_assistant_service.dart` | 25+ methods including `uploadManual()` (line 130) and `askQuestion()` (line 211) | Done |

### Additional capabilities already built (beyond spec scope)

The existing implementation goes far beyond the spec:

- **Full RAG service** (`manual_rag_service.py`, 981 lines) — query rewriting, HyDE retrieval, cross-manual synthesis, session summaries, agentic tool use
- **Chunk management** — CRUD, split, merge, re-embed, bulk delete endpoints
- **Answer feedback loop** — rating, flagging, review, verified answers persistence
- **AI settings** — model selection, system instructions, per-session configuration
- **Agentic tools** (`agentic_tools.py`, 555 lines) — work order retrieval and entity extraction integrated into the RAG loop
- **AI queue** (`ai_queue.py`) — async task queue for prioritized AI operations

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, httpx, Supabase Python client (backend); http, Flutter Material (frontend)
**Storage**: Supabase (PostgreSQL) with pgvector — `manuals`, `manual_chunks` tables, `search_manual_chunks` RPC
**Testing**: Manual / integration testing (no automated test suite observed)
**Target Platform**: Linux server (backend) + Web/PWA (frontend)
**Project Type**: Full-stack web application (FastAPI + Flutter PWA)
**Performance Goals**: Upload confirmation within 5 minutes for 50-page PDF; query response within 30 seconds
**Constraints**: All AI runs locally via Ollama (nomic-embed-text for embeddings, gemma4:e2b for generation); 15GB RAM server limit
**Scale/Scope**: Single-tenant, ~50 users, aviation maintenance domain (DGCA Kuwait)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Feature spans backend (services, router), database (migrations), frontend (service layer). UI screens are explicitly out of scope per spec and are separate features. |
| II. Explicit Over Automatic | PASS | Upload requires explicit user action (file + title); no auto-processing. Query is user-initiated. |
| III. Role-Based Access Control | PASS | Existing router has `_admin_check()` helper; endpoints accept `user_email` for audit. |
| IV. Server-First File Storage | N/A | Manual files are not stored on filesystem — text is extracted, chunked, and embedded. Original files are not retained. |
| V. Client-Side Computation | N/A | RAG queries require server-side vector search and LLM generation — cannot be client-side. |
| VI. Audit Everything | PASS | Router imports `log_activity` from `utils.activity` and uses it in endpoints. |
| VII. Simplicity & YAGNI | PASS | Implementation exists and is in use; no speculative additions. |

**All gates pass. No violations to justify.**

## Project Structure

### Documentation (this feature)

```text
specs/058-rag-pipeline/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── spec.md              # Feature specification
└── checklists/
    └── requirements.md  # Specification quality checklist
```

### Source Code (existing — no new files needed)

```text
backend/
├── main.py                              # Router registration (line 31, 119)
├── routers/
│   └── manuals.py                       # 17+ endpoints (1100+ lines)
├── services/
│   ├── ollama_embedder.py               # Embedding service (46 lines)
│   ├── ollama_generator.py              # LLM generation service (114 lines)
│   ├── manual_parser.py                 # File parsing: PDF, DOCX, TXT (85 lines)
│   ├── manual_chunker.py               # Text chunking with overlap (66 lines)
│   ├── manual_rag_service.py           # Core RAG pipeline (981 lines)
│   ├── manual_storage_service.py       # DB storage abstraction (40 lines)
│   ├── validated_qa_service.py         # Answer validation/review (364 lines)
│   ├── agentic_tools.py                # Tool-use framework (555 lines)
│   ├── entity_extractor.py             # NER service (233 lines)
│   └── ai_queue.py                     # Async AI task queue (78 lines)
└── requirements.txt                     # pymupdf, python-docx, httpx present

frontend/lib/
└── services/
    └── manual_assistant_service.dart    # 25+ methods (659 lines)
```

**Structure Decision**: No new directories or files are needed. The feature is fully implemented across the existing project structure.

## Recommendation

**This feature branch should be closed without implementation work.** The RAG pipeline described in the specification — embedding, chunking, upload, query, Flutter service layer — is fully operational in the current codebase.

If there are specific enhancements or gaps to address, they should be scoped as separate, targeted features rather than re-implementing what exists. Potential follow-up features:

1. **Quality improvements** — if answer quality needs tuning (prompt engineering, retrieval parameters)
2. **UI screens** — upload screen, chat screen, rating widget (already noted as out of scope)
3. **Performance optimization** — if upload or query times exceed the success criteria thresholds

## Complexity Tracking

> No violations detected. Table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
