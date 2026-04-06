# Tasks: Natural Language Work Order Creation

**Input**: Design documents from `/specs/024-nl-create-work-order/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/parse-work-order.md, quickstart.md

**Tests**: Not explicitly requested — test tasks are omitted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Audience**: This task file is designed for an LLM implementer to execute step by step. Each task is self-contained with exact file paths, clear acceptance criteria, and enough context to implement without ambiguity. After implementation, the work will be reviewed by a senior engineer.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `backend/` (Python/FastAPI)
- **Frontend**: `frontend/lib/` (Flutter/Dart)

---

## Phase 1: Setup

**Purpose**: No new dependencies needed. Verify existing infrastructure is ready.

- [x] T001 Verify the Ollama model `gemma4:e2b` is accessible by running `curl http://localhost:11434/api/tags` on the server and confirming the model appears in the list. No code changes needed — this is a precondition check.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the new backend endpoint and frontend service method. All user stories depend on these existing.

**CRITICAL**: No user story work can begin until this phase is complete.

- [x] T002 Add the new `POST /ai/parse-work-order` endpoint in `backend/routers/ai_assist.py`. This is added to the same file as the existing `/ai/suggest` endpoint. Specific implementation:

  **Add a new Pydantic request model** after the existing `AiSuggestRequest` class (around line 16):
  ```python
  class AiParseWorkOrderRequest(BaseModel):
      text: str
      language: str = "en"
      departments: list[str] = []
      types: list[str] = []
      statuses: list[str] = []
  ```

  **Add a helper function** `_build_parse_prompt(text, language, departments, types, statuses)` that builds an LLM prompt with these instructions:
  - "You are a work order parsing assistant."
  - "Parse the following user input into structured work order fields."
  - "Return ONLY a JSON object with these keys: title, description, location, type, department, status."
  - "For the description field: expand abbreviations, fix grammar, write 2-4 professional sentences."
  - Include the lists of valid departments, types, and statuses in the prompt so the LLM is constrained.
  - If language is `"ar"`, add: "Respond in Arabic. All field values must be in Arabic."
  - If language is `"en"`, add: "Respond in English."
  - "If you cannot determine a field, set it to null."
  - "Do NOT include any text outside the JSON object. No preamble, no explanation."
  - Append the user's text at the end: `\nUser input: {text}`

  **Add a helper function** `_extract_json(text)` that:
  - Finds the first `{` and last `}` in the response string
  - Extracts that substring and parses it with `json.loads()`
  - Returns the parsed dict, or raises `ValueError` if no valid JSON found

  **Add a helper function** `_validate_parse_response(data, departments, types, statuses)` that:
  - Checks `data.get("type")` is in the `types` list; sets to `None` if not
  - Checks `data.get("department")` is in the `departments` list; sets to `None` if not
  - Checks `data.get("status")` is in the `statuses` list; sets to `None` if not
  - Passes through `title`, `description`, `location` as-is (free text)
  - Returns the cleaned dict

  **Add the route handler** `@router.post("/ai/parse-work-order")`:
  - Validate `request.text.strip()` is non-empty; raise `HTTPException(422, "Text cannot be empty")` if empty
  - Build the prompt using `_build_parse_prompt()`
  - Call Ollama using the same pattern as the existing `suggest_description` endpoint (httpx POST to `OLLAMA_URL` with `OLLAMA_MODEL` and `stream: False`)
  - Use same error handling pattern: `ConnectError/ConnectTimeout` → 503, `ReadTimeout` → 503, non-200 → 502
  - Extract JSON from response using `_extract_json()`; if extraction fails, raise `HTTPException(502, "AI returned invalid response")`
  - Validate the parsed response using `_validate_parse_response()`
  - Return the validated dict
  - Add `import json` at the top of the file if not already present

