# Research: Fix System Status Screen Font Scale

**Feature**: 008-fix-status-font-scale  
**Date**: 2026-04-03

## Key Finding

The system_status_screen font scale issue was already resolved by commit `5195d4b`, which added a global `MediaQuery(textScaler: TextScaler.linear(themeController.fontScale))` wrapper in `main.dart`. This approach scales ALL text in the entire app automatically — no per-file modifications needed.

## Decision: Use Global TextScaler Instead of Per-File Multiplications

**Decision**: Keep the `MediaQuery.textScaler` approach. Remove manual per-file fontScale multiplications.

**Rationale**: Flutter's `TextScaler` is the framework-standard way to apply font scaling. It automatically affects all `Text` widgets and `RichText` widgets in the subtree, including those with hardcoded `fontSize` values. This means:
- system_status_screen.dart (43 hardcoded font sizes): automatically scaled
- settings_page.dart (26 hardcoded font sizes): automatically scaled, but currently double-scaled due to leftover manual multiplications
- All other screens: automatically scaled

**Alternatives considered**:
- Per-file manual multiplication (what we did in settings_page.dart): Rejected — doesn't scale to 40+ files, error-prone, and now causes double-scaling with the global textScaler.
- Per-theme fontScale in AppTheme._build() (what 007-increase-font-size PR did): Already reverted by commit 5195d4b — theme font sizes were also being double-scaled via TextScaler.

## Bug: Double-Scaling in settings_page.dart

Commit `8db895b` added manual `* s` / `* fs` / `* fontScale` multiplications to 26 font sizes in settings_page.dart. Commit `5195d4b` then added global `MediaQuery.textScaler` without removing these manual multiplications. Result: settings_page.dart text is scaled twice.

**Fix**: Revert the manual multiplications in settings_page.dart to their original static values.
