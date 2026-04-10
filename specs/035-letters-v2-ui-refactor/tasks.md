# Tasks: Letters V2 UI/UX Refactor

**Input**: Design documents from `/specs/035-letters-v2-ui-refactor/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Tests**: No test tasks included — testing is manual visual verification per quickstart.md.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Web app**: `frontend/lib/` for Flutter source
- All modifications are in `frontend/lib/screens/letters_v2/`
- Reference files (read-only): `frontend/lib/screens/work_orders/add_work_order.dart`, `frontend/lib/theme/app_theme.dart`, `frontend/lib/widgets/claude_widgets.dart`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: No new project setup required — this is a refactor of existing files. This phase reads reference files and confirms baseline.

- [ ] T001 Read the Work Orders header and `_Tab` widget pattern from `frontend/lib/screens/work_orders/add_work_order.dart` (lines ~1195-1225 for header, ~2840-2902 for `_Tab` widget) to use as the canonical reference for all UI changes
- [ ] T002 Read the current Letters V2 main screen at `frontend/lib/screens/letters_v2/letter_generator_screen_v2.dart` to understand the existing header, `_SegmentedTabs` widget, and layout structure before modifying

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational/blocking tasks — all files already exist. User story phases can proceed directly.

**Checkpoint**: No new infrastructure needed — proceed to user story implementation.

---

## Phase 3: User Story 1 — Consistent Screen Layout and Navigation (Priority: P1) MVP

**Goal**: Replace the Letters V2 header and tab system to match Work Orders exactly. Users see the same polished header with rounded back button and bottom-border tabs instead of the segmented control.

**Independent Test**: Navigate to Letters V2 screen. Verify header back button is 34x34, rounded (9px), `bgSurface2` background, `arrow_back_rounded` icon (16px). Verify tabs use accent-colored bottom border for active state. Verify tab switching animates smoothly and content updates without flicker.

### Implementation for User Story 1

- [ ] T003 [US1] Replace the header back button in `frontend/lib/screens/letters_v2/letter_generator_screen_v2.dart`: change icon from `Icons.arrow_back` to `Icons.arrow_back_rounded`, size from 17 to 16, and normalize container padding to `EdgeInsets.fromLTRB(16, 12, 16, 0)` matching `add_work_order.dart` header
- [ ] T004 [US1] Delete the `_SegmentedTabs` class (~65 lines) from `frontend/lib/screens/letters_v2/letter_generator_screen_v2.dart` and create a new `_Tab` widget class with `label` (String), `active` (bool), and `onTap` (VoidCallback) parameters, using bottom border active state (`AppColors.accent`, 2px width), text color toggle (`accent` active / `textSecondary` inactive), `fontSize: 13`, `fontWeight: w500`, container padding `EdgeInsets.only(bottom: 10)` and margin `EdgeInsets.only(right: 20)`
- [ ] T005 [US1] Update the layout structure in `frontend/lib/screens/letters_v2/letter_generator_screen_v2.dart`: move tab bar inside the header container (below title row, above divider) as a `Row` of `_Tab` widgets, remove the old padded segmented control container, and ensure `_tabIndex` state correctly drives the new `_Tab` active states and content switching

**Checkpoint**: Letters V2 header and tabs visually match Work Orders. Tab switching works. All existing letter creation and history functionality still works.

---

## Phase 4: User Story 2 — Polished Form Experience (Priority: P1)

**Goal**: Form fields use theme input decoration, iOS PWA keyboard handling scrolls fields into view, and form labels match Work Orders typography.

**Independent Test**: Open letter creation form. Verify all text fields use theme `InputDecoration` (filled, rounded, accent focus ring). On iOS PWA, tap a field and verify it scrolls into view after keyboard appears. Submit empty form and verify validation errors use danger colors.

### Implementation for User Story 2

- [ ] T006 [US2] Remove the `_inputDecor(String hint)` helper method from `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart` and replace all its call sites with `InputDecoration(hintText: hint)` or `InputDecoration(labelText: label)` to use the global `InputDecorationTheme` defaults from `app_theme.dart`
- [ ] T007 [US2] Add FocusNode declarations for each text field (reference, date, recipient, subject, body/CC fields) in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`, implement the `_ensureVisible(FocusNode node)` method (400ms delay, `Scrollable.ensureVisible` with alignment 0.3, duration 300ms, easeInOut curve) matching `add_work_order.dart` lines 164-187, call `_ensureVisible()` for each node in `initState`, dispose all nodes in `dispose`, and attach each FocusNode to its corresponding `TextFormField`
- [ ] T008 [US2] Standardize form labels in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`: evaluate the `_buildLabel(text)` helper against the Work Orders pattern (which uses `InputDecoration.labelText` directly) and either replace with `labelText` in the decoration or normalize the helper to use `AppColors.textPrimary` with consistent font weight and size matching Work Orders
- [ ] T009 [US2] Standardize all button styling in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`: replace hardcoded `Color(0xFFCC0000)` with `AppColors.accent` for primary buttons and `AppColors.dangerText` for destructive actions, apply consistent `ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(horizontal: 20, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))` for primary buttons and `OutlinedButton.styleFrom(side: BorderSide(color: AppColors.border2, width: 0.5))` for secondary buttons
- [ ] T010 [US2] Add loading state to the PDF generation and save buttons in `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`: when loading, replace button child with `SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))` and set `onPressed: null` to disable, matching the Work Orders button loading pattern

