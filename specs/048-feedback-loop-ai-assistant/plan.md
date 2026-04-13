# Implementation Plan: Feedback Loop AI Assistant

**Branch**: `048-feedback-loop-ai-assistant` | **Date**: 2026-04-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/048-feedback-loop-ai-assistant/spec.md`

## Summary

Add a feedback loop to the manual assistant AI pipeline. Technicians rate AI answers (thumbs up/down) in the Flutter chat interface. Thumbs-down answers are flagged for admin review. Admins can approve or correct flagged answers in a new Review Queue tab. Validated QA pairs are stored with pgvector embeddings and used to short-circuit the RAG pipeline when a semantically similar question arrives (>=0.90 similarity → direct return, 0.75–0.90 → high-priority context). Ratings are stored in a dedicated `answer_ratings` table; validated pairs in `validated_qa`. The system gets smarter over time as expert-validated answers accumulate.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, httpx, Supabase Python client, ollama_embedder (backend); http, Flutter Material (frontend)
**Storage**: Supabase (PostgreSQL) with pgvector — new `answer_ratings` and `validated_qa` tables; existing `work_orders`, `users`, `manual_chunks` tables
**Testing**: Manual integration testing via the AI chat interface
**Target Platform**: Web (PWA) + Linux server backend
**Project Type**: Web service (FastAPI) + Flutter PWA frontend
**Performance Goals**: Rating action <1s; validated answer direct return <1s; similarity check adds negligible latency to normal pipeline
**Constraints**: Single GPU server (15GB RAM), nomic-embed-text via Ollama for embeddings (768-dim), existing `embed_single()` infrastructure
**Scale/Scope**: Single-user sequential requests; validated_qa table expected to grow to ~50-200 entries over months

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend: new rating + review + validated_qa endpoints in manuals router. Frontend: rating buttons on AnswerCard, Review Queue tab, "Verified Answer" label. Database: 2 new tables via migration. |
| II. Explicit Over Automatic | PASS | Ratings are explicit user actions. Validation is explicit admin action. Re-flagging threshold is explicitly defined (30% thumbs-down, min 3 ratings). |
| III. Role-Based Access Control | PASS | Review Queue tab visible only to `admin` role (existing `userRole == 'admin'` pattern). Rating endpoints require `user_email`. |
| IV. Server-First File Storage | N/A | No file uploads or storage changes. |
| V. Client-Side Computation | N/A | Similarity search is server-side (pgvector). Rating state is ephemeral per-session on client. |
| VI. Audit Everything | PASS | Rating and review actions logged via existing `log_activity()` pattern (fire-and-forget). |
| VII. Simplicity & YAGNI | PASS | Two new tables, one new tab, rating buttons on existing widget. No new frameworks. Embeddings reuse existing `embed_single()`. Thresholds are configurable but start with sensible defaults. |

## Project Structure

### Documentation (this feature)

```text
specs/048-feedback-loop-ai-assistant/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (from /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── manuals.py                  # New endpoints: rate_answer, get_flagged, review_answer, check_validated
├── services/
│   ├── manual_rag_service.py       # Add validated_qa check before RAG pipeline in ask()
│   ├── validated_qa_service.py     # NEW — CRUD for answer_ratings, validated_qa, similarity search
│   └── ollama_embedder.py          # Existing — reuse embed_single() for question embeddings
├── utils/
│   └── activity.py                 # Existing — extend with rating/review action categories
└── (no other new files)

frontend/
└── lib/
    ├── screens/manual_assistant/
    │   ├── manual_assistant_screen.dart  # Add Review Queue tab (admin-only, 3rd tab)
    │   ├── chat_tab.dart                 # Pass rating callback to AnswerCard
    │   ├── review_queue_tab.dart         # NEW — flagged answers list with approve/correct actions
    │   └── widgets/
    │       ├── answer_card.dart          # Add thumbs-up/down buttons, "Verified Answer" label
    │       └── review_entry_card.dart    # NEW — single flagged entry with question, answer, sources, actions
    └── services/
        └── manual_assistant_service.dart # New methods: rateAnswer, getFlagged, reviewAnswer

supabase/
└── migrations/
    └── 20260413000000_create_feedback_loop.sql  # NEW — answer_ratings, validated_qa tables + RPC
```

**Structure Decision**: Backend-only new service file (`validated_qa_service.py`) handles all feedback loop logic. Endpoints are added to the existing manuals router to keep the API surface cohesive. Frontend adds one new tab and two new widgets. Migration creates both tables and the similarity search RPC in a single file.

## Complexity Tracking

No constitution violations. No complexity justifications needed.
