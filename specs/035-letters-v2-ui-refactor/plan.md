# Implementation Plan: Letters V2 UI/UX Refactor

**Branch**: `035-letters-v2-ui-refactor` | **Date**: 2026-04-10 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/035-letters-v2-ui-refactor/spec.md`

## Summary

Refactor the Letters V2 screen (`letter_generator_screen_v2.dart`, `letter_form_tab_v2.dart`, `letter_history_tab_v2.dart`) to achieve exact visual and interaction parity with the Work Orders screen design system. This is a frontend-only refactor touching 3 files in `frontend/lib/screens/letters_v2/`, adopting the canonical header, tab, form, card, and button patterns already established in the Work Orders screen. No backend, data model, or WYSIWYG editor changes.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x  
**Primary Dependencies**: Flutter Material, AppColors/AppShadows/AppTheme (centralized theme), shared widgets from `claude_widgets.dart` (EmptyState, SectionLabel)  
**Storage**: N/A (no data changes)  
**Testing**: Visual manual testing on desktop browser + iOS PWA  
**Target Platform**: Web (desktop browsers) + iOS PWA  
**Project Type**: Mobile/web application (Flutter PWA)  
**Performance Goals**: Smooth 60fps tab transitions, no layout jank on keyboard appear/dismiss  
**Constraints**: Must preserve all existing letter functionality, RTL support, WYSIWYG editor integration  
**Scale/Scope**: 3 files modified, ~50 screens in total app

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | **PASS (with exclusion)** | Frontend-only refactor. Backend, migration, and model layers are excluded because no behavior or data changes — purely visual. Documented in spec Assumptions. |
| II. Explicit Over Automatic | **PASS** | No new state transitions or assignments introduced. |
| III. Role-Based Access Control | **PASS** | No access control changes. Screen visibility remains unchanged. |
| IV. Server-First File Storage | **N/A** | No file storage changes. |
| V. Client-Side Computation | **PASS** | No new API calls or data fetching patterns introduced. |
| VI. Audit Everything | **PASS** | No new user-facing actions created. Existing actions (create, edit, delete letter) unchanged. |
| VII. Simplicity & YAGNI | **PASS** | Refactor applies existing patterns directly. No new abstractions, shared widgets, or premature generalizations. Uses existing `EmptyState` widget rather than creating a new one. |

**Technology Constraints**:
- PWA URL handling: Existing `openInNewTab()` usage in letter PDF download preserved as-is.
- No new dependencies added.

**Post-Phase 1 Re-check**: All gates still pass. No design decisions introduced complexity beyond applying established patterns.

## Project Structure

### Documentation (this feature)

```text
specs/035-letters-v2-ui-refactor/
├── plan.md              # This file
├── research.md          # Phase 0 output — pattern research
├── data-model.md        # Phase 1 output — no data changes documented
├── quickstart.md        # Phase 1 output — dev setup and verification
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
frontend/lib/
├── screens/letters_v2/
│   ├── letter_generator_screen_v2.dart   # MODIFY: header, tabs, layout
│   ├── letter_form_tab_v2.dart           # MODIFY: form styling, focus nodes, buttons
│   └── letter_history_tab_v2.dart        # MODIFY: cards, empty state, bottom sheets
├── theme/
│   └── app_theme.dart                    # READ-ONLY: AppColors, AppShadows, InputDecorationTheme
└── widgets/
    └── claude_widgets.dart               # READ-ONLY: EmptyState widget to import
