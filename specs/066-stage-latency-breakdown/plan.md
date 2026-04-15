# Implementation Plan: Per-Stage RAG Pipeline Latency on Ask-the-AI Answer Card

**Branch**: `066-stage-latency-breakdown` | **Date**: 2026-04-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/066-stage-latency-breakdown/spec.md`

## Summary

Expose per-stage RAG pipeline timings (`embed_ms`, `hyde_ms`, `rewrite_ms`, `retrieval_ms`, `rerank_ms`, `generator_ms`, `total_ms`) in the `/manuals/ask` response as a new additive `latency_breakdown` object. The answer-card footer shows generator latency prominently alongside total (e.g., `Groq (Llama 3.3 70B) · 1.2s · pipeline 22s`) with an always-visible chevron that expands the full per-stage breakdown. Skipped/failed stages report explicit `null`; all seven keys are always present. Pure observability — no pipeline changes, no new dependencies, no migration, no persistence.

Technical approach: wrap each pipeline stage in `manual_rag_service.py` with a monotonic-clock timing helper that writes into a shared `latency_breakdown` dict; pass the dict through to `routers/manuals.py` which attaches it to the response. For generator timing specifically, wrap the provider call inside `ai_providers/resolver.py` so the measured value corresponds to the provider that actually produced the answer (including fallback). Frontend adds a `LatencyBreakdown` model, extends `ManualQaAnswer`, and refactors `answer_card.dart` footer with a new formatter utility (`formatStageLatency(int? ms)`) and an expansion panel with an always-visible chevron.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client, httpx, existing `ollama_embedder`/`ollama_generator`/`ai_providers` (backend); Flutter Material, existing answer-card widgets and `manual_assistant_service.dart` (frontend). **No new dependencies.**
**Storage**: None — `latency_breakdown` is transient per-response only (FR-010). No Supabase schema changes, no migration, no `user_activity_log` writes.
**Testing**: pytest (backend unit + integration), Flutter `flutter test` (widget + formatter unit tests)
**Target Platform**: Flutter Web PWA (primary), FastAPI on Uvicorn (Zorin server); same deployment path as spec 065
**Project Type**: Web application — backend + frontend (confirmed by existing `backend/` + `frontend/` structure)
**Performance Goals**: Timing instrumentation overhead per stage MUST be <1 ms (monotonic clock reads only). Pipeline total MUST NOT regress measurably vs. pre-feature baseline.
**Constraints**: Strictly additive to `/manuals/ask` response — existing clients ignoring the field MUST continue to work (FR-009). MUST NOT alter provider selection, fallback orchestration, 30 s timeout, or pipeline control flow (FR-012). Arabic and English render identically (FR-008). All seven breakdown keys always present; skipped/failed stages report `null` (FR-002).
**Scale/Scope**: One endpoint instrumented (`/manuals/ask`), one frontend answer card, ~3 backend files touched, ~3 frontend files touched, 0 migrations.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Notes |
|-----------|-----------|-------|
| I. Full-Stack Ownership | ✅ | Backend (service + router + resolver), frontend (model + service + widget) all covered. No DB migration needed — feature is transient by design per FR-010 (documented exclusion). |
| II. Explicit Over Automatic | ✅ | Skipped stages report explicit `null`, never inferred. `total_ms` is authoritative wall-clock. No silent fallback in timing semantics. |
| III. Role-Based Access Control | ✅ | No role-gating change; whoever can see the answer can see the breakdown (matches spec's explicit non-goal). Existing `/manuals/ask` role enforcement untouched. |
| IV. Server-First File Storage | ✅ | N/A — no files. |
| V. Client-Side Computation Where Possible | ✅ | Formatting (`<1s`, `0.3s`, `1.2s`, `1m 15s`) is computed client-side from raw millisecond values. Backend emits only integers. |
| VI. Audit Everything | ✅ with documented exclusion | Per FR-010 and clarification Q2, latency is intentionally NOT persisted to `user_activity_log` in phase 1. Documented as a deferred scope decision; no audit policy is violated because no persisted state is created. |
| VII. Simplicity & YAGNI | ✅ | No new dependencies, no new tables, no new endpoints. Timing hooks are a thin context-manager wrapper. Formatter is pure Dart, <30 lines. |

**Gate result**: PASS — no violations requiring Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/066-stage-latency-breakdown/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── manuals-ask-response.md   # Phase 1 output — response-shape delta
├── checklists/
│   └── requirements.md  # Created by /speckit.specify
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── services/
│   ├── manual_rag_service.py           # MODIFY — add _StageTimer context manager; wrap embed/HyDE/rewrite/retrieval/rerank stages; build latency_breakdown dict
│   └── ai_providers/
│       └── resolver.py                  # MODIFY — time the provider call (generator_ms), including fallback path so value reflects the provider that actually answered
├── routers/
│   └── manuals.py                       # MODIFY — thread latency_breakdown through /ask response payload; ensure all 7 keys present with null for skipped
└── tests/
    └── test_manual_rag_latency.py       # NEW — unit + contract tests (all-keys-present, null-for-skipped, fallback timing, greeting bypass shape)

frontend/lib/
├── models/
│   ├── manual_qa_answer.dart            # MODIFY — add latencyBreakdown field
│   └── latency_breakdown.dart           # NEW — LatencyBreakdown model + fromJson
├── services/
│   └── manual_assistant_service.dart    # MODIFY — parse latency_breakdown from response
├── screens/manual_assistant/widgets/
│   └── answer_card.dart                 # MODIFY — refactor footer: provider label + generator latency + pipeline total + chevron; add expansion panel with 7 rows
├── utils/
│   └── latency_formatter.dart           # NEW — formatStageLatency(int? ms) → "<1s" / "0.3s" / "1.2s" / "1m 15s" / "—" (for null)
└── test/
    ├── utils/latency_formatter_test.dart     # NEW — boundary tests for all format rules
    └── widgets/answer_card_latency_test.dart # NEW — widget test for footer + expansion
```

**Structure Decision**: Web application (backend + frontend). Backend changes are localized to three existing files plus one new test file; no new routers, no new services, no new packages. Frontend adds two small utility files (model + formatter) and modifies three existing files. Matches the project's established layout and the constitution's Full-Stack Ownership principle.

## Complexity Tracking

> No constitution gate violations. Table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| *(none)*  | —          | —                                   |
