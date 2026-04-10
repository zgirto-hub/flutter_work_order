# Research: Letters V2 UI/UX Refactor

**Date**: 2026-04-10  
**Feature**: 035-letters-v2-ui-refactor

## R1: Tab System — Segmented Control vs. Bottom-Border Tabs

**Decision**: Replace the Letters V2 `_SegmentedTabs` pill-style segmented control with the Work Orders `_Tab` bottom-border pattern.

**Rationale**: The Work Orders screen uses a `_Tab` widget with bottom border active state (`AppColors.accent`, 2px), text color toggle (`accent` when active, `textSecondary` when inactive), and optional badge support. This is the canonical tab pattern in the app. The current Letters V2 `_SegmentedTabs` uses a completely different pill/segmented approach with background color transitions and box shadows, creating visual inconsistency.

**Alternatives considered**:
- Keep segmented control but restyle to match accent colors — rejected because the shape and interaction model differ fundamentally from Work Orders.
- Use Material `TabBar` — rejected because the Work Orders custom `_Tab` provides the exact styling needed without fighting Material defaults.

## R2: Back Button Container Pattern

**Decision**: Adopt the exact 34x34 rounded container pattern from `add_work_order.dart`.

**Rationale**: Work Orders uses `Container(width: 34, height: 34)` with `bgSurface2` background, `BorderRadius.circular(9)`, `Border.all(color: AppColors.border2, width: 0.5)`, and `Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.textSecondary)`. Letters V2 already uses a nearly identical pattern (34x34, bgSurface2, borderRadius 9, border2) but with `Icons.arrow_back` (not `arrow_back_rounded`) and size 17 (not 16). The differences are minor but should be normalized.

**Alternatives considered**: Extract to shared widget — deferred per YAGNI (only 2 screens use it currently).

## R3: Form Field Styling — Theme vs. Custom InputDecoration

**Decision**: Use the app's `InputDecorationTheme` from `app_theme.dart` as the base, removing custom `_inputDecor()` helper in favor of theme defaults.

**Rationale**: The global `InputDecorationTheme` already defines: `filled: true`, `fillColor: bgSurface`, `contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 11)`, `borderRadius: 10`, `enabledBorder: border2/0.5px`, `focusedBorder: accent/2px`. Letters V2 has a custom `_inputDecor(hint)` helper that largely duplicates these theme defaults. Removing the helper and relying on the theme ensures consistency and reduces code.

**Alternatives considered**: Keep the helper for hint text customization — unnecessary since `InputDecoration(hintText: ...)` works with theme defaults.

## R4: iOS PWA Keyboard Scroll Handling

**Decision**: Implement the `_ensureVisible(FocusNode)` pattern from `add_work_order.dart` in the letter form.

**Rationale**: Work Orders uses a `FocusNode.addListener` pattern with a 400ms delay before calling `Scrollable.ensureVisible(context, alignment: 0.3, duration: 300ms, curve: easeInOut)`. This delay accommodates the iOS PWA keyboard animation. Letters V2 currently has no such handling, meaning form fields can be obscured by the keyboard.

**Alternatives considered**: Using `WidgetsBindingObserver.didChangeMetrics` — rejected because the FocusNode approach is already proven in the codebase and more targeted.

## R5: Letter History Card Design

**Decision**: Redesign letter history cards to use the card pattern from `WorkOrderCard` — specifically the `AnimatedContainer` with `bgSurface` background, `borderRadius: 14`, `border: border/0.5px`, and 14px internal padding.

**Rationale**: The current history cards use basic `Card` + `ListTile` with no theme-specific styling. Work Order cards use a more structured layout with explicit padding, border radius, and color tokens. The letter cards don't need the expandable/selection features of `WorkOrderCard`, but should match the visual foundation.

**Alternatives considered**:
- Reuse `WorkOrderCard` directly — rejected because it has work-order-specific logic (status dots, selection mode, expansion).
- Create a shared `AppCard` base widget — deferred per YAGNI; the visual pattern can be applied directly.

## R6: Empty State Widget Reuse

**Decision**: Use the existing shared `EmptyState` widget from `claude_widgets.dart`.

**Rationale**: The shared `EmptyState` widget already provides `icon`, `title`, `subtitle`, optional `action`, and optional `iconColor` parameters. Letters V2 currently builds its own inline empty state with `Icons.mail_outline`, `Colors.grey`, and a simple text. Switching to the shared widget ensures theme color usage and consistent layout.

**Alternatives considered**: None — the shared widget is the obvious choice.

## R7: Button Loading State Pattern

**Decision**: Replicate the Work Orders pattern of swapping button child content with a `SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))`.

**Rationale**: Work Orders uses a conditional inside button child: when loading, show spinner; when idle, show text. The button also sets `onPressed: null` to disable during loading. Letters V2 buttons currently don't have consistent loading states.

**Alternatives considered**: Using `ElevatedButton.icon` with spinner as icon — rejected because Work Orders replaces the entire child, which is simpler and more visually clean.

## R8: Bottom Sheet Keyboard Inset Handling

**Decision**: Add `MediaQuery.of(context).viewInsets.bottom` to bottom sheet content padding, matching the Work Orders quick-status-sheet pattern.

**Rationale**: Work Orders bottom sheets use `EdgeInsets.fromLTRB(16, 16, 16, 16 + viewInsets.bottom)` to prevent content from being hidden behind the keyboard. Letters V2 bottom sheets currently use fixed `EdgeInsets.all(20)` which doesn't account for keyboard.

**Alternatives considered**: `resizeToAvoidBottomInset` on Scaffold — doesn't apply to modal bottom sheets.
