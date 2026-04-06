# Tasks: AI Arabic/English Document Expert

**Input**: Design documents from `/specs/027-ai-document-expert/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api.md

**Tests**: Not explicitly requested — no test tasks generated.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

---

## Phase 1: Setup

**Purpose**: No setup needed — all target files already exist except one new widget file.

_(No tasks — project structure already in place)_

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Backend endpoint + health check + frontend service methods that ALL user stories depend on.

**CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T001 Add `DocumentExpertRequest` model, `_build_document_expert_prompt()` function, and `POST /ai/document-expert` endpoint to `backend/routers/ai_assist.py`
- [ ] T002 Add `GET /ai/health` endpoint to `backend/routers/ai_assist.py`
- [ ] T003 [P] Add `documentExpert()` and `checkAiHealth()` methods to `frontend/lib/services/ai_assist_service.dart`

**Checkpoint**: Backend endpoint responds to curl, frontend service can call both endpoints.

---

## Phase 3: User Story 1 - Improve Draft Letter Text (Priority: P1) MVP

**Goal**: User selects "تحسين وتنسيق" (Improve), AI rewrites text in formal Arabic, user applies result to editor.

**Independent Test**: Type Arabic text in editor → expand AI panel → click Improve → see result → click Apply → editor updated.

### Implementation for User Story 1

- [ ] T004 [US1] Create `frontend/lib/widgets/ai_document_expert_widget.dart` — collapsible panel with 6 action buttons, AR/EN toggle, instructions field, result area, Apply/Discard buttons, loading state
- [ ] T005 [US1] Embed `AiDocumentExpertWidget` in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart` below the editor iframe, wiring GET_HTML/SET_HTML postMessage for content extraction and injection

**Checkpoint**: Full improve flow works end-to-end — type text, improve, apply, editor updated.

---

## Phase 4: User Story 2 - Correct Grammar and Spelling (Priority: P1)

**Goal**: User selects "تصحيح نحوي", AI fixes grammar/spelling only with minimal rewrites.

**Independent Test**: Enter text with grammar errors → select Correct → verify corrections without structural changes.

### Implementation for User Story 2

_(No additional tasks — the "correct" action is already handled by T001 backend prompt and T004 widget action button. This story is functional once Phase 2 + Phase 3 are complete.)_

**Checkpoint**: Correct action produces grammar-only fixes distinct from Improve output.

---

## Phase 5: User Story 3 - Generate Letter from Notes (Priority: P2)

**Goal**: User enters notes in instructions field, selects "توليد من ملاحظات", AI generates complete letter body.

**Independent Test**: Enter brief notes in instructions field → select Generate → verify complete letter body generated.

### Implementation for User Story 3

_(No additional tasks — the "generate" action is handled by T001 backend prompt variant and T004 widget. The widget already includes the instructions field. Validation in T001 allows empty html_content for generate action.)_

**Checkpoint**: Generate action produces a full letter from notes even when editor is empty.

---

## Phase 6: User Story 4 - Translate Between Arabic and English (Priority: P2)

**Goal**: User toggles to target language, selects "ترجمة", AI translates maintaining formal register.

**Independent Test**: Enter Arabic text → set target to EN → Translate → verify formal English output.

### Implementation for User Story 4

_(No additional tasks — translate action handled by T001 prompt variant and T004 AR/EN toggle + action button.)_

**Checkpoint**: Translate produces correct target language output; AR→EN and EN→AR both work.

---

## Phase 7: User Story 5 - Graceful Degradation When AI Unavailable (Priority: P3)

**Goal**: When Ollama is offline, buttons are disabled with tooltip.

**Independent Test**: Stop Ollama → expand AI panel → verify buttons disabled with Arabic tooltip.

### Implementation for User Story 5

_(No additional tasks — T002 provides health check endpoint, T003 provides checkAiHealth() service method, T004 widget calls health check on panel expand and disables buttons when unavailable.)_

**Checkpoint**: Buttons disabled with "خدمة الذكاء الاصطناعي غير متاحة" tooltip when Ollama is down.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [ ] T006 Edge case handling: empty editor validation, empty AI response handling, request cancellation on new action — verify in `backend/routers/ai_assist.py` and `frontend/lib/widgets/ai_document_expert_widget.dart`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 2)**: No dependencies — start immediately
  - T001 and T002 modify same file (sequential)
  - T003 can run in parallel with T001/T002 (different file)
- **User Story 1 (Phase 3)**: Depends on T001, T002, T003
  - T004 and T005 are sequential (T005 embeds widget from T004)