- [x] T003 Add a `parseWorkOrder()` method to `frontend/lib/services/ai_assist_service.dart`. Read the existing file first — it has a `suggestDescription()` method. Add a new method following the same pattern:

  ```dart
  Future<Map<String, dynamic>> parseWorkOrder({
    required String text,
    required String language,
    required List<String> departments,
    required List<String> types,
    required List<String> statuses,
  }) async {
  ```

  Implementation:
  - POST to `${AppConfig.baseUrl}/ai/parse-work-order` with JSON body matching the contract: `{"text": text, "language": language, "departments": departments, "types": types, "statuses": statuses}`
  - Use 65-second timeout (same as existing `suggestDescription`)
  - On 200: parse JSON response body and return as `Map<String, dynamic>`
  - On 503: throw `Exception('AI service is currently unavailable. Please try again later.')`
  - On 502: throw `Exception('AI failed to parse the work order. Please try again.')`
  - On timeout: throw `Exception('AI service timed out. Please try again.')`
  - On other errors: throw `Exception('Failed to parse work order.')`

**Checkpoint**: Backend endpoint works (test with curl per quickstart.md). Frontend service method compiles. User story implementation can now begin.

---

## Phase 3: User Story 1 — Type a Sentence and Auto-Fill (Priority: P1) MVP

**Goal**: User types a sentence in an NL input area at the top of the Add Work Order screen, taps Generate, and all form fields are auto-filled.

**Independent Test**: Open Add Work Order, type "broken AC unit in room 205, urgent", tap Generate, verify title/description/location/type fields are populated.

### Implementation for User Story 1

- [x] T004 [US1] Add the natural language input card UI to `frontend/lib/screens/Work_Orders/add_work_order.dart`. Specific changes:

  **New state variables** (add near the existing dictation state variables, around line 120):
  ```dart
  // NL create state
  final TextEditingController _nlInputController = TextEditingController();
  bool _isGenerating = false;
  Set<String> _highlightedFields = {};
  bool _nlCardExpanded = true;
  ```

  **Dispose** `_nlInputController` in the existing `dispose()` method.

  **New method** `Widget _buildNlInputCard()` that returns an `AnimatedCrossFade` or `ExpansionTile`-style collapsible card containing:
  - A `Card` with slight elevation, wrapped in `Padding(padding: EdgeInsets.symmetric(horizontal: 0, vertical: 8))`
  - Inside the card:
    - A header row with `Icon(Icons.auto_awesome, size: 18)`, `Text("AI Work Order")`, and a collapse toggle `IconButton` (chevron up/down)
    - When expanded:
      - A `TextField` with `controller: _nlInputController`, `maxLines: 3`, `decoration: InputDecoration(hintText: "Describe your work order in a sentence...", border: OutlineInputBorder())`
      - A row below the text field containing:
        - A `DictationButton(controller: _nlInputController, language: _dictationLanguage, enabled: !_isGenerating)` — reuses existing widget from 022
        - A `Spacer()`
        - An `ElevatedButton.icon` with `icon: Icon(Icons.auto_awesome)`, `label: Text(_isGenerating ? "Generating..." : "Generate")`, `onPressed: _isGenerating || _nlInputController.text.trim().isEmpty ? null : _generateFromNl`
  - Only build this card when `widget.workOrder == null` (Add mode only, not Edit — per FR-012)

  **Place the card** in the `_buildDetailsTab()` method, right after the `Form` widget's opening `Column` children start (before the Job No field, around line 1252). Add:
  ```dart
  if (widget.workOrder == null) _buildNlInputCard(),
  ```

