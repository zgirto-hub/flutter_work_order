# Implementation Plan: AI Assistant Answer Streaming (SSE)

**Branch**: `079-sse-answer-streaming` | **Date**: 2026-04-17 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/079-sse-answer-streaming/spec.md`

## Summary

The AI Assistant RAG endpoint currently returns the full answer as a single JSON response after the entire pipeline completes (15-60s). This plan adds a parallel SSE streaming endpoint (`POST /manuals/ask/stream`) that runs the retrieval pipeline to completion, then streams LLM tokens to the Flutter frontend in real-time using Server-Sent Events. All 4 AI providers (Ollama, Gemini, Groq, Mistral) gain a `generate_stream()` async generator method. The frontend parses SSE events via the existing `http` package's chunked response API and renders tokens progressively in the AnswerCard widget. Nginx is configured to disable proxy buffering for the SSE endpoint.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, sse-starlette (NEW), httpx, google-generativeai (backend); http, supabase_flutter, Flutter Material (frontend)  
**Storage**: N/A — no persistent data; all stream events are transient  
**Testing**: Manual testing via browser DevTools (SSE inspection), curl  
**Target Platform**: PWA (Flutter Web) + Linux server (FastAPI behind Nginx)  
**Project Type**: Web application (full-stack)  
**Performance Goals**: First tokens within 3s of retrieval completing; smooth accumulation with <1s gaps between visible updates  
**Constraints**: Must not break existing `/manuals/ask` endpoint; Nginx proxy_buffering must be off for SSE  
**Scale/Scope**: Single concurrent user per stream; existing ~5 active users

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | **PASS** | Feature spans backend (endpoint, providers), frontend (service, widget), and infrastructure (Nginx). No database layer needed (transient data only) — documented in data-model.md. |
| II. Explicit Over Automatic | **PASS** | Streaming is explicit: new endpoint, explicit SSE event types, explicit cancellation via connection close. No implicit behavior changes. |
| III. Role-Based Access Control | **PASS** | Same JWT bearer auth as existing endpoint (FR-009). No new roles or permissions. |
| IV. Server-First File Storage | **N/A** | No file storage involved. |
| V. Client-Side Computation | **PASS** | SSE parsing happens client-side. No new server-per-view calls beyond the stream itself. |
| VI. Audit Everything | **PASS** | Activity logging reuses existing `log_activity` call from the ask endpoint. Fallback audit logging preserved. |
| VII. Simplicity & YAGNI | **PASS** | Parallel `generate_stream()` alongside existing `generate()` is the minimal change. No new abstractions. Agentic streaming deferred (v1 sends complete answer as single SSE event). |

**Post-Phase 1 re-check**: All gates still pass. No new violations introduced by design artifacts.

## Project Structure

### Documentation (this feature)

```text
specs/079-sse-answer-streaming/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── sse-stream-endpoint.md  # SSE endpoint contract
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── requirements.txt                          # Add sse-starlette
├── routers/
│   └── manuals.py                            # New POST /manuals/ask/stream endpoint
├── services/
│   ├── ollama_generator.py                   # Add generate_stream() async generator
│   ├── manual_rag_service.py                 # Add ask_stream() that yields tokens
│   └── ai_providers/
│       ├── base.py                           # Add generate_stream() to AIProvider ABC
│       ├── local_ollama.py                   # Implement streaming via generate_stream()
│       ├── gemini.py                         # Implement streaming via generate_content stream
│       ├── groq.py                           # Implement streaming via Groq SDK
│       ├── mistral.py                        # Implement streaming via Mistral SDK
│       └── resolver.py                       # Add generate_stream() with fallback logic

frontend/
├── lib/
│   ├── services/
│   │   └── manual_assistant_service.dart     # Add askQuestionStream() returning Stream
│   └── screens/
│       └── manual_assistant/
│           ├── chat_tab.dart                 # Wire streaming into _sendQuestion()
│           └── widgets/
│               └── answer_card.dart          # Support progressive text + streaming cursor

server/
└── nginx/
    └── flutter_app.conf                      # Add SSE location block
```

**Structure Decision**: Existing web application structure (backend/ + frontend/ + server/). No new directories needed. All changes are additions to existing files, plus one new dependency.

## Complexity Tracking

No constitution violations. Table intentionally left empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
