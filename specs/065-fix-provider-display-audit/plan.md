# Implementation Plan: AI Provider Manager — Phase 2 Cleanups

**Branch**: `065-fix-provider-display-audit` | **Date**: 2026-04-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/065-fix-provider-display-audit/spec.md`

## Summary

Three targeted production fixes from spec 063 smoke-testing: (1) add `provider_display_name` to the `/manuals/ask` response and render it in the chat footer (replacing the hardcoded `gemma4:e2b` label), (2) write an `ai_provider_fallback` row to `user_activity_log` when fallback fires (closed taxonomy for `detail`), and (3) make the Flutter provider chip react to each response's `fallback_used` flag, switching to `⚠ <display_name> (fallback)` warning state when true. Keep the legacy `model` field populated for one release (backwards-compat).

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client, existing `google-generativeai`/`groq`/`mistralai` SDKs (no new deps). Flutter Material + `http` + existing `AiProviderService` from spec 063.
**Storage**: Supabase (PostgreSQL) — **no schema changes**. Uses existing `user_activity_log` table.
**Testing**: Manual acceptance per user stories in spec. Smoke test: force fallback, verify audit row + chip warning state + footer label.
**Target Platform**: Linux server (Zorin) FastAPI under `document_server.service`; Flutter PWA via Nginx.
**Project Type**: Web application — backend + frontend.
**Performance Goals**: No regression. Audit write is fire-and-forget per constitution principle VI. Chip updates within same render frame as answer.
**Constraints**: Keep `model` field populated one more release (FR-009). No API keys or raw exception text in client payloads or audit rows (FR-010, taxonomy in FR-003).
**Scale/Scope**: 2 backend files modified, 1 Dart model modified, 1 Dart widget modified, 1 Dart screen modified. Zero migrations.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Full-Stack Ownership | ✅ | Backend (response builder + resolver audit call) + frontend (model, chip widget, chat footer). No layer skipped. |
| II. Explicit Over Automatic | ✅ | Chip reaction is driven by explicit per-response signal (`fallback_used`), not a poll. Audit write is explicit, gated on fallback occurring. |
| III. Role-Based Access Control | ✅ | No new endpoints; no role gate changes. |
| IV. Server-First File Storage | ✅ | No file storage involved. |
| V. Client-Side Computation | ✅ | Chip state derived client-side from response fields. |
| VI. Audit Everything | ✅ | This spec exists specifically to close the FR-010 audit gap from 063. Audit write uses existing `log_activity()` fire-and-forget helper. |
| VII. Simplicity & YAGNI | ✅ | Minimal change: one new response field, one new audit row on fallback, one chip state update. No new abstractions, no new endpoints, no new tables. Legacy `model` field kept as alias for exactly one release to avoid breakage. |

No violations. Proceed.

## Project Structure

### Documentation (this feature)

```text
specs/065-fix-provider-display-audit/
├── plan.md              # This file
├── spec.md              # Feature specification (with Clarifications session)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── ask_response_contract.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit.tasks — not created here)
```

### Source Code (repository root)

```text
backend/
├── services/
│   ├── manual_rag_service.py            # MODIFIED — response builder: add provider_display_name + keep model as alias
│   └── ai_providers/
│       └── resolver.py                   # MODIFIED — on fallback, call log_activity with closed-taxonomy detail; pass user_email through
└── routers/
    └── manuals.py                        # MODIFIED — thread user_email/admin_email into the resolver call path

frontend/lib/
├── models/
│   └── manual_ask_response.dart          # MODIFIED — add providerDisplayName field, preserve model alias
├── widgets/
│   └── ai_provider_chip.dart             # MODIFIED — accept per-response fallback state, render warning variant
└── screens/
    └── manual_rag_screen.dart            # MODIFIED — footer renders providerDisplayName; passes fallback state to chip on each response
```

**Structure Decision**: Web application (existing). No new files — all changes are in-place edits to files introduced or last touched by spec 063.

## Complexity Tracking

*No constitution violations; table not populated.*
