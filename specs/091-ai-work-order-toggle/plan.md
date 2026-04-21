# Implementation Plan: AI Work Order Toggle

**Branch**: `091-ai-work-order-toggle` | **Date**: 2026-04-21 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/091-ai-work-order-toggle/spec.md`

## Summary

Admin-controlled global toggle for AI-assisted work order creation. A new "AI Features" section in Admin settings provides a switch labeled "AI Work Order". When enabled, the Add Work Order screen shows an AI Assist entry (the existing `NlInputCard`) that accepts a free-text description and auto-fills form fields. When disabled, the AI entry is hidden from all users. The flag is persisted in `app_settings`, enforced server-side on the `/ai/parse-work-order` endpoint, and audit-logged via `user_activity_log`. A new `/ai/autofill-work-order` endpoint replaces and extends `/ai/parse-work-order` with server-side toggle gating, auth checks, input validation (20–500 chars), per-user rate limiting (10/min, 100/day), and side-by-side overwrite confirmation on the frontend.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client, `services.ai_providers.resolver` (existing), `services.ollama_generator` (existing); `http`, `supabase_flutter`, Flutter Material (frontend)
**Storage**: Supabase (PostgreSQL) — `app_settings` table (existing, adds `ai_work_order_enabled` row)
**Testing**: Manual testing via Admin UI + Add Work Order screen; no automated test framework currently
**Target Platform**: Linux server (backend), Flutter Web PWA (frontend)
**Project Type**: Web application (FastAPI backend + Flutter frontend)
**Performance Goals**: Toggle state fetch < 500ms on screen open; autofill response < 30s p95; server-side refusal < 1s when disabled
**Constraints**: Single-server deployment; AI provider call is the latency bottleneck; rate limiting must not burden the DB
**Scale/Scope**: ~50 concurrent users; 1 new `app_settings` row; 1 new backend endpoint; 1 new frontend toggle section; modifications to Add Work Order screen

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | ✅ PASS | Feature spans backend (new endpoint + toggle gate), database (new `app_settings` row), frontend (Admin toggle UI + conditional NlInputCard + overwrite preview). All layers covered. |
| II. Explicit Over Automatic | ✅ PASS | Admin must explicitly enable the feature. Overwrite requires per-field confirmation. No implicit auto-fill without user action. |
| III. Role-Based Access Control | ✅ PASS | Toggle is admin-only (server-verified). AI Assist entry is visible to any authenticated user when toggle is ON, but the settings UI is admin-only. Non-admin requests to change the toggle are rejected. |
| IV. Server-First File Storage | N/A | No file storage in this feature. |
| V. Client-Side Computation Where Possible | ✅ PASS | Toggle state is fetched from server (single source of truth). Overwrite conflict resolution happens client-side. Rate-limit counters are server-side (correct — they must be authoritative). |
| VI. Audit Everything | ✅ PASS | Toggle changes logged to `user_activity_log` (category `admin`, action `ai_work_order_toggled`). Autofill requests logged with outcome, not PII content. `app_settings.updated_by` tracks who changed the setting. |
| VII. Simplicity & YAGNI | ✅ PASS | Reuses existing `app_settings` table, existing `NlInputCard` widget, existing `ai_providers` resolver, existing admin settings pattern. No new abstract layers. Only one new endpoint. Only one new `app_settings` key. |

**Gate Result: PASS** — All applicable principles are satisfied. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/091-ai-work-order-toggle/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── ai_assist.py           # MODIFY — add /ai/autofill-work-order endpoint, toggle gate on /ai/parse-work-order
├── services/
│   └── rate_limiter.py        # NEW — per-user in-memory rate limiter
├── utils/
│   ├── app_settings.py        # EXISTING — used for toggle reads/writes
│   └── activity.py            # EXISTING — audit logging
└── main.py                    # EXISTING — no changes needed (routes in ai_assist.py)

frontend/
├── lib/
│   ├── screens/
│   │   ├── settings_page.dart          # MODIFY — add AI Features section with AI Work Order toggle
│   │   └── Work_Orders/
│   │       └── add_work_order.dart     # MODIFY — conditional NlInputCard visibility, overwrite dialog
│   ├── services/
│   │   ├── ai_provider_service.dart   # MODIFY — add getAiWorkOrderEnabled / setAiWorkOrderEnabled
│   │   └── ai_assist_service.dart      # MODIFY — add autofillWorkOrder method
│   └── widgets/
│       ├── nl_input_card.dart          # EXISTING — no change (reuse as-is)
│       └── ai_overwrite_dialog.dart    # NEW — side-by-side preview dialog for field conflicts

supabase/
└── migrations/
    └── 20260421000000_ai_work_order_toggle.sql  # NEW — seed ai_work_order_enabled=false
```

**Structure Decision**: Web application (Option 2) — following existing `backend/` + `frontend/` + `supabase/migrations/` layout. New files are minimal: one migration, one rate limiter, one dialog widget, plus targeted modifications to three existing files.

## Constitution Re-Check (Post-Design)

All 7 principles re-verified after Phase 1 design. No violations introduced. The design reuses existing infrastructure (`app_settings`, `AiProviderService`, `NlInputCard`, `resolver`) and adds minimal new code (one endpoint, one migration seed, one dialog widget, one rate limiter, two service methods). Rate limiting uses in-memory state (appropriate for single-server). No new tables, no new tables, no new abstractions.

## Complexity Tracking

> No constitution violations — table is empty.