# Implementation Plan: Train the AI Tab — 3-Stage Learning Pipeline

**Branch**: `080-train-ai-tab` | **Date**: 2026-04-17 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/080-train-ai-tab/spec.md`

## Summary

Add an admin-only "Train the AI" tab to the Manual Assistant screen with three sections: (A) Bootstrap from Manuals — auto-generate Q&A candidates from manual chunks, admin reviews and saves to validated_qa cache with EN+AR paraphrase variants; (B) From Real Usage — surface positively-rated technician questions for one-tap cache promotion; (C) Needs Review — flag stale cache entries when source manuals are re-processed. Requires 1 migration (2 table ALTERs), 4 new backend endpoints, 1 endpoint extension, 1 new Flutter tab with 3 card widgets, and 5 new service methods.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, Supabase Python client, httpx (backend); http, supabase_flutter, Flutter Material (frontend)  
**Storage**: Supabase (PostgreSQL) with pgvector — `validated_qa`, `answer_ratings`, `manuals`, `manual_chunks` tables  
**Testing**: Manual integration testing via browser (PWA)  
**Target Platform**: Web (PWA) — Flutter web with canvaskit renderer  
**Project Type**: Web application (Flutter frontend + FastAPI backend)  
**Performance Goals**: Q&A generation endpoint completes 20 candidates synchronously; admin workflow under 10 minutes  
**Constraints**: Max 20 candidates per generation run; all list endpoints limit 50 items; synchronous (no background jobs)  
**Scale/Scope**: 3-5 manuals bootstrapped (60-100 Q&A pairs); ~50 real-usage suggestions max

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Migration + backend endpoints + frontend tab + service + widgets — all layers covered |
| II. Explicit Over Automatic | PASS | All cache additions require explicit admin approval; no auto-save |
| III. Role-Based Access Control | PASS | Tab hidden for non-admin; all endpoints check `_admin_check(user_email)` |
| IV. Server-First File Storage | N/A | No file uploads in this feature |
| V. Client-Side Computation Where Possible | PASS | Candidate review state is client-side; dismiss is in-memory |
| VI. Audit Everything | PASS | Activity logging via `background_tasks.add_task(log_activity, ...)` on generate, save, review actions |
| VII. Simplicity & YAGNI | PASS | Reuses existing services (embedder, provider_generate, validated_qa_service); no new abstractions |

**Post-Phase 1 re-check**: All gates still pass. No new violations introduced by design decisions.

## Project Structure

### Documentation (this feature)

```text
specs/080-train-ai-tab/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── api-endpoints.md
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── manuals.py                    # MODIFY — 4 new endpoints + extend paraphrase + verify re-embed
├── services/
│   ├── validated_qa_service.py       # MODIFY — extend create_verified_answer for source_manual_id
│   ├── ai_providers/
│   │   └── resolver.py               # READ ONLY — reuse generate()
│   └── ollama_embedder.py            # READ ONLY — reuse embed_single/embed_many

frontend/
├── lib/
│   ├── screens/
│   │   └── manual_assistant/
│   │       ├── manual_assistant_screen.dart  # MODIFY — add 7th tab, admin guard
│   │       ├── train_ai_tab.dart             # NEW — main tab with 3-section SegmentedButton
│   │       └── widgets/
│   │           ├── qa_candidate_card.dart     # NEW — Section A card
│   │           ├── usage_suggestion_card.dart # NEW — Section B card
│   │           └── stale_entry_card.dart      # NEW — Section C card
���   └── services/
│       └── manual_assistant_service.dart      # MODIFY — 5 new methods + extend paraphrase

supabase/
└── migrations/
    └── 20260418000000_train_ai_staleness.sql  # NEW — ALTER validated_qa + manuals
```

**Structure Decision**: Follows existing project structure. New tab file (`train_ai_tab.dart`) mirrors pattern of existing tabs (e.g., `verified_answers_tab.dart`, `review_queue_tab.dart`). New card widgets follow existing widget pattern in `widgets/` directory.

## Complexity Tracking

> No constitution violations. Table is empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
