# Tasks: Add Verified Answer — Manual Entry

**Input**: Design documents from `/specs/059-add-verified-answer/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks are grouped by user story. This feature has 2 user stories but they share the same backend/service layer, so US2 (error handling) is integrated into US1 implementation tasks.

**Target executor**: opencode LLM — all tasks must be self-contained with exact file paths, code patterns to follow, and acceptance criteria.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Database Migration)

**Purpose**: Make `rating_id` nullable so direct admin inserts can bypass `answer_ratings`

- [ ] T001 Create migration file `supabase/migrations/20260415000000_make_rating_id_nullable.sql` with content: `ALTER TABLE validated_qa ALTER COLUMN rating_id DROP NOT NULL;` — include a comment header: `-- Make rating_id nullable to allow direct admin inserts (feature 059-add-verified-answer)`. Apply this migration to the Supabase database before proceeding.

**Checkpoint**: Verify by running: `INSERT INTO validated_qa (question_text, validated_answer, question_embedding, validated_by) VALUES ('test', 'test', '[' || array_to_string(array_fill(0::float, ARRAY[768]), ',') || ']', 'test@test.com');` — should succeed. Clean up the test row after.

---

## Phase 2: Foundational (Backend Service Layer)

**Purpose**: Add `create_verified_answer()` to the existing validated_qa_service — this is the core logic that both user stories depend on.

**⚠️ CRITICAL**: No frontend work can begin until this phase is complete.

- [ ] T002 Add `create_verified_answer()` async function to `backend/services/validated_qa_service.py`. Place it after the existing `update_verified_answer()` function (around line 342). Follow the EXACT same pattern as `review_answer()` (lines 194-206) for the insert, and `update_verified_answer()` (lines 318-324) for embedding. Implementation details:
  - **Function signature**: `async def create_verified_answer(question_text: str, validated_answer: str, editor_email: str) -> dict`
  - **Step 1**: Strip and validate both `question_text` and `validated_answer` — raise `ValueError("question and answer required")` if either is empty
  - **Step 2**: Embed the question: `embedding = await embed_single(question_text)` then format as `embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"`
  - **Step 3**: Auto-extract metadata: `equipment_type = _extract_equipment_type(question_text)` and `fault_code = _extract_fault_code(question_text)` — these helper functions already exist in the file
  - **Step 4**: Insert into `validated_qa` via Supabase: `supabase.table("validated_qa").insert({...}).execute()` with fields: `question_text`, `validated_answer`, `question_embedding: embedding_str`, `validated_by: editor_email`, `equipment_type`, `fault_code`, `source_chunks: []`, `manual_ids: []` — do NOT set `rating_id` (it will be NULL)
  - **Step 5**: Return the inserted row: `return result.data[0]`
  - **Imports needed**: `embed_single` and `EmbedderTimeoutError` are already imported at the top of the file — verify, do not duplicate

**Checkpoint**: The function should be importable and callable. Proceed to Phase 3.

---

## Phase 3: User Story 1 — Admin Creates a Verified Q&A Pair (Priority: P1) 🎯 MVP

**Goal**: Admin taps FAB on Verified Answers tab → fills dialog → entry appears at top of list

**Independent Test**: Open Manual Assistant → Verified Answers tab → tap FAB → fill question + answer → tap Add → entry appears at top of list with correct question/answer text

### Implementation for User Story 1

