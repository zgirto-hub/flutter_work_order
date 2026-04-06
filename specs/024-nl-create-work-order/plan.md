# Implementation Plan: Natural Language Work Order Creation

**Branch**: `024-nl-create-work-order` | **Date**: 2026-04-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/024-nl-create-work-order/spec.md`

## Summary

Add a natural language input area to the Add Work Order screen that lets users describe a work order in one sentence (typed or voice-dictated). A new backend endpoint (`POST /ai/parse-work-order`) sends the text to the local Ollama LLM, which parses it into structured fields (title, description, location, type, department, status). The frontend auto-fills the form, highlights changed fields, and lets the user review before submitting. Supports English and Arabic. Builds on existing AI assist infrastructure (020) and voice dictation (022).

## Technical Context

**Language/Version**: Python 3 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, httpx, Ollama/gemma4:e2b (backend); http, Flutter Material, DictationButton from 022 (frontend)  
**Storage**: N/A — no persistent data; request/response only  
**Testing**: Manual testing; backend endpoint testable via curl/httpx  
**Target Platform**: Linux server (backend), Mobile browsers via Flutter Web PWA (frontend)  
**Project Type**: Full-stack web application (backend API + Flutter PWA)  
**Performance Goals**: AI response under 10 seconds for single-sentence input  
**Constraints**: Requires network connectivity; Ollama must be running on server; constrained to valid types/statuses/departments  
**Scale/Scope**: 1 new backend endpoint, 1 new frontend service, modifications to 1 screen (AddWorkOrderScreen)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Full stack: new backend endpoint + frontend service + screen modification. No database migration needed (no persistent data). |
| II. Explicit Over Automatic | PASS | User explicitly taps "Generate" button. No auto-triggering. AI suggestions are reviewed before submission. |
| III. Role-Based Access Control | PASS | The new endpoint is accessible to all authenticated users who can create work orders. Existing role checks on the Add Work Order screen apply. |
| IV. Server-First File Storage | N/A | No files involved. |
| V. Client-Side Computation | N/A | AI parsing requires server-side LLM — cannot be client-side. This is a justified exception since the LLM runs on the server. |
| VI. Audit Everything | PASS | The resulting work order creation/update goes through existing flows that already log to `user_activity_log`. No additional audit needed for the AI parsing step itself (it's a stateless suggestion). |
| VII. Simplicity & YAGNI | PASS | Single endpoint, single service, reuses existing Ollama infrastructure and DictationButton widget. No new abstractions. |

**Technology Constraints Check**:
- Backend: FastAPI on Uvicorn — PASS (new router added to existing backend)
- Frontend: Flutter (Dart) targeting web — PASS
- No `url_launcher` usage — PASS
- No `backend/version.json` changes — PASS

**All gates pass. No violations to justify.**

## Project Structure

### Documentation (this feature)

```text
specs/024-nl-create-work-order/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── parse-work-order.md
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── ai_assist.py             # Modified: add POST /ai/parse-work-order endpoint
└── main.py                      # Verify router already registered (it is)

frontend/
├── lib/
│   ├── screens/Work_Orders/
│   │   └── add_work_order.dart   # Modified: add NL input area + Generate button + auto-fill logic
│   ├── services/
│   │   └── ai_assist_service.dart # Modified: add parseWorkOrder() method
│   └── widgets/
│       └── dictation_button.dart  # Reused (from 022) on the NL input area
└── pubspec.yaml                   # No changes needed (http package already present)
```

**Structure Decision**: Full-stack changes. Backend gets a new endpoint in the existing `ai_assist.py` router. Frontend gets a new service method and UI modifications to `AddWorkOrderScreen`. Reuses existing `DictationButton` widget from feature 022.

## Complexity Tracking

> No constitution violations — table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| (none)    | —          | —                                   |