- [x] T005 [US1] Implement the `_generateFromNl()` method in `frontend/lib/screens/Work_Orders/add_work_order.dart`. This method:

  1. Sets `_isGenerating = true` via `setState()`
  2. Collects the lists of valid values:
     - `departments`: `_departments.map((d) => d.name).toList()` (already loaded in state as `_departments`)
     - `types`: `["Technical", "Inspection", "Other"]` (these are the hardcoded allowed types already used in the form — check around line 80 for `selectedType`)
     - `statuses`: `_allowedStatuses` (already exists in the state — it's the list of statuses the user can select)
  3. Calls `_aiAssistService.parseWorkOrder(text: _nlInputController.text.trim(), language: _dictationLanguage, departments: departments, types: types, statuses: statuses)` (the `_aiAssistService` instance already exists in the state)
  4. On success, auto-fills the form fields from the response map:
     - `if (response['title'] != null) clientController.text = response['title'];`
     - `if (response['description'] != null) descriptionController.text = response['description'];`
     - `if (response['location'] != null) locationController.text = response['location'];`
     - `if (response['type'] != null && ["Technical", "Inspection", "Other"].contains(response['type'])) setState(() => selectedType = response['type']);`
     - `if (response['status'] != null && _allowedStatuses.contains(response['status'])) setState(() => selectedStatus = response['status']);`
     - For department: `if (response['department'] != null)` find the matching department in `_departments` by name, and set `selectedDepartment` and `selectedDepartmentId` accordingly, then call `_loadEmployees(departmentId: dept.id)` to refresh the technician list
  5. Builds a set of highlighted field names: add `"title"`, `"description"`, `"location"`, `"type"`, `"status"`, `"department"` to `_highlightedFields` for each field that was actually set (non-null in response)
  6. Sets `_isGenerating = false` via `setState()`
  7. Scrolls to the title field using the existing `_titleFocusNode.requestFocus()` or `Scrollable.ensureVisible()`
  8. Starts a 3-second timer to clear `_highlightedFields` via `setState(() => _highlightedFields = {})`
  9. On error: shows a `SnackBar` with the error message, sets `_isGenerating = false`
  10. Wrap the entire async body in try/catch

- [x] T006 [US1] Add visual highlighting for auto-filled fields in `frontend/lib/screens/Work_Orders/add_work_order.dart`. For each form field that can be auto-filled (title, description, location, type, status, department), wrap its existing `InputDecoration` to conditionally add a colored border when the field name is in `_highlightedFields`:

  Create a helper method:
  ```dart
  InputDecoration _highlightDecoration(InputDecoration base, String fieldName) {
    if (!_highlightedFields.contains(fieldName)) return base;
    return base.copyWith(
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.accent, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.accent, width: 2),
      ),
    );
  }
  ```

  Apply it to each field's decoration:
  - Title field (around line 1430): `decoration: _highlightDecoration(InputDecoration(labelText: "Title", suffixIcon: ...), "title")`
  - Description field (around line 1580): `decoration: _highlightDecoration(InputDecoration(labelText: "Description", suffixIcon: ...), "description")`
  - Location field (around line 1410): `decoration: _highlightDecoration(InputDecoration(labelText: "Location"), "location")`
  - For dropdown fields (type, status, department): apply similar border highlighting using the dropdown's `decoration` parameter

**Checkpoint**: User can type a sentence, tap Generate, and see all applicable form fields auto-filled with highlighted borders. This is the MVP.

---

## Phase 4: User Story 2 — Voice Dictation to Auto-Fill (Priority: P2)

**Goal**: User speaks into the NL input via mic button, then taps Generate.

**Independent Test**: Tap mic on NL input area, speak a sentence, verify text appears, tap Generate, verify form fields populate.

### Implementation for User Story 2

- [x] T007 [US2] Verify the `DictationButton` on the NL input card (added in T004) works correctly with the `_nlInputController`. No code changes should be needed — the DictationButton from feature 022 already accepts any `TextEditingController` and appends transcribed text. Verify by:
  - Running the app in Chrome
  - Opening Add Work Order
  - Tapping the mic button on the NL input area
  - Speaking a sentence
  - Confirming the transcribed text appears in the NL input field
  - Tapping Generate
  - Confirming form fields are auto-filled

  If the mic button doesn't show (same issue as 022), verify `DictationService.webSpeechApiLikelyAvailable` returns `true` on web. The lazy-init fix from 022 should handle this.

  **If verification passes**: Mark this task as complete with no code changes.
  **If verification fails**: Debug and fix the integration.

**Checkpoint**: Voice dictation flows seamlessly into AI auto-fill.

---

## Phase 5: User Story 3 — Arabic Language Input (Priority: P2)

**Goal**: Arabic text input is correctly parsed by the AI and form fields are filled with Arabic content.

**Independent Test**: Type Arabic text, select AR language, tap Generate, verify Arabic content in form fields.

### Implementation for User Story 3

- [x] T008 [US3] Add language selection to the NL input card in `frontend/lib/screens/Work_Orders/add_work_order.dart`. The `_dictationLanguage` state variable and `_buildDictationLanguageChip()` method already exist from feature 022. In the `_buildNlInputCard()` method (created in T004), add the EN/AR language chips in the row next to the DictationButton:

  Update the row inside the NL card to include:
  ```dart
  Row(
    children: [
      _buildDictationLanguageChip('EN', 'en'),
      SizedBox(width: 8),
      _buildDictationLanguageChip('AR', 'ar'),
      SizedBox(width: 8),
      DictationButton(controller: _nlInputController, language: _dictationLanguage, enabled: !_isGenerating),
      Spacer(),
      ElevatedButton.icon(...),
    ],
  )
  ```

  The `_dictationLanguage` value is already passed to `parseWorkOrder()` in T005's `_generateFromNl()` method as the `language` parameter. No backend changes needed — the prompt already handles Arabic via the language instruction.

- [x] T009 [US3] Verify the backend prompt handles Arabic correctly. In `backend/routers/ai_assist.py`, ensure the `_build_parse_prompt()` function (created in T002) includes the Arabic instruction when `language == "ar"`. The prompt should say: "Respond in Arabic. All field values must be in Arabic." This should already be implemented from T002 — verify and fix if needed.

**Checkpoint**: Arabic input produces Arabic output in all auto-filled fields.

---

## Phase 6: User Story 4 — Grammar Cleanup and Shorthand Expansion (Priority: P3)

**Goal**: Abbreviated/messy input is expanded into professional language.

**Independent Test**: Type "fix elev stuck 3rd flr bldg B asap", tap Generate, verify expanded professional text in description.

### Implementation for User Story 4

- [x] T010 [US4] Verify the LLM prompt in `backend/routers/ai_assist.py` explicitly instructs shorthand expansion. In `_build_parse_prompt()` (created in T002), ensure the prompt includes: "For the description field: expand all abbreviations and shorthand into full professional language. Fix grammar and spelling errors. Write 2-4 complete sentences." This should already be in the prompt from T002 — verify with a test input like "fix elev stuck 3rd flr bldg B asap" using curl and check that the response contains expanded text. Fix the prompt if needed.

**Checkpoint**: Abbreviated input is expanded into professional descriptions.

---

## Phase 7: User Story 5 — Department Auto-Detection (Priority: P3)

**Goal**: The AI matches input to the correct department from the available list.

**Independent Test**: Type "network switch down in server room", verify IT department is pre-selected.

### Implementation for User Story 5

- [x] T011 [US5] Verify department matching works end-to-end. In `_generateFromNl()` (T005), the department matching logic should already:
  1. Receive `response['department']` from the AI (a department name string)
  2. Find the matching department in `_departments` list by name
  3. Set `selectedDepartment` and `selectedDepartmentId`
  4. Call `_loadEmployees()` to refresh technicians for the matched department

  Test with curl: send a request with `"text": "network switch down in server room"` and `"departments": ["General", "IT", "Maintenance", "Electrical"]`. Verify the response includes `"department": "IT"`.

  If the AI frequently returns wrong departments, improve the prompt in `_build_parse_prompt()` by adding: "For the department field: carefully match the described issue to the most relevant department from the provided list. If unsure, set to null."

**Checkpoint**: Department is correctly pre-selected based on input content.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases and final refinements.

- [x] T012 Handle empty/short input edge case in `frontend/lib/screens/Work_Orders/add_work_order.dart`. In `_generateFromNl()`, before calling the service, check if `_nlInputController.text.trim().length < 3`. If so, show a SnackBar: "Please describe your work order in more detail." and return early without calling the API.

- [x] T013 Handle the "re-generate overwrites" behavior in `frontend/lib/screens/Work_Orders/add_work_order.dart`. When the user has already generated and then types new text and taps Generate again, the fields should simply be overwritten with the new AI output. This should already work from T005's implementation (it unconditionally sets field values). Verify by: generating once, editing a field manually, generating again, and confirming the manual edit is overwritten.

- [x] T014 Ensure the NL input card is NOT visible on the Edit Work Order screen. In `_buildNlInputCard()` and its placement in `_buildDetailsTab()` (T004), the condition `widget.workOrder == null` should already handle this. Verify by opening an existing work order and confirming the NL card is absent.

- [x] T015 Add the NL input card collapse/expand persistence. In `_buildNlInputCard()` (T004), the `_nlCardExpanded` state variable controls visibility. Ensure tapping the collapse toggle icon updates this state and the card animates between expanded and collapsed states. The collapsed state should show just the header row ("AI Work Order" with expand icon). No persistence needed across sessions — just within the current screen visit.

- [x] T016 Verify the loading state works correctly. While `_isGenerating` is true:
  - The Generate button should show "Generating..." and be disabled
  - The NL text input should be read-only (prevent edits during generation)
  - The mic button should be disabled
  In `_buildNlInputCard()`, pass `readOnly: _isGenerating` to the TextField and `enabled: !_isGenerating` to the DictationButton and Generate button. This should already be partially done in T004 — verify and complete.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — precondition check
- **Foundational (Phase 2)**: Depends on Phase 1 — backend endpoint + frontend service
- **User Stories (Phase 3-7)**: All depend on Phase 2
  - US1 (Phase 3): Can start after Phase 2 — **This is the MVP**
  - US2 (Phase 4): Depends on US1 (NL card must exist for mic button)
  - US3 (Phase 5): Depends on US1 (NL card must exist for language chips)
  - US4 (Phase 6): No code changes likely — prompt verification only
  - US5 (Phase 7): No code changes likely — prompt verification only
- **Polish (Phase 8)**: Depends on all user stories

### User Story Dependencies

- **US1 (P1)**: Foundation only — **This is the MVP**
- **US2 (P2)**: Depends on US1 (NL card and Generate flow must exist)
- **US3 (P2)**: Depends on US1 (NL card must exist for language selection)
- **US4 (P3)**: Depends on Phase 2 only (backend prompt quality)
- **US5 (P3)**: Depends on Phase 2 only (backend prompt quality)

### Within Each User Story

- Backend before frontend (T002 before T003)
- Service before UI (T003 before T004)
- UI structure before logic (T004 before T005)
- Logic before styling (T005 before T006)

### Parallel Opportunities

- T002 (backend) and T003 (frontend service) can be done in parallel after T001
- T010 and T011 (verification tasks) can be done in parallel
- T012-T016 (polish tasks) can be done in parallel

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002, T003)
3. Complete Phase 3: User Story 1 (T004, T005, T006)
4. **STOP and VALIDATE**: Type a sentence, tap Generate, verify auto-fill works
5. This alone delivers core value — single-sentence work order creation

