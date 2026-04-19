# Implementation Plan: Generator Prompt Tuning (RAG Over-Refusal Fix)

**Branch**: `089-generator-prompt-tuning` | **Date**: 2026-04-19 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/089-generator-prompt-tuning/spec.md`

## Summary

Rewrite `DOCUMENT_QA_SYSTEM_PROMPT` in `backend/services/manual_rag_service.py` to stop the generator from refusing questions when retrieval has already delivered strongly-ranked chunks (0.73–0.82 rerank scores, 5–10 candidates). Baseline evidence: 33/87 (37.9%) on the quality suite with 50/58 refusals classified as `generator_refused_with_chunks` by `rag_diagnostic_log`. Approach: replace `"only answer if explicitly stated"`-style language with balanced ANSWER / REFUSE / NEVER INVENT rules, plus four few-shot examples sourced from existing `validated_qa` rows (human-verified content, zero fabrication risk). Merge floors on all 7 SCs (aggregate score ≥ 48/87, Cat 6 ≥ 8/9 hallucination resistance, `generator_refused_with_chunks` ≤ 15 post-run, must-refuse regression set at 0 violations). Iteration cap 3; if unmet, revert branch and scaffold spec 090.

## Technical Context

**Language/Version**: Python 3.10 (backend only — no Flutter/Dart changes this spec)
**Primary Dependencies**: FastAPI (existing), Supabase Python client (existing), `services.ai_providers.resolver` (spec 063, existing), `services.manual_rag_service.DOCUMENT_QA_SYSTEM_PROMPT` (existing, target of edit), `services.ollama_generator` (existing). **No new dependencies.**
**Storage**: Supabase (PostgreSQL + pgvector). Existing `validated_qa` table (spec 083) read-only for few-shot sourcing. Existing `rag_diagnostic_log` table (spec 088) read-only for SC-007 verification. **No schema changes, no migrations.**
**Testing**: Existing `backend/tests/test_rag_quality.py` suite (87 questions). Extended in this spec with a `must_refuse: true` per-entry flag + non-zero exit code on flag violation. No new test framework — pure Python script changes.
**Target Platform**: Linux server (Zorin OS), deployed via existing `document_server.service` systemd unit behind Nginx.
**Project Type**: Web application (backend endpoint behavior change; no frontend involvement).
**Performance Goals**: No latency targets; spec 089 does not add steps to the pipeline. The change may shift average latency by ±5s (longer answers vs. shorter refusals) — acceptable and out of scope.
**Constraints**:
- Prompt must be **model-neutral** (per clarification Q1) — works against whichever provider `services.ai_providers.resolver` returns at runtime.
- No Gemma-specific or Gemini-specific tokens / preambles.
- `VALIDATED_QA_SYSTEM_PROMPT` (verbatim path, spec 083) MUST remain untouched.
- Atomic single-commit rollback via `git revert`.
**Scale/Scope**: One Python source file primary edit (`backend/services/manual_rag_service.py`), one test file edit (`backend/tests/test_rag_quality.py`), up to 3 iteration cycles, ≤ ~400 LOC diff expected (mostly prompt string).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| **I. Full-Stack Ownership** | ⚠️ Justified exception | Prompt tuning is backend-only — no endpoint surface, no DB, no frontend observable change. Documented here and in spec §3 / §8. |
| **II. Explicit Over Automatic** | ✅ Complies | No auto-behavior added. Prompt rules are explicit ("ANSWER when", "REFUSE only when", "NEVER INVENT"). |
| **III. Role-Based Access Control** | ✅ N/A | No new endpoints; existing `/api/manuals/ask` and `/api/manuals/ask/stream` permission model unchanged. |
| **IV. Server-First File Storage** | ✅ N/A | No file storage involved. |
| **V. Client-Side Computation** | ✅ N/A | Backend-only. |
| **VI. Audit Everything** | ✅ Complies | Each generation continues to emit a `rag_diagnostic_log` row via spec 088's instrumentation; SC-007 reads that audit signal. No new audit stream required. |
| **VII. Simplicity & YAGNI** | ✅ Complies strongly | Single prompt-string edit + per-entry test flag. No configuration surface, no abstraction layer, no feature flag. Rollback = `git revert` one commit. |

**Gate outcome**: PASS with one justified exception (Principle I — backend-only change documented). Proceed to Phase 0.

## Project Structure

### Documentation (this feature)

```text
specs/089-generator-prompt-tuning/
├── plan.md              # This file
├── research.md          # Phase 0 — prompt engineering decisions, few-shot sourcing protocol
├── data-model.md        # Phase 1 — trivial (no new entities; validated_qa read-side only)
├── quickstart.md        # Phase 1 — implementer walkthrough + validation protocol
├── contracts/
│   └── prompt-contract.md  # Phase 1 — the prompt block in its final form
├── spec.md              # Source feature specification
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── services/
│   ├── manual_rag_service.py          # EDIT: DOCUMENT_QA_SYSTEM_PROMPT (~line 292)
│   ├── ollama_generator.py            # READ: confirm prompt not duplicated here
│   ├── validated_qa_service.py        # READ: source few-shot rows from validated_qa
│   └── ai_providers/
│       └── resolver.py                # READ: confirm model-neutral context
└── tests/
    └── test_rag_quality.py            # EDIT: add `must_refuse` flag + exit-code logic
```

**Structure Decision**: Backend-only edit. Feature does NOT span frontend — the user-observable change (fewer over-refusals, more synthesized answers) happens entirely server-side. No migration, no API contract change, no Flutter screen touched. This is an intentional, documented exception to Principle I (Full-Stack Ownership) because the spec is a behavioral tuning of an already-shipped surface rather than a new feature.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Principle I — backend-only change | Spec 089 tunes generator behavior, not UX. Prompt lives in one backend file; the frontend observes the result implicitly. | A parallel frontend change (e.g., UI toggle for "conservative vs. liberal" generation) would add configurability the spec explicitly forbids under Principle VII (YAGNI). No user-facing setting is needed because success is measured from the user-invisible test suite and `rag_diagnostic_log`. |
