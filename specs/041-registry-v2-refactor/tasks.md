# Tasks: Document Registry V2 UI Refactor

**Input**: Design documents from `/specs/041-registry-v2-refactor/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: No automated tests requested. Manual visual/interaction testing only.

**Organization**: Tasks grouped by user story. All work happens in a single file: `frontend/lib/screens/document_registry/document_registry_screen.dart` (full rewrite). Reference patterns from Letters v2 files.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Frontend**: `frontend/lib/` (Flutter/Dart)
- **Target file**: `frontend/lib/screens/document_registry/document_registry_screen.dart`
- **Reference files** (read-only, do NOT modify):
  - `frontend/lib/screens/letters_v2/letter_generator_screen_v2.dart`
  - `frontend/lib/screens/letters_v2/letter_history_tab_v2.dart`
- **Unchanged dependencies** (import, do NOT modify):
  - `frontend/lib/models/registry_entry.dart`
  - `frontend/lib/services/document_registry_service.dart`
  - `frontend/lib/widgets/claude_widgets.dart` (ClaudeFAB, EmptyState)
  - `frontend/lib/widgets/form_fields.dart` (ValidatedTextField)
  - `frontend/lib/theme/app_theme.dart` (AppColors)
  - `frontend/lib/config.dart` (AppConfig.downloadUrl)

---

## Phase 1: Setup

**Purpose**: Understand existing code and reference patterns before writing anything

- [X] T001 Read the current implementation at `frontend/lib/screens/document_registry/document_registry_screen.dart` — understand all methods, state variables, imports, and the `WidgetsBindingObserver` lifecycle pattern. Note: the entire file will be rewritten but ALL existing functionality must be preserved.

- [X] T002 Read the reference pattern at `frontend/lib/screens/letters_v2/letter_generator_screen_v2.dart` — study the main screen structure: Scaffold with `AppColors.bgPrimary` background, `ClaudeFAB` in `floatingActionButton`, header container pattern, `_historyKey = UniqueKey()` refresh mechanism, `_openForm()` method using `Navigator.push` with `MaterialPageRoute` to push `_LetterFormScreen`, and the `onLetterSaved` callback pattern.

- [X] T003 Read the reference pattern at `frontend/lib/screens/letters_v2/letter_history_tab_v2.dart` — study the expandable card pattern: `_expandedIndex` state management, `RefreshIndicator` wrapping `ListView.builder`, `EmptyState` widget usage, and the `_LetterCard` stateful widget with `AnimationController` (240ms), `CurvedAnimation` (easeInOutCubic for size/chevron, easeOut for fade), `SizeTransition` + `FadeTransition`, chevron rotation via `Tween<double>(begin: 0.0, end: 0.5)`, card styling (14px border radius, 0.5px border, `AppColors.bgSurface` background, `AppColors.border` vs `border2` for collapsed/expanded), action buttons in expanded footer with 9px border radius.

- [X] T004 Read the shared widgets at `frontend/lib/widgets/claude_widgets.dart` — confirm `ClaudeFAB` constructor (`onTap`, `icon`, `tooltip`, `semanticsLabel`) and `EmptyState` constructor (`icon`, `title`, `subtitle`, `action`, `iconColor`).

---

## Phase 2: Foundational (Main Screen Scaffold)

**Purpose**: Create the main `DocumentRegistryScreen` widget that replaces the current implementation. This is the outer shell that all user stories build into.

**CRITICAL**: No user story work can begin until this phase is complete.

- [X] T005 Rewrite `frontend/lib/screens/document_registry/document_registry_screen.dart` with the main screen scaffold. The file must contain these imports:
```
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import '../../widgets/form_fields.dart';
import '../../models/registry_entry.dart';
import '../../services/document_registry_service.dart';
import '../../config.dart';
```
Create `DocumentRegistryScreen` as a `StatefulWidget` with `WidgetsBindingObserver` mixin. State variables: `_service = DocumentRegistryService()`, `_allEntries` (List<RegistryEntry>), `_filteredEntries` (List<RegistryEntry>), `_isLoading = true`, `_expandedIndex` (int? = null), `_searchCtrl = TextEditingController()`, `_historyKey = UniqueKey()`. The `build` method must return a `Scaffold` with `backgroundColor: AppColors.bgPrimary`, `floatingActionButton: ClaudeFAB(onTap: () => _openForm(), tooltip: 'New entry', semanticsLabel: 'Create new registry entry')`, and a `body: SafeArea(child: Column(...))` containing a header and the list content. Preserve `didChangeAppLifecycleState` for resume refresh. Include `_loadEntries()` async method that calls `_service.fetchEntries()` exactly as the current implementation does. Include `_applySearch()` method exactly as current. Include `_onEntrySaved()` callback that does `setState(() => _historyKey = UniqueKey())`. Include `_openForm({RegistryEntry? entry})` method that calls `Navigator.push(context, MaterialPageRoute(builder: (_) => _RegistryFormScreen(editEntry: entry, onEntrySaved: _onEntrySaved)))`. Also create empty placeholder classes `_RegistryFormScreen` (StatefulWidget accepting `editEntry` and `onEntrySaved`) and `_RegistryEntryCard` (StatefulWidget) so the file compiles.

- [X] T006 Implement the header section in `DocumentRegistryScreen.build()` at `frontend/lib/screens/document_registry/document_registry_screen.dart`. Pattern: `Container` with `color: AppColors.bgSurface`, `padding: EdgeInsets.fromLTRB(16, 12, 16, 12)`. Row containing: conditional back button (only if `ModalRoute.of(context)?.isFirst == false`) — back button is a 34x34 `Container` with `borderRadius: 9`, `color: AppColors.bgSurface2`, `border: Border.all(color: AppColors.border2, width: 0.5)`, containing `Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.textSecondary)`. Then `SizedBox(width: 12)`. Then `Expanded` child with `Text('Document Registry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: -0.3))`. Below the header container, add `Divider(height: 0, thickness: 0.5, color: AppColors.border)`.

**Checkpoint**: File compiles, screen shows header + empty body + FAB. Tapping FAB pushes an empty form screen.

---

## Phase 3: User Story 1 — Browse Registry Entries with Expandable Cards (Priority: P1) MVP

**Goal**: Display all registry entries as expandable cards with smooth animations. Only one card expanded at a time. Pull-to-refresh. EmptyState when no entries.

**Independent Test**: Open Document Registry with existing entries. Cards are collapsed. Tap a card — it expands with 240ms animation. Tap another — first collapses, second expands. Pull down to refresh. Empty state shows when no entries.

### Implementation for User Story 1

- [X] T007 [US1] Implement the list body in `DocumentRegistryScreen.build()` at `frontend/lib/screens/document_registry/document_registry_screen.dart`.

- [X] T008 [US1] Implement the `_RegistryEntryCard` stateful widget in `frontend/lib/screens/document_registry/document_registry_screen.dart`.

- [X] T009 [US1] Implement the `_RegistryEntryCard.build()` method in `frontend/lib/screens/document_registry/document_registry_screen.dart`.

- [X] T010 [US1] Implement the expanded section of `_RegistryEntryCard.build()` in `frontend/lib/screens/document_registry/document_registry_screen.dart`.

- [X] T011 [US1] Implement the action buttons row in the expanded section of `_RegistryEntryCard` in `frontend/lib/screens/document_registry/document_registry_screen.dart`.
  - **Attach button**: `GestureDetector(onTap: widget.onAttach, child: Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7), decoration: BoxDecoration(color: AppColors.bgSurface, borderRadius: BorderRadius.circular(9), border: Border.all(color: AppColors.border2, width: 0.5)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.attach_file_rounded, size: 13, color: AppColors.textSecondary), SizedBox(width: 4), Text('Attach', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500))])))`.
  - **Edit button**: Same styling as Attach, with `Icon(Icons.edit_outlined, size: 13)`, text `'Edit'`, and `onTap: widget.onEdit`.
  - **Delete button**: Same container styling but with `border: Border.all(color: AppColors.dangerText.withValues(alpha: 0.3), width: 0.5)`, icon `Icons.delete_outline_rounded` with `color: AppColors.dangerText`, text `'Delete'` with `color: AppColors.dangerText`, and `onTap: widget.onDelete`.

**Checkpoint**: Cards expand/collapse with smooth 240ms animation. Chevron rotates. Only one card expanded at a time. Pull-to-refresh works. EmptyState shows when empty. Action buttons visible only when expanded.

---

## Phase 4: User Story 2 — Create New Registry Entry via Pushed Form (Priority: P1)

**Goal**: FAB pushes a full-screen form for creating new entries. Form has document name, number, date picker, replied checkbox, Extract from PDF button, and pending attachment chip. Submit creates entry and refreshes list.

**Independent Test**: Tap FAB, fill in all fields, tap "Add Entry". Form dismisses, new entry appears in list. Also test Extract from PDF flow.

### Implementation for User Story 2

- [X] T012 [US2] Implement the `_RegistryFormScreen` stateful widget in `frontend/lib/screens/document_registry/document_registry_screen.dart`.

- [X] T013 [US2] Implement the `_RegistryFormScreen.build()` method in `frontend/lib/screens/document_registry/document_registry_screen.dart`.

- [X] T014 [US2] Implement the form fields inside `_RegistryFormScreen` in `frontend/lib/screens/document_registry/document_registry_screen.dart`.

- [X] T015 [US2] Implement `_pickDate()`, `_extractFromPdf()`, and `_submitEntry()` methods in `_RegistryFormScreen` at `frontend/lib/screens/document_registry/document_registry_screen.dart`.

**Checkpoint**: FAB opens create form. All fields work. Extract from PDF auto-fills fields and shows pending attachment chip. Submit creates entry, dismisses form, list refreshes with new entry. Back button dismisses without saving.

---

## Phase 5: User Story 3 — Edit Existing Entry via Pushed Form (Priority: P2)

**Goal**: Edit button in expanded card opens pre-filled form. Save updates entry and refreshes list.

**Independent Test**: Expand a card, tap Edit. Form shows with all fields pre-filled. Change a field, save. Form dismisses, list shows updated data.

### Implementation for User Story 3

- [X] T016 [US3] Verify edit flow integration in `frontend/lib/screens/document_registry/document_registry_screen.dart`.

**Checkpoint**: Edit flow fully functional. Pre-filled form, save updates entry, list refreshes.

---

## Phase 6: User Story 4 — Manage Attachments and Delete Entries (Priority: P2)

**Goal**: Attach, delete, remove attachment, and open attachment actions work from expanded cards with proper confirmation dialogs.

**Independent Test**: Expand a card, attach a file. Expand a card with attachment, tap filename to open. Tap delete, confirm deletion via dialog.

### Implementation for User Story 4

- [X] T017 [US4] Implement `_attachFile()`, `_openAttachment()`, `_removeAttachment()`, and `_deleteEntry()` methods in `DocumentRegistryScreen` at `frontend/lib/screens/document_registry/document_registry_screen.dart`.

- [X] T018 [US4] After `_loadEntries()` completes, reset `_expandedIndex = null` so no card is left in expanded state after data reloads.

**Checkpoint**: All CRUD and attachment operations work from expanded cards. Confirmation dialogs styled consistently. List refreshes and cards collapse after operations.

---

## Phase 7: User Story 5 — Search and Filter (Priority: P3)

**Goal**: Search bar filters entries by document name or number in real-time.

**Independent Test**: Type in search bar. List filters. Clear search. All entries return. Search with no results shows EmptyState.

### Implementation for User Story 5

- [X] T019 [US5] Add the search bar between the header divider and the list content in `DocumentRegistryScreen.build()` at `frontend/lib/screens/document_registry/document_registry_screen.dart`.

**Checkpoint**: Search filters in real-time. EmptyState shows "No Matching Entries" when search has no results. Clearing search restores full list.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanup and verification

- [X] T020 Verify all imports are correct and no unused imports remain in `frontend/lib/screens/document_registry/document_registry_screen.dart`. Run `flutter analyze` from `frontend/` to check for lint errors.

- [X] T021 Verify that the `dispose()` method in `DocumentRegistryScreen` removes the `WidgetsBindingObserver` and disposes `_searchCtrl`. Verify `_RegistryFormScreen.dispose()` disposes `_nameCtrl`, `_numberCtrl`, `_dateCtrl`.

- [ ] T022 Visual QA: Run `flutter run -d chrome` from `frontend/`, navigate to Document Registry, and verify side-by-side with Letters v2 screen that colors, spacing, border radii, font sizes, animation timing, and card styling match exactly. Check: header styling, card collapsed state, card expanded state, action buttons, FAB appearance, EmptyState, search bar.

- [ ] T023 Functional regression test: Verify all 6 existing operations work: (1) Create entry via form, (2) Edit entry via expanded card Edit button, (3) Delete entry with confirmation dialog, (4) Attach file to entry, (5) Remove attachment with confirmation, (6) Extract fields from PDF in create form. Also verify: (7) Pull-to-refresh, (8) Search filtering, (9) App lifecycle resume refresh, (10) Back button navigation from form.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — read-only research
- **Foundational (Phase 2)**: Depends on Setup — creates the file scaffold
- **US1 (Phase 3)**: Depends on Foundational — expandable card list
- **US2 (Phase 4)**: Depends on Foundational — pushed form (can run in parallel with US1 since form is a separate widget class)
- **US3 (Phase 5)**: Depends on US2 — edit mode relies on form implementation
- **US4 (Phase 6)**: Depends on US1 — actions are in expanded cards
- **US5 (Phase 7)**: Depends on Foundational — search bar in main screen
- **Polish (Phase 8)**: Depends on all stories complete

### User Story Dependencies

- **US1 (P1)**: Depends on Phase 2 only — card list is independent
- **US2 (P1)**: Depends on Phase 2 only — form is a separate widget class
- **US3 (P2)**: Depends on US2 — edit is a mode of the form
- **US4 (P2)**: Depends on US1 — actions live in expanded cards; also needs service methods wired in Phase 2
- **US5 (P3)**: Depends on Phase 2 only — search bar is independent of cards

### Within Each User Story

- Implementation tasks are sequential (same file, building on prior code)
- No test tasks (not requested)

### Parallel Opportunities

- T001-T004 (Setup reads) can all run in parallel
- US1 and US2 can be implemented in parallel by separate agents (different widget classes in same file — coordinate merge)
- US5 is independent and can be done any time after Phase 2

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1: Setup (read reference files)
2. Complete Phase 2: Foundational (main screen scaffold)
3. Complete Phase 3: User Story 1 (expandable card list)
4. Complete Phase 4: User Story 2 (create form)
5. **STOP and VALIDATE**: Cards expand/collapse, FAB opens form, create works end-to-end

### Incremental Delivery

1. Setup + Foundational -> Skeleton compiles
2. Add US1 -> Expandable cards working -> Visual MVP
3. Add US2 -> Create flow working -> Functional MVP
4. Add US3 -> Edit flow working -> Full CRUD (read/create/edit)
5. Add US4 -> Attach/delete working -> Full CRUD with attachments
6. Add US5 -> Search working -> Feature complete
7. Polish -> QA and regression -> Ship

---

## Notes

- **Single file rewrite**: All tasks target `frontend/lib/screens/document_registry/document_registry_screen.dart`
- **No backend changes**: All service methods and models are preserved as-is
- **Reference patterns**: Letters v2 files are read-only references — replicate patterns, don't import from them
- **Animation values are exact**: 240ms, easeInOutCubic, easeOut — these must match Letters v2 precisely
- **Color tokens are exact**: Use AppColors constants, never hardcode hex except for the document icon background (`Color(0xFFCFFAFE)`, `Color(0xFF0E7490)`) and badge colors which match the current implementation
- Commit after each phase checkpoint
- The implementing LLM should read the reference files (T001-T004) before writing any code
