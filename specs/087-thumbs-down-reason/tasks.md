---
description: "Task list — Thumbs-Down Reason & Comment (spec 087)"
---

# Tasks: Thumbs-Down Reason & Comment

**Input**: Design documents in `specs/087-thumbs-down-reason/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/patch-rating-feedback.md](./contracts/patch-rating-feedback.md)

**Tests**: Included. The quickstart.md explicitly lists a `pytest` run against a new `test_manuals_rating_feedback.py` file, and the contract specifies distinct failure modes that must be verified. Tests are authored as part of US1 (the P1 implementation) and extended per subsequent stories.

**Organization**: Tasks are grouped by the four user stories from [spec.md](./spec.md). Stories US1 and US2 are both P1; US3 and US4 are P2.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can be run in parallel with other tasks in the same phase (different files / no in-phase dependency)
- **[Story]**: which user story the task belongs to (US1–US4)
- All paths are relative to repo root (`C:\Development\flutter_work_order`)

## Path Conventions

Existing web-app layout (per [plan.md](./plan.md) §Project Structure):

- Backend code: `backend/routers/`, `backend/services/`
- Backend tests: `backend/tests/routers/`
- Frontend code: `frontend/lib/services/`, `frontend/lib/screens/manual_assistant/`
- Migrations: `supabase/migrations/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the branch and environment are ready. No new dependencies are introduced by this feature.

