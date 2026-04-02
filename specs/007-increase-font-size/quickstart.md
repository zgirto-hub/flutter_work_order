# Quickstart: Activate Font Scale Setting

**Feature**: 007-increase-font-size  
**Date**: 2026-04-03

## What This Feature Does

Wires up the existing but non-functional font scale setting so users can actually adjust text size in the app via Settings > Appearance > Text Size. The UI and persistence already work — only the theme application is missing.

## Implementation Approach

1. **app_theme.dart**: Add `fontScale` parameter to `light()`, `dark()`, and `_build()`. Multiply all 15 fontSize values by it.
2. **main.dart**: Pass `themeController.fontScale` to `AppTheme.light()` and `AppTheme.dark()`.
3. **Visual verification**: Test all 4 scale options across light/dark themes.

## Key Rules

- Only modify `app_theme.dart` and `main.dart`
- Do NOT touch `theme_controller.dart` or `settings_page.dart` — they already work
- Do NOT touch hardcoded fontSize values in screen/widget files — out of scope
- Do NOT touch PDF service font sizes — out of scope
- Multiply each fontSize by fontScale (e.g., `fontSize: 13 * fontScale`)
- Default fontScale is 1.0 — existing behavior must not change at default

## Verification Checklist

- [ ] "Small" (0.85x) makes theme text visibly smaller
- [ ] "Default" (1.0x) matches current behavior exactly
- [ ] "Large" (1.15x) makes theme text visibly larger
- [ ] "X-Large" (1.3x) makes theme text significantly larger
- [ ] Preference persists across app restart
- [ ] Light and dark themes scale identically
- [ ] No layout overflow at 1.3x scale on any screen
- [ ] Font family change + font scale work together correctly