- **User Stories 2-5 (Phases 4-7)**: No additional tasks — functional after Phase 3
- **Polish (Phase 8)**: After all stories complete

### Execution Order

```
T001 → T002 (same file, sequential)
T003 (parallel with T001/T002)
T004 (after T001, T002, T003)
T005 (after T004)
T006 (after T005)
```

### Parallel Opportunities

```
# Batch 1: Backend + Frontend service (parallel)
T001 + T002 (backend, sequential) || T003 (frontend service)

# Batch 2: Widget (after batch 1)
T004

# Batch 3: Integration (after T004)
T005

# Batch 4: Polish
T006
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001 + T002 + T003 (foundational)
2. Complete T004 + T005 (widget + integration)
3. **STOP and VALIDATE**: Test improve flow end-to-end
4. All 6 actions work immediately — stories 2-5 require no additional code

### Why So Few Tasks?

This feature is architecturally simple: one backend endpoint with action-based prompt switching, one frontend service method, one widget, one integration point. The 6 AI actions differ only in their prompt text (handled by `_build_document_expert_prompt()`), not in code paths. The widget renders all 6 buttons identically. Therefore, completing the foundational backend + widget covers all user stories simultaneously.

---

## Task Details

### T001: Backend Document Expert Endpoint

**File**: `backend/routers/ai_assist.py`
**What to add**:
- `DocumentExpertAction` string enum: `improve`, `correct`, `generate`, `translate`, `concise`, `elaborate`
- `DocumentExpertRequest(BaseModel)` with fields: `action: DocumentExpertAction`, `html_content: Optional[str]`, `target_language: str = "ar"`, `instructions: Optional[str]`
- `_build_document_expert_prompt(action, html_content, target_language, instructions) -> str` — builds the appropriate prompt based on action type with shared base persona
- `POST /ai/document-expert` async endpoint — validates input, calls Ollama, returns `{"html_content": "<result>"}`
**Signatures**:
```python
class DocumentExpertAction(str, Enum):
    improve = "improve"
    correct = "correct"
    generate = "generate"
    translate = "translate"
    concise = "concise"
    elaborate = "elaborate"

class DocumentExpertRequest(BaseModel):
    action: DocumentExpertAction
    html_content: Optional[str] = None
    target_language: str = "ar"
    instructions: Optional[str] = None

def _build_document_expert_prompt(action: str, html_content: Optional[str], target_language: str, instructions: Optional[str]) -> str: ...

@router.post("/ai/document-expert")
async def document_expert(request: DocumentExpertRequest): ...
```
**Input/Output**: Request body → JSON `{"html_content": "..."}` or HTTP 422/502/503
**Dependencies**: None
**Acceptance**: `curl -X POST localhost:8000/api/ai/document-expert -H "Content-Type: application/json" -d '{"action":"improve","html_content":"<p>نص</p>","target_language":"ar"}'` returns `{"html_content":"<p>...</p>"}`

### T002: Backend Health Check Endpoint

**File**: `backend/routers/ai_assist.py`
**What to add**:
- `GET /ai/health` async endpoint — pings `http://localhost:11434/api/tags` with 5s timeout, returns `{"available": true/false}`
**Signatures**:
```python
@router.get("/ai/health")
async def ai_health(): ...
```
**Input/Output**: No input → `{"available": true}` or `{"available": false}`
**Dependencies**: T001 (same file, add after)
**Acceptance**: `curl localhost:8000/api/ai/health` returns `{"available": true}` when Ollama is running

### T003: Frontend Service Methods

**File**: `frontend/lib/services/ai_assist_service.dart`
**What to add**:
- `documentExpert()` method — calls `POST /ai/document-expert`, returns HTML string
- `checkAiHealth()` method — calls `GET /ai/health`, returns bool
**Signatures**:
```dart
Future<String> documentExpert({
  required String action,
  String? htmlContent,
  String targetLanguage = 'ar',
  String? instructions,
}) async { ... }

Future<bool> checkAiHealth() async { ... }
```
**Input/Output**: Parameters → HTML string or throws Exception; no params → bool
**Dependencies**: None (can be written in parallel with T001/T002)
**Acceptance**: Methods compile, handle 200/422/502/503 status codes, 65s timeout

### T004: AI Document Expert Widget

