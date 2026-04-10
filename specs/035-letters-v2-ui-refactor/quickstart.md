# Quickstart: Letters V2 UI/UX Refactor

**Date**: 2026-04-10  
**Feature**: 035-letters-v2-ui-refactor

## Prerequisites

- Flutter SDK (3.x) installed
- Project dependencies resolved (`flutter pub get` in `frontend/`)
- Running backend server (for letter generation/history API calls)

## Development

```bash
cd frontend
flutter pub get
flutter run -d chrome --web-renderer canvaskit
```

## Files to Modify

All changes are in `frontend/lib/screens/letters_v2/`:

| File | Changes |
|------|---------|
| `letter_generator_screen_v2.dart` | Header, tab system, overall layout structure |
| `letter_form_tab_v2.dart` | Form field styling, focus nodes, keyboard handling, button styling |
| `letter_history_tab_v2.dart` | Card redesign, empty state, loading state, bottom sheet keyboard insets |

## Reference Files (read-only)

| File | Purpose |
|------|---------|
| `frontend/lib/screens/work_orders/add_work_order.dart` | Canonical header, `_Tab` widget, form field patterns, `_ensureVisible` |
| `frontend/lib/screens/work_orders/work_order_home.dart` | List layout patterns |
| `frontend/lib/widgets/work_order_card.dart` | Card visual design reference |
| `frontend/lib/widgets/claude_widgets.dart` | Shared `EmptyState`, `SectionLabel`, `StatusBadge` widgets |
| `frontend/lib/theme/app_theme.dart` | `AppColors`, `AppShadows`, `InputDecorationTheme` |

## Verification

### Phase 1: Header, Tabs, Layout
1. Navigate to Letters V2 screen
2. Verify back button is 34x34, rounded (9px), `bgSurface2`, with `arrow_back_rounded` icon (16px)
3. Verify tabs use bottom-border active state with `AppColors.accent` color
4. Verify tab switching animates smoothly

### Phase 2: Form Styling
1. Open letter creation form
2. Verify all fields use theme `InputDecoration` (no custom overrides)
3. On iOS PWA: tap a field, verify it scrolls into view after keyboard appears
4. Submit empty form, verify validation errors use danger colors

### Phase 3: History, Cards, Polish
1. View letter history with existing letters
2. Verify cards use `bgSurface` background, `borderRadius: 14`, theme borders
3. Verify empty state uses shared `EmptyState` widget with theme colors
4. Open letter detail bottom sheet, verify keyboard inset handling
5. Trigger PDF generation, verify button loading spinner (18x18, white)
