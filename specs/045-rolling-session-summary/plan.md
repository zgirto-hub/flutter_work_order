# Implementation Plan: Rolling Session Summary

**Branch**: `045-rolling-session-summary` | **Date**: 2026-04-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/045-rolling-session-summary/spec.md`

## Summary

Add rolling session summary (memory compression) to the manual assistant AI pipeline. When conversation history exceeds 8 turns, the backend compresses older turns into a 3-4 sentence summary via Ollama, keeping the last 4 raw turns plus the summary in the prompt. The frontend removes its last-10 truncation and sends all history; all compression logic lives on the backend. Fallback to the current last-10 behavior on compression failure.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, httpx, Ollama (gemma4:e2b) (backend); http package, Flutter Material (frontend)  
**Storage**: N/A — no persistent data; summary is transient/in-memory per request  
**Testing**: Manual testing via chat UI; backend log inspection  
**Target Platform**: Web (Flutter PWA) + Linux server (FastAPI)  
**Project Type**: Web application (backend API + frontend PWA)  
**Performance Goals**: Compression step adds ≤2 seconds to response time  
**Constraints**: 15 GB server RAM shared with Ollama; compression prompt must be lightweight  
**Scale/Scope**: Single concurrent user per conversation session; conversations up to 30+ turns

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend: new compression step in `manual_rag_service.py`, router updated in `manuals.py`. Frontend: `chat_tab.dart` (remove sublist truncation, store/send `_sessionSummary`), `manual_assistant_service.dart` (add `sessionSummary` param + parse from response). No migration needed (no persistent data). |
| II. Explicit Over Automatic | PASS | Compression is deterministic (threshold-based), not implicit. Fallback behavior is explicit. |
| III. Role-Based Access Control | N/A | No new endpoints or permissions. Uses existing `/manuals/ask` endpoint. |
| IV. Server-First File Storage | N/A | No file storage involved. |
| V. Client-Side Computation Where Possible | PASS | Compression is server-side because it requires LLM access (Ollama). Client cannot perform this. Justified exception. |
| VI. Audit Everything | N/A | No user-facing action to audit. This is an internal pipeline optimization. Logging the summary for debugging is recommended but not an audit requirement. |
| VII. Simplicity & YAGNI | PASS | Single function added to existing service. No new abstractions, no configurability. Fixed threshold (8) and window (4). |

**Gate result**: PASS — no violations.

## Project Structure

### Documentation (this feature)

```text
specs/045-rolling-session-summary/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
backend/
├── services/
│   └── manual_rag_service.py    # Add _compress_history(); update _build_prompt(); return session_summary from ask()
└── routers/
    └── manuals.py               # Add session_summary to AskRequest + response JSON

frontend/
└── lib/
    ├── screens/
    │   └── manual_assistant/
    │       └── chat_tab.dart    # Remove sublist truncation; store/send _sessionSummary
    └── services/
        └── manual_assistant_service.dart  # Add sessionSummary param; parse from response
```

**Structure Decision**: Existing web application structure. Backend service + router modifications. Frontend: ChatTab state + service method updated (no new files).

## Complexity Tracking

> No violations — table not needed.
