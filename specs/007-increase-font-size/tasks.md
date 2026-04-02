# Tasks: Activate Font Scale Setting

**Input**: Design documents from `/specs/007-increase-font-size/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, quickstart.md

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: No setup needed — project already exists and all infrastructure is in place. Skip to Phase 2.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Modify `AppTheme` to accept and apply the `fontScale` parameter. This MUST be complete before user story validation.

**⚠️ CRITICAL**: User story validation cannot begin until this phase is complete.

- [X] T001 Add `fontScale` parameter (default `1.0`) to `AppTheme.light()` and `AppTheme.dark()` static methods in `frontend/lib/theme/app_theme.dart`. Currently these methods have signature `static ThemeData light([Color accent = AppColors.accent, String fontFamily = 'DM Sans'])`. Add a third optional positional parameter: `double fontScale = 1.0`. Pass it through to `_build()`.

- [X] T002 Add `fontScale` parameter to the private `AppTheme._build()` method in `frontend/lib/theme/app_theme.dart`. Currently the signature is `static ThemeData _build(Brightness brightness, Color accent, String fontFamily)`. Add a fourth parameter: `double fontScale`. Do NOT apply it yet — just thread it through. This task only changes the method signatures.

- [X] T003 Apply `fontScale` to all 7 TextTheme fontSize values inside `_build()` in `frontend/lib/theme/app_theme.dart`. Multiply each fontSize by `fontScale`. The current values and their locations in the `textTheme: base.copyWith(...)` block are:
  - `displayLarge`: `fontSize: 28` → `fontSize: 28 * fontScale`
  - `titleLarge`: `fontSize: 20` → `fontSize: 20 * fontScale`
  - `titleMedium`: `fontSize: 16` → `fontSize: 16 * fontScale`
  - `bodyLarge`: `fontSize: 14` → `fontSize: 14 * fontScale`
  - `bodyMedium`: `fontSize: 13` → `fontSize: 13 * fontScale`
  - `bodySmall`: `fontSize: 11` → `fontSize: 11 * fontScale`
  - `labelSmall`: `fontSize: 10` → `fontSize: 10 * fontScale`

- [X] T004 Apply `fontScale` to all 8 component-level theme fontSize values inside `_build()` in `frontend/lib/theme/app_theme.dart`. Multiply each fontSize by `fontScale`. The current values and their locations are:
  - `inputDecorationTheme` → `hintStyle`: `fontSize: 13` → `fontSize: 13 * fontScale`
  - `inputDecorationTheme` → `labelStyle`: `fontSize: 11` → `fontSize: 11 * fontScale`
  - `elevatedButtonTheme` → `textStyle`: `fontSize: 13` → `fontSize: 13 * fontScale`
  - `outlinedButtonTheme` → `textStyle`: `fontSize: 13` → `fontSize: 13 * fontScale`
  - `chipTheme` → `labelStyle`: `fontSize: 12` → `fontSize: 12 * fontScale`
  - `navigationBarTheme` → `labelTextStyle` (selected): `fontSize: 10` → `fontSize: 10 * fontScale`
  - `navigationBarTheme` → `labelTextStyle` (unselected): `fontSize: 10` → `fontSize: 10 * fontScale`
  - `appBarTheme` → `titleTextStyle`: `fontSize: 17` → `fontSize: 17 * fontScale`

- [X] T005 Pass `themeController.fontScale` to `AppTheme.light()` and `AppTheme.dark()` in `frontend/lib/main.dart`. Currently line 45-46 read:
  ```dart
  theme: AppTheme.light(themeController.color, themeController.fontFamily),
  darkTheme: AppTheme.dark(themeController.color, themeController.fontFamily),
  ```
  Change to:
  ```dart
  theme: AppTheme.light(themeController.color, themeController.fontFamily, themeController.fontScale),
  darkTheme: AppTheme.dark(themeController.color, themeController.fontFamily, themeController.fontScale),
  ```

**Checkpoint**: Foundation ready. The font scale value from ThemeController is now threaded through to all 15 theme font sizes. The app should rebuild the theme whenever `themeController.fontScale` changes (ThemeController already calls `notifyListeners()` in `setFontScale()`, and `main.dart` already wraps `MaterialApp` in an `AnimatedBuilder` listening to `themeController`).

---

## Phase 3: User Story 1 - User Changes Font Scale and Sees Immediate Effect (Priority: P1) 🎯 MVP

**Goal**: User selects a text size option in Settings and all theme-based text immediately renders at the chosen scale. Preference persists across restarts.

**Independent Test**: Open the app → Settings → Appearance → Text Size → tap "Large" → navigate to any screen → confirm headings, body text, button labels, chips, nav bar labels, and app bar title are all visibly larger. Restart app → confirm "Large" is still selected and text is still scaled.

### Implementation for User Story 1

- [ ] T006 [US1] Verify the complete wiring works end-to-end by manually testing the app: launch the app, go to Settings > Appearance > Text Size, select each of the 4 options (Small, Default, Large, X-Large) one by one, and confirm that theme-based text visibly changes size on the Settings page itself (e.g., section labels, button text, navigation bar labels).

- [ ] T007 [US1] Navigate to the Dashboard screen, Work Orders screen, Files screen, and Calendar screen with "X-Large" (1.3x) selected. Verify that theme-styled text (headings, body, labels) is visibly larger and no text overflows or clips. If any layout issues are found, document them for the Polish phase.

- [ ] T008 [US1] Verify persistence: select "Large" (1.15x), fully close and reopen the app. Confirm the Text Size option still shows "Large" selected and text renders at the larger size immediately on launch.

**Checkpoint**: User Story 1 is complete. Users can change font scale and it takes effect immediately and persists.

---

## Phase 4: User Story 2 - Font Scale Works Across Both Themes (Priority: P1)

**Goal**: Font scale applies identically in light mode, dark mode, and system mode. Switching themes does not reset the font scale.

**Independent Test**: Set font scale to "X-Large", switch between light and dark mode, confirm text sizes remain scaled. Return to Settings and confirm Text Size still shows "X-Large".

### Implementation for User Story 2

- [ ] T009 [US2] With "X-Large" selected, switch from Light to Dark mode in Settings > Appearance. Verify all theme-based text remains at 1.3x scale in dark mode. Switch back to Light — verify 1.3x scale still applies.

- [ ] T010 [US2] Switch to "System" theme mode with "X-Large" selected. If the device/browser is in dark mode, verify dark theme shows 1.3x text. If in light mode, verify light theme shows 1.3x text. The font scale must be independent of the theme mode.

**Checkpoint**: Both user stories are complete. Font scale works across all theme modes.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Fix any layout issues discovered during verification and handle edge cases.

- [ ] T011 If any layout overflow was found in T007, fix the affected screens by adjusting container constraints (e.g., adding `Flexible`, `Expanded`, or `overflow: TextOverflow.ellipsis` where needed). Only fix screens that actually overflow at 1.3x — do NOT preemptively modify screens that work fine.

- [ ] T012 Verify font scale works correctly when combined with a non-default font family: select "Poppins" as font type and "X-Large" as text size. Navigate through 3-4 screens and confirm both preferences apply together without issues.

- [ ] T013 Run `quickstart.md` verification checklist: confirm all 8 items pass (Small works, Default matches current, Large works, X-Large works, persistence works, light/dark identical, no overflow, font family + scale combo works).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Skipped — not needed.
- **Foundational (Phase 2)**: No dependencies — start immediately. Tasks T001-T005 are sequential (each builds on the previous signature change). BLOCKS all user stories.
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion.
- **User Story 2 (Phase 4)**: Depends on Phase 2 completion. Can run in parallel with US1 (but US1 is recommended first as it validates the basic wiring).
- **Polish (Phase 5)**: Depends on Phase 3 and Phase 4 completion.

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Phase 2 — no dependencies on other stories.
- **User Story 2 (P1)**: Can start after Phase 2 — independent of US1 but naturally follows it since it tests theme switching which requires the same wiring.

### Within Phase 2 (Implementation)

Tasks MUST be executed in order:
1. T001 (add param to `light()`/`dark()`) → T002 (add param to `_build()`) → T003 (apply to TextTheme) and T004 (apply to component themes) can be parallel → T005 (wire in main.dart)

### Parallel Opportunities

```
# T003 and T004 can run in parallel (different sections of the same method, no overlap):
Task T003: Apply fontScale to 7 TextTheme fontSize values
Task T004: Apply fontScale to 8 component theme fontSize values

