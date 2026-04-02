# Implementation Plan: Activate Font Scale Setting

**Branch**: `007-increase-font-size` | **Date**: 2026-04-03 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/007-increase-font-size/spec.md`

## Summary

Wire up the existing but non-functional font scale setting in the app. The ThemeController already stores a fontScale preference and the Settings UI already lets users pick Small/Default/Large/X-Large — but the value is never applied to the theme. This plan passes the fontScale into AppTheme._build() and multiplies all 15 centralized theme font sizes by it.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x  
**Primary Dependencies**: Flutter Material, GoogleFonts, app_theme.dart (centralized theme), ThemeController  
**Storage**: SharedPreferences (already used by ThemeController for fontScale persistence)  
**Testing**: Manual visual inspection across all screens at each scale level  
**Target Platform**: Web (primary), iOS, Android  
**Project Type**: Mobile/web app (Flutter)  
**Performance Goals**: No performance impact — theme rebuild on scale change only  
**Constraints**: Must not break layouts at 1.3x (X-Large); only theme-based styles in scope  
**Scale/Scope**: 15 centralized theme font sizes in 1 file (app_theme.dart), plus wiring in main.dart

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | Justified exclusion | Frontend-only cosmetic change. No backend endpoint, migration, or API needed — font scale is purely client-side. |
| II. Explicit Over Automatic | Pass | User explicitly selects their preferred scale; no implicit behavior. |
| III. Role-Based Access Control | N/A | All roles see the same font scale options. |
| IV. Server-First File Storage | N/A | No file storage involved. |
| V. Client-Side Computation | Pass | Font scaling is computed client-side from the stored preference. |
| VI. Audit Everything | N/A | User preference change — not a user-facing action requiring audit logging. |
| VII. Simplicity & YAGNI | Pass | Activating existing infrastructure (ThemeController + Settings UI). No new abstractions. |

All gates pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/007-increase-font-size/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── spec.md              # Feature specification
├── quickstart.md        # Phase 1 output
├── checklists/          # Quality checklists
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
frontend/
├── lib/
│   ├── theme/
│   │   ├── app_theme.dart          # PRIMARY: Add fontScale parameter to _build(), multiply 15 font sizes
│   │   └── theme_controller.dart   # Already stores fontScale — no changes needed
│   ├── main.dart                   # Pass themeController.fontScale to AppTheme.light() and AppTheme.dark()
│   └── screens/
│       └── settings_page.dart      # Already has Text Size UI — no changes needed
```

**Structure Decision**: Only 2 files need modification: `app_theme.dart` (accept and apply fontScale) and `main.dart` (pass fontScale from ThemeController to AppTheme). The ThemeController and Settings UI already work correctly.
