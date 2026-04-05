# Tasks: AI-Assisted Work Order Description

**Input**: Design documents from `/specs/020-ai-wo-description/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story. Tasks are written for LLM implementation — each task contains all context needed to execute without referencing other documents.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `backend/` (FastAPI Python)
- **Frontend**: `frontend/lib/` (Flutter Dart)

---

## Phase 1: Setup

**Purpose**: No new project initialization needed. Existing project structure is used. This phase registers the new router.

- [x] T001 Register the new `ai_assist` router in `backend/main.py`. Add `ai_assist` to the existing router import line: `from routers import ..., ai_assist`. Then add `app.include_router(ai_assist.router, prefix="/api")` after the existing `include_router` calls. Do NOT modify any other lines. The router file does not exist yet — this registration will be satisfied by T002.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the backend endpoint that all frontend user stories depend on.

**⚠️ CRITICAL**: The Flutter UI cannot call the AI service until this phase is complete.

- [x] T002 Create the FastAPI router file `backend/routers/ai_assist.py` with the following:

  **Imports**: `fastapi` (APIRouter, HTTPException), `pydantic` (BaseModel), `typing` (Optional), `httpx`.

  **Pydantic model** `AiSuggestRequest`:
  - `title: str` (required, must be non-empty after strip)
  - `location: Optional[str] = None`
  - `type: Optional[str] = None`

  **Constants**:
  - `OLLAMA_URL = "http://localhost:11434/api/generate"`
  - `OLLAMA_MODEL = "gemma4:e2b"`
  - `OLLAMA_TIMEOUT = 60.0`

  **Preamble stripping function** `_strip_preamble(text: str) -> str`:
  - Split text into lines
  - Drop leading lines (case-insensitive) starting with: "Here", "Sure", "Of course", "Certainly", "Below", "I'd", "I would"
  - Also drop empty lines at the start after stripping
  - Rejoin remaining lines with `\n`
  - If result is empty after stripping, return original text (safety net)

  **Prompt builder function** `_build_prompt(title: str, location: Optional[str], type: Optional[str]) -> str`:
  - Build a prompt like: `"Write a professional 2-4 sentence work order description for the following:\nTitle: {title}\n"` 
  - Append `"Location: {location}\n"` only if location is non-empty
  - Append `"Type: {type}\n"` only if type is non-empty
  - Append `"\nProvide only the description text. Do not include any preamble, greeting, or commentary."`

  **Endpoint** `POST /ai/suggest`:
  - Validate `request.title.strip()` is non-empty, raise `HTTPException(422)` if empty
  - Build prompt using `_build_prompt`
  - Use `httpx.AsyncClient(timeout=OLLAMA_TIMEOUT)` to POST to `OLLAMA_URL` with JSON body: `{"model": OLLAMA_MODEL, "prompt": prompt, "stream": False}`
  - Catch `httpx.ConnectError`, `httpx.ConnectTimeout` → raise `HTTPException(503, detail="AI service is currently unavailable")`
  - Catch `httpx.ReadTimeout` → raise `HTTPException(503, detail="AI service timed out")`
  - If Ollama returns non-200 → raise `HTTPException(502, detail="AI model error")`
  - Parse JSON response, extract `response` field
  - Apply `_strip_preamble()` to the response text
  - If result is empty → raise `HTTPException(502, detail="AI model returned an empty response")`
  - Return `{"description": stripped_text}`
  - Catch any other `Exception` → raise `HTTPException(503, detail="AI service is currently unavailable")`

  **Router**: `router = APIRouter()`

**Checkpoint**: After T001 + T002, verify with: `curl -X POST http://localhost:8000/api/ai/suggest -H "Content-Type: application/json" -d '{"title":"Broken AC in Room 101","location":"Building A","type":"HVAC"}'` — should return a JSON object with a `description` field. Stopping Ollama and retrying should return HTTP 503.

---

## Phase 3: User Story 1 — Generate Description for New Work Order (Priority: P1) 🎯 MVP

**Goal**: User creates a new work order, fills in title/location/type, taps Suggest, and the AI-generated description fills the empty description field directly.

**Independent Test**: Create a new work order, enter a title, tap Suggest → description field populates with AI text. No bottom sheet should appear.

### Implementation for User Story 1

- [x] T003 [P] [US1] Create the Flutter service file `frontend/lib/services/ai_assist_service.dart` with the following:

  **Imports**: `dart:convert`, `package:http/http.dart as http`, `../config.dart`.

  **Class** `AiAssistService` (stateless, no constructor state):

  **Method** `Future<String> suggestDescription({required String title, String? location, String? type}) async`:
  - POST to `Uri.parse('${AppConfig.baseUrl}/ai/suggest')`
  - Headers: `{'Content-Type': 'application/json'}`
  - Body: `jsonEncode({'title': title, if (location != null && location.isNotEmpty) 'location': location, if (type != null && type.isNotEmpty) 'type': type})`
  - Wrap the call in `.timeout(const Duration(seconds: 65))` to give the backend's 60s timeout room
  - If `res.statusCode == 200`: parse JSON, return `data['description'] as String`
  - If `res.statusCode == 503`: throw `Exception('AI service is currently unavailable. Please try again later.')`
  - If `res.statusCode == 502`: throw `Exception('AI could not generate a description. Please try again.')`
  - On `TimeoutException`: throw `Exception('Request timed out. Please try again.')`
  - On any other error: throw `Exception('Failed to get AI suggestion.')`

