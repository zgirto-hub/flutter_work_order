# Implementation Plan: Add Verified Answer — Manual Entry

**Branch**: `059-add-verified-answer` | **Date**: 2026-04-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/059-add-verified-answer/spec.md`

## Summary

Allow admins to create verified Q&A pairs directly from the Verified Answers tab, bypassing the review queue. Requires one schema migration (make `rating_id` nullable), one new service function + router endpoint, one new Flutter service method, and one FAB + dialog in the Flutter UI. All patterns are cloned from existing edit/update flows.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend)
**Storage**: Supabase (PostgreSQL) — existing `validated_qa` table; one migration to make `rating_id` nullable
**Testing**: Manual integration testing
**Target Platform**: Linux server (backend) + Web/PWA (frontend)
**Project Type**: Full-stack web application
**Performance Goals**: Q&A creation completes in under 30 seconds (embedding is the bottleneck)
**Constraints**: Embedding via `ollama_embedder.embed_single()` on local Ollama; admin-only access
**Scale/Scope**: Single-tenant, ~50 users; feature touches 4 files + 1 migration

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Spans migration, backend service, backend router, Flutter service, Flutter UI. All layers covered. |
| II. Explicit Over Automatic | PASS | Admin explicitly fills in both fields and submits. No auto-population or implicit behavior. |
| III. Role-Based Access Control | PASS | Admin-only enforced via existing `_admin_check()` helper in router. |
| IV. Server-First File Storage | N/A | No file uploads — text only. |
| V. Client-Side Computation | N/A | Embedding requires server-side computation. |
| VI. Audit Everything | PASS | Router will call `log_activity()` on successful creation (matches existing update/delete pattern). |
| VII. Simplicity & YAGNI | PASS | Clones existing patterns exactly — no new abstractions, no extra configurability. |

**Post-design re-check**: All gates still pass. The nullable `rating_id` migration is the simplest approach (see research.md R1).

## Project Structure

### Documentation (this feature)

```text
specs/059-add-verified-answer/
├── plan.md                              # This file
├── research.md                          # Phase 0 output
├── data-model.md                        # Phase 1 output
├── contracts/
│   └── create-verified-answer.md        # API contract
├── checklists/
│   └── requirements.md                  # Spec quality checklist
├── spec.md                              # Feature specification
└── tasks.md                             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (files to modify/create)

```text
supabase/migrations/
└── 20260415000000_make_rating_id_nullable.sql   # NEW — ALTER TABLE

backend/
├── routers/
│   └── manuals.py                               # MODIFY — add POST endpoint + request model
└── services/
    └── validated_qa_service.py                   # MODIFY — add create_verified_answer()

frontend/lib/
├── services/
│   └── manual_assistant_service.dart             # MODIFY — add createVerifiedAnswer()
└── screens/manual_assistant/
    └── verified_answers_tab.dart                 # MODIFY — add FAB + dialog + save method
```

**Structure Decision**: All changes are additions to existing files. One new migration file. No new directories.

## Complexity Tracking

> No violations detected. Table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
