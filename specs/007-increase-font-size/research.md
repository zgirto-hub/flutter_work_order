# Research: Activate Font Scale Setting

**Feature**: 007-increase-font-size  
**Date**: 2026-04-03

## Research Summary

No NEEDS CLARIFICATION items in technical context. Research focused on understanding the existing font scale infrastructure and determining the minimal wiring needed.

## Decision 1: Approach — Activate Existing System vs. Hardcode +2

**Decision**: Activate the existing font scale system rather than hardcoding +2 to every fontSize value.

**Rationale**: The app already has complete infrastructure for user-selectable font scaling: ThemeController stores `fontScale` in SharedPreferences, and the Settings page has a working Text Size UI with 4 options (Small 0.85x, Default 1.0x, Large 1.15x, X-Large 1.3x). The only gap is that `fontScale` is never passed to `AppTheme._build()`. Wiring this up gives users control over text size with minimal code changes (~2 files), versus modifying 457 hardcoded values across 40 files.

**Alternatives considered**:
- Hardcode +2 to all 457 fontSize values: Rejected — more invasive (40 files), less flexible (no user control), and the font scale UI would remain broken.
- MediaQuery textScaler: Rejected — affects all text including hardcoded sizes, which could break tightly constrained layouts.

## Decision 2: Scope — Theme-Only vs. All Font Sizes

**Decision**: Apply font scaling only to the 15 centralized theme font sizes in app_theme.dart.

**Rationale**: The centralized theme covers all 7 TextTheme styles plus 8 component-level overrides (buttons, chips, inputs, app bar, nav bar). These are the "correct" way to define text styles in Flutter. The ~457 hardcoded fontSize values bypass the theme and would need individual refactoring — a separate effort. Theme-only scaling delivers immediate user value with minimal risk.

**Alternatives considered**:
- Refactor all 457 hardcoded values: Rejected — massive scope creep, separate refactoring task.
- Scale theme + hardcoded: Rejected — same scope issue.

## Existing Infrastructure Inventory

### ThemeController (theme_controller.dart)
- `fontScale` property: stored, persisted via SharedPreferences, exposed via getter
- `setFontScale(double)`: setter that updates state and persists
- Available fonts: `kAvailableFonts = ['Inter', 'DM Sans', 'Roboto', 'Poppins', 'Lato', 'Nunito']`
- **Status**: Fully functional. No changes needed.

### Settings UI (settings_page.dart)
- `_FontSizeRow` widget: displays 4 scale options with labels
- Scale values: `[0.85, 1.0, 1.15, 1.3]`
- Labels: `['Small', 'Default', 'Large', 'X-Large']`
- Calls `themeController.setFontScale(scale)` on tap
- **Status**: Fully functional. No changes needed.

### AppTheme (app_theme.dart)
- `light()` and `dark()` factory methods accept `accent` color and `fontFamily`
- `_build()` does all theme construction — both light and dark use same method
- 15 fontSize values defined:
  - TextTheme (7): displayLarge 28, titleLarge 20, titleMedium 16, bodyLarge 14, bodyMedium 13, bodySmall 11, labelSmall 10
  - InputDecoration (2): hint 13, label 11
  - ElevatedButton (1): 13
  - OutlinedButton (1): 13
  - Chip (1): 12
  - NavigationBar (2): 10 (selected), 10 (unselected)
  - AppBar (1): 17
- **Status**: Missing fontScale parameter. This is the gap to fill.

### main.dart
- Calls `AppTheme.light(themeController.color, themeController.fontFamily)` and `.dark()`
- **Status**: Does not pass fontScale. Needs to add it.
