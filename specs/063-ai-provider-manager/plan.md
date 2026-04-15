# Implementation Plan: AI Provider Manager — Extensible Multi-Provider System

**Branch**: `063-ai-provider-manager` | **Date**: 2026-04-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/063-ai-provider-manager/spec.md`

## Summary

Introduce a thin provider abstraction for AI answer generation so an Admin can switch the backend that powers `/manuals/ask` between Local Ollama and Google Gemini 2.5 Flash at runtime, with automatic fallback to Local when a non-Local provider fails. Phase 1 scope is generation-only and limited to the Ask-the-AI flow (see Clarifications in spec). Embeddings stay on Ollama. The design is intentionally minimal: a single in-memory TTL cache reading from a new `app_settings` Supabase table, a small `ai_providers/` package with an `AIProvider` ABC, two concrete providers, and a registry dict. Adding a future provider requires only a new module file, one registry line, and updating the `ai_providers_available` row — no schema, routing, or Flutter changes.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client, httpx (existing); `google-generativeai` (NEW — backend only, for Gemini SDK). Flutter Material + `supabase_flutter` + `http` (existing).
**Storage**: Supabase (PostgreSQL) — new `app_settings` key-value table (2 rows in phase 1). No pgvector changes. Existing `user_activity_log` reused for fallback audit events.
**Testing**: Manual acceptance checks per user stories in spec (aligned with project's existing test posture — no automated backend test suite in repo). Smoke test: toggle provider, ask a question, verify chip + logs.
**Target Platform**: Linux server (Zorin) running FastAPI under `document_server.service`; Flutter PWA served via Nginx; Ollama on localhost:11434.
**Project Type**: Web application — backend (`backend/`) + frontend (`frontend/`).
**Performance Goals**: Provider switch propagates within 60s (TTL cache). Cloud-provider timeout budget 30s (per Q3 clarification) before fallback triggers. Ask-the-AI end-to-end within existing Nginx 300s ceiling.
**Constraints**: API keys server-side only (FR-016); no Flutter code change required to add future providers (FR-017); existing `/manuals/ask` contract must remain backward compatible (FR-018).
**Scale/Scope**: Internal tool, <100 concurrent users. Two providers shipped in phase 1. One new Supabase table, three new backend endpoints, one new Flutter settings section, one new Flutter chip widget.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Full-Stack Ownership | ✅ | Touches backend router, migration, Flutter model, service, UI (Admin settings + chat chip). Navigation wiring via existing settings entry. |
| II. Explicit Over Automatic | ✅ | Provider switch is explicit Admin action. Fallback is an explicit, logged event with a visible flag — not a silent swap. |
| III. Role-Based Access Control | ✅ | Provider-change endpoint is Admin-only (FR-004). Chip read-only for all roles. |
| IV. Server-First File Storage | ✅ | No file storage involved. |
| V. Client-Side Computation | ✅ | No client-side datasets. |
| VI. Audit Everything | ✅ | Fallback events logged to `user_activity_log` (FR-010). Setting changes logged with `updated_by` and `updated_at` in `app_settings`. |
| VII. Simplicity & YAGNI | ✅ | Minimal abstraction (one ABC + registry). `embed()` method reserved per Q2 clarification but left NotImplemented to avoid premature coupling. Phase-1 scope deliberately narrow (Ask-the-AI only). |

No violations. Proceed.

## Project Structure

### Documentation (this feature)

```text
specs/063-ai-provider-manager/
├── plan.md              # This file
├── spec.md              # Feature specification (with Clarifications session)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output — HTTP contracts
│   └── ai_providers_api.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit.tasks — not created here)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   ├── ai_providers.py          # NEW — GET /api/ai/providers, POST /api/ai/provider, GET /api/ai/provider/health
│   └── manuals.py               # MODIFIED — /manuals/ask synthesis step routes through active provider
├── services/
│   ├── ai_providers/            # NEW package
│   │   ├── __init__.py
│   │   ├── base.py              # AIProvider ABC (generate, health_check, display_name, embed-reserved)
│   │   ├── local_ollama.py      # OllamaProvider — wraps existing ollama_generator.generate()
│   │   ├── gemini.py            # GeminiProvider — google-generativeai SDK
│   │   ├── registry.py          # PROVIDERS dict
│   │   └── resolver.py          # TTL-cached active-provider resolver + fallback orchestration
│   └── ollama_generator.py      # UNCHANGED — reused by OllamaProvider internally
├── utils/
│   └── app_settings.py          # NEW — thin reader/writer for app_settings table
├── main.py                      # MODIFIED — include ai_providers router
└── requirements.txt             # MODIFIED — add google-generativeai

supabase/migrations/
└── 20260415_app_settings.sql    # NEW — app_settings table + seed rows

frontend/lib/
├── models/
│   └── ai_provider.dart         # NEW — AiProvider, AiProviderHealth models
├── services/
│   └── ai_provider_service.dart # NEW — GET providers, POST provider, GET health
├── screens/
│   ├── settings_screen.dart     # MODIFIED — add "AI Assistant" admin section
│   └── manual_rag_screen.dart   # MODIFIED (or equivalent Ask-the-AI screen) — add provider chip
└── widgets/
    └── ai_provider_chip.dart    # NEW — read-only chip with fallback warning variant

.env (server)
└── GEMINI_API_KEY=...           # NEW — admin configures out-of-band; never client-visible
```

**Structure Decision**: Web application (existing). Backend + frontend layout already established. All new code lives inside existing directories under clearly named subpaths (`backend/services/ai_providers/`, `frontend/lib/widgets/ai_provider_chip.dart`). No new top-level directories.

## Complexity Tracking

*No constitution violations; table not populated.*
