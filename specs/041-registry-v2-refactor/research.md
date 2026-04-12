# Research: Document Registry V2 UI Refactor

**Date**: 2026-04-12  
**Branch**: `041-registry-v2-refactor`

## Research Summary

This is a frontend-only UI refactor replicating an existing proven pattern (Letters v2). No new technologies, external dependencies, or architectural decisions are required. All research items resolved by examining existing codebase patterns.

## Findings

### 1. Expandable Card Animation Pattern

**Decision**: Replicate the `_LetterCard` pattern from `letter_history_tab_v2.dart`

**Rationale**: The Letters v2 expandable card is production-tested and provides exactly the behavior specified: AnimationController (240ms), CurvedAnimation (easeInOutCubic for size/chevron, easeOut for fade), SizeTransition + FadeTransition for expanded content, and Tween<double>(0.0, 0.5) for chevron rotation.

**Alternatives considered**:
- Flutter's built-in `ExpansionTile` — rejected because it doesn't match the custom visual styling (card borders change on expand, action buttons in expanded footer, specific animation curves)
- `AnimatedCrossFade` — rejected because it crossfades between two widgets rather than revealing content below, which doesn't match the desired expand-from-bottom behavior

### 2. Pushed Form Navigation Pattern

**Decision**: Replicate the `_LetterFormScreen` pattern from `letter_generator_screen_v2.dart`

**Rationale**: The Letters v2 screen uses `Navigator.push` with `MaterialPageRoute` to push a private `_LetterFormScreen` widget, passing an optional edit object and an `onLetterSaved` callback. The callback triggers `UniqueKey` refresh in the parent. This is the exact pattern needed.

**Alternatives considered**:
- Bottom sheet form — rejected per spec requirement for full-screen pushed form
- In-place form toggle (current pattern) — rejected per spec requirement to separate browsing and editing modes

### 3. Single-Expanded-Card State Management

**Decision**: Use an `_expandedIndex` integer (nullable) tracked in the list parent's state, passed as `expanded: bool` to each card widget

**Rationale**: This is the exact pattern used in `letter_history_tab_v2.dart`. The parent calls `setState(() => _expandedIndex = i)` on tap, and each card widget's `didUpdateWidget` checks if `expanded` changed to trigger `_ctrl.forward()` or `_ctrl.reverse()`.

**Alternatives considered**:
- Per-card self-managed expansion state — rejected because it doesn't enforce the "only one expanded at a time" requirement without additional coordination logic

### 4. Shared Widget Availability

**Decision**: Use existing `ClaudeFAB` and `EmptyState` from `claude_widgets.dart`

**Rationale**: Both widgets are already available, production-tested, and match the Letters v2 visual language. ClaudeFAB accepts `onTap`, `tooltip`, `semanticsLabel`. EmptyState accepts `icon`, `title`, `subtitle`, optional `action`.

**Alternatives considered**: None — these are the canonical shared widgets for this project.

### 5. File Structure

**Decision**: Single file rewrite of `document_registry_screen.dart` containing three widgets

**Rationale**: The Document Registry has fewer concerns than Letters v2 (no tabs, no HTML editor, no certificate linking). Three private widgets in one file keeps the refactor self-contained:
1. `DocumentRegistryScreen` — main scaffold with list, search, FAB
2. `_RegistryFormScreen` — pushed create/edit form
3. `_RegistryEntryCard` — expandable card with animations

**Alternatives considered**:
- Splitting into 3 files (like Letters v2 which has screen, history tab, form tab) — rejected because the registry screen is much simpler and doesn't warrant the file overhead. Letters v2 has ~1200 lines in the form tab alone due to the HTML editor; the registry form is ~200 lines.

## Unresolved Items

None. All technical decisions resolved from existing codebase patterns.