**Checkpoint**: Letter form fields use theme styling, keyboard scroll works on iOS PWA, buttons use AppColors consistently with loading states.

---

## Phase 5: User Story 3 — Refined Letter History List (Priority: P2)

**Goal**: Letter history cards use themed card styling matching Work Order card visuals with proper shadows, borders, and typography hierarchy.

**Independent Test**: View letter history tab with multiple letters. Verify cards use `bgSurface` background, 14px border radius, theme borders and shadows. Verify title/subtitle/date use theme text colors.

### Implementation for User Story 3

- [ ] T011 [US3] Redesign the letter history card widget in `frontend/lib/screens/letters_v2/letter_history_tab_v2.dart`: replace the basic `Card` + `ListTile` with a themed `Container` using `bgSurface` background, `BorderRadius.circular(14)`, `Border.all(color: AppColors.border, width: 0.5)`, `AppShadows.cardLight` shadows, internal `Padding(padding: EdgeInsets.all(14))`, title at `fontSize: 14, fontWeight: w600, color: AppColors.textPrimary`, subtitle at `fontSize: 13, color: AppColors.textSecondary`, date at `fontSize: 11, color: AppColors.textTertiary`, and certificate badge using `AppColors.bgSurface2` with `border2` border instead of default `Chip`
- [ ] T012 [US3] Ensure pull-to-refresh indicator in `frontend/lib/screens/letters_v2/letter_history_tab_v2.dart` uses `RefreshIndicator(color: AppColors.accent)` for the spinner color

**Checkpoint**: Letter history cards visually match Work Order card design system. Pull-to-refresh uses accent color.

---

## Phase 6: User Story 4 — Consistent Button and Action Styling (Priority: P2)

**Goal**: All action buttons across the entire Letters V2 screen follow the Work Orders button pattern consistently.

**Independent Test**: Trigger each button type (generate PDF, preview, save, delete, add CC). Verify primary buttons use accent color, destructive use danger color, outlined use border color. Verify loading spinners on long-running actions.

### Implementation for User Story 4

- [ ] T013 [US4] Standardize all button styling in `frontend/lib/screens/letters_v2/letter_history_tab_v2.dart` bottom sheet action buttons (edit, delete, download PDF, regenerate): apply same primary/outlined/destructive button patterns as T009, replace any hardcoded colors with `AppColors` tokens, and add loading state spinners for PDF download and regenerate actions
- [ ] T014 [US4] Ensure delete confirmation dialogs in `frontend/lib/screens/letters_v2/letter_history_tab_v2.dart` use `AppColors.bgSurface` for background, `AppColors.textPrimary` for title, `AppColors.dangerText` for destructive action text, matching the Work Orders delete confirmation pattern

**Checkpoint**: All buttons across form and history tabs follow the same styling pattern. No hardcoded button colors remain.

---

## Phase 7: User Story 5 — Proper Empty and Loading States (Priority: P3)

**Goal**: Empty and loading states use shared widgets and theme colors instead of hardcoded values.

**Independent Test**: View history tab with no letters — verify centered `EmptyState` widget with theme colors. View during data load — verify accent-colored spinner.

### Implementation for User Story 5

- [ ] T015 [US5] Replace the inline empty state in `frontend/lib/screens/letters_v2/letter_history_tab_v2.dart` with the shared `EmptyState` widget from `frontend/lib/widgets/claude_widgets.dart`: import the widget and use `EmptyState(icon: Icons.mail_outline, title: 'No Letters Yet', subtitle: 'Letters you create will appear here')`
- [ ] T016 [US5] Update the loading state in `frontend/lib/screens/letters_v2/letter_history_tab_v2.dart` to use `Center(child: CircularProgressIndicator(color: AppColors.accent))` instead of the default unstyled `CircularProgressIndicator()`

