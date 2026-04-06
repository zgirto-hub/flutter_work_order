# Implementation Plan: AI Arabic/English Document Expert

**Branch**: `027-ai-document-expert` | **Date**: 2026-04-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/027-ai-document-expert/spec.md`

## Summary

Add an AI-powered document expert assistant to the letter composer that rewrites, corrects grammar, generates, and translates formal Arabic/English correspondence using the existing Ollama/Gemma backend. The implementation extends the proven `ai_assist.py` pattern with a new endpoint and adds a collapsible Flutter panel widget to the letter form that communicates with the editor iframe via the existing postMessage protocol.

## Technical Context

**Language/Version**: Python 3 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, httpx (backend); http, Flutter Material (frontend)  
**Storage**: N/A — no persistent data  
**Testing**: Manual testing against running Ollama instance  
**Target Platform**: Web (PWA)  
**Project Type**: Web application (backend + frontend)  
**Performance Goals**: AI response within 15 seconds for typical letter content (<2000 words)  
**Constraints**: Ollama timeout 60s; single batch response (no streaming)  
**Scale/Scope**: Single-user interaction; no concurrent request handling needed beyond what FastAPI provides

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend endpoint + frontend widget + service — all layers covered. No DB migration needed (no persistence). |
| II. Explicit Over Automatic | PASS | User explicitly triggers each AI action; result requires explicit "Apply" to take effect. No auto-replacement. |
| III. Role-Based Access Control | PASS | Panel available to all letter form users (clarification confirmed no role restriction needed — the letter form itself is already role-gated). |
| IV. Server-First File Storage | N/A | No file storage involved. |
| V. Client-Side Computation Where Possible | N/A | AI inference requires server-side Ollama; no client-side alternative. |
| VI. Audit Everything | PASS | AI requests are ephemeral utility calls (like spell-check). No user-facing action that changes persisted state — Apply only changes in-memory editor content. Existing AI endpoints don't log to activity either. |
| VII. Simplicity & YAGNI | PASS | Single endpoint with action enum, single widget, no new abstractions. Reuses existing patterns entirely. |

**Post-Phase 1 Re-check**: All gates still pass. No new entities, no new storage, no new roles.

## Project Structure

### Documentation (this feature)

```text
specs/027-ai-document-expert/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── api.md           # API contract
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
└── routers/
    └── ai_assist.py          # Modified — add document-expert endpoint + health check

frontend/
└── lib/
    ├── services/
    │   └── ai_assist_service.dart    # Modified — add documentExpert() + checkAiHealth()
    ├── widgets/
    │   └── ai_document_expert_widget.dart  # NEW — collapsible AI panel
    └── screens/
        └── letters_v2/
            └── letter_form_tab_v2.dart     # Modified — embed AI widget
```

**Structure Decision**: Follows existing project layout. One new widget file; three modified files. No new directories needed (widgets/ already exists).

## Complexity Tracking

No constitution violations. Table intentionally empty.
