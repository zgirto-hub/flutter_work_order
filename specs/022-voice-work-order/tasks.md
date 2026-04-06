# Tasks: Voice-to-Work-Order Dictation

**Input**: Design documents from `/specs/022-voice-work-order/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Not explicitly requested — test tasks are omitted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Audience**: This task file is designed for an LLM implementer to execute step by step. Each task is self-contained with exact file paths, clear acceptance criteria, and enough context to implement without ambiguity. After implementation, the work will be reviewed by a senior engineer.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Frontend**: `frontend/lib/` (Flutter/Dart)
- **No backend changes** — this feature is entirely client-side

---

## Phase 1: Setup

**Purpose**: Add the speech_to_text dependency and verify it works in the Flutter Web project.

- [x] T001 Add `speech_to_text: ^7.0.0` to the `dependencies` section of `frontend/pubspec.yaml` and run `flutter pub get` to install it. Verify no version conflicts with existing dependencies (Flutter SDK `^3.3.0`, supabase_flutter `2.5.6`, etc.).

- [x] T002 Check `frontend/web/index.html` for any Content-Security-Policy meta tags that might block microphone access. If a CSP exists, ensure `microphone` is in the `allow` list for the relevant permissions-policy. If no CSP exists, no changes needed — browsers handle mic permissions via the Permissions API by default.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the DictationService that wraps speech_to_text. All user stories depend on this service existing.

**CRITICAL**: No user story work can begin until this phase is complete.

- [x] T003 Create `frontend/lib/services/dictation_service.dart` — a singleton service that wraps the `speech_to_text` package. Requirements:
  - Import `package:speech_to_text/speech_to_text.dart` and `package:speech_to_text/speech_recognition_result.dart`.
  - Singleton pattern (match existing services like `WorkOrderService` in `frontend/lib/services/work_order_service.dart` — they use simple class instantiation, not formal singleton).
  - Public properties:
    - `bool isAvailable` — whether speech recognition is supported on this device/browser (set after `initialize()`).
    - `bool isListening` — whether currently recording.
  - Public methods:
    - `Future<bool> initialize()` — calls `SpeechToText().initialize()`. Returns `true` if available. Handles the case where `initialize()` throws (browser doesn't support Web Speech API) by returning `false`. Should only be called once; subsequent calls return cached result.
    - `Future<void> startListening({required String localeId, required Function(String) onResult, required Function(String) onError})` — calls `SpeechToText().listen()` with the given `localeId` (e.g., `en-US` or `ar-SA`). The `onResult` callback receives the recognized text (use `result.recognizedWords` from `SpeechRecognitionResult`). The `onError` callback receives error description strings. Set `listenMode: ListenMode.dictation` for continuous dictation. Set `cancelOnError: false` so partial results are preserved.
    - `Future<void> stopListening()` — calls `SpeechToText().stop()`.
  - Do NOT add any UI code to this file. It is a pure service.

**Checkpoint**: DictationService exists and compiles. User story implementation can now begin.

---

## Phase 3: User Story 1 — Dictate Work Order Description (Priority: P1) MVP

**Goal**: Field technician can tap a mic button next to the Description field on the Add/Edit Work Order screen, speak, and see their words appear in real-time.

**Independent Test**: Open Add Work Order screen in Chrome, tap mic button next to Description, speak a sentence, verify transcribed text appears in the description field. Tap mic again to stop. Verify text persists and is editable.

### Implementation for User Story 1

- [x] T004 [US1] Create `frontend/lib/widgets/dictation_button.dart` — a reusable `StatefulWidget` named `DictationButton`. Requirements:
  - Constructor parameters:
    - `TextEditingController controller` (required) — the text field this button appends dictated text to.
    - `String language` (required) — `'en'` or `'ar'`. Maps to `localeId`: `'en'` → `'en-US'`, `'ar'` → `'ar-SA'`.
    - `bool enabled` (default `true`) — when `false`, button is greyed out and non-interactive (used when form is read-only via `canEdit`).
  - Internal state:
    - `bool _isRecording` — toggles on each tap.
    - `bool _isAvailable` — set in `initState` by calling `DictationService().initialize()`.
  - Behavior:
    - In `initState`, call `DictationService().initialize()` and set `_isAvailable` based on result. If not available, the widget renders `SizedBox.shrink()` (invisible).
    - On tap (when not recording): Call `DictationService().startListening(...)` with the mapped `localeId`. The `onResult` callback MUST **append** the recognized text to the controller's existing text (add a space separator if controller text is non-empty). Use `controller.text = '${controller.text} $recognizedWords'.trim()` pattern. The `onError` callback should show a `SnackBar` via `ScaffoldMessenger.of(context)` with the message "Speech recognition unavailable — please type instead" and set `_isRecording = false`.
    - On tap (when recording): Call `DictationService().stopListening()` and set `_isRecording = false`.
  - Visual appearance:
    - Render an `IconButton` with `Icons.mic` (idle) or `Icons.mic_off` (recording, in red/error color from theme).
    - When recording, wrap the icon in a simple pulsing animation (use `AnimatedContainer` or `AnimatedOpacity` with a repeating controller — keep it simple, no complex animations).
    - Size and style should match other icon buttons in the app (check existing `suffixIcon` usage in `add_work_order.dart` for reference).
  - Import `DictationService` from `../../services/dictation_service.dart`.
  - Dispose: If recording when widget is disposed, call `stopListening()` in `dispose()`.

- [x] T005 [US1] Modify `frontend/lib/screens/Work_Orders/add_work_order.dart` to add a `DictationButton` to the **Description** field.
  - Add import: `import '../../widgets/dictation_button.dart';`
  - Add a state variable: `String _dictationLanguage = 'en';` (near the other state variables around line 76-120).
  - Locate the Description `TextFormField` (around line 1521-1528, controller: `descriptionController`, labelText: "Description").
  - Change the `decoration` to include a `suffixIcon` that is a `DictationButton(controller: descriptionController, language: _dictationLanguage, enabled: canEdit)`.
  - The `canEdit` variable is already available in the `_buildDetailsTab` method — pass it to `DictationButton.enabled`.
  - Do NOT change any other fields or behavior in this file for this task.

**Checkpoint**: At this point, the Description field should have a working mic button. You can test dictation in English on the Add Work Order screen in Chrome. This is the MVP.

---

## Phase 4: User Story 2 — Dictate Work Order Title (Priority: P2)

**Goal**: Field technician can also dictate the work order title using the same mic button pattern.

**Independent Test**: Open Add Work Order screen, tap mic button next to Title, speak a short phrase, verify it appears in the title field.

### Implementation for User Story 2

- [x] T006 [US2] Modify `frontend/lib/screens/Work_Orders/add_work_order.dart` to add a `DictationButton` to the **Title** field. Specific changes:
  - Locate the Title `TextFormField` (around line 1378-1388, controller: `clientController`, labelText: "Title").
  - Change the `decoration` to include a `suffixIcon` that is a `DictationButton(controller: clientController, language: _dictationLanguage, enabled: canEdit)`.
  - No other changes needed — the import and `_dictationLanguage` state variable already exist from T005.

**Checkpoint**: Both Title and Description fields now have working mic buttons.

---

## Phase 5: User Story 3 — Dictate in Arabic (Priority: P2)

**Goal**: Users can switch between English and Arabic for dictation. The language toggle follows the same chip pattern used in the AI Insights card.

**Independent Test**: Switch language to AR, tap mic, speak in Arabic, verify Arabic text appears correctly in the field.

### Implementation for User Story 3

- [x] T007 [US3] Add a language toggle (EN/AR chips) to the Add/Edit Work Order form in `frontend/lib/screens/Work_Orders/add_work_order.dart`. Specific changes:
  - Reference the existing pattern in `frontend/lib/features/analytics/ai_insights_card.dart` (the `_buildLanguageChip` method around line 84 and the toggle row around lines 204-209).
  - Add a private method `Widget _buildDictationLanguageChip(String label, String value)` that returns a `ChoiceChip` or `FilterChip`:
    - `label`: display text ("EN" or "AR")
    - `value`: locale code ("en" or "ar")
    - `selected`: `_dictationLanguage == value`
    - `onSelected`: `setState(() { _dictationLanguage = value; })`
    - Style: use theme colors from `AppTheme` (import already exists at line 28).
  - Place the language chips in a `Row` widget **above** the Title field (after the Created At field section, before the Title TextFormField, around line 1377). The row should contain:
    - `Icon(Icons.mic, size: 16)` as a label
    - `SizedBox(width: 4)`
    - `_buildDictationLanguageChip('EN', 'en')`
    - `SizedBox(width: 8)`
    - `_buildDictationLanguageChip('AR', 'ar')`
  - Wrap the row in a `Padding` with bottom padding of 8.
  - Only show this row when `canEdit` is true AND at least one DictationButton is available (you can check `DictationService().isAvailable` — but to avoid async in build, a simpler approach is to add a `bool _speechAvailable = false;` state variable, set it in `initState` via `DictationService().initialize().then((v) => setState(() => _speechAvailable = v));`, and conditionally render the row with `if (canEdit && _speechAvailable)`).

**Checkpoint**: Users can now toggle between EN and AR for dictation. Both mic buttons on Title and Description use the selected language.

---

## Phase 6: User Story 4 — Visual Feedback During Dictation (Priority: P3)

**Goal**: The mic button clearly shows when it's actively recording so users know the system is listening.

**Independent Test**: Tap mic button, verify it visually changes (color, animation). Stop recording, verify it returns to default state.

### Implementation for User Story 4

- [x] T008 [US4] Enhance the recording indicator in `frontend/lib/widgets/dictation_button.dart`. The basic state toggle (mic/mic_off icon, red color) was already implemented in T004. Now add a subtle pulsing animation:
  - Add an `AnimationController` and `Animation<double>` for a repeating pulse (duration: 1 second, repeat).
  - When `_isRecording` is true, start the animation. When false, stop and reset it.
  - Wrap the `Icon` in an `AnimatedBuilder` that uses the animation value to scale the icon slightly (e.g., `Transform.scale(scale: 1.0 + 0.15 * _animation.value)`) or to modulate opacity.
  - Add `SingleTickerProviderStateMixin` to the State class for the AnimationController.
  - Dispose the AnimationController in `dispose()`.
  - Keep the animation subtle — this is a professional tool, not a flashy app.

**Checkpoint**: All 4 user stories are now implemented. Mic buttons pulse when recording and return to idle state when stopped.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Edge case handling and final cleanup.

- [x] T009 Handle the "only one field recording at a time" constraint in `frontend/lib/services/dictation_service.dart`. Add:
  - A property `String? activeFieldId` that tracks which field is currently recording (can be the controller's `hashCode.toString()` or a passed-in identifier).
  - In `startListening()`, if already listening for a different field, call `stopListening()` first, then start the new one.
  - This ensures FR-012 (only one field recording at a time) is enforced at the service level.

- [x] T010 Handle the "speech unavailable" edge case in `frontend/lib/widgets/dictation_button.dart`. Verify that:
  - When `_isAvailable` is `false` (browser doesn't support Web Speech API), the widget returns `SizedBox.shrink()` — already done in T004 but confirm it works in Firefox.
  - When the user denies microphone permission, the `onError` callback shows the SnackBar message — already done in T004 but verify the error message is user-friendly: "Microphone access denied. Please enable it in your browser settings to use voice input."

- [x] T011 Handle the "network failure" edge case in `frontend/lib/widgets/dictation_button.dart`. In the `onError` callback:
  - Check if the error string contains "network" or "not-allowed" or "service-not-allowed".
  - For network errors: show SnackBar "Speech recognition unavailable — please type instead."
  - For permission errors: show SnackBar "Microphone access denied. Please enable it in your browser settings."
  - For other errors: show SnackBar "Speech recognition error. Please try again."
  - Always set `_isRecording = false` on any error.

- [x] T012 Ensure the silence timeout works correctly. In `frontend/lib/services/dictation_service.dart`, when calling `SpeechToText().listen()`, set `pauseFor: Duration(seconds: 3)` (or the package's equivalent parameter for auto-stop on silence). This ensures FR-011 (stop after silence) without custom timer logic. Verify the `speech_to_text` package version supports this parameter — if not, use `listenFor: Duration(seconds: 30)` as a maximum listen duration fallback.

- [x] T013 Verify append behavior works correctly on the Edit Work Order screen. Open an existing work order (which passes a `workOrder` object to `AddWorkOrderScreen`), confirm:
  - The description field is pre-populated with existing text.
  - Tapping mic and speaking appends new text after existing text with a space separator.
  - The appended text does not overwrite existing content.
  - This should already work from T004's implementation but must be manually verified.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (T001 must complete before T003)
- **User Stories (Phase 3-6)**: All depend on Phase 2 (T003 must complete)
  - US1 (Phase 3): Can start after Phase 2
  - US2 (Phase 4): Depends on US1 (T005 adds import and state variable that T006 reuses)
  - US3 (Phase 5): Depends on US1 (T005 adds `_dictationLanguage` state variable that T007 builds upon)
  - US4 (Phase 6): Depends on US1 (T004 creates the widget that T008 enhances)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: Foundation only — no story dependencies. **This is the MVP.**
- **US2 (P2)**: Depends on US1 (reuses imports and state from T005)
- **US3 (P2)**: Depends on US1 (builds on `_dictationLanguage` from T005)
- **US4 (P3)**: Depends on US1 (enhances widget from T004)

### Within Each User Story

- Service before widget (T003 before T004)
- Widget before screen integration (T004 before T005)
- Core implementation before language toggle (T005/T006 before T007)

### Parallel Opportunities

- T001 and T002 can run in parallel (different files)
- T006 and T007 can run in parallel after T005 completes (T006 modifies a different section of add_work_order.dart than T007, but since they both modify the same file, sequential is safer)
- T009, T010, T011, T012 in Phase 7 can all run in parallel (different files or isolated changes)

---

## Parallel Example: Phase 7 (Polish)

```
# These can all be done in parallel:
Task T009: Update dictation_service.dart (activeFieldId tracking)
Task T010: Verify speech-unavailable edge case in dictation_button.dart
Task T011: Update error handling in dictation_button.dart
Task T012: Configure silence timeout in dictation_service.dart
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001, T002)
2. Complete Phase 2: Foundational (T003)
3. Complete Phase 3: User Story 1 (T004, T005)
4. **STOP and VALIDATE**: Test Description dictation in English on Chrome mobile
5. This alone delivers core value — hands-free description entry

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add US1 (Description dictation) → Test → **MVP ready**
3. Add US2 (Title dictation) → Test → Both fields work
4. Add US3 (Arabic support) → Test → Bilingual support
5. Add US4 (Visual feedback) → Test → Polished UX
6. Polish phase → Edge cases handled → **Feature complete**

### Step-by-Step for LLM Implementer

Execute tasks in strict numerical order (T001 → T002 → T003 → ... → T013). After each task:
1. Save the file
2. Verify no compilation errors (`flutter analyze` or IDE error check)
3. Move to the next task

After completing each phase checkpoint, do a quick manual test in Chrome to verify the feature works as described.

---

## Notes

- **Single screen**: `AddWorkOrderScreen` handles both Add and Edit modes via the `workOrder` constructor parameter. No separate edit screen exists.
- **Field naming**: The "Title" field uses `clientController` (not `titleController`) — this is an existing naming convention in the codebase.
- **Existing AI pattern**: The EN/AR language chips follow the exact pattern from `frontend/lib/features/analytics/ai_insights_card.dart`.
- **No backend changes**: All 13 tasks are frontend-only.
- Commit after each phase completion (not after each task).
- The reviewer will check: correct append behavior, language switching, error handling, and visual consistency with the existing app.
