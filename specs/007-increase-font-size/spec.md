# Feature Specification: Activate Font Scale Setting

**Feature Branch**: `007-increase-font-size`  
**Created**: 2026-04-03  
**Status**: Draft  
**Input**: User description: "make the entire app font size bigger +2"

## Clarifications

### Session 2026-04-03

- Q: What should the new default font scale be? → A: Keep 1.0 as default, just wire it up so the setting actually works — users choose their own size.
- Q: Should font scaling apply to hardcoded font sizes too? → A: Scale only theme-based text styles (15 values in app_theme.dart + component themes).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - User Changes Font Scale and Sees Immediate Effect (Priority: P1)

A user navigates to Settings > Appearance > Text Size, selects one of the available options (Small, Default, Large, X-Large), and all theme-based text throughout the app immediately renders at the chosen scale factor. The preference persists across app restarts.

**Why this priority**: The text size UI already exists but does nothing. Wiring it up is the core deliverable — without this, the feature has no value.

**Independent Test**: Open Settings, tap "Large" under Text Size, navigate to any screen, and confirm that theme-based text (headings, body, labels) appears visibly larger. Restart the app and confirm the preference is retained.

**Acceptance Scenarios**:

1. **Given** the user is on the Settings page, **When** they select "Large" (1.15x) under Text Size, **Then** all theme-based text across the app renders at 1.15x the base font size.
2. **Given** the user selects "Small" (0.85x), **When** they navigate to any screen, **Then** theme-based text renders at 0.85x the base font size.
3. **Given** the user selects a font scale and closes the app, **When** they reopen the app, **Then** the previously selected scale is still active.
4. **Given** the user selects "Default" (1.0x), **When** they view any screen, **Then** text renders at the original base sizes (no change from current behavior).

---

### User Story 2 - Font Scale Works Across Both Themes (Priority: P1)

The font scale preference applies identically whether the user is in light mode, dark mode, or system mode. Switching themes does not reset or alter the font scale.

**Why this priority**: The app supports light/dark themes via a shared `_build()` method. The scale must apply in both modes to avoid inconsistent behavior.

**Independent Test**: Set font scale to "X-Large", switch between light and dark mode, and confirm text sizes remain scaled identically in both.

**Acceptance Scenarios**:

1. **Given** the user has selected "X-Large" (1.3x) font scale, **When** they switch from light to dark mode, **Then** all theme-based text remains at 1.3x scale.
2. **Given** the user changes theme mode, **When** they return to Settings, **Then** the Text Size selection still shows the previously chosen option.

---

### Edge Cases

- What happens when font scale is combined with a different font family? The scale must apply regardless of which font (Inter, DM Sans, Roboto, etc.) is selected.
- What about component-level theme overrides (buttons, chips, input hints, app bar title, navigation bar labels)? These must also scale since they are part of the centralized theme.
- Hardcoded `TextStyle(fontSize: N)` values throughout the codebase will NOT be affected by this feature. This is a known limitation; those can be migrated to the theme in a future refactoring effort.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The font scale preference stored in ThemeController MUST be applied to the centralized TextTheme when building the app theme.
- **FR-002**: All 7 TextTheme styles (displayLarge, titleLarge, titleMedium, bodyLarge, bodyMedium, bodySmall, labelSmall) MUST have their fontSize multiplied by the active font scale factor.
- **FR-003**: All component-level theme font sizes (InputDecoration hint/label, ElevatedButton, OutlinedButton, Chip, NavigationBar labels, AppBar title) MUST also be multiplied by the active font scale factor.
- **FR-004**: The font scale MUST apply identically across light and dark themes.
- **FR-005**: The selected font scale MUST persist across app restarts (already handled by ThemeController/SharedPreferences — just needs to be consumed).
- **FR-006**: The default font scale MUST remain 1.0 (no change from current baseline).
- **FR-007**: The available scale options MUST remain [0.85, 1.0, 1.15, 1.3] (Small, Default, Large, X-Large).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Selecting any of the 4 font scale options in Settings produces a visible, immediate change in theme-based text sizes across all screens.
- **SC-002**: Font scale preference survives app restart — 100% of the time the saved preference is restored on launch.
- **SC-003**: Zero visual difference in font scale behavior between light and dark themes.
- **SC-004**: All 15 centralized theme font sizes (7 TextTheme + 8 component overrides) respond to the scale factor.
- **SC-005**: No layout overflow or text clipping at the maximum scale (1.3x X-Large) on any screen.

## Assumptions

- The ThemeController already stores and persists the fontScale value via SharedPreferences — no new persistence mechanism is needed.
- The Settings UI for Text Size already exists and functions (displays options, calls `setFontScale`) — no UI changes are needed.
- Only theme-based text styles are in scope. Hardcoded `TextStyle(fontSize: N)` values throughout the codebase are explicitly out of scope for this feature.
- PDF generation font sizes are excluded — they control document layout, not app UI.
- The `AppTheme._build()` method needs to accept and apply a `fontScale` parameter to centralize the scaling logic.
