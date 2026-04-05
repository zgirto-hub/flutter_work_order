# Implementation Plan: AI-Assisted Work Order Description

**Branch**: `020-ai-wo-description` | **Date**: 2026-04-05 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/020-ai-wo-description/spec.md`

## Summary

Add an AI "Suggest" button next to the work order description field that calls a local Ollama instance (`gemma4:e2b`) through a new FastAPI endpoint. The backend strips preamble from AI responses and returns a clean 2-4 sentence professional description. The Flutter frontend integrates a new `AiAssistService` and modifies `add_work_order.dart` to present the button with proper loading/error states and an accept/dismiss flow based on whether the description field is already populated.

## Technical Context

**Language/Version**: Python 3 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, httpx (backend — already in requirements.txt at v0.28.1); http package (frontend — already used)
**Storage**: N/A — no persistent data; request/response only
**Testing**: Manual testing (no automated test framework currently in use for this project)
**Target Platform**: Flutter Web (PWA) + FastAPI on Linux server behind Nginx
**Project Type**: Web application (backend API + Flutter PWA frontend)
**Performance Goals**: AI response within 60 seconds; UI remains responsive during request
**Constraints**: 60s timeout on Ollama call; endpoint returns 503 when Ollama unreachable; no auth on endpoint (internal only)
**Scale/Scope**: Single concurrent user per request; no caching; no streaming

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | **Pass** | Backend router + Frontend service + Frontend screen. No database migration needed (no persistent data). Documented in Complexity Tracking. |
| II. Explicit Over Automatic | **Pass** | No implicit assignments or state transitions. AI fills description only on explicit user tap. |
| III. Role-Based Access Control | **Violation — Justified** | Endpoint has no auth per design (internal-only, not exposed externally). Button visibility is gated by `canEdit` and `_roleLoaded` on the frontend. Documented in Complexity Tracking. |
| IV. Server-First File Storage | **N/A** | No file uploads or storage involved. |
| V. Client-Side Computation | **N/A** | AI generation must happen server-side (model runs on server). |
| VI. Audit Everything | **Violation — Justified** | AI suggestion is a read-only convenience action that doesn't modify any persistent data. No activity log entry needed. If the user accepts and saves, the normal work order update audit applies. Documented in Complexity Tracking. |
| VII. Simplicity & YAGNI | **Pass** | Minimal implementation: one endpoint, one service, one UI button. No caching, streaming, or abstraction layers. |

## Project Structure

### Documentation (this feature)

```text
specs/020-ai-wo-description/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
backend/
├── main.py                          # Register new ai_assist router
├── requirements.txt                 # httpx already present, no changes needed
└── routers/
    └── ai_assist.py                 # NEW — /api/ai/suggest endpoint

frontend/lib/
├── config.dart                      # Existing — AppConfig.baseUrl used by new service
├── services/
│   └── ai_assist_service.dart       # NEW — AiAssistService class
├── screens/Work_Orders/
│   └── add_work_order.dart          # MODIFIED — Suggest button + bottom sheet
└── theme/
    └── app_theme.dart               # Existing — AppColors used for styling
```

**Structure Decision**: Follows existing web application pattern (backend/routers/ + frontend/lib/services/ + frontend/lib/screens/). New router follows the same `from routers import X` + `app.include_router(X.router, prefix="/api")` pattern. New service follows the existing stateless service pattern using `http` package and `AppConfig.baseUrl`.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| No database migration (Principle I) | Feature is request/response only — AI generates text on-the-fly with no storage requirement. No data to persist. | Adding a table for suggestion history would violate YAGNI (Principle VII). |
| No auth on `/api/ai/suggest` (Principle III) | Endpoint is internal-only (localhost Ollama). Adding auth would add complexity with no security benefit since the endpoint doesn't access/modify user data. | Frontend already gates button visibility by role/permissions. |
| No audit log for AI suggestions (Principle VI) | Suggestion generation is a read-only convenience action. The actual data mutation (saving description) is already audited through the existing work order update flow. | Logging every suggestion tap would create noise in activity logs with no compliance value. |