- [ ] T003 [US1] Add `POST /manuals/verified-answers` endpoint to `backend/routers/manuals.py`. Place it near the existing `PUT /manuals/verified-answers/{qa_id}` endpoint (around line 541). Follow the EXACT same pattern as `update_verified_answer` endpoint. Implementation details:
  - **Request model** (add near other Pydantic models at top of file, around line 36): `class CreateVerifiedAnswerRequest(BaseModel):` with fields `question_text: str`, `validated_answer: str`, `editor_email: str`
  - **Endpoint decorator**: `@router.post("/manuals/verified-answers")`
  - **Function**: `async def create_verified_answer(request: CreateVerifiedAnswerRequest, background_tasks: BackgroundTasks):`
  - **Step 1**: Admin check: `try: _admin_check(request.editor_email) except: raise HTTPException(status_code=403, detail={"error": "admin_required"})`
  - **Step 2**: Validate non-empty: if `not request.question_text.strip() or not request.validated_answer.strip()` → raise HTTPException(status_code=422, detail={"error": "question and answer required"})
  - **Step 3**: Call service: `result = await validated_qa_service.create_verified_answer(question_text=request.question_text.strip(), validated_answer=request.validated_answer.strip(), editor_email=request.editor_email)`
  - **Step 4**: Log activity: `background_tasks.add_task(log_activity, user_email=request.editor_email, category="manual_assistant", action="created_verified_answer", details={"qa_id": result.get("id"), "question_preview": request.question_text[:100]})` — matches existing logging pattern in the file
  - **Step 5**: `return result`
  - **Error handling**: Wrap the service call in try/except matching the `update_verified_answer` endpoint pattern: `except ValueError: raise HTTPException(422, ...)`, `except EmbedderTimeoutError: raise HTTPException(504, detail={"error": "embedding_timeout"})`, `except Exception: raise HTTPException(500, detail={"error": "create_failed"})`
  - **IMPORTANT**: The endpoint path `/manuals/verified-answers` must NOT conflict with the existing `GET /manuals/verified-answers` (line 523) or `PUT /manuals/verified-answers/{qa_id}` (line 541). FastAPI distinguishes by HTTP method, so POST is fine at the same path.
  - **Verify** `EmbedderTimeoutError` is already imported at line 22: `from services.ollama_embedder import embed_single, embed_many, EmbedderTimeoutError` — do not add a duplicate import

- [ ] T004 [P] [US1] Add `createVerifiedAnswer()` method to `frontend/lib/services/manual_assistant_service.dart`. Place it after the existing `updateVerifiedAnswer()` method (around line 627). Clone the EXACT pattern of `updateVerifiedAnswer()` with these changes:
  - **Method signature**: `Future<Map<String, dynamic>> createVerifiedAnswer({required String questionText, required String validatedAnswer, required String editorEmail}) async`
  - **HTTP method**: `http.post` (not `http.put`)
  - **URL**: `Uri.parse('${AppConfig.baseUrl}/manuals/verified-answers')` (no ID in path)
  - **Body**: `jsonEncode({'question_text': questionText, 'validated_answer': validatedAnswer, 'editor_email': editorEmail})`
  - **Headers**: Same as `updateVerifiedAnswer()` — `Content-Type: application/json` + Bearer token from `Supabase.instance.client.auth.currentSession?.accessToken`
  - **Response handling**: Same status code checks as `updateVerifiedAnswer()`:
    - 200 → return `jsonDecode(res.body) as Map<String, dynamic>`
    - 403 → throw `Exception('Admin access required')`
    - 422 → throw `Exception('Question and answer are required')`
    - 504 → throw `Exception('Embedding timed out — please try again')` (EXACT string — matches existing pattern)
    - else → throw `Exception('Failed to create verified answer')`
  - **No timeout override needed** — use default http timeout (matches existing pattern)

- [ ] T005 [US1] Add FAB, add dialog, and save method to `frontend/lib/screens/manual_assistant/verified_answers_tab.dart`. Three changes to this file:

  **Change A — Wrap body in Stack to add FAB**: The current `build()` method (around line 265) returns a `Column`. Wrap it in a `Stack` and add a `Positioned` FAB:
  ```dart
  return Stack(
    children: [
      Column(
        children: [
          // ... ALL existing Column children unchanged ...
        ],
      ),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton(
          onPressed: _showAddDialog,
          tooltip: 'Add verified answer',
          child: const Icon(Icons.add),
        ),
      ),
    ],
  );
  ```

  **Change B — Add `_showAddDialog()` method**: Place it after `_deleteEntry()` (around line 262). Clone the structure of `_showEditDialog()` (lines 113-165) with these differences:
  - Title: `'Add Verified Answer'` (not `'Edit Verified Answer'`)
  - Controllers: `TextEditingController()` with no initial text (not pre-filled from entry)
  - `autofocus: true` on the question TextFormField
  - NO delete IconButton in actions (only Cancel + Add buttons)
  - On submit: validate `questionCtrl.text.trim().isEmpty || answerCtrl.text.trim().isEmpty` → return (do nothing). Otherwise `Navigator.pop(context)` then `await _saveNewEntry(questionCtrl.text.trim(), answerCtrl.text.trim())`
  - Button text: `'Add'` (not `'Save'`)

  **Change C — Add `_saveNewEntry()` method**: Place it after `_showAddDialog()`. Clone the pattern of `_saveEdit()` (lines 167-198) with these differences:
  - **Signature**: `Future<void> _saveNewEntry(String questionText, String answerText) async`
  - **Service call**: `await _service.createVerifiedAnswer(questionText: questionText, validatedAnswer: answerText, editorEmail: widget.userEmail)`
  - **On success**: `setState(() { _entries.insert(0, result); _totalCount++; })` — insert at TOP of list (not update in place)
  - **Snackbar text**: `'Verified answer added'` (not `'Verified answer updated'`)
  - **Error handling**: EXACT same pattern as `_saveEdit()`:
    ```dart
    final message = e.toString().contains('timed out')
        ? 'Embedding timed out — please try again'
        : 'Failed to add: $e';
    ```

