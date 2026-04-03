# Quickstart: Fix System Status Screen Font Scale

**Feature**: 008-fix-status-font-scale  
**Date**: 2026-04-03

## What This Fix Does

Removes manual fontScale multiplications from settings_page.dart that cause double-scaling. The system_status_screen issue is already resolved by the global `MediaQuery.textScaler` in main.dart.

## Implementation

1. In `settings_page.dart`, revert all `fontSize: N * s`, `fontSize: N * fs`, and `fontSize: N * fontScale` back to `fontSize: N`
2. Remove the `fontScale` parameter from `_DarkModeRow`, `_FontTypeRow`, `_FontSizeRow`, `_NavBarRow`
3. Remove the `final s = currentScale;` and `final fs = widget.themeController.fontScale;` variables

## Verification

- [ ] Settings page text sizes match other screens at each scale level (no double-scaling)
- [ ] System Status screen text scales correctly when changing Text Size
- [ ] All 4 scale options (Small/Default/Large/X-Large) work correctly app-wide
- [ ] Default (1.0x) shows no change from original baseline sizes