**File**: `frontend/lib/widgets/ai_document_expert_widget.dart` (NEW)
**What to create**: A `StatefulWidget` with:
- Collapsible panel (ExpansionTile or similar)
- 6 action buttons in a Wrap: تحسين وتنسيق, تصحيح نحوي, توليد من ملاحظات, ترجمة, تلخيص, توسيع
- AR/EN toggle button (ToggleButtons or SegmentedButton)
- Optional instructions TextField
- Read-only result area (SelectableText or similar) showing AI HTML output as rendered text
- "تطبيق" (Apply) and "تجاهل" (Discard) buttons below result
- Loading indicator (CircularProgressIndicator) during request
- Disabled state with tooltip "خدمة الذكاء الاصطناعي غير متاحة" when AI unavailable
- Health check call on first panel expand, cached via bool flag
- Request cancellation when new action triggered
**Signatures**:
```dart
class AiDocumentExpertWidget extends StatefulWidget {
  final Future<String> Function() onGetHtml;
  final void Function(String html) onApplyHtml;
  const AiDocumentExpertWidget({super.key, required this.onGetHtml, required this.onApplyHtml});
  @override
  State<AiDocumentExpertWidget> createState() => _AiDocumentExpertWidgetState();
}

class _AiDocumentExpertWidgetState extends State<AiDocumentExpertWidget> { ... }
```
**Input/Output**: `onGetHtml` callback to extract editor HTML; `onApplyHtml` callback to inject result
**Dependencies**: T003 (uses AiAssistService)
**Acceptance**: Widget renders, all 6 buttons visible, AR/EN toggle works, loading state shows, result area displays, Apply/Discard functional

### T005: Integration into Letter Form

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**What to modify**:
- Import `AiDocumentExpertWidget`
- Add the widget below the editor iframe in the build tree
- Wire `onGetHtml` to existing `GET_HTML` postMessage + Completer pattern
- Wire `onApplyHtml` to send `SET_HTML:<html>` postMessage to iframe
**Signatures**: No new classes — modifications to existing `_LetterFormTabV2State` build method
**Dependencies**: T004
**Acceptance**: AI panel appears below editor in letter form; clicking Apply updates editor content

### T006: Edge Case Polish

**Files**: `backend/routers/ai_assist.py`, `frontend/lib/widgets/ai_document_expert_widget.dart`
**What to verify/fix**:
- Backend: 422 when `html_content` empty for improve/correct/translate/concise/elaborate actions
- Backend: empty Ollama response returns 502
- Frontend: empty editor shows snackbar "يرجى إدخال نص أولاً" for non-generate actions
- Frontend: new action cancels pending request (cancel the http client or ignore stale response)
- Frontend: malformed/empty AI response shows error snackbar
**Dependencies**: T005
**Acceptance**: All edge cases from spec handled gracefully

---

## Implementation Prompts

--- IMPLEMENTATION PROMPT T001 ---
You are an expert Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/ai_assist.py
Task: Add a document expert endpoint to the existing AI assist router. Add a DocumentExpertAction enum (str, Enum) with values: improve, correct, generate, translate, concise, elaborate. Add a DocumentExpertRequest(BaseModel) with fields: action (DocumentExpertAction), html_content (Optional[str], default None), target_language (str, default "ar"), instructions (Optional[str], default None). Add a _build_document_expert_prompt() function that builds prompts for each action. The base system prompt for ALL actions is: "أنت خبير في كتابة المراسلات الرسمية الحكومية باللغة العربية الفصحى. أنت متخصص في دواوين الحكومة الكويتية ومراسلات الطيران المدني." Each action adds specific instructions: improve = rewrite in expert formal style, fix grammar, improve structure, maintain meaning; correct = fix grammar and spelling only, minimal rewrites, preserve structure; generate = write a complete professional letter body from the provided notes/instructions; translate = translate to the target language maintaining formal register; concise = shorten while keeping all key points; elaborate = expand with formal governmental phrasing. All prompts MUST end with: "أعد فقط نص المستند بصيغة HTML. لا تضف أي مقدمة أو شرح." (Return only the document HTML text. No preamble or explanation.) If target_language is "en", add instruction to write in formal English. If instructions are provided, append them. Add the POST /ai/document-expert endpoint following the exact same pattern as the existing suggest_description endpoint (httpx.AsyncClient, OLLAMA_URL, OLLAMA_MODEL, stream: False, same error handling). Validate: for actions other than "generate", html_content must be non-empty (raise 422). Use the existing _strip_preamble() function on the response. Return {"html_content": stripped_result}.

Signatures required:
- class DocumentExpertAction(str, Enum) with 6 values
- class DocumentExpertRequest(BaseModel) with 4 fields
- def _build_document_expert_prompt(action: str, html_content: Optional[str], target_language: str, instructions: Optional[str]) -> str
- @router.post("/ai/document-expert") async def document_expert(request: DocumentExpertRequest)

