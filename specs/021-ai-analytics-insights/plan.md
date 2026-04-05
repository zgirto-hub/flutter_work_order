# Implementation Plan: AI-Powered Analytics & Insights

**Branch**: `021-ai-analytics-insights` | **Date**: 2026-04-05 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `/specs/021-ai-analytics-insights/spec.md`

## Summary

Add an AI-powered insights endpoint and dashboard widget that generates natural language summaries (3-5 bullet points) of work order statistics and system status health. Uses the existing Ollama + Gemma4:e2b infrastructure. Three insight types (overview, system_status, trends) with English/Arabic language toggle. Role-gated to admin/supervisor. No new database tables — reads from existing `work_orders`, `system_status_reports`, and `departments` tables.

## Technical Context

**Language/Version**: Python 3 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, Supabase Python client, httpx (backend); http, Flutter Material (frontend)  
**Storage**: N/A — no new tables; reads from existing Supabase (PostgreSQL) tables  
**Testing**: Manual endpoint testing via curl; manual UI testing  
**Target Platform**: Web (Flutter PWA) + Linux server (FastAPI)  
**Project Type**: Web application (backend + frontend)  
**Performance Goals**: Insight generation under 90 seconds end-to-end  
**Constraints**: Local Ollama model (Gemma4:e2b), 60s timeout for LLM calls  
**Scale/Scope**: Hundreds to low thousands of work orders per 30-day window

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend endpoint + frontend service + frontend widget. No database migration needed (read-only). |
| II. Explicit Over Automatic | PASS | Insights generated on-demand via explicit user action (button press). Language selection is explicit toggle. |
| III. Role-Based Access Control | PASS | Endpoint validates admin/supervisor role. Frontend hides card for other roles. |
| IV. Server-First File Storage | N/A | No file storage involved. |
| V. Client-Side Computation | N/A | Server-side aggregation is required (data too large for client, LLM is server-side). Documented exception. |
| VI. Audit Everything | PASS | Will log insight generation via `log_activity()` with category "ai" and action "generated_insight". |
| VII. Simplicity & YAGNI | PASS | Single endpoint, single widget, no caching, no stored results. Minimal implementation. |

## Project Structure

### Documentation (this feature)

```text
specs/021-ai-analytics-insights/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Research decisions
├── data-model.md        # Data model (transient entities)
├── quickstart.md        # Quick reference
├── contracts/
│   └── ai-insights.md   # API contract
├── checklists/
│   └── requirements.md  # Quality checklist
└── tasks.md             # Implementation tasks (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   ├── ai_insights.py     # NEW — endpoint, aggregation, prompts
│   └── ai_assist.py       # REFERENCE — Ollama pattern, preamble stripping
├── main.py                # MODIFIED — register ai_insights router
├── db.py                  # REFERENCE — Supabase client
└── utils/
    └── activity.py        # REFERENCE — activity logging

frontend/
├── lib/
│   ├── services/
│   │   ├── ai_insights_service.dart  # NEW — HTTP service
│   │   └── ai_assist_service.dart    # REFERENCE — existing AI service pattern
│   ├── features/
│   │   └── analytics/
│   │       ├── ai_insights_card.dart  # NEW — dashboard card widget
│   │       └── chart_widgets.dart     # REFERENCE — existing widget patterns
│   ├── screens/
│   │   └── dashboard_screen.dart      # MODIFIED — add insights card
│   └── theme/
│       └── app_theme.dart             # REFERENCE — AppColors
```

**Structure Decision**: Follows existing separation — new backend router in `routers/`, new frontend service in `services/`, new widget in `features/analytics/` (alongside existing chart widgets). Dashboard screen is the integration point.

## Complexity Tracking

No constitution violations. No complexity justifications needed.