**Checkpoint**: Empty and loading states use theme colors and shared widgets. No hardcoded `Colors.grey` in these states.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final color audit, keyboard inset handling, and cross-file consistency verification.

- [ ] T017 Add keyboard inset handling to the letter detail bottom sheet in `frontend/lib/screens/letters_v2/letter_history_tab_v2.dart`: read `MediaQuery.of(context).viewInsets.bottom` and apply it to the `ListView` padding as `EdgeInsets.fromLTRB(20, 20, 20, 20 + viewInsets.bottom)`
- [ ] T018 Perform a hardcoded color audit across all 3 files (`letter_generator_screen_v2.dart`, `letter_form_tab_v2.dart`, `letter_history_tab_v2.dart`): replace all remaining `Colors.grey` with `AppColors.textTertiary`, `Color(0xFFCC0000)` with `AppColors.accent` or `AppColors.dangerText`, and any other direct `Color(...)` or `Colors.*` references with the appropriate `AppColors` token — excluding colors inside WYSIWYG editor HTML strings
- [ ] T019 Run quickstart.md verification checklist: navigate through all 3 phases of verification (header/tabs, form styling/keyboard, history cards/empty states) on both desktop browser and iOS PWA to confirm no visual regressions

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — read reference files
- **Foundational (Phase 2)**: N/A — no blocking prerequisites
- **US1 (Phase 3)**: Can start immediately — modifies `letter_generator_screen_v2.dart` only
- **US2 (Phase 4)**: Can start immediately — modifies `letter_form_tab_v2.dart` only (independent of US1)
- **US3 (Phase 5)**: Can start immediately — modifies `letter_history_tab_v2.dart` only (independent of US1, US2)
- **US4 (Phase 6)**: Depends on US2 (T009 button patterns) — applies same patterns to history tab buttons
- **US5 (Phase 7)**: Can start immediately — modifies `letter_history_tab_v2.dart` (independent, different code sections than US3)
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: No dependencies — `letter_generator_screen_v2.dart` only
- **User Story 2 (P1)**: No dependencies — `letter_form_tab_v2.dart` only
- **User Story 3 (P2)**: No dependencies — `letter_history_tab_v2.dart` cards
- **User Story 4 (P2)**: Soft dependency on US2 for button pattern reference — `letter_history_tab_v2.dart` buttons
- **User Story 5 (P3)**: No dependencies — `letter_history_tab_v2.dart` empty/loading states

### Within Each User Story

- Read reference pattern → apply to target file → verify visually
- No model/service/endpoint chain — all tasks are widget-level modifications

### Parallel Opportunities

- **US1 + US2 + US3 + US5** can all run in parallel (different files or different code sections)
- **US4** should follow US2 to reuse the same button styling decisions
- Within US2: T006, T007, T008 modify different sections of the same file but can be done sequentially in one pass

---

## Parallel Example: User Stories 1, 2, 3

```text
# These three stories can be launched in parallel (different files):
Agent 1: T003-T005 — Header and tabs in letter_generator_screen_v2.dart
Agent 2: T006-T010 — Form styling in letter_form_tab_v2.dart
Agent 3: T011-T012 — History cards in letter_history_tab_v2.dart
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001-T002: Read reference files
2. Complete T003-T005: Header and tab refactor
3. **STOP and VALIDATE**: Verify header and tabs match Work Orders visually
4. All existing functionality still works

### Incremental Delivery

1. US1 (header/tabs) → Validate → Visual foundation set
2. US2 (form styling) → Validate → Form experience polished
3. US3 (history cards) → Validate → List view refined
4. US4 (button consistency) → Validate → All actions styled
5. US5 (empty/loading) → Validate → Edge states polished
6. Polish (color audit) → Final validation → Complete

### Parallel Team Strategy

With multiple agents:

1. Agent A: US1 (`letter_generator_screen_v2.dart`)
2. Agent B: US2 (`letter_form_tab_v2.dart`)
3. Agent C: US3 + US5 (`letter_history_tab_v2.dart`)
4. After all complete: US4 + Polish (cross-file cleanup)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story targets a different file, enabling true parallel implementation
- No test tasks included — testing is manual visual verification per quickstart.md
- WYSIWYG editor HTML strings are explicitly excluded from color audit (FR-010, FR-013)
- Commit after each user story phase for clean git history