```

**Structure Decision**: No new files or directories. All changes are modifications to the 3 existing Letters V2 screen files. Shared widgets (`EmptyState`) are imported, not duplicated.

## Phase 1: Header, Tabs, and Core Layout (P1)

### 1.1 Replace Header in `letter_generator_screen_v2.dart`

**Current**: Header container with back button (arrow_back icon, size 17) and title text.

**Target**: Match Work Orders `add_work_order.dart` header exactly:
- Container: `color: AppColors.bgSurface`, padding `EdgeInsets.fromLTRB(16, 12, 16, 0)`
- Back button: `Container(width: 34, height: 34)` with `bgSurface2`, `BorderRadius.circular(9)`, `Border.all(color: AppColors.border2, width: 0.5)`
- Icon: `Icons.arrow_back_rounded`, size 16, color `AppColors.textSecondary`
- Title: `fontSize: 20, fontWeight: w600, letterSpacing: -0.3, color: AppColors.textPrimary`
- Divider: `Divider(height: 0, thickness: 0.5, color: AppColors.border)`

**Changes**: Minor normalization — icon name (`arrow_back` → `arrow_back_rounded`), icon size (17 → 16), padding adjustment.

### 1.2 Replace Tab System in `letter_generator_screen_v2.dart`

**Current**: `_SegmentedTabs` widget — pill-shaped segmented control with animated background, box shadow on active tab.

**Target**: Replace with `_Tab` widget pattern from `add_work_order.dart`:
- Remove `_SegmentedTabs` class entirely
- Create local `_Tab` widget with: `label`, `active`, `onTap` parameters
- Active state: bottom border `BorderSide(color: AppColors.accent, width: 2)`
- Text: `fontSize: 13, fontWeight: w500`, color toggles between `accent` (active) and `textSecondary` (inactive)
- Container: `padding: EdgeInsets.only(bottom: 10)`, `margin: EdgeInsets.only(right: 20)`
- Tab bar: `Row` of `_Tab` widgets inside header area below title, above divider

**Changes**: Delete `_SegmentedTabs` (~65 lines), add `_Tab` (~40 lines). Update `_tabIndex` usage to work with new tab `onTap` callbacks. Remove outer `Container` with bgSurface2/border2 that wraps the segmented control.

### 1.3 Layout Structure Adjustment

**Current**: Column with header → segmented tabs (inside padded container) → Expanded content.

**Target**: Column with header (containing tabs inline) → Divider → Expanded content. Tabs sit inside the header container, below the title row, matching Work Orders where tabs are part of the header area before the divider.

## Phase 2: Form Styling, Input Fields, and Validation (P1)

### 2.1 Remove Custom Input Decoration Helper in `letter_form_tab_v2.dart`

**Current**: `_inputDecor(String hint)` helper that manually builds `InputDecoration` with hardcoded values duplicating theme defaults.

**Target**: Remove helper. Use `InputDecoration(hintText: hint)` or `InputDecoration(labelText: label)` directly — the global `InputDecorationTheme` already provides `filled`, `fillColor`, `contentPadding`, `border`, `enabledBorder`, `focusedBorder`, `hintStyle`, `labelStyle`.

### 2.2 Add Focus Nodes and iOS PWA Keyboard Handling in `letter_form_tab_v2.dart`

**Current**: No focus node management, no scroll-into-view on keyboard appear.

**Target**: 
- Declare `FocusNode` for each text field (reference, date, recipient, subject, body)
- Implement `_ensureVisible(FocusNode node)` method matching `add_work_order.dart`:
  - `node.addListener` → check `node.hasFocus && node.context != null`
  - `Future.delayed(Duration(milliseconds: 400))` → `Scrollable.ensureVisible(node.context!, alignment: 0.3, duration: Duration(milliseconds: 300), curve: Curves.easeInOut)`
- Call `_ensureVisible()` for each node in `initState`
- Dispose all focus nodes in `dispose`
- Attach focus nodes to corresponding `TextFormField` widgets

### 2.3 Standardize Form Labels in `letter_form_tab_v2.dart`

**Current**: `_buildLabel(text)` helper with `fontWeight: bold, fontSize: 14`.

**Target**: Evaluate if labels should use `SectionLabel` from `claude_widgets.dart` or be simplified to just `InputDecoration.labelText`. If Work Orders uses `labelText` in the input decoration directly, match that pattern and remove the separate label builder.

### 2.4 Standardize Button Styling in `letter_form_tab_v2.dart`

**Current**: Mixed button styling with some hardcoded `Color(0xFFCC0000)` (red) for accent buttons.

**Target**:
- Primary buttons: `ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(horizontal: 20, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))`
- Outlined buttons: `OutlinedButton.styleFrom(side: BorderSide(color: AppColors.border2, width: 0.5), padding: EdgeInsets.symmetric(horizontal: 16, vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))`
- Destructive buttons/icons: Use `AppColors.dangerText` instead of hardcoded red
- Loading state: Replace button child with `SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))` when loading; set `onPressed: null`

## Phase 3: History List, Cards, Empty States, and Final Polish (P2-P3)

### 3.1 Redesign Letter History Cards in `letter_history_tab_v2.dart`

**Current**: Basic `Card` + `ListTile` with default styling, hardcoded `Colors.grey` for date text.

**Target**: Replace with themed container matching Work Order card visual:
- Outer: `Container` with `bgSurface` background, `BorderRadius.circular(14)`, `Border.all(color: AppColors.border, width: 0.5)`
- Shadows: `AppShadows.cardLight`
- Padding: `EdgeInsets.all(14)`
- Title: `fontSize: 14, fontWeight: w600, color: AppColors.textPrimary`
- Subtitle: `fontSize: 13, color: AppColors.textSecondary`
- Date: `fontSize: 11, color: AppColors.textTertiary`
- Certificate badge: Use `AppColors.bgSurface2` background with `border2` border instead of default `Chip`
- Spacing between cards: `SizedBox(height: 8)` or `margin: EdgeInsets.only(bottom: 8)`

### 3.2 Replace Empty State in `letter_history_tab_v2.dart`

**Current**: Inline `Center(Column(Icon(Icons.mail_outline, color: Colors.grey), Text('No previous letters', color: Colors.grey)))`.

**Target**: Import and use `EmptyState` from `claude_widgets.dart`:
```
EmptyState(
  icon: Icons.mail_outline,
  title: 'No Letters Yet',
  subtitle: 'Letters you create will appear here',
)
```

### 3.3 Standardize Loading State in `letter_history_tab_v2.dart`

**Current**: Basic `Center(CircularProgressIndicator())`.

**Target**: `Center(CircularProgressIndicator(color: AppColors.accent))` — simply add accent color.

### 3.4 Bottom Sheet Keyboard Inset Handling in `letter_history_tab_v2.dart`

**Current**: `ListView(padding: EdgeInsets.all(20))` inside `DraggableScrollableSheet`.

**Target**: Add keyboard inset awareness:
- `final viewInsets = MediaQuery.of(context).viewInsets;`
- `ListView(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + viewInsets.bottom))`

### 3.5 Color Audit — Remove All Hardcoded Colors

Scan all 3 files for:
- `Colors.grey` → replace with `AppColors.textTertiary` or `AppColors.textSecondary`
- `Color(0xFFCC0000)` → replace with `AppColors.accent` or `AppColors.dangerText`
- `Colors.black.withValues(...)` → replace with `AppColors.border` or `AppColors.border2`
- Any other direct `Color(...)` or `Colors.*` references → replace with appropriate `AppColors` token

Exception: Colors inside WYSIWYG editor HTML strings are explicitly excluded (FR-010, FR-013).

## Complexity Tracking

No constitution violations to justify. All principles pass cleanly for this frontend-only visual refactor.
