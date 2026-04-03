# Feature Specification: Fix System Status Screen Font Scale

**Feature Branch**: `008-fix-status-font-scale`  
**Created**: 2026-04-03  
**Status**: Draft  
**Input**: User description: "system_status_screen.dart is not responding to text size setting — investigate and fix"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - System Status Screen Responds to Text Size Setting (Priority: P1)

A user changes the Text Size preference in Settings > Appearance (Small, Default, Large, X-Large). When they navigate to the System Status screen, all text — headings, labels, status indicators, chart labels, issue details, history cards, and bottom sheet content — renders at the chosen scale, matching the behavior of other screens in the app.

**Why this priority**: This is the only user story — the System Status screen currently ignores the font scale setting entirely, making it visually inconsistent with the rest of the app.

**Independent Test**: Go to Settings, select "X-Large" text size, then navigate to the System Status screen. Confirm all text is visibly larger. Switch to "Small" and confirm all text is visibly smaller.

**Acceptance Scenarios**:

1. **Given** the user has selected "Large" (1.15x) text size in Settings, **When** they open the System Status screen, **Then** all text elements on the screen render at 1.15x their base size.
2. **Given** the user has selected "Small" (0.85x) text size, **When** they open the System Status screen, **Then** all text elements render at 0.85x their base size.
3. **Given** the user changes text size while viewing the System Status screen, **When** they return to it after the change, **Then** the screen reflects the new text size.
4. **Given** the user has "Default" (1.0x) text size selected, **When** they view the System Status screen, **Then** text renders at the same sizes as before the fix (no regression).

---

### Edge Cases

- How does the screen behave at maximum scale (1.3x X-Large)? Text in tightly constrained areas (status badges, chart axis labels, compact history cards) must not overflow or clip.
- Do bottom sheets launched from this screen (report issue, issue details, edit) also respect the font scale?
- Do chart labels and axis text scale correctly without overlapping the chart area?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: All 43 hardcoded text sizes on the System Status screen MUST respond to the user's font scale preference.
- **FR-002**: Bottom sheets launched from this screen (report issue, issue details, edit) MUST also have their text sizes respond to the font scale.
- **FR-003**: The font scale MUST be obtained from the app's existing font scale preference system, consistent with how other screens access it.
- **FR-004**: At default scale (1.0x), text sizes MUST match the current values exactly — no visual regression.
- **FR-005**: No text element MUST overflow, clip, or overlap at the maximum scale (1.3x X-Large).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of the 43 text elements on the System Status screen respond to font scale changes.
- **SC-002**: Zero visual difference between current behavior and the fixed version when the default (1.0x) scale is selected.
- **SC-003**: Zero layout overflow or text clipping at maximum scale (1.3x) across all sections of the screen and its bottom sheets.
- **SC-004**: The System Status screen is visually consistent with other screens (e.g., Settings, Dashboard) at every scale level.

## Assumptions

- The font scale value is already available via the app's existing preference system — the same mechanism used on the Settings page.
- Only the System Status screen file is in scope. Other screens with the same issue would be addressed separately.
- Chart library text (axis labels, tooltips) may have its own sizing mechanism; these should be scaled where the app controls the font size values.
- The fix follows the same pattern already established on the Settings page: multiply each hardcoded fontSize by the scale factor.
