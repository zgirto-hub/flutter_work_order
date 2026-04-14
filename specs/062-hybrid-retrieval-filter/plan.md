# Implementation Plan: Hybrid Retrieval — System Keyword Pre-filtering

**Branch**: `062-hybrid-retrieval-filter` | **Date**: 2026-04-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/062-hybrid-retrieval-filter/spec.md`

## Summary

Before cosine vector search runs, detect whether the user's question references a known operational system (CADAS-ATS, AIDA-NG, IRTOS, etc.) using a static Python keyword registry with aliases. If detected, look up which uploaded manuals reference that system in either their `title` or `file_name` column (case-insensitive substring). Pass the narrowed manual-id list into the existing `_retrieve_chunks_per_manual` path (spec 046) by filtering its manuals-list input. No changes to the `search_manual_chunks` RPC signature. A small `retrieval_info` block is added to the response (always populated — `detected_system`, `filtered_manual_ids`, `filter_applied`, optional `fallback_reason`) and surfaced in the Flutter answer card as a "Filtered to: <system>" chip when `filter_applied=true`. When a system is detected but no matching manuals exist, the backend prepends an explicit directive to the generator prompt so the LLM states info is unavailable rather than substituting near-neighbor content.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client, httpx, existing `ollama_embedder`/`ollama_generator` (backend); Flutter Material, existing answer-card widgets (frontend). **No new dependencies.**
**Storage**: Supabase (PostgreSQL) — existing `manuals`, `manual_chunks` tables. No schema changes. No migrations.
**Testing**: pytest (backend unit tests for `system_registry`); manual black-box verification of the five benchmark questions from spec Testing section; Flutter widget test for the filter chip
**Target Platform**: Linux server (backend, systemd `document_server.service`); Flutter Web PWA (primary), Android/iOS (secondary)
**Project Type**: Web application (Flutter frontend + FastAPI backend + Supabase) — Option 2
**Performance Goals**: System detection p95 < 5 ms (SC-005, pure in-process string matching). Per-manual retrieval already profiled under spec 046 — this feature only reduces the number of manuals iterated, never increases it.
**Constraints**: No change to `search_manual_chunks` RPC signature. No schema changes. Response contract backward compatible (clients ignoring `retrieval_info` continue to work). No new network calls in the hot path.
**Scale/Scope**: Registry ~10–20 canonical systems + aliases; typical corpus <50 manuals, <10 matching per system. Hot-path impact: one extra Supabase `manuals` query (`select id, title, file_name ILIKE ...`) when a system is detected, else zero new queries.

## Constitution Check

Evaluated against the Work Order System Constitution v1.0.0. This is a backend-focused feature with a minor frontend chip; no new auth surface, no new storage, no new cross-cutting concerns.

| Principle | Compliance | Notes |
|---|---|---|
| I. Full-Stack Ownership | ✅ PASS | Backend module + integration, frontend model + UI chip, docs updated (spec/plan). No new DB migration by design — clarification Q1 resolved registry as code module. Layer-skip is explicit. |
| II. Explicit Over Automatic | ✅ PASS | System detection is deterministic string matching; no silent inference across system boundaries. "No manuals for system" triggers an explicit `fallback_reason` + generator directive, not a silent substitution. |
| III. Role-Based Access Control | ✅ PASS | No new endpoints. Feature lives inside existing `ask()` service call which already uses the caller's session context. |
| IV. Server-First File Storage | ✅ N/A | No file storage involved. |
| V. Client-Side Computation Where Possible | ✅ PASS | Detection runs server-side (where the registry lives and where retrieval happens — cannot be moved client-side). The answer card chip is a pure presentation change of data already in the response payload. |
| VI. Audit Everything | ✅ PASS | No user-facing action state change. Detection is logged at INFO/WARNING level (system detected, fallback reason) per existing observability conventions for the RAG pipeline; no new `user_activity_log` category is needed because this is a retrieval-internal signal, not a user action. |
| VII. Simplicity & YAGNI | ✅ PASS | Static constant over DB-backed registry (Q1). Single retrieval code path reused (Q2). No new tables, no new RPC. Matching rule restricted to two existing columns (Q3). |

**Gate status**: PASS. No Complexity Tracking entries needed.

## Project Structure

### Documentation (this feature)

```text
specs/062-hybrid-retrieval-filter/
├── plan.md              # This file
├── research.md          # Phase 0 output — registry shape, matching rule, integration point
├── data-model.md        # Phase 1 output — in-memory/response entities (no DB)
├── quickstart.md        # Phase 1 output — manual-verification recipe for the 5 benchmark questions
├── contracts/
│   └── retrieval_info.schema.md   # Response-shape contract for retrieval_info
├── checklists/
│   └── requirements.md  # Written by /speckit.specify
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
backend/
├── services/
│   ├── system_registry.py        # NEW — KNOWN_SYSTEMS constant, detect_system(), get_manual_ids_for_system()
│   └── manual_rag_service.py     # MODIFY — integrate detection in ask(), narrow manuals-list in _retrieve_chunks_per_manual
└── tests/
    └── test_system_registry.py   # NEW — detection unit tests (acceptance criteria from spec FR-001, FR-002)

frontend/
├── lib/
│   ├── models/
│   │   └── manual_qa_answer.dart # MODIFY — add RetrievalInfo class, wire into ManualQaAnswer.fromJson
│   └── features/
│       └── manual_assistant/
│           └── widgets/
│               └── answer_card.dart  # MODIFY — show "Filtered to: <system>" chip when filter_applied=true
```

**Structure Decision**: Option 2 (web application) — the existing repo layout already separates `backend/` (FastAPI) and `frontend/` (Flutter). This feature touches two new files (`system_registry.py` + test) and three existing files (`manual_rag_service.py`, `manual_qa_answer.dart`, `answer_card.dart`). No new directories.

## Complexity Tracking

No constitution violations. Table intentionally empty.
