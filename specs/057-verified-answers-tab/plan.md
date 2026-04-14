# Implementation Plan: Verified Answers Admin Tab

**Branch**: `057-verified-answers-tab` | **Date**: 2026-04-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/057-verified-answers-tab/spec.md`

## Summary

Add a 6th admin-only tab ("Verified") to the AI Assistant screen that lets admins browse, search, edit, and delete validated Q&A pairs from the `validated_qa` table. Backend: 3 new endpoints (GET/PUT/DELETE) and 3 service functions. Frontend: 1 new tab widget, 3 service methods, TabController wiring. No database migration needed.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend)
**Storage**: Supabase (PostgreSQL) — existing `validated_qa` and `answer_ratings` tables
**Testing**: Manual verification via curl + Flutter browser
**Target Platform**: Web (Flutter PWA) + Linux server (FastAPI)
**Project Type**: Full-stack web application
**Performance Goals**: Search response <500ms for up to 1000 entries (SC-002)
**Constraints**: Single server, Ollama embedding on localhost:11434, 15GB RAM limit
**Scale/Scope**: Hundreds of validated_qa entries (low volume)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend endpoints + frontend service + screen + navigation wiring all covered |
| II. Explicit Over Automatic | PASS | Edit/delete are explicit admin actions with confirmation dialogs |
| III. Role-Based Access Control | PASS | Admin-only via `_admin_check()` on all 3 endpoints; non-admin sees 2 tabs |
| IV. Server-First File Storage | N/A | No file storage involved |
| V. Client-Side Computation | N/A | Server-side pagination is appropriate here (validated_qa has embeddings = large rows) |
| VI. Audit Everything | PASS | `log_activity()` called for edit and delete actions |
| VII. Simplicity & YAGNI | PASS | No abstractions, no soft delete, no cursor pagination — simplest approach that works |

**DB migration exclusion**: No migration needed — `validated_qa` table already exists with all columns. Justified because this feature only reads/updates/deletes existing rows.

## Project Structure

### Documentation (this feature)

```text
specs/057-verified-answers-tab/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 research
├── data-model.md        # Phase 1 data model
├── quickstart.md        # Phase 1 quickstart
├── contracts/
│   └── api-endpoints.md # Phase 1 API contracts
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── manuals.py                    # +3 endpoints, +1 Pydantic model
└── services/
    └── validated_qa_service.py       # +3 functions

frontend/lib/
├── screens/manual_assistant/
│   ├── manual_assistant_screen.dart  # Wire 6th tab
│   └── verified_answers_tab.dart     # NEW — tab widget
└── services/
    └── manual_assistant_service.dart  # +3 methods
```

## Phase 1: Backend Service Layer

### Task 1.1: `get_all_verified_answers()` in `validated_qa_service.py`

**Add after** `update_validated_rating()` (line ~274)

```python
def get_all_verified_answers(search: Optional[str] = None, limit: int = 50, offset: int = 0) -> dict:
```

- Query `supabase.table("validated_qa")` selecting: id, question_text, validated_answer, equipment_type, fault_code, validated_by, validated_at, thumbs_up_count, thumbs_down_count, is_reflagged, updated_at
- If `search` non-empty: `.ilike("question_text", f"%{search}%")`
- `.order("updated_at", desc=True).range(offset, offset + limit - 1)`
- Get total count via separate `.select("id", count="exact")` query (with same search filter)
- Return `{"items": data, "count": count}`

### Task 1.2: `update_verified_answer()` in `validated_qa_service.py`

```python
async def update_verified_answer(qa_id: str, question_text: Optional[str], validated_answer: Optional[str], editor_email: str) -> dict:
```

- Fetch existing: `supabase.table("validated_qa").select("*").eq("id", qa_id).single().execute()`
- If not found → raise `ValueError("not found")`
- Build update dict, always set `updated_at` to `datetime.now(timezone.utc).isoformat()`
- If `question_text` provided and differs from existing:
  - `embedding = await embed_single(question_text)` — may raise `EmbedderTimeoutError`
  - Format: `"[" + ",".join(str(x) for x in embedding) + "]"` (same pattern as line 138)
  - Add `question_embedding`, `question_text` to update dict
  - Re-extract: `_extract_equipment_type(question_text)`, `_extract_fault_code(question_text)`
- If `validated_answer` provided, add to update dict
- Execute update, return updated row

### Task 1.3: `delete_verified_answer()` in `validated_qa_service.py`

```python
def delete_verified_answer(qa_id: str) -> str:
```

- Fetch existing row to get `rating_id`: `supabase.table("validated_qa").select("id, rating_id").eq("id", qa_id).single().execute()`
- If not found → raise `ValueError("not found")`
- Hard-delete: `supabase.table("validated_qa").delete().eq("id", qa_id).execute()`
- Reset linked rating: `supabase.table("answer_ratings").update({"review_status": "pending"}).eq("id", rating_id).execute()`
- Return `qa_id`

## Phase 2: Backend Router

### Task 2.1: Pydantic model + 3 endpoints in `manuals.py`

**Add after** `review_answer` endpoint (line ~514), before `_admin_check()`.

**New Pydantic model:**
```python
class UpdateVerifiedAnswerRequest(BaseModel):
    question_text: Optional[str] = None
    validated_answer: Optional[str] = None
    editor_email: str