Constraints: Follow the exact same code style as existing endpoints in this file. Use the same OLLAMA_URL, OLLAMA_MODEL, OLLAMA_TIMEOUT constants. Import Enum from enum module. Same httpx error handling pattern (ConnectError, ConnectTimeout → 503; ReadTimeout → 503; non-200 → 502). Do not modify existing endpoints or functions.

Acceptance criteria: The endpoint accepts POST requests with action/html_content/target_language/instructions, calls Ollama with the appropriate prompt, strips preamble, and returns {"html_content": "..."}.
--- END PROMPT T001 ---

--- IMPLEMENTATION PROMPT T002 ---
You are an expert Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/ai_assist.py
Task: Add a GET /ai/health endpoint to the existing AI assist router. This endpoint pings Ollama's /api/tags endpoint (http://localhost:11434/api/tags) with a 5-second timeout. If it gets a 200 response, return {"available": true}. If any exception occurs (ConnectError, ConnectTimeout, ReadTimeout, any other), return {"available": false}. This endpoint should NEVER raise an HTTPException — it always returns 200 with the boolean.

Signatures required:
- @router.get("/ai/health") async def ai_health()

Constraints: Use httpx.AsyncClient with timeout=5.0. Same code style as existing endpoints. Add after the document_expert endpoint. Do not modify existing endpoints.

Acceptance criteria: GET /ai/health returns {"available": true} when Ollama is running, {"available": false} when it's not. Never returns an error status code.
--- END PROMPT T002 ---

--- IMPLEMENTATION PROMPT T003 ---
You are an expert Dart/Flutter developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/services/ai_assist_service.dart
Task: Add two new methods to the existing AiAssistService class: documentExpert() and checkAiHealth(). The documentExpert() method calls POST /ai/document-expert with action, htmlContent, targetLanguage, and instructions. It returns the html_content string from the response. The checkAiHealth() method calls GET /ai/health and returns the "available" boolean from the response.

Signatures required:
```dart
Future<String> documentExpert({
  required String action,
  String? htmlContent,
  String targetLanguage = 'ar',
  String? instructions,
}) async { ... }

Future<bool> checkAiHealth() async { ... }
```

Constraints: Follow the exact same pattern as existing suggestDescription() method — same imports (http, dart:convert, dart:async, config.dart), same AppConfig.baseUrl usage, same error handling (503 → "AI service unavailable", 502 → "AI error", timeout 65 seconds). For checkAiHealth(), use a 10-second timeout, return false on any exception (TimeoutException, FormatException, etc.) — never throw. The body for documentExpert should include: action, html_content (only if not null), target_language, instructions (only if not null).

Acceptance criteria: Both methods compile, documentExpert returns HTML string on success and throws on error, checkAiHealth returns bool and never throws.
--- END PROMPT T003 ---

--- IMPLEMENTATION PROMPT T004 ---
You are an expert Dart/Flutter developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/widgets/ai_document_expert_widget.dart (NEW FILE)
Task: Create a StatefulWidget called AiDocumentExpertWidget that provides a collapsible AI document expert panel. The widget takes two callbacks: onGetHtml (Future<String> Function() — extracts current editor HTML) and onApplyHtml (void Function(String html) — injects HTML back into editor).

The widget layout (top to bottom inside an ExpansionTile or similar collapsible):
1. Row of 6 action buttons (Wrap widget for responsive layout): "تحسين وتنسيق", "تصحيح نحوي", "توليد من ملاحظات", "ترجمة", "تلخيص", "توسيع". Map to action strings: improve, correct, generate, translate, concise, elaborate. Use OutlinedButton or ElevatedButton.
2. AR/EN toggle: Two ToggleButtons or a SegmentedButton — "العربية" / "English". State: selectedLanguage (default "ar").
3. Optional instructions TextField with label "تعليمات إضافية (اختياري)" and max 1000 chars.
4. Result area: Visible only when result is available. Shows the AI HTML result as rendered text (use SelectableText.rich or just SelectableText showing the raw HTML — the user reviews before applying). Below it, two buttons: "تطبيق" (Apply, primary) and "تجاهل" (Discard, outlined).
5. Loading: When _isLoading is true, show CircularProgressIndicator centered, hide action buttons.

