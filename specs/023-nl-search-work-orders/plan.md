# Implementation Plan: Natural Language Search for Work Orders

**Branch**: `023-nl-search-work-orders` | **Date**: 2026-04-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/023-nl-search-work-orders/spec.md`

## Summary

Add natural language search to the work orders list screen. Users type queries like "closed technical orders this week" into the existing search bar. The backend parses the query via the existing Ollama AI infrastructure (gemma4:e2b) to extract structured filters (status, type, department, location, date range, resolution time), queries the work_orders table with those filters, and returns matching results. Falls back to keyword search if AI parsing fails or times out (5s). Extracted filters are displayed as removable chips; manual filter controls are hidden while NL search is active.

## Technical Context

**Language/Version**: Python 3 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, httpx, Supabase Python client (backend); http, Flutter Material (frontend)  
**Storage**: Supabase (PostgreSQL) — existing `work_orders`, `departments`, `users` tables; no schema changes  
**Testing**: Manual testing against Ollama service; acceptance scenarios from spec  
**Target Platform**: Flutter Web (PWA) + FastAPI on Linux server  
**Project Type**: Web application (backend + frontend)  
**Performance Goals**: NL search complete in <10s total; AI parsing timeout at 5s; keyword fallback <2s  
**Constraints**: Ollama on localhost:11434; existing gemma4:e2b model; 30 items/page pagination  
**Scale/Scope**: Same scale as existing work order list; ~hundreds to low thousands of WOs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | **PASS** | Feature spans backend (new endpoint), frontend (search UI, service, filter chips). No database migration needed. |
| II. Explicit Over Automatic | **PASS** | Search is user-initiated (Enter/button). No auto-search on typing pause. Fallback is explicit with indicator. |
| III. Role-Based Access Control | **PASS** | Search results enforce existing RBAC: admin=all, technician=department, reporter=own. Backend applies role filtering. |
| IV. Server-First File Storage | **N/A** | No file storage involved. |
| V. Client-Side Computation Where Possible | **JUSTIFIED DEVIATION** | NL parsing must happen server-side (Ollama). Filter-based querying also server-side since we need to apply structured filters at the DB level. Keyword fallback uses existing client-side search when AI is unavailable. See Complexity Tracking. |
| VI. Audit Everything | **PASS** | NL search requests will be logged via `log_activity()` with category "search" and action "nl_search". |
| VII. Simplicity & YAGNI | **PASS** | Reuses existing Ollama infrastructure, existing work order query endpoint pattern, existing filter chip UI pattern. No new abstractions. |

**Post-Phase 1 Re-check**: All gates still pass. The new `/api/search/nl` endpoint follows the same pattern as existing AI endpoints. No over-engineering detected.

## Project Structure

### Documentation (this feature)

```text
specs/023-nl-search-work-orders/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── api-contracts.md
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── ai_search.py          # NEW — NL search endpoint
└── utils/
    └── activity.py            # EXISTING — audit logging

frontend/
└── lib/
    ├── screens/Work_Orders/
    │   └── work_order_home.dart    # MODIFIED — integrate NL search bar
    ├── services/
    │   └── ai_search_service.dart  # NEW — NL search API client
    ├── controllers/
    │   └── filter_controller.dart  # MODIFIED — add NL filter state
    ├── filters/
    │   └── work_order_filter_engine.dart  # MODIFIED — NL filter mode
    └── models/
        └── nl_search_result.dart   # NEW — parsed filter response model
```

**Structure Decision**: Web application pattern (backend + frontend). New backend router follows the existing `ai_assist.py` and `ai_insights.py` patterns. Frontend adds a service + model following existing conventions. Existing search service (`features/search/search_service.dart`) is NOT reused — its endpoints don't exist and its model is over-engineered for our needs.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Server-side search (Principle V) | NL parsing requires Ollama (localhost only). Structured filter queries need DB-level filtering for accuracy and pagination support. | Client-side NL parsing impossible (no local LLM in browser). Client-side filtering of pre-loaded data would miss results not yet paginated in. |
