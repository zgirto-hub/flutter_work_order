# Implementation Plan: Thumbs-Down Reason & Comment

**Branch**: `087-thumbs-down-reason` | **Date**: 2026-04-19 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/087-thumbs-down-reason/spec.md`

## Summary

Capture an optional categorical reason (one of five: Inaccurate, Incomplete, Outdated, Wrong source, Unclear) and an optional free-text comment when a technician clicks thumbs-down on an AI-assistant answer. The thumbs-down click itself continues to persist immediately (unchanged); a bottom sheet then slides up asking "What went wrong?" and the rater can either pick a reason + comment and Save, or Skip/dismiss to leave nulls. Admins see the reason as a colored chip (with the text label) and a 100-character comment preview on existing Review-tab cards.

Two nullable columns are added to the existing `answer_ratings` table. A new `PATCH /manuals/ratings/{rating_id}/feedback` endpoint handles the reason save, enforcing that only the original rater can modify their own row. A `rated_answer_feedback` activity-log event is emitted on each successful save. No changes to the approve/correct workflow, the automatic reflag threshold, or any downstream pipeline that reads `answer_ratings`.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Pydantic, Supabase Python client (backend); `supabase_flutter`, `http`, Flutter Material (frontend). **No new dependencies.**
**Storage**: Supabase (PostgreSQL). Existing `answer_ratings` table gains two nullable columns. No new tables, no pgvector changes, no RLS changes.
**Testing**: pytest (backend — existing `backend/tests/routers/test_manuals_*`), Flutter widget/unit tests where feasible; manual QA on the `/manuals/ask` chat and `/manuals` Train AI Review tab.
**Target Platform**: Flutter web (primary — PWA); FastAPI on Linux server (Zorin OS via `document_server.service`).
**Project Type**: Web application (existing backend + Flutter frontend).
**Performance Goals**: Thumbs-down click persists rating within 2 s (SC-001). Feedback PATCH completes within 500 ms under normal conditions. No impact on existing Review-tab list query.
**Constraints**: Server-side comment hard cap = 2000 characters (FR-014). Client-side soft advisory = ~500 characters with live counter. Feedback save MUST NOT block on network errors — user sees a toast, rating remains saved with NULL reason.
**Scale/Scope**: 1:1 with existing rating volume (~ dozens to low hundreds of ratings per week today). No scaling concern introduced by this feature.

## Constitution Check

*GATE: All applicable principles satisfied. No violations.*

| # | Principle | Status | Notes |
|---|---|---|---|
| I | Full-Stack Ownership | ✅ PASS | Migration + backend router + frontend service method + widget + existing-card update. All layers covered. |
| II | Explicit Over Automatic | ✅ PASS | Save is explicit (button press). No silent fallbacks. Ownership check enforced explicitly. No auto-retry on PATCH failure. |
| III | Role-Based Access Control | ✅ PASS | Authorization = rater owns the row (same model as existing `DELETE /manuals/ratings/{rating_id}`). No new roles. Admins do not edit user-provided reason/comment (out of scope). |
| IV | Server-First File Storage | N/A | No files involved. |
| V | Client-Side Computation | N/A | Trivial state (one row update per rating). No dataset filtering logic added. |
| VI | Audit Everything | ✅ PASS | FR-015 mandates a `rated_answer_feedback` activity-log event on every successful save, routed via the existing `log_activity` utility (fire-and-forget, non-blocking). |
| VII | Simplicity & YAGNI | ✅ PASS | Two nullable columns on an existing table. One PATCH endpoint. One bottom-sheet widget. One card update. No abstraction layers, no feature flags, no configurability. |

**Technology Constraints**: All respected. Migration placed in `supabase/migrations/` as timestamped file. `backend/version.json` NOT touched. No new deployment steps beyond the standard `systemctl restart document_server.service` after backend code changes (per project memory). No new OneSignal or PDF paths.

**Development Workflow**: Follows `AGENT.md` new-feature checklist — backend router (modify `routers/manuals.py`), migration, Flutter service method (`manual_assistant_service.dart`), Flutter UI (new widget + card update), no new screen or navigation wiring needed because the feature lives in existing chat and Review-tab surfaces, docs update queued for `architecture-doc-updater` after merge.

## Project Structure

### Documentation (this feature)

```text
specs/087-thumbs-down-reason/
├── plan.md              # This file
├── research.md          # Phase 0 output — design decisions + alternatives considered
├── data-model.md        # Phase 1 output — schema diff for answer_ratings
├── quickstart.md        # Phase 1 output — local dev/test walkthrough
├── contracts/
│   └── patch-rating-feedback.md   # PATCH /manuals/ratings/{rating_id}/feedback contract
├── checklists/
│   └── requirements.md  # Created by /speckit.specify
└── tasks.md             # Created by /speckit.tasks (next step)
```

### Source code (repository root — files to create/modify)

```text
supabase/migrations/
└── 20260419000000_add_rating_feedback.sql        # NEW — ALTER TABLE answer_ratings

backend/
├── routers/
│   └── manuals.py                                # MODIFY — add RatingFeedbackRequest Pydantic model and PATCH /manuals/ratings/{id}/feedback endpoint. RateAnswerRequest and the POST path are intentionally unchanged (per research Decision 2).
├── services/
│   └── validated_qa_service.py                   # MODIFY — add new update_rating_feedback(rating_id, reason, comment, user_email) method; update get_flagged_answers() to SELECT feedback_reason and feedback_comment. save_rating() intentionally unchanged (per research Decision 2).
└── tests/
    └── routers/
        └── test_manuals_rating_feedback.py       # NEW — contract tests for PATCH endpoint (ownership, validation, idempotency, log emission)

frontend/lib/
├── services/
│   └── manual_assistant_service.dart             # MODIFY — add saveFeedback(ratingId, reason, comment) calling PATCH endpoint
└── screens/manual_assistant/
    ├── chat_tab.dart                             # MODIFY — after _handleRate('negative'), open the new bottom sheet
    └── widgets/
        ├── feedback_reason_sheet.dart            # NEW — "What went wrong?" bottom sheet (5 chips + comment field)
        └── review_entry_card.dart                # MODIFY — render reason chip + comment preview
```

**Structure Decision**: Existing web-application layout (Option 2 — `backend/` + `frontend/`). All additions are localized; no new top-level directories. The bottom-sheet widget goes under `frontend/lib/screens/manual_assistant/widgets/` to match the colocation pattern used by `review_entry_card.dart`, `variants_modal.dart`, etc.

## Complexity Tracking

> No constitution violations. Table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| — | — | — |
