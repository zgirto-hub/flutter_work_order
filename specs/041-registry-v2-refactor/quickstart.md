# Quickstart: Document Registry V2 UI Refactor

**Branch**: `041-registry-v2-refactor`

## What This Feature Does

Refactors the Document Registry screen from a combined form-and-list layout to a modern card-based expandable list with a floating action button (FAB) that pushes a full-screen form. Matches the Letters v2 design pattern exactly.

## Files Changed

| File | Change Type | Description |
| ---- | ----------- | ----------- |
| `frontend/lib/screens/document_registry/document_registry_screen.dart` | Rewrite | Main screen, pushed form, expandable card |

## Files Referenced (unchanged)

| File | Purpose |
| ---- | ------- |
| `frontend/lib/models/registry_entry.dart` | Data model |
| `frontend/lib/services/document_registry_service.dart` | Backend API service |
| `frontend/lib/widgets/claude_widgets.dart` | ClaudeFAB, EmptyState widgets |
| `frontend/lib/widgets/form_fields.dart` | ValidatedTextField widget |
| `frontend/lib/theme/app_theme.dart` | AppColors, styling tokens |
| `frontend/lib/config.dart` | AppConfig.downloadUrl |
| `frontend/lib/models/nav_screen.dart` | Navigation wiring (unchanged) |

## Reference Patterns (to replicate)

| File | What to replicate |
| ---- | ----------------- |
| `frontend/lib/screens/letters_v2/letter_generator_screen_v2.dart` | Main screen + FAB + pushed form + UniqueKey refresh |
| `frontend/lib/screens/letters_v2/letter_history_tab_v2.dart` | Expandable card with animations, RefreshIndicator, EmptyState |

## How to Test

1. Run `flutter run -d chrome` from `frontend/`
2. Navigate to Document Registry via the navigation menu
3. Verify: list view shows expandable cards, FAB opens create form, edit works from expanded card actions
4. Verify: all existing functionality preserved (create, edit, delete, attach, search, PDF extract)

## Key Design Decisions

- **Single file**: All three widgets (main screen, form screen, entry card) live in `document_registry_screen.dart` because the registry is simpler than Letters v2 (no tabs, no HTML editor)
- **Animation tokens**: 240ms duration, easeInOutCubic for size/chevron, easeOut for fade — matching Letters v2 exactly
- **Card styling**: 14px border radius, 0.5px border, 14px padding, AppColors color scheme
- **State management**: `_expandedIndex` for single-card-expanded; `UniqueKey` for list refresh after form submission
