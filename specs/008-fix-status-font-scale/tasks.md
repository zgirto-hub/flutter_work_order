# Tasks: Fix Double-Scaling Bug in Settings Page

**Input**: Design documents from `/specs/008-fix-status-font-scale/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, quickstart.md

**Tests**: Not requested — no test tasks included.

**Organization**: Single user story — fix the double-scaling bug in settings_page.dart.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to
- Include exact file paths in descriptions

---

## Context for the Implementor

**IMPORTANT — Read this first before making any changes.**

The app uses `MediaQuery(textScaler: TextScaler.linear(themeController.fontScale))` in `frontend/lib/main.dart` (lines 54-61) to globally scale ALL text in the app. This means every `Text` widget automatically gets its `fontSize` multiplied by the user's font scale preference.

However, `frontend/lib/screens/settings_page.dart` ALSO manually multiplies its hardcoded `fontSize` values by the font scale factor (via `* s`, `* fs`, or `* fontScale` variables). This causes **double-scaling** — text on the settings page is scaled twice (once manually, once by MediaQuery).

**The fix**: Remove all manual font scale multiplications from `settings_page.dart`, reverting each `fontSize: N * s` / `fontSize: N * fs` / `fontSize: N * fontScale` back to `fontSize: N`.

---

## Phase 1: Setup

**Purpose**: No setup needed — this is a single-file revert.

---

## Phase 2: Foundational

**Purpose**: No foundational work needed.

---

## Phase 3: User Story 1 - Remove Double-Scaling from Settings Page (Priority: P1) 🎯 MVP

**Goal**: Remove all manual fontScale multiplications from `settings_page.dart` so text is only scaled once (by the global `MediaQuery.textScaler`).

**Independent Test**: Open Settings, select "X-Large" text size. Verify settings page text is the same size as text on other screens (e.g., Dashboard). Previously, settings page text would appear disproportionately large compared to other screens.

### Implementation for User Story 1

**File**: `frontend/lib/screens/settings_page.dart`

All changes are in this single file. Execute these tasks in order:

- [X] T001 [US1] In the `_signOut()` method (around line 126), remove the line `final fs = widget.themeController.fontScale;`. Then on line 133, change `fontSize: 15 * fs` to `fontSize: 15`. On line 135, change `fontSize: 13 * fs` to `fontSize: 13`.

- [X] T002 [US1] In the `build()` method (around line 167), remove the line `final s = currentScale; // shorthand for font scale multiplier`. Note: keep the `final currentScale = widget.themeController.fontScale;` line — it is still used by the `_FontSizeRow` widget to highlight the selected option.

- [X] T003 [US1] In the `build()` method body, revert all `* s` multiplications back to static values. Find and replace each occurrence:
  - Line ~198: `fontSize: 20 * s` → `fontSize: 20` (Settings header)
  - Line ~220: `fontSize: 14 * s` → `fontSize: 14` (user name)
  - Line ~226: `fontSize: 11 * s` → `fontSize: 11` (email)
  - Line ~385: `fontSize: 12 * s` → `fontSize: 12` (update message)
  - Line ~392: `fontSize: 12 * s` → `fontSize: 12` (update now button)
  - Line ~417: `fontSize: 13 * s` → `fontSize: 13` (sign out button)
  - Line ~426: `fontSize: 12 * s` → `fontSize: 12` (Work Order footer)
  - Line ~433: `fontSize: 10 * s` → `fontSize: 10` (version text)
  - Line ~437: `fontSize: 10 * s` → `fontSize: 10` (developer credit)

- [X] T004 [US1] Remove the `fontScale` parameter from the call sites where sub-widgets are constructed in the `build()` method. Remove these named parameters:
  - `_DarkModeRow(... fontScale: s,)` → `_DarkModeRow(... )` — remove the `fontScale: s,` argument
  - `_FontSizeRow(... fontScale: s,)` → `_FontSizeRow(... )` — remove the `fontScale: s,` argument
  - `_FontTypeRow(... fontScale: s,)` → `_FontTypeRow(... )` — remove the `fontScale: s,` argument
  - `_NavBarRow(... fontScale: s,)` → `_NavBarRow(... )` — remove the `fontScale: s,` argument