- [ ] T001 Confirm branch `087-thumbs-down-reason` is checked out, working tree clean (other than this spec directory), and both backend virtualenv and Flutter workspace resolve without errors (`pip install -r backend/requirements.txt`, `flutter pub get` in `frontend/`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Schema changes required by every user story. No user-story work may begin until both tasks complete.

**⚠️ CRITICAL**: T002 and T003 block US1, US2, US3, and US4.

- [ ] T002 Create migration file `supabase/migrations/20260419000000_add_rating_feedback.sql` adding two nullable columns to `answer_ratings`: `feedback_reason TEXT CHECK (feedback_reason IN ('inaccurate','incomplete','outdated','wrong_source','unclear'))` and `feedback_comment TEXT`. Use the exact SQL from [data-model.md](./data-model.md) §Migration, including the `IF NOT EXISTS` guard and the file-level comment explaining scope.
- [ ] T003 Apply the migration to the dev Supabase project (via `supabase db push`, Studio SQL editor, or equivalent). Verify with `\d answer_ratings` that both columns exist with the CHECK constraint on `feedback_reason`.

**Checkpoint**: Foundation ready — all four user stories can now proceed.

---

## Phase 3: User Story 1 — Technician picks a reason and leaves a comment (Priority: P1) 🎯 MVP

**Goal**: A technician who clicks thumbs-down can attach one of five reasons plus an optional comment; the admin sees both on the existing Review tab.

**Independent Test**: Sign in as a technician. Thumbs-down an AI answer. In the bottom sheet that appears, pick "Outdated", type a short note, tap Save. Sign in as admin → Review tab. Confirm the amber "Outdated" chip and comment preview appear on the flagged entry (Scenario A in [quickstart.md](./quickstart.md)).

### Tests for User Story 1 (write first — ensure they FAIL before T005/T006 implementation)

- [ ] T004 [US1] Write backend contract tests in `backend/tests/routers/test_manuals_rating_feedback.py` covering every case in [contracts/patch-rating-feedback.md](./contracts/patch-rating-feedback.md): 200 happy path (both fields), 200 reason-only (null comment), 200 idempotent second call, 404 when `rating_id` does not exist, 403 when `user_email` ≠ `rater_email`, 422 on unknown reason value, 422 on comment >2000 chars, 400 on rating that is `positive`. Also assert `user_activity_log` receives exactly one new row with `action='rated_answer_feedback'` and `detail=<reason value>` on the happy path.

### Implementation for User Story 1

- [ ] T005 [US1] Add `update_rating_feedback(rating_id, reason, comment, user_email)` in `backend/services/validated_qa_service.py`: SELECT the target row, raise `RatingNotFound` if missing, raise `NotOwner` if `rater_email != user_email`, raise `NotNegativeRating` if `rating != 'negative'`, otherwise UPDATE the two columns and return the updated row. After a successful UPDATE, call `log_activity(user_email, 'manual', 'rated_answer_feedback', target_label=<first 80 chars of question_text>, detail=reason)` wrapped in `try/except` (fire-and-forget per constitution VI).
- [ ] T006 [US1] Add the `PATCH /manuals/ratings/{rating_id}/feedback` endpoint in `backend/routers/manuals.py`: define a `RatingFeedbackRequest` Pydantic model with `feedback_reason: Literal['inaccurate','incomplete','outdated','wrong_source','unclear']`, `feedback_comment: Optional[str] = Field(None, max_length=2000)`, `user_email: str`. Dispatch to `validated_qa_service.update_rating_feedback`; translate exceptions to 404/403/400 HTTPExceptions per the contract; return `{status, rating_id, feedback_reason, feedback_comment}`. Do NOT modify the existing `RateAnswerRequest` or `save_rating()` — the POST path stays unchanged (per research Decision 2).
- [ ] T007 [US1] Add `saveFeedback({required String ratingId, required String reason, String? comment, required String userEmail}) async` to `frontend/lib/services/manual_assistant_service.dart`. Call `PATCH ${AppConfig.baseUrl}/manuals/ratings/$ratingId/feedback` with the JSON body from the contract; throw on non-200. Return void; the caller only needs success/failure.
- [ ] T008 [P] [US1] Create `frontend/lib/screens/manual_assistant/widgets/feedback_reason_sheet.dart` as a stateful widget exposing `Future<FeedbackSheetResult?> show(BuildContext context)`. Layout (inside `showModalBottomSheet`): title "What went wrong?"; 5 `ChoiceChip`s in a `Wrap` (single-select, labels + colors per research Decision 7); multiline `TextField` with placeholder "Tell us more (optional)", `maxLines: 3`, `maxLength: null` but showing a live counter that turns red past 500; two buttons — `TextButton('Skip')` returns `null`, `FilledButton('Save')` enabled only when a chip is selected and returns `FeedbackSheetResult(reason, comment)`. Respect swipe-to-dismiss (returns `null`). Add enum `FeedbackReason` with values matching the 5 server enum strings.
- [ ] T009 [US1] Modify `frontend/lib/screens/manual_assistant/chat_tab.dart` `_handleRate`: after the existing `_service.rateAnswer(...)` returns a `ratingId` AND `rating == 'negative'`, await `FeedbackReasonSheet.show(context)`. If the result is non-null, call `_service.saveFeedback(ratingId: ratingId, reason: result.reason, comment: result.comment, userEmail: email)`. On saveFeedback exception, show a `SnackBar('Could not save feedback — rating was still recorded')` (the rating itself remains saved; the user is not penalized). Do NOT trigger the sheet for `rating == 'positive'`.

**Checkpoint**: US1 fully functional. A 👎 → chip-pick → Save → DB row update → activity log → Review-tab chip works end-to-end. Tests in T004 pass.

---

## Phase 4: User Story 2 — Technician dismisses the reason prompt (Priority: P1)

**Goal**: Technicians who skip or swipe away the bottom sheet still have their thumbs-down recorded — the rating is never lost, just without a reason.

**Independent Test**: Thumbs-down an answer and swipe the sheet down (or tap Skip). Confirm (a) the row persists in `answer_ratings` with `rating='negative'` and `feedback_reason IS NULL`, (b) no toast appears, (c) the Review tab shows the entry with the muted "No reason given" chip (the chip rendering lives in US4 but the data state asserted here is US2's contract).

### Tests for User Story 2

- [ ] T010 [P] [US2] Add Flutter widget test in `frontend/test/screens/manual_assistant/widgets/feedback_reason_sheet_test.dart` (new file): (a) tapping Skip returns `null`; (b) swipe-to-dismiss returns `null`; (c) Save is disabled until a chip is selected; (d) tapping a chip and tapping Save returns the correct reason + comment; (e) a chat_tab integration test (or the widget test with a mocked `rateAnswer`) asserts that `_handleRate(rating: 'positive')` does NOT call `showModalBottomSheet`, covering FR-012's client-side guard. No server calls involved.
- [ ] T011 [P] [US2] Extend the backend contract tests from T004 to include an assertion: after a `POST /manuals/rate-answer` with `rating='negative'` *without* a follow-up PATCH, the row remains queryable via `GET /manuals/flagged-answers` with `feedback_reason IS NULL` and `feedback_comment IS NULL`. This guards the "sentiment signal is never lost" invariant (FR-001).

**Checkpoint**: US1 and US2 both complete. Dismissal path produces NULL state; Save path populates it. `_handleRate` in chat_tab.dart correctly handles both branches.

---

## Phase 5: User Story 3 — Technician un-rates (Priority: P2)

**Goal**: Re-tapping thumbs-down deletes the rating, including any associated reason/comment. No orphan data remains.

**Independent Test**: Thumbs-down, add reason+comment, Save. Re-tap thumbs-down (un-rate). Query `answer_ratings` — the row is gone. Query `GET /manuals/flagged-answers` — the entry is absent.

### Tests for User Story 3

- [ ] T012 [US3] Extend `backend/tests/routers/test_manuals_rating_feedback.py` (or the existing `backend/tests/routers/test_manuals_delete_rating.py` — pick whichever reads cleaner) with a case: create a rating, PATCH it with reason+comment, then `DELETE /manuals/ratings/{rating_id}` as the same rater, assert the row is absent via a SELECT. Confirms the existing delete flow correctly drops the new columns.

**Checkpoint**: US3 complete. Un-rate cleanup verified — no code change needed, only a regression test.

---

## Phase 6: User Story 4 — Admin triages flagged answers by reason (Priority: P2)

**Goal**: Admins see each flagged rating's reason at a glance (colored chip) on the Review tab without expanding the card. Comment preview surfaces below the question if present.

**Independent Test**: Seed 5 ratings, one for each reason, plus one with no reason. Open the Review tab. Confirm each card shows the correct chip color/label inline, that the no-reason card shows a muted grey "No reason given" chip, and that the comment preview respects the 100-char truncation with the full comment visible on expansion.

### Implementation for User Story 4

- [ ] T013 [US4] Update `get_flagged_answers()` in `backend/services/validated_qa_service.py` to include `feedback_reason` and `feedback_comment` in the `select()` for the `pending` branch of `answer_ratings`. (The `is_reflagged` branch from `validated_qa` has no such fields — leave those rows unchanged; the frontend will render them with the "No reason given" chip.)
- [ ] T014 [US4] Add widget test in `frontend/test/screens/manual_assistant/widgets/review_entry_card_test.dart` (new file or extend existing) covering the six chip states: each of the 5 reasons + NULL (no-reason). Assert the chip's label text and background color match research Decision 7.
- [ ] T015 [US4] Update `frontend/lib/screens/manual_assistant/widgets/review_entry_card.dart` to render the reason chip. Introduce a private helper `_buildReasonChip(String? reason)` returning a `Chip` with: label = human-readable name (e.g. `wrong_source` → "Wrong source"), background per research Decision 7, padding matching existing card chrome. Place the chip on the same row as the question text (use `Row` with `Wrap` fallback for narrow widths).
- [ ] T016 [US4] In the same `review_entry_card.dart`, render the comment preview. In collapsed state, show `Text('${feedbackComment.substring(0, min(100, length))}…')` as italic muted (`color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7)`) only when `feedbackComment != null && isNotEmpty`. In expanded state, show the full comment in the same row as the existing answer text block.
- [ ] T017 [US4] Render the muted grey "No reason given" chip for entries with `feedback_reason == null` or `feedback_reason` missing from the map — covers skipped thumbs-down AND the `is_reflagged` `validated_qa` path (which never produces a reason). Use `Colors.grey.shade400` per research Decision 7.

**Checkpoint**: US4 complete. Admin scrolling the Review tab can triage by reason at a glance. All four user stories are now independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T018 [P] Run the full [quickstart.md](./quickstart.md) Scenarios A–E manually against local dev (chat + Review tab). Verify every ✅ checkpoint and every curl response.
- [ ] T019 [P] Regression test for FR-011 in `backend/tests/routers/test_manuals_reason_informational.py` (new file): seed `answer_ratings` rows with each of the 5 reason values, then exercise `update_validated_rating` (reflag threshold logic in `backend/services/validated_qa_service.py`) and the `/manuals/real-usage-suggestions` pipeline. Assert reflag behavior, approve/correct behavior, and From-Real-Usage ordering are identical to a baseline run without `feedback_reason` set. Confirms reason/comment are informational only.
- [ ] T020 [P] Smoke test for SC-006 in `backend/tests/routers/test_manuals_approve_correct_regression.py` (new file): seed one flagged rating with reason + comment, invoke the existing Review-tab approve flow, assert a single `validated_qa` row is created with the correct answer and no extra steps required. Repeat for the correct action with a corrected answer. Confirms click-count and success-rate parity with pre-feature baseline.
- [ ] T021 [P] Run `ruff check backend/` and `flutter analyze` in `frontend/`. Fix any new warnings this feature introduces. Do NOT touch pre-existing warnings.
- [ ] T022 [P] Invoke the `architecture-doc-updater` agent after merge to refresh `ARCHITECTURE.md` and `AGENT.md` with the new `feedback_reason`/`feedback_comment` fields and the PATCH endpoint. (Scheduled — not blocking merge.)
- [ ] T023 Deploy: push branch, open PR, land to `main`, apply migration to production Supabase (same SQL as T002), `sudo systemctl restart document_server.service` on the Zorin server per project memory.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)** — no dependencies; runs immediately.
- **Phase 2 (Foundational)** — T002 → T003 sequential (apply the file you just created); blocks Phases 3–6.
- **Phase 3 (US1)** — T004 (tests) should be written before T005/T006 (per template guidance "tests must fail before implementation"). T007–T009 can follow once T006 is green. T008 is `[P]` with T007 (different files). T009 depends on T007 and T008.
- **Phase 4 (US2)** — T010 and T011 are `[P]` (different file pairs) and depend on T008 (widget) and T006 (endpoint) respectively being implemented.
- **Phase 5 (US3)** — T012 depends on T005/T006 being merged; otherwise standalone.
- **Phase 6 (US4)** — T013 can start after Phase 2. T015–T017 depend on T013 (field availability). T014 is `[P]` with T015.
- **Phase 7 (Polish)** — all tasks run only after US1+US2+US3+US4 all complete.

### Parallel opportunities

- Within Phase 3: T007 and T008 are `[P]` (different files).
- Within Phase 4: T010 and T011 are `[P]`.
- Within Phase 6: T014 is `[P]` alongside T015.
- Within Phase 7: T018 through T022 are all `[P]` (independent files / manual smoke). Only T023 (deploy) is sequential.
- A second developer could own US3+US4 in parallel with US1+US2 once Phase 2 completes (spec stories are independent by design).

---

## Parallel Example: User Story 1

```text
# After T004 (backend tests) and T005+T006 (backend impl) are merged:
Task T007: Add saveFeedback() method — frontend/lib/services/manual_assistant_service.dart
Task T008: Create FeedbackReasonSheet widget — frontend/lib/screens/manual_assistant/widgets/feedback_reason_sheet.dart
# Then T009 wires them into chat_tab.dart and the sheet.
```

---

## Implementation Strategy

### MVP first (US1 only)

1. Complete Phase 1 (T001) — minutes.
2. Complete Phase 2 (T002, T003) — schema is live.
3. Complete Phase 3 (T004–T009) — ship the save path.
4. **STOP & VALIDATE**: Scenario A in quickstart.md passes. At this point thumbs-down reasons are being captured; admins can view them if willing to query the DB directly (US4 chrome not yet shipped).
5. Ship to production if acceptable as an interim step, or continue.

### Incremental delivery

1. Phase 1 + Phase 2 → Foundation.
2. Phase 3 (US1) → Save works. Deploy / demo (MVP).
3. Phase 4 (US2) → Dismissal verified. No new UI.
4. Phase 5 (US3) → Un-rate regression test. No new UI.
5. Phase 6 (US4) → Review-tab chips. Deploy / demo (Complete).
6. Phase 7 → Polish, doc updates, ship.

### Parallel team strategy

- Dev A: Phase 3 (US1) backend — T004, T005, T006.
- Dev B: Phase 3 (US1) frontend — T007, T008, then T009 after A's work lands.
- Dev C: Phase 6 (US4) in parallel — T013, T015, T016, T017 + T014.

---

## Notes

- The existing `POST /manuals/rate-answer` is NOT modified. Reason/comment travel exclusively through the new PATCH endpoint, preserving the "thumbs-down is never lost" invariant (FR-001, research Decision 2).
- No retroactive backfill of `feedback_reason` / `feedback_comment` onto historical rows — they stay NULL and render "No reason given" in the Review tab (FR-010).
- Legacy `is_reflagged = true` rows surfaced by `get_flagged_answers` from `validated_qa` never carry a reason; the frontend (T017) treats them the same as null-reason rows.
- Keep commits small per task or logical group so `opencode` (per user memory) can pick up per-file changes without cross-file conflicts.
- Never skip hooks, do not amend commits (per project memory).
