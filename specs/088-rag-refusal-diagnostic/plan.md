# Implementation Plan: RAG Refusal Diagnostic Logging

**Branch**: `088-rag-refusal-diagnostic` | **Date**: 2026-04-19 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/088-rag-refusal-diagnostic/spec.md`

## Summary

Add per-stage structured logging to `/api/manuals/ask` so every request produces a forensic record of how each RAG pipeline stage (query rewrite, HyDE, retrieval, rerank, grounding decision, generation) contributed to the final answer. Purpose: turn the current 43.7% RAG-quality-suite pass rate + 35 over-refusals into classifiable data, so a subsequent tuning spec can target the actual bottleneck stage instead of guessing. **No tuning of the pipeline itself** — behaviour-preserving observability only (SC-004).

Technical approach: piggyback on spec 066's existing `_StageTimer` pattern — a shared dict threaded through the agentic loop that stages write into. Spec 066 writes only `*_ms` latency fields; spec 088 adds `*_decision`, `*_top_chunks`, `*_scores`, `*_threshold` fields to the same dict and persists the whole dict to a new Supabase table. Fire-and-forget write via existing `backend/utils/activity.py` pattern so logging failures can't block user responses. Admin-only browse screen added as a sibling tab alongside Train AI in the existing manual-assistant screen.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend, web target)
**Primary Dependencies**: FastAPI, Supabase Python client, existing `services.manual_rag_service`, existing `services.agentic_tools`, existing `utils.activity.log_activity` (backend); `http`, `supabase_flutter`, Flutter Material (frontend). **No new dependencies on either side.**
**Storage**: Supabase (PostgreSQL) — one new table `rag_diagnostic_log` with JSONB payload columns for per-stage data. One migration. Existing `user_activity_log` gets a short heartbeat row per diagnostic write.
**Testing**: pytest for backend unit tests around the reason-code classifier. **Primary acceptance harness**: `backend/tests/test_rag_quality.py` — used before/after to validate SC-002 (≥95% of refusals classified to the 3 named buckets) and SC-004 (identical pass/fail outcome per question, no behaviour drift).
**Target Platform**: Linux server behind Nginx (backend), PWA web via Flutter (frontend, primarily desktop Chrome for admin screen).
**Project Type**: Web application (Flutter frontend + FastAPI backend + Supabase).
**Performance Goals**: SC-003 — summary view renders grouped refusal counts for one day of traffic (~600 entries) in under 3 seconds. SC-006 — no measurable slowdown on user-facing response times; diagnostic write is fire-and-forget on a background task.
**Constraints**: FR-013 (behaviour-preserving — same questions produce same answers as before spec 088 ships); FR-014 (logging subsystem failures MUST NOT affect user-facing responses); Clarification Q1 (first-trigger-wins reason code); Clarification Q2 (asymmetric retention: 30d refused/errored, 7d grounded); Clarification Q3 (explicit `source` tag, not email-pattern-based).
**Scale/Scope**: ~600 diagnostic rows/day at steady state; ~9K rows at the 30-day retention horizon. Each row carries a JSONB payload of ~5–20 KB (the chunk/score breakdown). Total footprint well under 200 MB after pruning — negligible for Supabase.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Full-Stack Ownership** — ✓ Backend router (new admin sub-router `/api/admin/rag-diagnostics`), Supabase migration (`rag_diagnostic_log` table), Flutter model, Flutter service, Flutter screen (new admin tab), navigation wiring into the existing `ManualAssistantScreen` TabController. AGENT.md checklist followed.
- **II. Explicit Over Automatic** — ✓ Reason codes are a fixed enum; source tag is explicit (`user` / `test_suite` / `internal`) with no auto-detection from email; no implicit state transitions.
- **III. Role-Based Access Control** — ✓ Admin-only per FR-012. Backend admin sub-router protected by existing admin guard; frontend tab gated by `userRole == 'admin'` following the same pattern as the existing Train AI tab. Supabase RLS on `rag_diagnostic_log` restricts `SELECT` to admin role as defence-in-depth.
- **IV. Server-First File Storage** — N/A, no files.
- **V. Client-Side Computation Where Possible** — **Documented exception**: the diagnostic list is server-paginated and server-filtered (not fully client-loaded). Dataset at full 30-day retention is ~9K rows × ~10 KB JSONB each = ~90 MB, which exceeds the "practical memory limits" escape clause in the principle. Grouped-counts summary is computed server-side via SQL aggregation for SC-003's sub-3s target.
- **VI. Audit Everything** — ✓ Each diagnostic write also emits a `user_activity_log` heartbeat row (category `manual`, action `rag_diagnostic_logged`, detail = diagnostic_id). This ensures the constitutional audit trail is intact even for admin inspection of the logs. The diagnostic entries themselves are not "user-facing actions" per the constitution's definition, so a single heartbeat row per request is sufficient.
- **VII. Simplicity & YAGNI** — ✓ One table, one admin tab, one reason-code classifier function, one migration. No pub/sub, no realtime, no analytics beyond grouped counts. Reuses existing `_StageTimer` mechanism rather than introducing new infrastructure.

**Gate status: all principles satisfied. No entries for Complexity Tracking.**

## Project Structure

### Documentation (this feature)

```text
specs/088-rag-refusal-diagnostic/
├── plan.md                # This file (/speckit.plan command output)
├── spec.md                # Feature specification (already committed)
├── research.md            # Phase 0 output (generated below)
├── data-model.md          # Phase 1 output
├── quickstart.md          # Phase 1 output
├── contracts/
│   └── diagnostic-api.md  # Phase 1 output — admin GET endpoints
└── checklists/
    └── requirements.md    # From /speckit.specify (already committed)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   ├── manuals.py                       # existing — /api/manuals/ask; minimal hook + optional source field on AskRequest
│   └── admin_rag_diagnostics.py         # NEW — GET /api/admin/rag-diagnostics (list+filter) + /summary
├── services/
│   ├── manual_rag_service.py            # existing — _StageTimer already present from spec 066; extend the threaded dict with diagnostic fields
│   ├── agentic_tools.py                 # existing — thread the same dict through the agentic loop
│   └── rag_diagnostic_service.py        # NEW — reason-code classifier + persistence layer
├── tests/
│   └── test_rag_quality.py              # existing — update USER_EMAIL-based calls to pass source="test_suite"
├── utils/
│   └── activity.py                      # existing — fire-and-forget audit write (reused, not modified)
└── supabase/migrations/
    └── 20260419000000_rag_diagnostic_log.sql   # NEW — table + RLS + indexes

frontend/lib/
├── models/
│   └── rag_diagnostic_entry.dart        # NEW — typed model for admin list
├── services/
│   └── rag_diagnostic_service.dart      # NEW — HTTP client for admin endpoints
└── screens/manual_assistant/
    ├── manual_assistant_screen.dart     # existing — register new tab in TabController (admin-only)
    ├── train_ai_tab.dart                # existing — untouched
    └── rag_diagnostics_tab.dart         # NEW — admin-only diagnostic browse/summary
```

**Structure Decision**: Web-application layout (option 2 from the template) — this project already splits `backend/` and `frontend/` directories, matching the constitution's technology constraints. No new top-level directories; all new files fit into the existing layout.

## Complexity Tracking

> No constitutional violations to justify. Table intentionally empty.