# T009 and T010 can run in parallel (independent verification scenarios):
Task T009: Verify light/dark mode switching
Task T010: Verify system theme mode
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (T001-T005) — ~5 edits across 2 files
2. Complete Phase 3: User Story 1 (T006-T008) — verification only
3. **STOP and VALIDATE**: Font scale setting works and persists
4. Deploy/demo if ready

### Incremental Delivery

1. Complete Phase 2 → Foundation ready (font scale wired into theme)
2. Verify User Story 1 → Font scale works (MVP!)
3. Verify User Story 2 → Works across themes
4. Polish → Fix any overflow issues found

### Summary

**Total files to modify**: 2 (`app_theme.dart`, `main.dart`)
**Total files unchanged**: 2 (`theme_controller.dart`, `settings_page.dart` — already functional)
**Total implementation tasks**: 5 (T001-T005)
**Total verification tasks**: 8 (T006-T013)
**Total tasks**: 13

---

## Notes

- This is a minimal-change feature: only 2 source files need editing
- ThemeController already persists fontScale and calls notifyListeners() — no changes needed
- Settings UI already displays and calls setFontScale() — no changes needed
- The AnimatedBuilder in main.dart already listens to themeController — theme rebuilds automatically
- Hardcoded fontSize values (457 across 40 files) are explicitly OUT OF SCOPE
- PDF service font sizes are explicitly OUT OF SCOPE
