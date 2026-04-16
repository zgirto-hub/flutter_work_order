# Implementation Plan: Default Q&A Generation to Gemini Flash

**Branch**: `076-gemini-default-generation` | **Date**: 2026-04-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/076-gemini-default-generation/spec.md`

## Summary

Flip the default AI provider for final Q&A answer generation from local Ollama to Gemini Flash, while keeping query rewrite, HyDE, history compression, and embedding stages hardcoded to local Ollama. All existing mechanics — provider resolver (spec 063), automatic fallback, and single-row fallback audit logging (spec 065) — remain unchanged. Changes are limited to (per `research.md`): (1) the `_DEFAULT_PROVIDER` constant in `backend/services/ai_providers/resolver.py` flips `"local"` → `"gemini"`, (2) a one-time code-level migration in `backend/main.py`'s FastAPI `lifespan` handler rewrites any `app_settings.ai_provider` row whose value is exactly `"local"` to `"gemini"` and emits an audit row via `log_activity`, (3) the seed migration `supabase/migrations/20260415_app_settings.sql` is updated so fresh databases start with `'gemini'` directly, and (4) a small pytest module documents and guards the invariants (default constant, rewrite/HyDE/embedding direct-to-Ollama isolation, migration idempotency). No new endpoints, no frontend changes, no data-model additions.

## Technical Context

**Language/Version**: Python 3.10 (backend only — no Flutter/Dart changes this spec)
**Primary Dependencies**: FastAPI, Supabase Python client, httpx, `google-generativeai` (all existing from spec 063), existing `services.ai_providers.resolver`, `services.ollama_generator`
**Storage**: Supabase (PostgreSQL) — existing `app_settings` table (row `key='ai_provider'`) and existing `user_activity_log` table. No schema changes. Existing seed migration `20260415_app_settings.sql` edited in place to change the seed value; no new migration file is added.
**Testing**: pytest (existing). Patch target `services.ai_providers.resolver._DEFAULT_PROVIDER` is already used in spec 063/065 tests and remains the seam.
**Target Platform**: Linux server (Zorin OS), single-server deployment behind Nginx. Backend runs as `document_server.service` (systemd).
**Project Type**: web-service (backend-only). Frontend already renders whatever provider the backend returns via `/api/ai-providers/active`; no UI change required.
**Performance Goals**: Rewrite / HyDE / embedding stages ≤ 110% of pre-spec baseline (SC-002). Generation step latency is not targeted — Gemini Flash is typically faster than Ollama on the server's hardware, so the change is expected to improve, not regress, generation time.
**Constraints**: Preserve the single-audit-row-per-fallback contract (FR-005). Migration must be idempotent on subsequent startups (FR-008). Rate-limit / quota-exceeded (HTTP 429) responses must flow through the existing fallback path with no circuit-breaker state (FR-004, clarified by Q3).
**Scale/Scope**: One constant change in `resolver.py`, one small addition to `main.py`'s lifespan handler (idempotent one-time migration + audit), one-line edit to `supabase/migrations/20260415_app_settings.sql` (seed value), one new pytest module. Zero frontend changes. Existing fallback + audit tests remain authoritative for spec 063/065 invariants.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Notes |
|-----------|-----------|-------|
| I. Full-Stack Ownership | **Exempt with justification** | Spec Assumption 5 documents backend-only scope. No migration of frontend state needed because the admin provider settings screen already reads the active provider dynamically via `/api/ai-providers/active` (spec 063). The frontend will display "Gemini" automatically after the migration. Documented here and in spec Assumptions rather than bypassed silently. |
| II. Explicit Over Automatic | **Pass** | The one-time migration is explicit (SQL file, tracked by Supabase migrations), audited (user_activity_log insert), and documented in FR-008 with the trade-off spelled out: prior admin `"local"` choices require re-selection. No silent fallback. |
| III. RBAC | **Pass** | No permission model changes. The existing admin-only `/api/ai-providers/settings` endpoint continues to gate overrides. RLS on `app_settings` unchanged. |
| IV. Server-First File Storage | **N/A** | No file storage touched. |
| V. Client-Side Computation Where Possible | **N/A** | No client-side computation affected. |
| VI. Audit Everything | **Pass** | FR-005 preserves the single-row-per-fallback contract. FR-008 adds exactly one `user_activity_log` row for the migration event via `log_activity()` from the lifespan handler (category `admin`, action `ai_provider_migrated`, per research.md R-006). Idempotency: the lifespan handler reads the current value first and only writes/logs if the value is exactly `"local"` — repeat startups after the first successful migration find `"gemini"` already in place and do nothing. No blocking audit writes on the request path. |
| VII. Simplicity & YAGNI | **Pass** | Deliberately minimal: one constant, one migration, one invariant test. Circuit-breaker (Q3 alternative) and per-content data governance (Q2 alternative) are explicitly deferred to future specs. No new abstraction, no feature flag. |

**Overall gate**: **PASS — no violations requiring Complexity Tracking.**

## Project Structure

### Documentation (this feature)

```text
specs/076-gemini-default-generation/
├── plan.md              # This file
├── spec.md              # Feature specification (clarified 2026-04-16)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── contract-deltas.md  # Phase 1 output (behavior change to existing endpoints, not new contracts)
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

This is a mature monolith; the plan touches a narrow set of existing files rather than adding a new module. Paths follow the project's established layout:

```text
backend/
├── main.py                             # CHANGE: extend existing `lifespan` handler with a one-time ai_provider migration step (per research.md R-004); no other logic touched
├── services/
│   └── ai_providers/
│       └── resolver.py                 # CHANGE: _DEFAULT_PROVIDER = "local" → "gemini" (per research.md R-001)
├── services/
│   ├── manual_rag_service.py           # VERIFY: rewrite/HyDE paths call `services.ollama_generator` directly; no change (research.md R-003)
│   ├── validated_qa_service.py         # VERIFY: embedding + paraphrase paths direct-to-Ollama; no change
│   └── ollama_embedder.py              # VERIFY: direct-to-Ollama; no change
└── tests/
    └── test_provider_default.py        # NEW: covers the default constant, idempotency of the migration, and invariance of pipeline-stage routing (research.md R-007)

supabase/
└── migrations/
    └── 20260415_app_settings.sql       # CHANGE: seed value `'local'` → `'gemini'` so fresh databases start correct (research.md R-005). Supabase migrations run once per DB, so this is safe for deployed environments.

frontend/
└── (no changes — provider label is fetched dynamically from /api/ai-providers/active; research.md R-003)
```

**Structure Decision**: Follow existing `backend/` + `supabase/migrations/` layout. No new directories. Two existing Python files and one existing SQL migration are modified in place; one new pytest module is added. Frontend untouched.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations. Constitution gate passes.
