# Implementation Plan: Fix System Status Screen Font Scale

**Branch**: `008-fix-status-font-scale` | **Date**: 2026-04-03 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/008-fix-status-font-scale/spec.md`

## Summary

**Investigation result**: The system_status_screen font scale issue is **already resolved**. Commit `5195d4b` added `MediaQuery(textScaler: TextScaler.linear(themeController.fontScale))` in `main.dart`, which globally scales ALL text in the entire app — including system_status_screen.dart. No per-file font size modifications are needed.

However, this investigation uncovered a **double-scaling bug** in `settings_page.dart`: commit `8db895b` manually multiplied 26 hardcoded fontSize values by fontScale, and now the global `MediaQuery.textScaler` multiplies them again. These manual multiplications must be removed.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x  
**Primary Dependencies**: Flutter Material, MediaQuery.textScaler  
**Storage**: N/A  
**Testing**: Manual visual inspection  
**Target Platform**: Web (primary), iOS, Android  
**Project Type**: Mobile/web app (Flutter)  
**Performance Goals**: N/A  
**Constraints**: Must not introduce double-scaling  
**Scale/Scope**: 1 file to fix (settings_page.dart) — revert 26 manual fontScale multiplications

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | Justified exclusion | Frontend-only bug fix. |
| II. Explicit Over Automatic | N/A | No state transitions. |
| III. Role-Based Access Control | N/A | No access control. |
| IV. Server-First File Storage | N/A | No file storage. |
| V. Client-Side Computation | Pass | Font scaling via MediaQuery is client-side. |
| VI. Audit Everything | N/A | Bug fix, not user action. |
| VII. Simplicity & YAGNI | Pass | Removing unnecessary manual scaling. |

## Project Structure

### Source Code

```text
frontend/lib/
├── main.dart                       # Already has MediaQuery.textScaler — NO CHANGES NEEDED
├── screens/
│   ├── settings_page.dart          # FIX: Remove 26 manual fontScale multiplications (double-scaling bug)
│   └── system_status_screen.dart   # NO CHANGES NEEDED — already scaled by MediaQuery.textScaler
```

## What Happened

1. **Commit 53ea9ef** (007-increase-font-size PR): Added `fontScale` parameter to `AppTheme._build()`, multiplying 15 theme font sizes by fontScale
2. **Commit 8db895b**: Manually multiplied 26 hardcoded font sizes in `settings_page.dart` by fontScale
3. **Commit 5195d4b** (separate fix): Replaced the per-theme approach with `MediaQuery(textScaler: TextScaler.linear(fontScale))` in `main.dart`, which scales ALL text globally. Also reverted the `AppTheme._build()` fontScale changes.
4. **Result**: settings_page.dart still has manual `* s` / `* fs` / `* fontScale` multiplications that now stack with the global textScaler → **double-scaling on settings page**

## Fix

Remove all `* s`, `* fs`, and `* fontScale` multiplications from `settings_page.dart`, reverting hardcoded font sizes to their original static values. Also remove the `fontScale` parameters from the sub-widgets (`_DarkModeRow`, `_FontTypeRow`, `_FontSizeRow`, `_NavBarRow`) and the `s` / `fs` shorthand variables.