- [x] T004 [US1] Integrate the Suggest button into the work order form in `frontend/lib/screens/Work_Orders/add_work_order.dart`. This is the core UI task. Follow these steps precisely:

  **1. Add import** at the top of the file:
  `import '../../services/ai_assist_service.dart';`

  **2. Add state variables** in the `_AddWorkOrderScreenState` class (near the existing state vars around line 89):
  ```dart
  bool _aiLoading = false;
  final AiAssistService _aiAssistService = AiAssistService();
  ```

  **3. Add the `_suggestDescription()` method** in the state class (before the `build` method). Logic:
  - Set `_aiLoading = true` via `setState`
  - In a try block: call `_aiAssistService.suggestDescription(title: titleController.text.trim(), location: locationController.text.trim(), type: selectedType)` — note: `selectedType` is the current type dropdown value, check the actual variable name in the file; `locationController` is the location text controller, check actual name
  - If `descriptionController.text.trim().isEmpty`: set `descriptionController.text = result` directly (no confirmation needed for empty field)
  - If description has text: this is handled in US2 (for now, just set directly as a temporary behavior)
  - In catch block: if `mounted`, show a SnackBar:
    ```dart
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(e.toString().replaceFirst('Exception: ', '')),
      backgroundColor: AppColors.dangerText,
      behavior: SnackBarBehavior.floating,
    ));
    ```
  - In finally block: if `mounted`, set `_aiLoading = false` via `setState`

  **4. Add a listener** so the button reactivity updates when title changes. In `initState` (or wherever controllers are set up), add:
  ```dart
  titleController.addListener(() { if (mounted) setState(() {}); });
  ```
  Check if this listener already exists — if title changes already trigger `setState`, skip this step. Do NOT add a duplicate listener.

  **5. Add the Suggest button widget** immediately BEFORE the description `TextFormField` (around line 1175). Wrap the description field and button in a Column or place the button in a Row above the field. The button should be:
  - A `TextButton.icon` widget
  - **Hidden entirely** (return `SizedBox.shrink()`) when `!canEdit || !_roleLoaded`
  - **Disabled** (onPressed: null) when `titleController.text.trim().isEmpty || _aiLoading`
  - **Icon**: when `_aiLoading` use `SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))`, otherwise use `Icon(Icons.auto_awesome, size: 18, color: AppColors.accent)`
  - **Label**: `Text(_aiLoading ? 'Suggesting...' : 'Suggest', style: TextStyle(color: AppColors.accent))`
  - **onPressed**: `_suggestDescription`
  - Style with `TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap)` to keep it compact
  - Align the button to the right side above the description field

  **CRITICAL**: Do NOT modify the description `TextFormField` itself. Do NOT change its `readOnly`, `controller`, `focusNode`, or any other properties. Do NOT interfere with the auto-save timer (`_autoSaveTimer`).

**Checkpoint**: After T003 + T004, create a new work order in the app. Fill in a title. The Suggest button should appear. Tap it → loading spinner → description field fills with AI text. The button should be disabled while loading and when title is empty. The button should be hidden when the user is a reporter viewing an existing work order.

---

## Phase 4: User Story 2 — Replace Existing Description (Priority: P2)

**Goal**: When the description field already has text, tapping Suggest shows a bottom sheet with the new suggestion and Replace/Dismiss options.

**Independent Test**: Open an existing work order with a description, tap Suggest → bottom sheet appears with AI suggestion text and two buttons. Replace replaces the text. Dismiss closes the sheet.

**Depends on**: Phase 3 (US1) — uses the same `_suggestDescription` method and `AiAssistService`.

### Implementation for User Story 2

- [x] T005 [US2] Update the `_suggestDescription()` method in `frontend/lib/screens/Work_Orders/add_work_order.dart` to handle the non-empty description case.

  When `descriptionController.text.trim().isNotEmpty`, show a modal bottom sheet:
  ```dart
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AI Suggestion', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Text(result, style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary),
                  child: const Text('Dismiss'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    descriptionController.text = result;
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
                  child: const Text('Replace'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  ```

  Keep the empty-field case unchanged (direct fill from US1).

**Checkpoint**: Open a work order with an existing description. Tap Suggest → bottom sheet shows the AI suggestion. Tap Dismiss → nothing changes. Tap Replace → description field updates. Verify the empty-field flow from US1 still works (no bottom sheet for empty fields).

---

## Phase 5: User Story 3 — Error Handling & Unavailability (Priority: P3)

**Goal**: When Ollama is unreachable or returns errors, the user gets clear feedback via floating snackbar and can continue working normally.

