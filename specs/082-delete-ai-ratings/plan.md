# Implementation Plan: Delete Review/Rating from Ask-the-AI

**Branch**: `082-delete-ai-ratings` | **Date**: 2026-04-18 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/082-delete-ai-ratings/spec.md`

## Summary

Add three deletion surfaces to the AI assistant, all backed by removing rows from the existing `answer_ratings` table:

1. **Chat**: technician can undo their own rating by tapping the same thumb again (plus a one-time "tap again to remove" hint on first rating).
2. **Review tab**: admin can delete a single flagged rating (red "Delete" button alongside Approve/Correct).
3. **Train AI → From Real Usage**: admin can permanently remove an entire Q&A group (overflow menu "Delete permanently").

Critical data rule: before a rating row is deleted, any linked `validated_qa.rating_id` pointers are set to `NULL`. The verified-answer cache entry survives — this is the inverse of the spec 080 cascade. No schema migration is required (`rating_id` is already nullable since spec 059 and its FK was dropped in migration `20260418110000`).

Two new backend endpoints, two new service helpers, three widget changes, one service-method addition, one `user_activity_log` action per flow. Failure path: error snackbar + optimistic-state rollback. Idempotent: `404 already-gone` is treated as success on the client.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client (backend); `http`, `supabase_flutter`, Flutter Material, `shared_preferences` (existing) (frontend)
**Storage**: Supabase (PostgreSQL) — existing `answer_ratings`, `validated_qa` tables. No schema changes.
**Testing**: pytest (backend), Flutter widget/integration tests (frontend), manual smoke via the quickstart in this feature dir.
**Target Platform**: Flutter web / PWA (primary), Linux server for FastAPI behind Nginx.
**Project Type**: Web application — separate `backend/` and `frontend/` trees under the repo root (matches existing layout).
**Performance Goals**: Single-row delete p95 < 150 ms; bulk delete p95 < 500 ms for typical group sizes (≤50 rows); no user-visible degradation on admin tabs.
**Constraints**: Must preserve `validated_qa` rows when their originating rating is deleted. Must be idempotent. Activity log writes must stay fire-and-forget (constitution VI). No new DB migration.
**Scale/Scope**: `answer_ratings` row count is low thousands; per-Q&A groups typically single digits. Admin ops are low-frequency. Chat undo is per-user, per-message.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Notes |
|---|---|---|
| I. Full-Stack Ownership | PASS | Backend router + service helpers, frontend service + three widgets + three hosting screens. Migration layer explicitly N/A (no schema changes; rationale below). Docs: AGENT.md + ARCHITECTURE.md updated. |
| II. Explicit Over Automatic | PASS | All destructive flows require an explicit confirmation dialog or same-thumb re-tap. No auto-cascade of verified entries. No silent state drift on failure (rollback is explicit). |
| III. Role-Based Access Control | PASS | Backend endpoints enforce: technician → only own `rater_email`; admin → via existing `_admin_check()`. Bulk-delete is admin-only. Non-admin delete attempt returns `403 admin_required`. |
| IV. Server-First File Storage | N/A | No file handling. |
| V. Client-Side Computation Where Possible | PASS | Review list and Real-Usage list refresh by removing the affected item locally; next full reload re-fetches canonical state. Matches existing tab patterns. |
| VI. Audit Everything | PASS | Every delete writes a `user_activity_log` row via existing `log_activity(...)`: `unrated_answer` (self), `admin_deleted_rating` (admin on others), `admin_bulk_deleted_ratings` (admin bulk). Fire-and-forget, does not block delete. |
| VII. Simplicity & YAGNI | PASS | No soft-delete, no trash, no per-user quota, no size cap (clarified with user), no new admin screen. Exactly the three surfaces the user asked for. |

**Migration gap (full-stack ownership)**: The constitution requires either a migration or an explicit justification for omitting one. Justification:
- `answer_ratings.id` already exists; no new columns required.
- `validated_qa.rating_id` is already nullable (`20260415000000_make_rating_id_nullable.sql`, feature 059) AND the FK has already been dropped (`20260418110000_drop_rating_id_fk.sql`, feature 080 follow-up). So `DELETE FROM answer_ratings WHERE id = ...` neither fails nor cascades.
- Our code still performs the `UPDATE validated_qa SET rating_id = NULL WHERE rating_id = $1` step *before* the delete. This keeps the data clean (no dangling UUIDs on `validated_qa` rows) and future-proofs against any later re-introduction of the FK.

No complexity-tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/082-delete-ai-ratings/
├── plan.md                 # this file
├── spec.md                 # feature spec (with clarifications)
├── research.md             # Phase 0 output
├── data-model.md           # Phase 1 output
├── quickstart.md           # Phase 1 output — manual verification flow
├── contracts/
│   ├── delete-rating.md    # DELETE /manuals/ratings/{rating_id}
│   └── bulk-delete.md      # POST /manuals/ratings/bulk-delete
└── checklists/
    └── requirements.md     # created by /speckit.specify
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── manuals.py                          # + 2 endpoints: DELETE /manuals/ratings/{rating_id}, POST /manuals/ratings/bulk-delete
├── services/
│   └── validated_qa_service.py             # + delete_rating(rating_id), bulk_delete_ratings_by_qa(question_text, answer_text)
└── utils/
    └── activity.py                         # unchanged — reuse log_activity()

frontend/lib/
├── services/
│   └── manual_assistant_service.dart       # + deleteRating(), bulkDeleteRatings()
└── screens/manual_assistant/
    ├── chat_tab.dart                       # wire onUnrate + hint snackbar; store returned rating_id on ChatMessage
    ├── review_queue_tab.dart               # wire onDelete → service.deleteRating; local removal on success; badge decrement
    ├── train_ai_tab.dart                   # wire onDeletePermanently → service.bulkDeleteRatings; local removal
    └── widgets/
        ├── answer_card.dart                # track _ratingId, onUnrate callback, same-thumb-undo, one-time hint
        ├── review_entry_card.dart          # + red "Delete" button + onDelete callback + confirmation dialog
        └── usage_suggestion_card.dart      # + PopupMenuButton "Delete permanently" + onDeletePermanently callback + confirmation dialog

supabase/migrations/                        # NO CHANGES — see Constitution Check justification
```

**Structure Decision**: Existing `backend/` + `frontend/lib/` web-application layout. No new top-level directories. All changes are edits to pre-existing files; no new source files required (every new capability fits inside an existing module, which matches the YAGNI principle).

## Complexity Tracking

No constitution violations. Table intentionally empty.