Behavior:
- On first panel expand: call AiAssistService().checkAiHealth(). Cache result in _isAvailable bool. If false, disable all action buttons with Tooltip "خدمة الذكاء الاصطناعي غير متاحة".
- On action button press: call widget.onGetHtml() to get editor HTML. For non-generate actions, if HTML is empty/only whitespace, show SnackBar "يرجى إدخال نص أولاً" and return. Then call AiAssistService().documentExpert(action: action, htmlContent: html, targetLanguage: selectedLanguage, instructions: instructionsController.text.isEmpty ? null : instructionsController.text). Show loading during call. On success, set _resultHtml. On error, show SnackBar with error message.
- On "تطبيق" (Apply): call widget.onApplyHtml(_resultHtml!), clear result.
- On "تجاهل" (Discard): clear _resultHtml.
- On new action while loading: set a flag to ignore the stale response (simple: increment a request counter, check it on response).

Signatures required:
```dart
class AiDocumentExpertWidget extends StatefulWidget {
  final Future<String> Function() onGetHtml;
  final void Function(String html) onApplyHtml;
  const AiDocumentExpertWidget({super.key, required this.onGetHtml, required this.onApplyHtml});
  @override
  State<AiDocumentExpertWidget> createState() => _AiDocumentExpertWidgetState();
}
```

Constraints: Import only: material.dart, ai_assist_service.dart. Use RTL-friendly layout (Directionality.of(context) or explicit textDirection where needed). Arabic labels for all UI elements. Follow standard Flutter widget patterns. No external packages beyond Flutter Material.

Acceptance criteria: Widget compiles, renders collapsible panel with 6 buttons + AR/EN toggle + instructions field + result area + Apply/Discard. Health check fires on first expand. Loading state shows during AI call. Apply calls onApplyHtml, Discard clears result.
--- END PROMPT T004 ---

--- IMPLEMENTATION PROMPT T005 ---
You are an expert Dart/Flutter developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: Embed the AiDocumentExpertWidget into the letter form, below the existing editor iframe. Wire the two callbacks:

1. onGetHtml: Use the existing pattern in this file — create a Completer<String>, send 'GET_HTML' postMessage to the iframe contentWindow, and return the Completer's future with a 2-second timeout. The existing code already has this pattern with _htmlCompleter — reuse or follow the same approach. The existing message listener parses "EDITOR_HTML:<html>" responses.

2. onApplyHtml: Send 'SET_HTML:<html>' postMessage to the iframe contentWindow. This follows the existing SET_HTML pattern already used in this file for initial content loading.

Add the import for AiDocumentExpertWidget at the top of the file. Place the widget in the build tree after the editor Container (the one containing the HtmlElementView) but before any existing buttons or spacing below.

Signatures required: No new classes — modify the existing build method of _LetterFormTabV2State.

Constraints: Do not change the existing editor iframe, postMessage protocol, or message listener. Only add the widget and wire its callbacks. Minimal changes to existing code. If the GET_HTML completer pattern needs to be extracted into a reusable method, do so. Import the widget file.

Acceptance criteria: The AI panel appears below the editor in the letter form. Clicking an action extracts editor HTML via postMessage. Clicking Apply injects the result back into the editor via postMessage.
--- END PROMPT T005 ---

--- IMPLEMENTATION PROMPT T006 ---
You are an expert Dart/Flutter and Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python + Dart
Files: backend/routers/ai_assist.py, frontend/lib/widgets/ai_document_expert_widget.dart
Task: Verify and fix edge case handling:

Backend (ai_assist.py):
- The document_expert endpoint MUST return 422 with detail "html_content is required for this action" when html_content is None or empty string for actions: improve, correct, translate, concise, elaborate. The "generate" action should allow empty html_content.
- If Ollama returns an empty response after stripping preamble, return 502 with "AI model returned an empty response".

Frontend (ai_document_expert_widget.dart):
- Before calling documentExpert for non-generate actions, check if the HTML from onGetHtml is empty or contains only whitespace/empty HTML tags (e.g., "<p><br></p>"). If so, show SnackBar "يرجى إدخال نص أولاً" and do not call the service.
- When a new action is triggered while a previous request is pending, the previous response should be ignored (use an incrementing request counter: _requestId++, capture id before await, check _requestId == id after await, if not equal discard result silently).
- On any exception from documentExpert(), show SnackBar with the exception message and set _isLoading = false.

Constraints: Minimal changes — only add missing validation and error handling. Do not restructure existing code.

Acceptance criteria: Empty editor → shows snackbar for non-generate actions. Rapid action switching → only latest result displayed. Ollama errors → user-friendly snackbar. Backend validates html_content correctly per action type.
--- END PROMPT T006 ---