**Independent Test**: Stop Ollama on the server (`sudo systemctl stop ollama`), tap Suggest → floating snackbar error appears. Start Ollama again, tap Suggest → works normally.

**Depends on**: Phase 3 (US1) — error handling is already wired in `_suggestDescription` catch block.

### Implementation for User Story 3

- [x] T006 [US3] Verify and refine error handling in `frontend/lib/screens/Work_Orders/add_work_order.dart`. The catch block in `_suggestDescription()` from T004 already shows a SnackBar. Verify:
  1. The `mounted` check is present before showing the SnackBar (async gap safety)
  2. `_aiLoading` is reset to `false` in the `finally` block even when errors occur
  3. The description field remains unchanged and editable after an error
  4. The Suggest button returns to normal state (not stuck in loading) after an error
  5. The SnackBar uses `SnackBarBehavior.floating` and `AppColors.dangerText` background
  6. Test with: Ollama stopped (503), empty model response (502), network timeout (65s client timeout)
  
  If any of these are not already correct from T004, fix them. This task may result in no code changes if T004 was implemented correctly.

**Checkpoint**: Stop Ollama → tap Suggest → see "AI service is currently unavailable" floating snackbar → description field unchanged → button returns to normal → can type in description field → restart Ollama → tap Suggest → works.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final verification and cleanup.

- [x] T007 Verify auto-save compatibility in `frontend/lib/screens/Work_Orders/add_work_order.dart`. After AI fills the description (both empty-fill and replace flows), confirm:
  1. The existing `_autoSaveTimer` continues to fire normally
  2. The AI-filled text is picked up by the next auto-save cycle (because `descriptionController.text = result` triggers the controller's listeners)
  3. No duplicate auto-save timers are created
  4. Manually test: fill title, tap Suggest, wait for auto-save → verify the work order saves with the AI description

- [x] T008 Run the quickstart.md verification steps in `specs/020-ai-wo-description/quickstart.md`:
  1. Backend curl test (200 response with description)
  2. Backend error test (503 when Ollama stopped)
  3. Frontend new work order flow (empty description → direct fill)
  4. Frontend existing work order flow (non-empty description → bottom sheet)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — register router in main.py
- **Phase 2 (Foundational)**: Depends on Phase 1 — create the router file
- **Phase 3 (US1)**: Depends on Phase 2 — needs backend endpoint running
- **Phase 4 (US2)**: Depends on Phase 3 — extends the `_suggestDescription` method
- **Phase 5 (US3)**: Depends on Phase 3 — verifies error paths in existing code
- **Phase 6 (Polish)**: Depends on Phases 3-5

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational only — can be tested independently
- **US2 (P2)**: Depends on US1 — extends the same method, but testable independently once US1 is in place
- **US3 (P3)**: Depends on US1 — verifies error paths, can be tested independently by stopping Ollama

### Within Each Phase

- T001 → T002 (register router before creating it, or vice versa — order doesn't matter as long as both are done before starting the server)
- T003 and T004 can start in parallel (different files), but T004 imports T003's class
- T005 depends on T004 (modifies same method)
- T006 depends on T004 (verifies same method)
- T007, T008 depend on all prior tasks

### Parallel Opportunities

- **T003 [P] + T004**: Different files (`ai_assist_service.dart` vs `add_work_order.dart`), but T004 imports T003 — can be written in parallel, tested together
- **T005 + T006**: Both modify/verify `_suggestDescription` — must be sequential (T005 first, then T006)

---

## Parallel Example: Phase 2 + Phase 3

```text
# These can be written in parallel (different files):
T003: Create AiAssistService in frontend/lib/services/ai_assist_service.dart
T004: Integrate Suggest button in frontend/lib/screens/Work_Orders/add_work_order.dart

# But T004 imports T003, so both must be complete before testing
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 + Phase 2: Backend endpoint ready
2. Complete Phase 3: Suggest button works for new work orders with empty descriptions
3. **STOP and VALIDATE**: Test with curl + Flutter UI
4. This alone delivers the core value: AI-generated descriptions

### Incremental Delivery

1. Phase 1 + 2 → Backend ready, testable via curl
2. Phase 3 (US1) → Suggest works for empty descriptions (MVP!)
3. Phase 4 (US2) → Replace/Dismiss flow for existing descriptions
4. Phase 5 (US3) → Error handling verification
5. Phase 6 → Polish and final verification

### For LLM Implementation

Tasks are designed to be executed sequentially (T001 → T002 → ... → T008). Each task contains:
- Exact file paths
- Complete implementation details (imports, class structure, method signatures)
- Expected behavior for verification
- Checkpoint after each phase for human review

---

## Notes

- No test tasks included (not requested)
- No database migrations needed
- `httpx` is already in `backend/requirements.txt` — no dependency changes needed
- The `http` package is already used in Flutter — no `pubspec.yaml` changes needed
- The implementing LLM should read each target file before editing to verify current state matches expectations (variable names, line numbers may shift)
- After implementation, the reviewing LLM should verify: all checkpoints pass, no hardcoded colors (only AppColors), all SnackBars use floating behavior, auto-save is unaffected
