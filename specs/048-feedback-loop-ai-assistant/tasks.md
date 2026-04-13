# Tasks: Feedback Loop AI Assistant

**Input**: Design documents from `/specs/048-feedback-loop-ai-assistant/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api.md, quickstart.md

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Execution context**: These tasks are designed for an LLM agent to execute step-by-step. Each task includes exact file paths, references to design documents for detailed specifications, and clear acceptance criteria. Read the referenced design documents before implementing each task.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `backend/` (Python 3.10 + FastAPI)
- **Frontend**: `frontend/lib/` (Dart 3.x / Flutter 3.x)
- **Migrations**: `supabase/migrations/`

---

## Phase 1: Setup

**Purpose**: Database schema and shared backend service

- [x] T001 Create database migration file `supabase/migrations/20260413000000_create_feedback_loop.sql` with the `answer_ratings` table, `validated_qa` table (with VECTOR(768) column), IVFFlat index on `question_embedding`, and the `search_validated_qa` RPC function. Follow the exact schema in `specs/048-feedback-loop-ai-assistant/data-model.md`. Use the existing `20260411000000_create_manuals.sql` migration as a reference for pgvector patterns and naming conventions.

- [x] T002 Create `backend/services/validated_qa_service.py` with the following functions (all async). This is the core service — every subsequent task depends on it:
  - `save_rating(question_text, answer_text, source_chunks, rating, rater_email, manual_id, model_used)` → inserts into `answer_ratings` table. If `rating == 'negative'`, set `review_status = 'pending'`. Return the inserted row's `id`.
  - `get_flagged_answers()` → queries `answer_ratings` WHERE `review_status = 'pending'` ORDER BY `created_at DESC`. Returns list of dicts.
  - `review_answer(rating_id, action, corrected_answer, reviewer_email)` → For 'approve': creates a `validated_qa` row using the original answer; for 'correct': creates a `validated_qa` row using `corrected_answer`. In both cases, updates the `answer_ratings` row's `review_status` to 'approved' or 'corrected'. Must call `embed_single()` from `backend/services/ollama_embedder.py` to generate the `question_embedding` synchronously before inserting the `validated_qa` row. Log the review action via `log_activity()` from `backend/utils/activity.py` with category `'manual'` and action `'reviewed_answer'`.
  - `check_validated_match(question_text)` → Embeds the question via `embed_single()`, calls the `search_validated_qa` RPC with `match_count=1`, returns `{'match_type': 'direct', 'validated_qa': row}` if distance <= 0.10 (similarity >= 0.90), `{'match_type': 'context', 'validated_qa': row}` if distance <= 0.25 (similarity >= 0.75), or `{'match_type': 'none'}` otherwise.
  - `update_validated_rating(validated_qa_id, rating)` → Increments `thumbs_up_count` or `thumbs_down_count` on the `validated_qa` row. After incrementing, checks the re-flagging threshold: if `thumbs_down_count / (thumbs_up_count + thumbs_down_count) > 0.30` AND total >= 3, sets `is_reflagged = TRUE`.
  - Use the existing Supabase client pattern from `backend/routers/manuals.py` (import `supabase` from the same location other services do). Reference `backend/services/ollama_embedder.py` for the `embed_single()` import pattern.

**Checkpoint**: Database tables exist and backend service compiles without errors.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Backend API endpoints that both the frontend and the RAG pipeline depend on

**CRITICAL**: No user story work can begin until this phase is complete.

- [x] T003 Add three new endpoints to `backend/routers/manuals.py`. Read the existing file first to understand the router structure, Pydantic model patterns, and how `user_email` is passed. Reference `specs/048-feedback-loop-ai-assistant/contracts/api.md` for exact request/response shapes:
  - `POST /manuals/rate-answer` → calls `validated_qa_service.save_rating()`. Log the rating via `log_activity()` with category `'manual'`, action `'rated_answer'`. No admin check needed — any user can rate.
  - `GET /manuals/flagged-answers?user_email=...` → calls `validated_qa_service.get_flagged_answers()`. Must check that `user_email` belongs to an admin user (query `users` table for `role == 'admin'`). Return 403 if not admin. Follow the existing admin-check pattern if one exists, otherwise query `supabase.table("users").select("role").eq("email", user_email).single().execute()`.
  - `POST /manuals/review-answer` → calls `validated_qa_service.review_answer()`. Must verify admin role same as above. Return the `validated_qa_id` and action in response.
  - Add Pydantic request/response models (`RateAnswerRequest`, `FlaggedAnswerResponse`, `ReviewAnswerRequest`, etc.) following the same patterns used by existing models like `AskRequest` in the same file.

- [x] T004 Add the `ManualAssistantService` methods in `frontend/lib/services/manual_assistant_service.dart`. Read the existing file first — it already has `askQuestion()`. Add these methods following the same HTTP call pattern (base URL, headers, error handling):
  - `rateAnswer({required String questionText, required String answerText, required List<Map<String, dynamic>> sourceChunks, required String rating, required String raterEmail, String? manualId, String? modelUsed})` → POST to `/manuals/rate-answer`
  - `getFlaggedAnswers({required String userEmail})` → GET `/manuals/flagged-answers?user_email=...` → returns `List<Map<String, dynamic>>`
  - `reviewAnswer({required String ratingId, required String action, String? correctedAnswer, required String reviewerEmail})` → POST to `/manuals/review-answer`

**Checkpoint**: All 3 API endpoints return correct responses when called via curl/Postman. Frontend service methods compile.

---

## Phase 3: User Story 1 — Technician Rates an AI Answer (Priority: P1) MVP

**Goal**: Technicians see thumbs-up/down buttons below each AI answer. Tapping a button saves the rating. Thumbs-down flags the answer for review.

**Independent Test**: Ask a question in the chat, receive an answer, tap thumbs-down. Verify the button state changes and `SELECT * FROM answer_ratings` shows the new row with `review_status = 'pending'`.

### Implementation for User Story 1

- [x] T005 [US1] Modify `frontend/lib/screens/manual_assistant/widgets/answer_card.dart` to add rating buttons. Read the existing file first — it renders the AI answer in a Card widget. Add the following:
  - Two `IconButton` widgets (thumb_up and thumb_down icons) in a `Row` at the bottom of the card, below the existing content.
  - Local state: `String? _selectedRating` (null, 'positive', 'negative'). Use `setState` to update on tap.
  - When tapped, visually highlight the selected button (use `Theme.of(context).colorScheme.primary` for selected, grey for unselected).
  - If the user taps the already-selected button, do nothing (keep selection).
  - If the user taps the other button, switch the selection (toggle behavior per spec acceptance scenario 3).
  - The widget needs these new constructor parameters: `Function(String rating)? onRate` callback, and the data needed to submit the rating (questionText, answerText, sourceChunks as serializable data).
  - Call `onRate?.call(rating)` when a button is tapped (or toggled to a new value).

- [x] T006 [US1] Modify `frontend/lib/screens/manual_assistant/chat_tab.dart` to wire up the rating callback. Read the existing file first to understand how `AnswerCard` is instantiated and how `ManualAssistantService` is used. When the `onRate` callback fires:
  - Call `ManualAssistantService.rateAnswer()` with the question text, answer text, source chunks, rating value, and the current user's email.
  - Handle errors silently (fire-and-forget pattern — don't block the UI). If the call fails, optionally show a brief snackbar.
  - Pass the question text and answer text to `AnswerCard` — these are likely already available in the chat message data structure. Check how messages are stored and rendered.

**Checkpoint**: User Story 1 is fully functional. A technician can rate any AI answer with a single tap. Ratings appear in the `answer_ratings` table. Thumbs-down ratings have `review_status = 'pending'`.

---

## Phase 4: User Story 2 — Senior Engineer Reviews Flagged Answers (Priority: P2)

**Goal**: Admin users see a "Review Queue" tab in the Manual Assistant screen. They can approve or correct flagged answers, creating validated QA pairs.

**Independent Test**: Flag an answer (from US1), log in as admin, open Review Queue tab, approve or correct the entry. Verify `validated_qa` table has the new row with an embedding.

**Depends on**: US1 (needs flagged answers to exist in the review queue)

### Implementation for User Story 2

- [x] T007 [US2] Create `frontend/lib/screens/manual_assistant/widgets/review_entry_card.dart` — a widget that displays a single flagged answer for review. Read `answer_card.dart` for styling patterns. The widget should display:
  - The original question text (bold, at the top)
  - The AI-generated answer text (in a scrollable container if long)
  - Source chunks in an `ExpansionTile` — each chunk shows manual_title, source_page, and content preview (follow the same pattern used in `answer_card.dart` for source display)
  - Timestamp of when the question was asked (formatted)
  - Rater email (who flagged it)
  - Two action buttons at the bottom:
    - "Approve" — calls `onApprove(ratingId)` callback
    - "Correct" — opens a `TextField` for the admin to type a corrected answer, then calls `onCorrect(ratingId, correctedAnswer)` callback
  - Constructor parameters: `Map<String, dynamic> entry`, `Function(String ratingId) onApprove`, `Function(String ratingId, String correctedAnswer) onCorrect`

- [x] T008 [US2] Create `frontend/lib/screens/manual_assistant/review_queue_tab.dart` — a new tab widget for the admin review queue. Reference the existing `chat_tab.dart` and `manuals_tab.dart` for the tab widget pattern used in this screen:
  - On init (or on tab activation), call `ManualAssistantService.getFlaggedAnswers(userEmail: currentUserEmail)` to load pending items.
  - Display the count as a badge somewhere visible (e.g., in the app bar or as a header "X items pending").
  - Render each flagged entry using `ReviewEntryCard` from T007.
  - Sort by newest first (the API already returns this order).
  - When the admin taps "Approve": call `ManualAssistantService.reviewAnswer(ratingId: id, action: 'approve', reviewerEmail: email)`. On success, remove the entry from the list with `setState`.
  - When the admin taps "Correct" and submits: call `ManualAssistantService.reviewAnswer(ratingId: id, action: 'correct', correctedAnswer: text, reviewerEmail: email)`. On success, remove the entry from the list.
  - Show an empty state message when no flagged answers exist (use the existing `EmptyState` widget from `claude_widgets.dart` if available, otherwise a simple `Center(child: Text(...))`.
  - Handle loading state with `CircularProgressIndicator`.

- [x] T009 [US2] Modify `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart` to add the Review Queue tab. Read the existing file first — it uses `DefaultTabController` with 2 tabs (Chat, Knowledge). Changes:
  - Check if the user is admin using the existing `userRole == 'admin'` pattern (already used in this file for the system instructions icon).
  - If admin: change `DefaultTabController(length: 2)` to `length: 3`, add a third `Tab` with text "Review Queue" and an icon (e.g., `Icons.rate_review`), and add `ReviewQueueTab()` as the third tab view.
  - If not admin: keep the existing 2-tab layout unchanged.
  - Pass the current user's email and role to `ReviewQueueTab`.

**Checkpoint**: User Story 2 is fully functional. Admin sees 3 tabs, can review flagged answers. `validated_qa` rows are created with embeddings on approve/correct. Non-admin users see only 2 tabs.

---

## Phase 5: User Story 3 — System Returns Validated Answer for Matching Question (Priority: P3)

**Goal**: Before running the full RAG pipeline, check `validated_qa` for a semantically similar question. If similarity >= 0.90, return the validated answer directly. If 0.75-0.90, inject as high-priority context.

**Independent Test**: Validate an answer (from US2), then ask a semantically similar question. Verify the response comes back instantly with `is_verified: true` (for >= 0.90 match) or that the validated answer influences the AI response (for 0.75-0.90).

**Depends on**: US2 (needs validated QA pairs to exist)

### Implementation for User Story 3

- [x] T010 [US3] Modify `backend/services/manual_rag_service.py` to add the validated QA check at the very beginning of the `ask()` function, BEFORE query rewriting and HyDE. Read the existing file first — understand the `ask()` function flow (it's a long function, ~300 lines). Insert the check right after any initial parameter handling but before `_rewrite_query()`:
  - Import and call `validated_qa_service.check_validated_match(question)`.
  - If `match_type == 'direct'`: return immediately with a response dict matching the existing return shape: `{'answer': validated_qa['validated_answer'], 'grounded': True, 'sources': [], 'model': 'validated_qa', 'duration_seconds': elapsed, 'is_verified': True, 'verified_source': {'validated_qa_id': str(id), 'validated_by': email, 'validated_at': timestamp, 'similarity': 1.0 - distance}}`. Do NOT call `generate()` or any pipeline step.
  - If `match_type == 'context'`: store the validated answer text in a variable (e.g., `validated_context`). Later in the function, when building the prompt for `generate()`, prepend the validated answer as a high-priority reference chunk ABOVE the retrieved manual chunks. Format it as: `"[VERIFIED REFERENCE — Expert-validated answer to a similar question]\n{validated_answer}\n\n"`. The exact insertion point depends on how the prompt is built — read the existing prompt construction code carefully.
  - If `match_type == 'none'`: proceed with the existing pipeline unchanged.
  - Wrap the `check_validated_match` call in a try/except — if it fails for any reason (embedding error, DB error), log the error and fall through to the normal pipeline (spec edge case: "system falls back to the standard AI pipeline without interruption").

- [x] T011 [US3] Modify `frontend/lib/screens/manual_assistant/widgets/answer_card.dart` to display a "Verified Answer" label when the response indicates a validated answer was returned directly. Read the existing widget (already modified in T005):
  - Check for `is_verified == true` in the response data passed to the widget.
  - If verified: show a prominent label at the top of the card — a `Container` with a green background and white text saying "Verified Answer" with a `Icons.verified` icon. Use `Theme.of(context).colorScheme` for colors.
  - If verified: hide the rating buttons (no need to rate an expert-validated answer) OR keep them visible to allow re-rating for the metrics system (check spec — FR-015 says "increment counts each time it is served and subsequently rated", so keep the buttons visible).
  - The `is_verified` and `verified_source` fields need to be parsed from the API response. Check how `ManualQaAnswer` model (or equivalent) is structured in `manual_assistant_service.dart` and add the new fields there.

- [x] T012 [US3] Update the response parsing in `frontend/lib/services/manual_assistant_service.dart` (or wherever the `ManualQaAnswer` model/response parsing lives). Add support for the new `is_verified` (bool) and `verified_source` (map with `validated_qa_id`, `validated_by`, `validated_at`, `similarity`) fields. These should be optional/nullable since most responses won't have them.

**Checkpoint**: User Story 3 is fully functional. Validated answers are returned directly for high-similarity questions. The chat shows "Verified Answer" label. Normal pipeline is unaffected when no match exists.

---

## Phase 6: User Story 4 — Feedback Metrics Accumulate Over Time (Priority: P4)

**Goal**: When a validated answer is served and rated, cumulative counts update. If thumbs-down exceeds 30% (min 3 ratings), the answer is re-flagged.

**Independent Test**: Serve a validated answer multiple times, rate it thumbs-down 2 out of 3 times (67% > 30%). Verify `is_reflagged = TRUE` in `validated_qa` table and the answer appears in the review queue.

**Depends on**: US3 (needs validated answers being served to generate ratings on them)

### Implementation for User Story 4

- [x] T013 [US4] Modify the `save_rating` function in `backend/services/validated_qa_service.py` to handle ratings on validated answers. When a rating is submitted and the answer text matches a validated answer (or the response included `validated_qa_id`):
  - Call `update_validated_rating(validated_qa_id, rating)` to increment the appropriate counter and check the re-flagging threshold.
  - To know which `validated_qa_id` to update, the rating submission needs this ID. Modify the `RateAnswerRequest` in `backend/routers/manuals.py` to include an optional `validated_qa_id: Optional[str] = None` field. The frontend will pass this when rating a verified answer.
  - Update the frontend `rateAnswer()` call in `chat_tab.dart` to pass `validated_qa_id` when rating a verified answer (the `verified_source` data from the response contains this ID).

- [x] T014 [US4] Modify `backend/services/validated_qa_service.py` `get_flagged_answers()` to ALSO return re-flagged validated answers. Query `validated_qa` WHERE `is_reflagged = TRUE` and include those entries in the review queue results alongside the `answer_ratings` pending items. Each re-flagged entry should include the validated answer's ID, question, current answer, source chunks, and cumulative rating counts so the admin has full context.

- [x] T015 [US4] Modify `backend/services/validated_qa_service.py` `review_answer()` to handle re-reviews of re-flagged validated answers. When the `rating_id` corresponds to a re-flagged `validated_qa` entry (not a fresh `answer_ratings` row):
  - Update the existing `validated_qa` row in place: set the new answer (or keep the original if approved), update `validated_by` and `validated_at`, reset `thumbs_up_count` and `thumbs_down_count` to 0, set `is_reflagged = FALSE`.
  - Re-generate the `question_embedding` via `embed_single()` (in case the question or answer context changed).

**Checkpoint**: User Story 4 is fully functional. Cumulative metrics update on validated answers. Re-flagging triggers at 30%/3-minimum threshold. Re-flagged answers appear in the review queue and can be re-reviewed.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T016 [P] Add activity logging for rating actions in `backend/routers/manuals.py` — ensure the `rate-answer` endpoint calls `log_activity(user_email=rater_email, category='manual', action='rated_answer', target_label=question_text[:80], detail=rating)`. Verify `review-answer` endpoint also logs via `log_activity()` (should already be done in T002's `review_answer()` function, but verify the log entry includes the action taken and the rating_id).

- [x] T017 [P] Add a badge count to the Review Queue tab in `manual_assistant_screen.dart`. When the admin user is detected, make a lightweight call to `getFlaggedAnswers()` to get the count, and display it as a badge on the Review Queue tab icon (e.g., using a `Badge` widget or a small `Container` with the count overlaid on the tab icon). Update the count when switching to/from the tab.

- [x] T018 Run the verification steps from `specs/048-feedback-loop-ai-assistant/quickstart.md`: test rating flow, review queue (admin), validated answer reuse, and non-admin access. Fix any issues found.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (T001, T002 must be complete)
- **User Story 1 (Phase 3)**: Depends on Phase 2 (T003, T004)
- **User Story 2 (Phase 4)**: Depends on Phase 2 + US1 must exist for flagged answers to review
- **User Story 3 (Phase 5)**: Depends on Phase 2 + US2 must exist for validated QA pairs
- **User Story 4 (Phase 6)**: Depends on US3 (validated answers must be served to generate metrics)
- **Polish (Phase 7)**: Depends on all user stories complete

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational only — **this is the MVP**
- **US2 (P2)**: Depends on US1 (needs flagged answers in the database)
- **US3 (P3)**: Depends on US2 (needs validated QA pairs in the database)
- **US4 (P4)**: Depends on US3 (needs validated answers being served to rate)

**Note**: These are sequential dependencies — each story builds on the previous one's data. They cannot be parallelized across stories, but tasks within each story marked [P] can run in parallel.

### Within Each User Story

- Models/services before endpoints
- Backend before frontend
- Core implementation before integration

---

## Parallel Example: Phase 2 (Foundational)

```
# These can run in parallel (different files):
Task T003: Backend endpoints in backend/routers/manuals.py
Task T004: Frontend service methods in frontend/lib/services/manual_assistant_service.dart
```

## Parallel Example: User Story 2

```
# These can run in parallel (different files):
Task T007: ReviewEntryCard widget in frontend/.../widgets/review_entry_card.dart
Task T008: ReviewQueueTab in frontend/.../review_queue_tab.dart (after T007)
Task T009: ManualAssistantScreen tab wiring (after T008)
# T007 → T008 → T009 is sequential within US2
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001, T002)
2. Complete Phase 2: Foundational (T003, T004)
3. Complete Phase 3: User Story 1 (T005, T006)
4. **STOP and VALIDATE**: Test rating flow end-to-end
5. Deploy if ready — technicians can start providing feedback immediately

### Incremental Delivery

1. Setup + Foundational → Infrastructure ready
2. Add US1 → Ratings work → Deploy (MVP!)
3. Add US2 → Admin review works → Deploy
4. Add US3 → Validated answers reused → Deploy
5. Add US4 → Metrics accumulate → Deploy
6. Polish → Final cleanup → Deploy

Each story adds value and builds on the previous one.

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- User stories are sequential in this feature (each builds on previous data)
- Commit after each task or logical group
- Stop at any checkpoint to validate the current story independently
- All design details are in the referenced spec files — read them before implementing
- The existing codebase patterns (Supabase client, activity logging, admin check, service structure) should be followed — read existing files before writing new code