```

**GET `/manuals/verified-answers`:**
- Params: `user_email: str = Query(...)`, `search: Optional[str] = Query(None)`, `limit: int = Query(50)`, `offset: int = Query(0)`
- `_admin_check(user_email)`
- Call `validated_qa_service.get_all_verified_answers(search, limit, offset)`
- Return result dict

**PUT `/manuals/verified-answers/{qa_id}`:**
- Body: `UpdateVerifiedAnswerRequest`
- `_admin_check(request.editor_email)`
- Try: `await validated_qa_service.update_verified_answer(...)`
- Catch `ValueError` → 404, `EmbedderTimeoutError` → 504, `Exception` → 500
- `log_activity(editor_email, "manual", "edited_verified_answer", target_id=qa_id)`
- Return updated row

**DELETE `/manuals/verified-answers/{qa_id}`:**
- Params: `editor_email: str = Query(...)`
- `_admin_check(editor_email)`
- Try: `validated_qa_service.delete_verified_answer(qa_id)`
- Catch `ValueError` → 404, `Exception` → 500
- `log_activity(editor_email, "manual", "deleted_verified_answer", target_id=qa_id)`
- Return `{"status": "deleted", "id": qa_id}`

## Phase 3: Frontend Service

### Task 3.1: 3 new methods in `manual_assistant_service.dart`

**`getVerifiedAnswers()`** — pattern: `getFlaggedAnswers()` at line 336
- GET to `${AppConfig.baseUrl}/manuals/verified-answers?user_email=...&search=...&limit=...&offset=...`
- Returns `Future<Map<String, dynamic>>` with `items` (List) and `count` (int)

**`updateVerifiedAnswer()`** — pattern: `reviewAnswer()` at line 363
- PUT to `${AppConfig.baseUrl}/manuals/verified-answers/$qaId`
- Body: `{'question_text': ..., 'validated_answer': ..., 'editor_email': ...}` (omit null fields)
- Returns `Future<Map<String, dynamic>>` (updated row)

**`deleteVerifiedAnswer()`** — new DELETE pattern
- DELETE to `${AppConfig.baseUrl}/manuals/verified-answers/$qaId?editor_email=...`
- Returns `Future<Map<String, dynamic>>`

All three use `_getAuthHeaders()` for Supabase JWT.

## Phase 4: Frontend Tab Widget

### Task 4.1: New `verified_answers_tab.dart`

Follow `review_queue_tab.dart` pattern:

**State:**
- `_entries` List<Map<String, dynamic>>, `_totalCount` int
- `_loading` bool, `_loadingMore` bool, `_error` String?
- `_searchController` TextEditingController, `_searchQuery` String
- `_debounce` Timer?, `_currentRequestId` int (for cancellation)
- `_offset` int (pagination), `_limit` = 50

**`_loadEntries({bool append = false})`:**
- Increment `_currentRequestId`, capture local copy
- Call `_service.getVerifiedAnswers(userEmail, search, limit, offset)`
- Before setState, check `requestId == _currentRequestId` (stale guard)
- If append: add to `_entries`; else: replace `_entries`

**Search with debounce:**
- `_onSearchChanged(String value)`: cancel `_debounce`, start 300ms timer, reset offset to 0, call `_loadEntries()`
- Clear button: reset search, reload

**Build:**
1. Search bar (TextField with Icons.search prefix, clear suffix)
2. Summary: "${_totalCount} verified answers" + refresh IconButton
3. `Expanded` > `RefreshIndicator` > `ListView.builder`
   - Item count: `_entries.length + (_hasMore ? 1 : 0)`
   - Last item (if _hasMore): "Load More" OutlinedButton → `_loadMore()`
   - Each item: Card with question (bold, maxLines 2), answer (maxLines 2), thumbs row, onTap → `_showEditDialog(entry)`

**`_showEditDialog(entry)`:**
- AlertDialog with two TextFormFields (question, answer)
- Delete button (icon) in dialog actions → `_confirmDelete(entry)`
- Save button: disabled if either field empty
- On save: call `updateVerifiedAnswer()`, on 504 show "Embedding timed out — please try again"
- On success: replace entry in `_entries` with server response, SnackBar

**`_confirmDelete(entry)`:**
- showDialog: "Delete verified answer?" with question text preview + "This action is permanent" warning
- On confirm: call `deleteVerifiedAnswer()`, remove from `_entries`, SnackBar

## Phase 5: Wire into Main Screen

### Task 5.1: Update `manual_assistant_screen.dart`

1. Add import: `import 'verified_answers_tab.dart';`
2. Line 33: `TabController(length: _isAdmin ? 6 : 2, vsync: this)` (was 5)
3. After Alerts tab in TabBar (after line ~125):
   ```dart
   if (_isAdmin)
     Tab(
       child: Row(
         mainAxisSize: MainAxisSize.min,
         children: const [
           Icon(Icons.verified_outlined, size: 18),
           SizedBox(width: 4),
           Text('Verified'),
         ],
       ),
     ),
   ```
4. After AlertsTab in TabBarView (after line ~142):
   ```dart
   if (_isAdmin) VerifiedAnswersTab(userEmail: _userEmail),
   ```
5. Audit `_onTabChanged`: only checks `index == 2` (Review Queue) — new tab at index 5 needs no special handling. **No changes needed.**

## Complexity Tracking

No constitution violations. No complexity justifications needed.