### Incremental Delivery

1. Setup + Foundational → Backend endpoint and frontend service ready
2. Add US1 (Type & auto-fill) → Test → **MVP ready**
3. Add US2 (Voice integration) → Test → Hands-free flow
4. Add US3 (Arabic support) → Test → Bilingual support
5. Add US4 (Grammar/shorthand) → Test → Professional output quality
6. Add US5 (Department matching) → Test → Smart department selection
7. Polish phase → Edge cases → **Feature complete**

### Step-by-Step for LLM Implementer

Execute tasks in strict numerical order (T001 → T002 → ... → T016). After each task:
1. Save the file
2. Verify no compilation/syntax errors
3. For backend tasks: verify the server starts without errors
4. For frontend tasks: verify `flutter analyze` passes or IDE shows no errors
5. Move to the next task

After completing each phase checkpoint, test the feature as described.

---

## Notes

- **Single screen**: `AddWorkOrderScreen` handles both Add and Edit via the `workOrder` constructor param. NL card only shows in Add mode (`workOrder == null`).
- **Field naming**: The "Title" field uses `clientController` (not `titleController`) — existing codebase convention.
- **Existing AI service**: `_aiAssistService` is already instantiated in the screen state. Just add the new `parseWorkOrder()` method to the service class.
- **Existing dictation**: `DictationButton` and `_dictationLanguage` / `_buildDictationLanguageChip()` already exist from feature 022.
- **Existing departments**: `_departments` list is already loaded in `initState` — no new API call needed.
- Commit after each phase completion.
- The reviewer will check: JSON parsing robustness, field validation, highlight UX, error handling, and Arabic output quality.
