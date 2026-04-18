# Implementation Plan: Verbatim Verified Answers

**Branch**: `083-verbatim-verified-answers` | **Date**: 2026-04-18 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/083-verbatim-verified-answers/spec.md`

## Summary

When the verified-Q&A similarity search returns a top-1 match that is both **strong** (similarity ≥ 0.85) and **clearly dominant** over the next-best match (gap ≥ 0.05) — or is a lone match meeting the similarity floor — the RAG pipeline short-circuits around the language-model generator and returns the stored `validated_answer` verbatim. Otherwise it continues today's synthesis behavior (LLM grounded on top-3). A new backend response field `verification_mode: "verbatim" | "synthesized"` drives a small UI difference: both modes show the existing green "Verified Answer" badge, but only the synthesis mode shows a grey footer caption "Synthesized from N verified sources" (N counts **distinct underlying curated answers** — spec-068 paraphrase variants that share the same stored answer text count once). Every verified response (both modes) writes one row to the existing `user_activity_log` table via the fire-and-forget helper so thresholds can be tuned from real traffic post-ship. Zero schema changes, zero new endpoints.

**Technical approach**: extract two private helpers (`_should_return_verbatim(matches)` and `_build_verbatim_payload(...)`) at module scope inside `backend/services/manual_rag_service.py` so the four existing is-verified code paths (pre-rewrite streaming ~L725, post-rewrite streaming ~L819, pre-rewrite non-streaming ~L988, post-rewrite non-streaming ~L1170) call the same logic. The streaming paths yield the stored answer as a single SSE `data:` chunk and `return` before calling `provider_generate_stream`; the non-streaming paths build and return the response dict directly without calling `provider_generate`. `verification_mode` travels in `stream_meta` (streaming) or the response dict (non-streaming), reaching the frontend via the same channel that already carries `is_verified` and `verified_source`.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend, primarily web target)
**Primary Dependencies**: FastAPI, Supabase Python client, existing `services.manual_rag_service`, existing `services.validated_qa_service`, existing `utils.activity.log_activity`, existing `services.ai_providers.resolver` (touched only to **not** invoke on verbatim path). Flutter Material. **No new dependencies.**
**Storage**: Supabase (PostgreSQL with pgvector) — existing `validated_qa` and `user_activity_log` tables. **No schema changes, no migrations.**
**Testing**: pytest (backend unit tests for `_should_return_verbatim`); no new Flutter test harness required — model parse + widget conditional covered by manual quickstart.
**Target Platform**: Linux server (FastAPI via systemd — `document_server.service`), Flutter Web PWA served by Nginx.
**Project Type**: Web (backend + frontend).
**Performance Goals**: Verbatim path round-trip < 2 seconds end-to-end (embedding + pgvector search only, zero LLM generation); synthesis path unchanged from today (~10–15 s including generation).
**Constraints**: Zero schema migrations. Zero new endpoints. No change to `validated_qa_service.check_validated_match`. No change to the spec-067 direct-lookup fast path. No change to non-verified (is_verified=false) response paths. Thresholds must be centralized so all four paths share identical behavior.
**Scale/Scope**: Single-server internal deployment (Zorin OS), small team (<20 users). Activity-log row volume: one row per verified response; negligible incremental table growth.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Full-Stack Ownership | ✅ Pass | Backend (`manual_rag_service.py` modify + new unit test file) and frontend (`manual_qa_answer.dart` + `answer_card.dart` modify) both covered. Database migration column = none required (explicitly by design). Documentation: agent-context file updated via script per workflow. |
| II. Explicit Over Automatic | ✅ Pass | The verbatim vs. synthesis decision is explicit — driven by two named constants (`VERBATIM_MIN_SIMILARITY`, `VERBATIM_DOMINANCE_GAP`) evaluated by a single named helper. `verification_mode` is an explicit response field; the UI does not infer it. |
| III. Role-Based Access Control | ✅ Pass | No role changes. Both verbatim and synthesized responses are served to anyone who can already ask the AI assistant. Feedback targeting (`validated_qa_id`) is unchanged. |
| IV. Server-First File Storage | ✅ Pass | N/A — no file I/O in this feature. |
| V. Client-Side Computation Where Possible | ✅ Pass | The UI branches purely on server-provided `verification_mode`; no client-side re-scoring or threshold evaluation. |
| VI. Audit Everything | ✅ Pass | FR-014 writes exactly one `user_activity_log` row per verified response via the existing fire-and-forget `log_activity(...)` helper. FR-015 ensures log failures never block the response path (consistent with `utils/activity.py`'s existing try/except). |
| VII. Simplicity & YAGNI | ✅ Pass | Thresholds are recompile-only constants (no runtime tuning UI — explicitly out of scope). No new abstractions beyond the two required helpers. No new database tables. No new endpoints. |

**Initial gate result**: PASS. No violations, no Complexity Tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/083-verbatim-verified-answers/
├── plan.md                    # This file
├── spec.md                    # Feature specification (from /speckit.specify + /speckit.clarify)
├── research.md                # Phase 0 output
├── data-model.md              # Phase 1 output — entities, helper signatures
├── quickstart.md              # Phase 1 output — manual verification walkthrough
├── contracts/
│   └── response-schema.md     # Phase 1 output — JSON diff for /manuals/ask response
└── checklists/
    └── requirements.md        # Spec-quality checklist
```

### Source Code (repository root)

```text
backend/
├── services/
│   ├── manual_rag_service.py           # MODIFY — add constants + 2 helpers, wire into 4 paths
│   └── validated_qa_service.py         # UNCHANGED (per FR-019)
├── utils/
│   └── activity.py                     # UNCHANGED — existing log_activity reused
├── routers/
│   └── manuals.py                      # UNCHANGED — stream_meta already carries extra fields to the final metadata event
└── tests/
    └── test_verbatim_helper.py         # NEW — unit tests for _should_return_verbatim

frontend/
└── lib/
    ├── models/
    │   └── manual_qa_answer.dart       # MODIFY — add `verificationMode` field + fromJson parse
    └── screens/
        └── manual_assistant/
            └── widgets/
                └── answer_card.dart    # MODIFY — render footer caption only when verified + synthesized
```

**Structure Decision**: Web-app layout (backend + frontend), matching the existing project. All changes land in files the spec called out; the helpers stay module-private inside `manual_rag_service.py` to preserve encapsulation (no new service module needed — the logic is not reused outside this file).

## Complexity Tracking

> **Not applicable** — Constitution Check passed with no violations.

## Artifacts produced by Phase 0 and Phase 1

- [research.md](research.md) — resolved design questions (similarity-rounding precision, dedup strategy for N, SSE ordering, log-activity plumbing)
- [data-model.md](data-model.md) — helper signatures, response-dict diff, stream_meta diff
- [contracts/response-schema.md](contracts/response-schema.md) — JSON contract diff for `/manuals/ask`
- [quickstart.md](quickstart.md) — manual verification steps post-deploy
- Agent context updated via `.specify/scripts/powershell/update-agent-context.ps1 -AgentType claude`

## Post-design Constitution re-check

After Phase 1 design:

- Helpers are pure functions of their inputs (no hidden state) — consistent with II (Explicit) and VII (Simplicity).
- No new dependencies introduced — VII (YAGNI) preserved.
- Telemetry write uses existing `log_activity` exactly as Constitution VI requires (fire-and-forget, never blocks).
- Response contract is additive only (`verification_mode` as a new field; existing fields unchanged) — no break for any existing consumer.

**Post-design gate result**: PASS.
