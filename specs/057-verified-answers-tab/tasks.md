# Tasks: Verified Answers Admin Tab

**Input**: Design documents from `/specs/057-verified-answers-tab/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api-endpoints.md, quickstart.md

**Tests**: No automated tests — manual verification via curl + Flutter browser per quickstart.md.

**Organization**: Tasks are grouped by user story. US1-US3 share backend infrastructure (Phase 2), then each story builds its frontend slice. US4 (delete) is independent.

**Target implementer**: opencode LLM. Each task is self-contained with exact file paths, function signatures, and patterns to follow.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Exact file paths included in every task

## Path Conventions

- **Backend**: `backend/routers/`, `backend/services/`
- **Frontend**: `frontend/lib/screens/manual_assistant/`, `frontend/lib/services/`

---

## Phase 1: Foundational (Backend — Blocking Prerequisites)

**Purpose**: Backend service functions and endpoints that all user stories depend on. These MUST be complete before any frontend work.

**⚠️ CRITICAL**: No frontend tasks can begin until this phase is complete.

- [X] T001 [P] Add `get_all_verified_answers(search, limit, offset)` function in `backend/services/validated_qa_service.py`. Add after `update_validated_rating()` (~line 274). Signature: `def get_all_verified_answers(search: Optional[str] = None, limit: int = 50, offset: int = 0) -> dict`. Query `supabase.table("validated_qa")` selecting: id, question_text, validated_answer, equipment_type, fault_code, validated_by, validated_at, thumbs_up_count, thumbs_down_count, is_reflagged, updated_at. If search non-empty: `.ilike("question_text", f"%{search}%")`. Order by `updated_at` desc. Use `.range(offset, offset + limit - 1)`. Get total count via separate query with `.select("id", count="exact")` (apply same search filter). Return `{"items": data, "count": count}`.

- [X] T002 [P] Add `async update_verified_answer(qa_id, question_text, validated_answer, editor_email)` function in `backend/services/validated_qa_service.py`. Signature: `async def update_verified_answer(qa_id: str, question_text: Optional[str], validated_answer: Optional[str], editor_email: str) -> dict`. Fetch existing row: `supabase.table("validated_qa").select("*").eq("id", qa_id).single().execute()`. If not found, raise `ValueError("not found")`. Build update dict, always set `updated_at = datetime.now(timezone.utc).isoformat()`. If `question_text` provided and differs from existing: call `embedding = await embed_single(question_text)` (may raise `EmbedderTimeoutError`), format as `"[" + ",".join(str(x) for x in embedding) + "]"` (same pattern as line 138), add question_embedding + question_text to update dict, re-extract equipment_type via `_extract_equipment_type(question_text)` and fault_code via `_extract_fault_code(question_text)`. If `validated_answer` provided, add to update dict. Execute update and return the updated row selecting same columns as T001.

- [X] T003 [P] Add `delete_verified_answer(qa_id)` function in `backend/services/validated_qa_service.py`. Signature: `def delete_verified_answer(qa_id: str) -> str`. Fetch existing row: `supabase.table("validated_qa").select("id, rating_id").eq("id", qa_id).single().execute()`. If not found, raise `ValueError("not found")`. Hard-delete: `supabase.table("validated_qa").delete().eq("id", qa_id).execute()`. Reset linked rating: `supabase.table("answer_ratings").update({"review_status": "pending"}).eq("id", rating_id).execute()`. Return qa_id.

- [X] T004 Add Pydantic model and 3 endpoints in `backend/routers/manuals.py`. Add AFTER the `review_answer` endpoint (~line 514), BEFORE the `_admin_check()` helper function. (1) New Pydantic model: `class UpdateVerifiedAnswerRequest(BaseModel): question_text: Optional[str] = None; validated_answer: Optional[str] = None; editor_email: str`. (2) GET `/manuals/verified-answers` — params: `user_email: str = Query(...)`, `search: Optional[str] = Query(None)`, `limit: int = Query(50)`, `offset: int = Query(0)`. Call `_admin_check(user_email)`, then `validated_qa_service.get_all_verified_answers(search, limit, offset)`, return result. Wrap in try/except → 500. (3) PUT `/manuals/verified-answers/{qa_id}` — body: UpdateVerifiedAnswerRequest. Call `_admin_check(request.editor_email)`, then `await validated_qa_service.update_verified_answer(qa_id, request.question_text, request.validated_answer, request.editor_email)`. Catch ValueError→404, EmbedderTimeoutError→504 (import from `services.ollama_embedder`), Exception→500. Fire-and-forget `log_activity(request.editor_email, "manual", "edited_verified_answer", target_id=qa_id)`. Return updated row. (4) DELETE `/manuals/verified-answers/{qa_id}` — params: `editor_email: str = Query(...)`. Call `_admin_check(editor_email)`, then `validated_qa_service.delete_verified_answer(qa_id)`. Catch ValueError→404, Exception→500. Fire-and-forget `log_activity(editor_email, "manual", "deleted_verified_answer", target_id=qa_id)`. Return `{"status": "deleted", "id": qa_id}`. Follow the existing error handling pattern from `upload_manual` endpoint (~line 203): `raise HTTPException(status_code=X, detail={"error": "message"})`.

**Checkpoint**: Backend complete. Test with curl:
```
curl "http://localhost:8000/manuals/verified-answers?user_email=<admin_email>"
```

---

## Phase 2: User Story 1 — Browse all verified answers (Priority: P1) 🎯 MVP

**Goal**: Admin sees a "Verified" tab in the AI Assistant screen with a paginated list of all validated Q&A entries.

**Independent Test**: Log in as admin → AI Assistant → tap "Verified" tab → list of validated_qa entries loads, ordered by updated_at desc. Pull to refresh works. Non-admin sees only 2 tabs.

### Implementation for User Story 1

- [X] T005 [P] [US1] Add `getVerifiedAnswers()` method in `frontend/lib/services/manual_assistant_service.dart`. Pattern: follow `getFlaggedAnswers()` at line 336. Signature: `Future<Map<String, dynamic>> getVerifiedAnswers({required String userEmail, String? search, int limit = 50, int offset = 0}) async`. GET to `${AppConfig.baseUrl}/manuals/verified-answers?user_email=$userEmail&limit=$limit&offset=$offset` (append `&search=$search` only if search is non-null and non-empty). Use `_getAuthHeaders()`. Parse response JSON. On 403 throw descriptive error. Return the full map with `items` (List) and `count` (int).

- [X] T006 [US1] Create new file `frontend/lib/screens/manual_assistant/verified_answers_tab.dart`. Build a StatefulWidget `VerifiedAnswersTab` with `userEmail` parameter. Use `AutomaticKeepAliveClientMixin` (pattern: review_queue_tab.dart). State variables: `_entries` List<Map<String, dynamic>>, `_totalCount` int = 0, `_loading` bool = true, `_loadingMore` bool = false, `_error` String?, `_offset` int = 0, `_limit` = 50, `_currentRequestId` int = 0. In `initState`, call `_loadEntries()`. `_loadEntries({bool append = false})`: increment `_currentRequestId`, capture localId, call `_service.getVerifiedAnswers(userEmail: widget.userEmail, limit: _limit, offset: append ? _offset : 0)`. Before setState check `localId == _currentRequestId` (stale guard). If append: add items to `_entries` and increment `_offset`; else: replace `_entries`, set `_offset = items.length`, set `_totalCount = result['count']`. Build method: (1) loading indicator if `_loading`, (2) error state if `_error`, (3) empty state "No verified answers yet." if entries empty, (4) Column with summary row ("$_totalCount verified answers" + refresh IconButton), (5) Expanded > RefreshIndicator > ListView.builder with itemCount = `_entries.length + (_hasMore ? 1 : 0)` where `_hasMore = _entries.length < _totalCount`. Last item if `_hasMore`: centered OutlinedButton "Load More" that calls `_loadEntries(append: true)`. Each regular item: Card with ListTile — title: question_text (bold, maxLines: 2, overflow: ellipsis), subtitle: validated_answer (maxLines: 2, overflow: ellipsis), trailing: Row with thumbs_up icon + count and thumbs_down icon + count (small text).

- [X] T007 [US1] Wire the Verified tab into `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart`. (1) Add import: `import 'verified_answers_tab.dart';`. (2) Line 33: change `TabController(length: _isAdmin ? 5 : 2, vsync: this)` to `TabController(length: _isAdmin ? 6 : 2, vsync: this)`. (3) In TabBar tabs list, after the Alerts tab block (~line 116-125), add: `if (_isAdmin) Tab(child: Row(mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.verified_outlined, size: 18), SizedBox(width: 4), Text('Verified')]))`. (4) In TabBarView children, after `AlertsTab` (~line 142), add: `if (_isAdmin) VerifiedAnswersTab(userEmail: _userEmail)`. (5) Verify `_onTabChanged` only checks `index == 2` (Review Queue) — no changes needed since new tab is at index 5.

**Checkpoint**: Admin sees 6 tabs. "Verified" tab loads paginated list. Non-admin sees 2 tabs. Pull-to-refresh and Load More work.

---

## Phase 3: User Story 2 — Search verified answers (Priority: P1)

**Goal**: Admin can search verified answers by question text with 300ms debounce and in-flight request cancellation.

**Independent Test**: Type a keyword → list filters after 300ms. Type quickly → only final search fires. Clear search → full list reloads. No results → empty state shown.

### Implementation for User Story 2

- [X] T008 [US2] Add search functionality to `frontend/lib/screens/manual_assistant/verified_answers_tab.dart`. Add state variables: `_searchController` TextEditingController, `_debounce` Timer?. In `initState` (before _loadEntries call): initialize `_searchController`. In `dispose`: cancel `_debounce`, dispose `_searchController`. Add `_onSearchChanged(String value)` method: cancel existing `_debounce`, start new Timer(Duration(milliseconds: 300)) that resets `_offset = 0` and calls `_loadEntries()`. Update `_loadEntries` to pass `search: _searchController.text` (only if non-empty) to `getVerifiedAnswers()`. Add clear button: when search text is cleared, cancel debounce, reset offset, reload. Update build method: insert a Padding with TextField above the summary row. TextField decoration: `InputDecoration(hintText: 'Search questions...', prefixIcon: Icon(Icons.search), suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: Icon(Icons.clear), onPressed: () { _searchController.clear(); _onSearchChanged(''); }) : null, border: OutlineInputBorder())`. Set `onChanged: _onSearchChanged`. The existing `_currentRequestId` stale guard from T006 already handles in-flight request cancellation.

**Checkpoint**: Search works with debounce. Rapid typing only fires final query. Clear resets to full list.

---

## Phase 4: User Story 3 — Edit verified answers (Priority: P1)

**Goal**: Admin taps a card to open an edit dialog with pre-populated question and answer fields. Save updates the record; if question changed, backend re-embeds. List item refreshes with server-returned data.

**Independent Test**: Tap entry → edit dialog opens with current values. Edit answer only → save → no re-embedding. Edit question → save → metadata re-extracted. Embedder timeout → shows "Embedding timed out" SnackBar. Success → list item updates in place.

### Implementation for User Story 3

- [X] T009 [P] [US3] Add `updateVerifiedAnswer()` method in `frontend/lib/services/manual_assistant_service.dart`. Pattern: follow `reviewAnswer()` at line 363. Signature: `Future<Map<String, dynamic>> updateVerifiedAnswer({required String qaId, String? questionText, String? validatedAnswer, required String editorEmail}) async`. PUT to `${AppConfig.baseUrl}/manuals/verified-answers/$qaId`. Body: build map with `editor_email: editorEmail`, include `question_text` only if questionText non-null, include `validated_answer` only if validatedAnswer non-null. Use `_getAuthHeaders()` + `Content-Type: application/json`. On 404 throw "Answer not found". On 504 throw "Embedding timed out — please try again". On other errors throw generic message. Return parsed response body.

- [X] T010 [US3] Add edit dialog to `frontend/lib/screens/manual_assistant/verified_answers_tab.dart`. Add `_showEditDialog(Map<String, dynamic> entry)` method. Create two TextEditingController instances pre-populated with `entry['question_text']` and `entry['validated_answer']`. Show `showDialog` with AlertDialog: title "Edit Verified Answer", content: SingleChildScrollView with Column containing two TextFormFields (label "Question", label "Answer", both maxLines: 5). Actions: TextButton "Cancel" (pop), ElevatedButton "Save" (disabled if either field empty). On save: show loading indicator, call `_service.updateVerifiedAnswer(qaId: entry['id'], questionText: questionCtrl.text, validatedAnswer: answerCtrl.text, editorEmail: widget.userEmail)`. On success: find the entry index in `_entries` by id, replace it with server-returned data (do NOT patch locally), pop dialog, show success SnackBar. On error containing "timed out": show SnackBar "Embedding timed out — please try again". On other error: show generic error SnackBar. Wire `onTap: () => _showEditDialog(entry)` on each list item card from T006.

**Checkpoint**: Edit dialog opens with current values. Save updates entry in list. Embedder timeout shows distinct message.

---

## Phase 5: User Story 4 — Delete verified answers (Priority: P2)

**Goal**: Admin can delete a verified answer with confirmation. The linked answer_ratings row has its review_status reset to 'pending'.

**Independent Test**: Tap delete → confirmation dialog with question text and permanent warning. Confirm → entry removed from list. Cancel → entry remains. GET endpoint no longer returns deleted entry.

### Implementation for User Story 4

- [X] T011 [P] [US4] Add `deleteVerifiedAnswer()` method in `frontend/lib/services/manual_assistant_service.dart`. Signature: `Future<Map<String, dynamic>> deleteVerifiedAnswer({required String qaId, required String editorEmail}) async`. DELETE to `${AppConfig.baseUrl}/manuals/verified-answers/$qaId?editor_email=$editorEmail`. Use `_getAuthHeaders()`. On 404 throw "Answer not found". On other errors throw generic message. Return parsed response body.

- [X] T012 [US4] Add delete confirmation to `frontend/lib/screens/manual_assistant/verified_answers_tab.dart`. Add `_confirmDelete(Map<String, dynamic> entry)` method. Show `showDialog` with AlertDialog: title "Delete Verified Answer?", content: Column with Text showing the question_text (max 3 lines, italic) and SizedBox(height: 12) then Text("This action is permanent. The Q&A will no longer be used by the AI assistant.", style: TextStyle(color: Colors.red[700])). Actions: TextButton "Cancel" (pop), ElevatedButton "Delete" with red background (style: ElevatedButton.styleFrom(backgroundColor: Colors.red)). On confirm: call `_service.deleteVerifiedAnswer(qaId: entry['id'], editorEmail: widget.userEmail)`. On success: remove entry from `_entries`, decrement `_totalCount`, pop dialog, show success SnackBar "Verified answer deleted". On error: show error SnackBar. Add a delete IconButton (Icons.delete_outline) to the edit dialog from T010 (in the dialog actions, before Cancel) that calls `_confirmDelete(entry)` after popping the edit dialog first.

**Checkpoint**: Delete with confirmation works. Entry removed from list. Linked answer_ratings.review_status reset to pending (verify via Review Queue or database).

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final verification across all stories

- [ ] T013 Verify non-admin access in `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart` — log in as non-admin user, confirm only 2 tabs visible (Chat, Knowledge). Verify no console errors.
- [ ] T014 Verify existing tab behaviors unchanged — confirm Review Queue tab (index 2) still reloads on tab switch via `_onTabChanged`, confirm Rules tab and Alerts tab function normally. Confirm flagged count badge still works.
- [ ] T015 Run quickstart.md validation — execute all curl commands from `specs/057-verified-answers-tab/quickstart.md` and all Flutter browser checks.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Backend)**: No dependencies — start immediately. T001, T002, T003 are parallel. T004 depends on T001-T003.
- **Phase 2 (US1 Browse)**: Depends on Phase 1. T005 is parallel with T006. T007 depends on T006.
- **Phase 3 (US2 Search)**: Depends on Phase 2 (T006 specifically — adds to same file).
- **Phase 4 (US3 Edit)**: Depends on Phase 2 (T006). T009 is parallel with T005/T006 work. T010 depends on T006+T009.
- **Phase 5 (US4 Delete)**: Depends on Phase 4 (T010 — adds delete button to edit dialog). T011 is parallel. T012 depends on T010+T011.
- **Phase 6 (Polish)**: Depends on all previous phases.

### User Story Dependencies

- **US1 (Browse)**: Foundation only — independent
- **US2 (Search)**: Adds to US1's tab widget file — must follow US1
- **US3 (Edit)**: Adds to US1's tab widget file — must follow US1. Service method (T009) is independent.
- **US4 (Delete)**: Adds delete button to US3's edit dialog — must follow US3. Service method (T011) is independent.

### Parallel Opportunities

```
Phase 1: T001 ║ T002 ║ T003  →  T004
Phase 2: T005 ║ T006  →  T007
Phase 3: T008 (sequential — same file as T006)
Phase 4: T009 ║ (T008 done)  →  T010
Phase 5: T011 ║ (T010 done)  →  T012
Phase 6: T013 ║ T014 ║ T015
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Backend (all 3 service functions + 3 endpoints)
2. Complete Phase 2: US1 — Browse tab with pagination
3. **STOP and VALIDATE**: Admin sees "Verified" tab, list loads, pagination works
4. Continue to US2-US4 incrementally

### Incremental Delivery

1. Phase 1 (Backend) → All endpoints ready
2. Phase 2 (US1 Browse) → Tab visible, list loads → **MVP ready**
3. Phase 3 (US2 Search) → Search bar with debounce
4. Phase 4 (US3 Edit) → Edit dialog with re-embedding
5. Phase 5 (US4 Delete) → Delete with confirmation
6. Phase 6 (Polish) → Cross-cutting verification

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- All tasks include exact file paths and function signatures
- Follow existing code patterns: review_queue_tab.dart for frontend, manuals.py for backend
- Commit after each phase checkpoint
- Backend error pattern: `raise HTTPException(status_code=X, detail={"error": "message"})`
- Audit logging pattern: `log_activity(email, "manual", "action_verb", target_id=id)` in try/except pass
- Embedding format: `"[" + ",".join(str(x) for x in embedding) + "]"`
