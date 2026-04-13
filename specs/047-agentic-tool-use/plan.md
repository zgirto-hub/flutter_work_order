# Implementation Plan: Agentic Tool Use (Layer 5)

**Branch**: `047-agentic-tool-use` | **Date**: 2026-04-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/047-agentic-tool-use/spec.md`

## Summary

Add an agentic tool-calling loop (Layer 5) to the manual assistant pipeline. The AI model (Gemma via Ollama) receives a tool manifest describing three tools — `work_orders`, `manuals`, `compare` — and decides which (if any) to call before generating a final answer. The loop runs inside the existing `ask_question` endpoint with a 3-call maximum and 60-second timeout. When no tools are needed, the model answers directly. The existing Layer 1-4 pipeline is wrapped by the `manuals` tool and remains unchanged.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, httpx, Supabase Python client (backend); http, Flutter Material (frontend)
**Storage**: Supabase (PostgreSQL) — existing `work_orders`, `users`, `departments` tables; pgvector for manual chunks
**Testing**: Manual integration testing via the AI chat interface
**Target Platform**: Web (PWA) + Linux server backend
**Project Type**: Web service (FastAPI) + Flutter PWA frontend
**Performance Goals**: 60-second wall-clock timeout for entire agentic loop per question
**Constraints**: Single GPU server (15GB RAM), Gemma 4 E2B via Ollama, prompt-based tool calling (no native Ollama tool-use API)
**Scale/Scope**: Single-user sequential requests; no concurrent agentic loops needed

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend: new agentic loop + tool executors in manuals router/service. Frontend: response metadata display. No new DB tables. |
| II. Explicit Over Automatic | PASS | Tool calls are explicit decisions by the model, not implicit fallbacks. The model must output a structured tool-call block to trigger a tool. |
| III. Role-Based Access Control | PASS | Work order data returned by the tool respects existing access patterns. The ask_question endpoint already requires user_email. |
| IV. Server-First File Storage | N/A | No file uploads or storage changes. |
| V. Client-Side Computation | N/A | Agentic loop is entirely server-side. |
| VI. Audit Everything | PASS | Tool calls logged in response metadata (FR-011). Activity log already exists for ask_manual. |
| VII. Simplicity & YAGNI | PASS | Prompt-based tool calling using existing `generate()` — no new frameworks, no agent SDK, no JSON mode. Three tools only. |

## Project Structure

### Documentation (this feature)

```text
specs/047-agentic-tool-use/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (from /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── manuals.py              # ask_question endpoint — add agentic routing
├── services/
│   ├── manual_rag_service.py   # Wrap existing ask() as manuals tool callable
│   ├── ollama_generator.py     # Existing generate() — used for tool decisions + compare
│   └── agentic_tools.py        # NEW — tool manifest, tool executor, agentic loop
└── (no new files elsewhere)

frontend/
└── lib/
    └── services/
        └── ai_assist_service.dart  # Parse tools_used metadata from response
```

**Structure Decision**: Backend-only new file (`agentic_tools.py`) contains the tool manifest, individual tool executors, and the agentic loop. The manuals router calls the agentic loop instead of `manual_rag_service.ask()` directly. Frontend changes are minimal — display tools_used metadata if present.

## Complexity Tracking

No constitution violations. No complexity justifications needed.