- [X] T005 [US1] In the `_DarkModeRow` class definition (around line 453), remove the `final double fontScale;` field and the `this.fontScale = 1.0` from the constructor. Then in its `build()` method, revert:
  - `fontSize: 13 * fontScale` → `fontSize: 13` (Appearance label)
  - `fontSize: 11 * fontScale` → `fontSize: 11` (Light/System/Dark labels)

- [X] T006 [US1] In the `_FontTypeRow` class definition (around line 568), remove the `final double fontScale;` field and the `this.fontScale = 1.0` from the constructor. Change `_previewStyle` back to `static` and revert all `fontSize: 13 * fontScale` → `fontSize: 13` inside it (5 occurrences for Roboto, Poppins, Lato, Nunito, Inter). Then in its `build()` method, revert:
  - `fontSize: 13 * fontScale` → `fontSize: 13` (Font type label)
  - `fontSize: 11 * fontScale` → `fontSize: 11` (current family badge)

- [X] T007 [US1] In the `_FontSizeRow` class definition (around line 662), remove the `final double fontScale;` field and the `this.fontScale = 1.0,` from the constructor. Then in its `build()` method, revert:
  - `fontSize: 13 * fontScale` → `fontSize: 13` (Text size label)
  - `fontSize: 11 * fontScale` → `fontSize: 11` (current scale badge)
  - `fontSize: 9 * fontScale` → `fontSize: 9` (scale option labels like "Small", "Default")
  - Note: Do NOT change `fontSize: 10 + (i * 2.0)` — that is the "Aa" preview which intentionally uses progressive sizes.

- [X] T008 [US1] In the `_NavBarRow` class definition (around line 780), remove the `final double fontScale;` field and the `this.fontScale = 1.0` from the constructor. Then in its `build()` method, revert:
  - `fontSize: 13 * fontScale` → `fontSize: 13` (Navigation bar label)
  - `fontSize: 11 * fontScale` → `fontSize: 11` (pinned count badge)

**Checkpoint**: All manual fontScale multiplications removed. The settings page now relies solely on the global `MediaQuery.textScaler` for font scaling, consistent with every other screen in the app.

---

## Phase 4: Verification

- [ ] T009 Run the app. Go to Settings > Appearance > Text Size. Select "X-Large" (1.3x). Verify that all text on the settings page scales up, but is the same relative size as text on other screens (Dashboard, Files, etc.) — NOT disproportionately larger.

- [ ] T010 Select "Default" (1.0x) and verify the settings page looks identical to how it looked before any font scale changes were made (no regression).

- [ ] T011 Navigate to the System Status screen with "X-Large" selected. Verify all text on that screen also scales correctly (this should already work via MediaQuery.textScaler — just confirm).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 3 (US1)**: All tasks T001-T008 are sequential within the same file. Execute in order.
- **Phase 4 (Verification)**: Depends on Phase 3 completion.

### Within Phase 3

Tasks MUST be executed in order (T001 → T002 → T003 → T004 → T005 → T006 → T007 → T008) because they all modify the same file and later tasks reference line numbers that shift as earlier tasks remove lines.

**Alternative approach**: If your editor supports it, you can do a single pass through the file applying all changes at once — just ensure every `* s`, `* fs`, and `* fontScale` multiplication is removed, and every `fontScale` field/parameter is removed from the 4 sub-widget classes.

---

## Implementation Strategy

### MVP (All Tasks)

1. Complete T001-T008 (all in `settings_page.dart`)
2. Run verification T009-T011
3. Commit and push

### Summary

**Total files to modify**: 1 (`frontend/lib/screens/settings_page.dart`)
**Total implementation tasks**: 8 (T001-T008)
**Total verification tasks**: 3 (T009-T011)
**Total tasks**: 11
**Parallel opportunities**: None (single file)

---

## Notes

- This is a **revert** of commit `8db895b` changes to settings_page.dart only
- The global `MediaQuery.textScaler` in `main.dart` (lines 54-61) already handles font scaling for ALL screens
- Do NOT modify `main.dart`, `app_theme.dart`, `theme_controller.dart`, or `system_status_screen.dart`
- The `currentScale` variable in `build()` must be kept — it's used by `_FontSizeRow` to highlight the selected option
- The `fontScale` on `_FontSizeRow` was only used for text sizing, not for selection logic — safe to remove