**Checkpoint**: At this point, the full flow should work: FAB → dialog → add → entry appears at top of list. Test with the quickstart.md steps.

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: Final verification and cleanup

- [ ] T006 Run quickstart.md validation: verify the full flow end-to-end per `specs/059-add-verified-answer/quickstart.md` — migration applied, backend endpoint responds to curl, Flutter FAB visible, dialog works, entry appears at top of list, error handling shows correct timeout message
- [ ] T007 Verify no regressions: confirm existing edit dialog (`_showEditDialog`), delete (`_deleteEntry`), search, and pagination all still work unchanged in `verified_answers_tab.dart`. Confirm existing `GET /manuals/verified-answers` and `PUT /manuals/verified-answers/{qa_id}` endpoints still work.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Migration)**: No dependencies — start immediately
- **Phase 2 (Backend Service)**: Depends on Phase 1 (migration must be applied)
- **Phase 3 (User Story 1)**: Depends on Phase 2 (service function must exist)
  - T003 (router endpoint) depends on T002 (service function)
  - T004 (Flutter service) can run in PARALLEL with T003 (different codebase layer)
  - T005 (Flutter UI) depends on T004 (needs `createVerifiedAnswer()` method)
- **Phase 4 (Polish)**: Depends on all Phase 3 tasks

### User Story Dependencies

- **User Story 1 (P1)**: Requires Phase 1 + Phase 2 complete. This is the entire feature.
- **User Story 2 (P2)**: Error handling — integrated into US1 tasks (T003 error handling, T005 Change C error display). No separate tasks needed.

### Parallel Opportunities

```
T003 (backend endpoint) ──┐
                          ├── T005 (Flutter UI) → T006, T007
T004 (Flutter service) ───┘
```

T003 and T004 can be developed in parallel since they touch different codebases (Python vs Dart). T005 depends on T004 completing first.

---

## Implementation Strategy

### MVP (Complete Feature)

This feature is small enough that US1 = the complete feature:

1. T001: Apply migration
2. T002: Add service function
3. T003 + T004 (parallel): Backend endpoint + Flutter service method
4. T005: Flutter UI (FAB + dialog + save)
5. T006 + T007: Verify and regression check

### Key Files Modified

| File | Change Type | Task |
|------|-------------|------|
| `supabase/migrations/20260415000000_make_rating_id_nullable.sql` | NEW | T001 |
| `backend/services/validated_qa_service.py` | ADD function | T002 |
| `backend/routers/manuals.py` | ADD endpoint + model | T003 |
| `frontend/lib/services/manual_assistant_service.dart` | ADD method | T004 |
| `frontend/lib/screens/manual_assistant/verified_answers_tab.dart` | ADD FAB + dialog + method | T005 |

---

## Notes

- Every task references the EXACT existing code to clone from (function names, line numbers, patterns)
- Error messages must be EXACT strings — `'Embedding timed out — please try again'` (matches existing)
- The `_admin_check()` helper already exists in `manuals.py` — do not recreate
- `log_activity` is already imported in `manuals.py` — do not add duplicate import
- `widget.userEmail` is an existing field on the widget — use it as-is
- Do NOT modify any existing endpoints, methods, or UI behavior
- Commit after each task or logical group
