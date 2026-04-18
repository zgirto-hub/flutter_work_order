---
description: "Task list for feature 082 — implementation guide for opencode; Claude Code performs a superpowers code review after implementation."
---

# Tasks: Delete Review/Rating from Ask-the-AI (spec 082)

**Input**: Design documents from `specs/082-delete-ai-ratings/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/delete-rating.md](contracts/delete-rating.md), [contracts/bulk-delete.md](contracts/bulk-delete.md), [quickstart.md](quickstart.md)

**Implementer**: opencode. Read *all* prerequisites before starting T001. Do not invent new files outside the paths listed below. Do not add a DB migration — `validated_qa.rating_id` is already nullable (migration `20260415000000_make_rating_id_nullable.sql`) and the FK has been dropped (migration `20260418110000_drop_rating_id_fk.sql`); any DB schema change constitutes a review failure. Follow existing patterns in `backend/routers/manuals.py` (`_admin_check`, `log_activity`, Pydantic request models) and the existing dialog/RTL patterns in `frontend/lib/screens/manual_assistant/widgets/review_entry_card.dart` and `usage_suggestion_card.dart`.

**Reviewer**: after opencode signals "implementation complete", Claude Code runs the `superpowers:code-reviewer` workflow against the changes on branch `082-delete-ai-ratings`, using this tasks.md + the spec/plan as the acceptance baseline.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Maps to a user story in spec.md — [US1], [US2], [US3]
- Setup, Foundational, and Polish tasks have NO story label

## Path Conventions

Web application — `backend/` and `frontend/` at repo root (`C:\Development\flutter_work_order\`). All paths below are repo-relative.

---

## Phase 1: Setup

**Purpose**: Confirm workspace state before touching code.

- [ ] T001 Confirm the current git branch is `082-delete-ai-ratings` (`git branch --show-current`). If it's not, stop and abort — do NOT create or switch branches. Read spec.md, plan.md, research.md, data-model.md, contracts/delete-rating.md, contracts/bulk-delete.md in full before proceeding.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The DELETE endpoint + its service helper + its frontend service method are used by BOTH US1 (chat undo) and US2 (admin Review delete). They must exist before either story can be completed.

**⚠️ CRITICAL**: US1 and US2 cannot finish until Phase 2 is complete. US3 has its own backend/service work in Phase 5.

- [ ] T002 Add `delete_rating(rating_id: str) -> dict` helper to `backend/services/validated_qa_service.py`. Contract (see [contracts/delete-rating.md](contracts/delete-rating.md)):
  - Step 1: `UPDATE validated_qa SET rating_id = NULL WHERE rating_id = :rating_id`. Run unconditionally (cheap; idempotent). Use `supabase.table("validated_qa").update({"rating_id": None}).eq("rating_id", rating_id).execute()`.
  - Step 2: Fetch the row to be deleted first so the caller has `question_text`, `rating`, `rater_email` for the activity-log entry: `supabase.table("answer_ratings").select("question_text, rating, rater_email").eq("id", rating_id).maybe_single().execute()`. If missing, return `{"existed": False, "question_text": None, "rating": None, "rater_email": None}`.
  - Step 3: `supabase.table("answer_ratings").delete().eq("id", rating_id).execute()`.
  - Return `{"existed": True, "question_text": ..., "rating": ..., "rater_email": ...}`.
  - Let exceptions propagate; the router wraps them. Do NOT add try/except here.

- [ ] T003 Add `DELETE /manuals/ratings/{rating_id}` endpoint to `backend/routers/manuals.py`. Place it near `@router.post("/manuals/rate-answer")` (around line 764) to keep related ratings endpoints grouped. Requirements from [contracts/delete-rating.md](contracts/delete-rating.md):
  - Signature: `async def delete_rating(rating_id: str, user_email: str = Query(...))`.
  - Fetch the row's `rater_email` first (single `select`). If missing, short-circuit: skip the NULL+DELETE, skip activity logging, return `{"status": "deleted", "existed": False}`.
  - Authorize: if `row.rater_email != user_email`, call `_admin_check(user_email)` — let its 403 propagate.
  - Call `validated_qa_service.delete_rating(rating_id)`.
  - Activity log via `log_activity(...)` (fire-and-forget, wrap in `try/except Exception: pass`):
    - If `user_email == row.rater_email`: `action="unrated_answer"`, `target_label=row.question_text[:80]`, `detail=row.rating`.
    - Else: `action="admin_deleted_rating"`, `target_label=row.question_text[:80]`, `detail=row.rater_email`.
    - `category="manual"` in both cases.
  - Return `{"status": "deleted", "existed": True}`.
  - Wrap Supabase errors (not HTTPException) in a 500: `{"detail": {"error": "delete_failed", "message": str(e)}}`.

- [ ] T004 Add `frontend/lib/services/manual_assistant_service.dart::deleteRating`. Signature: `Future<bool> deleteRating({required String ratingId, required String userEmail}) async`. Return value: `true` if the server reported `existed: true`, `false` if `existed: false` (both are successful outcomes). Error handling:
  - 200 → parse body, return `body['existed'] == true`.
  - 403 → `throw Exception('Admin access required')` (matches existing pattern; chat tab will never see this for own ratings).
  - Anything else → `throw Exception('Failed to remove rating')`.
  - Use `Uri.encodeComponent` on `userEmail`, same as other methods in this file. Add Supabase Bearer auth header following the existing pattern (`getFlaggedAnswers` is a reference).

- [ ] T005 [P] Add backend contract tests for T003 in `backend/tests/routers/test_manuals_delete_rating.py` (new file). Cover exactly T1–T7 from [contracts/delete-rating.md](contracts/delete-rating.md) § "Contract tests". Use the existing test harness / fixtures from other files under `backend/tests/routers/` (inspect one or two before writing). Verify `answer_ratings` is gone, `validated_qa` row is preserved with `rating_id IS NULL`, and `user_activity_log` has the expected action. Tests must be deterministic (no sleeps, no external Ollama calls).

**Checkpoint**: After T005, the DELETE endpoint is fully functional and verified. US1 and US2 can now proceed in parallel.

---

## Phase 3: User Story 1 — Technician undo (Priority: P1) 🎯 MVP

**Goal**: A technician can remove their own rating from the chat by tapping the currently-selected thumb a second time, with a one-time discoverability hint on first rating and an error-rollback path on failure.

**Independent Test**: Quickstart § "Flow 1 — Technician undo (chat)". After US1 alone is shipped, Flow 1 passes end-to-end while Flow 2 and Flow 3 may still be partially broken.

- [ ] T006 [US1] Update `frontend/lib/screens/manual_assistant/widgets/answer_card.dart`:
  - Add field `final String? ratingId;` and constructor parameter. Passed in by parent when a rating has been recorded (drives the "can undo" state).
  - Add callback `final VoidCallback? onUnrate;`. Called when the user taps the currently-selected thumb.
  - State: keep `_selectedRating` local; initialize from widget's `ratingId != null` path so a rating shows selected when the card rebuilds (e.g., after a re-render).
  - In `_handleRate(String rating)`: if `_selectedRating == rating`, call `widget.onUnrate?.call()` and set `_selectedRating = null`; DO NOT early-return as it does today. If `_selectedRating != rating`, call `widget.onRate?.call(rating)` as before.
  - Keep the Material Tooltip; no new per-widget hint logic here (the first-time snackbar hint lives in `chat_tab.dart`).
  - Do NOT fire any network calls from this widget — it stays a pure view. All service calls happen in `chat_tab.dart`.

- [ ] T007 [US1] Update `frontend/lib/screens/manual_assistant/chat_tab.dart`:
  - Extend the per-message state so each `ChatMessage` / message entry tracks `String? ratingId`. The existing `_handleRate` already calls `_service.rateAnswer(...)` and discards the returned id — capture it into state via `setState` on success, then pass it to the `AnswerCard` as `ratingId`.
  - Add `_handleUnrate(int messageIndex)` that:
    1. Captures the current `ratingId` from state. If null, no-op (defensive).
    2. Optimistically clears the local `ratingId` and `_selectedRating` via `setState`.
    3. Calls `await _service.deleteRating(ratingId: ratingId, userEmail: ...)`. The return value (true/false) doesn't change local behavior.
    4. On success: show snackbar "Rating removed." (2-second duration).
    5. On any thrown error: restore the previous `ratingId` via `setState` (rollback), and show snackbar "Could not remove rating — please try again.".
  - Add a one-time discoverability hint the FIRST time `_handleRate` successfully records a rating, keyed per user email in `SharedPreferences`. Reuse `shared_preferences` — it is already in use by `ThemeController` (see `frontend/lib/controllers/theme_controller.dart` for the pattern). Key: `rating_undo_hint_shown_<user_email>` (bool). After `_service.rateAnswer(...)` returns successfully and the key is not set, show snackbar "Tap the thumb again to remove your rating." (4-second duration) and set the key. Do NOT show the hint on the undo path.
  - Wire `onUnrate` on `AnswerCard` to `_handleUnrate(messageIndex)`. Keep `onRate` callback logic intact.
  - The email comes from `Supabase.instance.client.auth.currentUser?.email ?? ''` — match the existing pattern.

**Checkpoint**: US1 works end-to-end. Technician rating, undoing, failure rollback, and one-time hint all verified.

---

## Phase 4: User Story 2 — Admin single-rating delete (Priority: P2)

**Goal**: An admin can delete a single flagged rating from the Review tab via a red "Delete" button, with a confirmation dialog. On success the card is removed locally; on failure the card is restored and an error snackbar is shown. The verified-answer cache is unaffected.

**Independent Test**: Quickstart § "Flow 2 — Admin single-rating delete (Review tab)".

- [ ] T008 [US2] Update `frontend/lib/screens/manual_assistant/widgets/review_entry_card.dart`:
  - Add callback `final Function(String ratingId) onDelete;` alongside existing `onApprove` / `onCorrect`.
  - In the action row (alongside "Approve" and "Correct" — around lines 155–175), add a third `TextButton.icon` with red color: icon `Icons.delete_outline`, label "Delete", `onPressed` calls a helper that:
    1. Opens an `AlertDialog` via `showDialog<bool>(...)`. Title: "Delete rating?". Content: "This thumbs-down will be removed and the answer will leave the review queue. The verified-answer cache (if any) is unaffected.". Actions: "Cancel" (pops false) and "Delete" (pops true, destructive red style).
    2. Wrap the `AlertDialog` with `Directionality(textDirection: Directionality.of(context), child: ...)` — matches existing RTL pattern in this file. If the card content's language is Arabic, the dialog inherits RTL; otherwise LTR. Do not hard-code text direction.
    3. If confirmed, invoke `widget.onDelete(entryId)`. The parent screen handles the actual delete + rollback.
  - Preserve all existing UI; do not restructure the card.

- [ ] T009 [US2] Update `frontend/lib/screens/manual_assistant/review_queue_tab.dart`:
  - Add `_handleDelete(String ratingId, int index)` that:
    1. Snapshots the card (`final removed = _entries[index];`).
    2. Optimistically removes the entry via `setState` (and decrements the "Needs Review" badge — if it is derived from `_entries.length`, nothing more is needed; if there is a separate counter state, decrement it too).
    3. Calls `await _service.deleteRating(ratingId: ratingId, userEmail: adminEmail)`.
    4. On success: show snackbar "Rating deleted." (2-second duration). No re-fetch is needed.
    5. On any thrown error: restore via `setState(() { _entries.insert(index, removed); ... })` and show snackbar "Could not delete rating — please try again.". Re-increment badge if applicable.
  - Wire `onDelete: (id) => _handleDelete(id, index)` on each `ReviewEntryCard`. The `entryId` used in the card is the same `rating_id` the backend expects.
  - `adminEmail` comes from the same auth source the tab already uses for `getFlaggedAnswers`.

**Checkpoint**: US2 works end-to-end. Flagged-answer Delete path passes its quickstart flow.

---

## Phase 5: User Story 3 — Admin permanent delete of From-Real-Usage suggestion (Priority: P3)

**Goal**: An admin can permanently delete a Q&A group from Train AI → From Real Usage via an overflow menu action. The existing "Dismiss" button keeps its current UI-only local-hide behavior. Permanent delete removes all matching `answer_ratings` rows, preserves linked `validated_qa` rows, and the suggestion does not reappear on reload.

**Independent Test**: Quickstart § "Flow 3 — Admin permanent delete (Train AI → From Real Usage)".

- [ ] T010 [US3] Add `bulk_delete_ratings_by_qa(question_text: str, answer_text: str) -> int` helper to `backend/services/validated_qa_service.py`. Contract (see [contracts/bulk-delete.md](contracts/bulk-delete.md)):
  - `SELECT id FROM answer_ratings WHERE question_text = :q AND answer_text = :a` → list of IDs.
  - If list is empty: return 0. Do not touch `validated_qa`.
  - Else: `UPDATE validated_qa SET rating_id = NULL WHERE rating_id IN (:ids)`, then `DELETE FROM answer_ratings WHERE id IN (:ids)`.
  - Return `len(ids)`. Let exceptions propagate.
  - Use Supabase `in_("id", ids)` filter. Be careful with empty lists — Supabase-py raises on empty `in_`, so gate on `if ids:`.

- [ ] T011 [US3] Add Pydantic model `BulkDeleteRatingsRequest(BaseModel)` (fields: `question_text: str`, `answer_text: str`) and endpoint `POST /manuals/ratings/bulk-delete` to `backend/routers/manuals.py`. Place near `@router.get("/manuals/real-usage-suggestions")`. Signature: `async def bulk_delete_ratings(request: BulkDeleteRatingsRequest, user_email: str = Query(...))`. Flow:
  - Call `_admin_check(user_email)` first — let 403 propagate.
  - Call `deleted = validated_qa_service.bulk_delete_ratings_by_qa(request.question_text, request.answer_text)`.
  - Activity log (fire-and-forget, wrap in `try/except Exception: pass`): `log_activity(user_email, "manual", "admin_bulk_deleted_ratings", target_label=request.question_text[:80], detail=f"count={deleted}")`. Write it even when `deleted == 0`.
  - Return `{"deleted_count": deleted}`.
  - Wrap unexpected errors: 500 with `{"detail": {"error": "bulk_delete_failed", "message": str(e)}}`.

- [ ] T012 [US3] Add backend contract tests for T011 in `backend/tests/routers/test_manuals_bulk_delete.py` (new file). Cover exactly B1–B6 from [contracts/bulk-delete.md](contracts/bulk-delete.md) § "Contract tests". Same harness as T005.

- [ ] T013 [P] [US3] Add `frontend/lib/services/manual_assistant_service.dart::bulkDeleteRatings`. Signature: `Future<int> bulkDeleteRatings({required String questionText, required String answerText, required String userEmail}) async`. POST body `{"question_text": ..., "answer_text": ...}` with JSON Content-Type. On 200, return `body['deleted_count'] as int`. On 403, throw `Exception('Admin access required')`. On anything else, throw `Exception('Failed to bulk delete ratings')`. Match the existing `reviewAnswer` / `generateParaphraseVariants` pattern for headers.

- [ ] T014 [P] [US3] Update `frontend/lib/screens/manual_assistant/widgets/usage_suggestion_card.dart`:
  - Add callback `final VoidCallback onDeletePermanently;` alongside `onDismiss`, `onAddToCache`.
  - Add a `PopupMenuButton<String>` (three-dot icon) in the card's header or action row. Single item: `PopupMenuItem(value: 'delete_permanent', child: Row([Icon(Icons.delete_forever, color: Colors.red), Text('Delete permanently')]))`.
  - When selected, show an `AlertDialog` (wrapped in a `Directionality` matching current context; same RTL-aware pattern used by T008). Title: "Delete permanently?". Content: `"Permanently delete ${widget.ratingCount} positive ratings for this question? It will stop appearing here. Cannot be undone."` (pull `ratingCount` from the card's existing field — check the widget's current constructor to confirm the field name). Actions: "Cancel" (pops false) and "Delete permanently" (red; pops true).
  - If confirmed, invoke `widget.onDeletePermanently()`.
  - DO NOT change "Dismiss" behavior — it remains a UI-only local hide. DO NOT remove the Dismiss button.

- [ ] T015 [US3] Update `frontend/lib/screens/manual_assistant/train_ai_tab.dart`:
  - Add `_handleDeletePermanently(Map<String, dynamic> suggestion, int index)` that:
    1. Snapshots the card.
    2. Optimistically removes via `setState`.
    3. Calls `await _service.bulkDeleteRatings(questionText: suggestion['question'], answerText: suggestion['answer'], userEmail: adminEmail)`.
    4. On success: show snackbar `"Deleted ${deletedCount} ratings."`.
    5. On any thrown error: restore via `setState(() { _suggestions.insert(index, snapshot); })` and show snackbar "Could not delete suggestion — please try again.".
  - Wire `onDeletePermanently: () => _handleDeletePermanently(suggestion, index)` on each `UsageSuggestionCard`.
  - Leave `onDismiss` wiring untouched.

**Checkpoint**: All three stories complete. Quickstart Flows 1, 2, and 3 all pass.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T016 [P] Update `AGENT.md` and `ARCHITECTURE.md` to list the two new endpoints (`DELETE /manuals/ratings/{rating_id}`, `POST /manuals/ratings/bulk-delete`), the three new activity-log action values (`unrated_answer`, `admin_deleted_rating`, `admin_bulk_deleted_ratings` under category `manual`), and the rating-delete surfaces on the three screens. Do NOT restructure either doc — append concise entries in the nearest existing section.

- [ ] T017 Run `flutter analyze` from `frontend/` and `pytest backend/tests/routers/test_manuals_delete_rating.py backend/tests/routers/test_manuals_bulk_delete.py` from the repo root. Both must pass cleanly before signaling "implementation complete". If analyze surfaces warnings unrelated to this feature, leave them; fix only warnings introduced by this change.

- [ ] T018 Execute the entire [quickstart.md](quickstart.md) manually (all three flows plus the DB verification and failure-path checks). Report pass/fail per flow. Do NOT mark the feature complete if any flow fails.

- [ ] T019 Do NOT commit `backend/version.json`. Do NOT run the bump-version script in this phase — the user handles version bumping and deploy manually per project convention.

---

## Dependencies & Execution Order

### Phase dependencies

- Phase 1 (T001) → no dependencies.
- Phase 2 (T002–T005) → depends on T001.
- Phase 3 (US1, T006–T007) → depends on T002–T004 (frontend needs `deleteRating`; T005 can run in parallel).
- Phase 4 (US2, T008–T009) → depends on T002–T004.
- Phase 5 (US3, T010–T015) → independent of US1/US2 (own backend + frontend chain).
- Phase 6 (T016–T019) → depends on all earlier phases.

### Within-task dependencies

- T002 → T003 → T004 (backend chain)
- T004 is parallelizable with T005 (different files, independent)
- T006 → T007 (widget then screen)
- T008 → T009
- T010 → T011 → T012 (backend chain)
- T013 and the T011 chain are independent — can run in parallel.
- T014 → T015 (widget then screen).
- T015 also depends on T013 (screen uses the new service method).

### Parallel opportunities

- Within Phase 2, T004 and T005 can be parallel.
- US1, US2, and US3 phases are mutually independent once their required backend work is done. A single opencode session can proceed sequentially; two sessions could split US1/US2 vs US3 on different worktrees if desired.
- Within US3, T013 is parallel to (T010→T011→T012); T014 is parallel to (T010→T011→T012) and T013.

---

## Implementation Strategy

### MVP-first

1. T001 → T002–T005 (foundational) → T006–T007 (US1) → run Quickstart Flow 1. Ship.
2. Add T008–T009 (US2) → run Quickstart Flow 2. Ship.
3. Add T010–T015 (US3) → run Quickstart Flow 3. Ship.
4. T016–T019 (polish) — run once at the end before review.

### Single opencode session (recommended for this feature)

Proceed strictly in task ID order (T001 through T019). After each task, run the relevant validation (analyze / pytest / manual check) before moving on. Commit per phase (Setup, Foundational, US1, US2, US3, Polish) using messages like `feat(082): US1 — technician undo`.

---

## Review gate

When all tasks T001–T018 are ticked (T019 is a no-op reminder), signal completion to Claude Code with a message like:

> "Feature 082 implementation complete. Please run superpowers code review against branch 082-delete-ai-ratings using specs/082-delete-ai-ratings/tasks.md as the acceptance baseline."

Claude Code will then invoke the `superpowers:code-reviewer` agent to verify:

1. Every task T001–T018 is actually implemented in the diff (no "forgot to push" gaps).
2. The DB-schema constraint held (no migration added; `validated_qa.rating_id` changes remain nulling-only).
3. The orphan-before-delete ordering is implemented in both T002 and T010 (this is the critical data rule).
4. Activity-log writes use the three specific action strings from [data-model.md](data-model.md).
5. Authorization runs BEFORE side effects in both endpoints.
6. Failure-path rollback is wired in all three frontend flows (chat, Review, Train AI).
7. Contract tests (T005, T012) cover all listed scenarios and actually pass.
8. RTL + existing code style are preserved.

Address any review comments in the same branch. Do not open a PR until review is clean.

---

## Notes

- [P] tasks are parallelizable by touching different files with no unresolved dependency.
- [Story] label maps each task to a user story in [spec.md](spec.md) for traceability.
- Commits should not include `backend/version.json` (operator-managed on server).
- Do NOT run `pip install -r requirements.txt` as part of implementation — no new Python deps are introduced.
- Do NOT add new Flutter dependencies — `shared_preferences` is already a project dependency.
