# Feature Specification: Letters V2 UI/UX Refactor

**Feature Branch**: `035-letters-v2-ui-refactor`  
**Created**: 2026-04-10  
**Status**: Draft  
**Input**: User description: "Refactor the Letters V2 screen UI/UX to match the Work Orders screen design system exactly"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Consistent Screen Layout and Navigation (Priority: P1)

A user navigates to the Letters V2 screen and immediately recognizes the same polished, iOS-inspired layout they see on the Work Orders screen. The header displays a rounded back-button container, proper title typography, and a clean divider. The tab system uses the same custom tab widget with an active-state bottom border instead of the current segmented control.

**Why this priority**: The header and tab system are the first things users see. Visual consistency here sets the tone for the entire screen and is the foundation all other UI elements sit within.

**Independent Test**: Can be fully tested by navigating to the Letters V2 screen and visually comparing the header, back button, title, and tab bar against the Work Orders screen. Delivers immediate visual parity with the rest of the application.

**Acceptance Scenarios**:

1. **Given** a user is on any screen in the app, **When** they navigate to Letters V2, **Then** the header displays a rounded back-button container with the same background color, border radius, border width, and icon styling as the Work Orders header.
2. **Given** a user is viewing the Letters V2 screen, **When** they look at the tab bar, **Then** they see custom-styled tabs with an active-state indicator matching the Work Orders tab pattern, not a segmented control.
3. **Given** a user taps the back button, **When** the navigation completes, **Then** they return to the previous screen without any visual glitch or layout shift.
4. **Given** a user switches between "Create Letter" and "Letter History" tabs, **When** the tab transition occurs, **Then** the active tab indicator animates smoothly and the content area updates without flicker.

---

### User Story 2 - Polished Form Experience (Priority: P1)

A user creating or editing a letter encounters form fields that look and behave identically to the Work Orders form. Input fields use the same decoration (fill color, border radius, focus states), labels follow the same typography, and spacing between fields is consistent. On iOS PWA, tapping a field scrolls it into view smoothly after the keyboard appears.

**Why this priority**: The form is the primary interaction surface for letter creation. Consistent styling and smooth keyboard handling directly impact usability and user confidence.

**Independent Test**: Can be fully tested by filling out the letter creation form on both desktop and iOS PWA, comparing field appearance and keyboard behavior against the Work Orders add/edit form.

**Acceptance Scenarios**:

1. **Given** a user is on the letter creation form, **When** they view any text input field, **Then** the field uses the application theme's standard input decoration (filled background, rounded border, standard border width, accent-colored focus ring).
2. **Given** a user taps a text field on iOS PWA, **When** the on-screen keyboard appears, **Then** the focused field scrolls into view at approximately 30% from the top of the visible area after a brief delay to allow keyboard animation.
3. **Given** a user submits a form with missing required fields, **When** validation runs, **Then** error messages appear inline below the relevant fields using the standard danger color scheme.
4. **Given** a user views form section labels, **When** comparing to Work Orders, **Then** the typography (font weight, size, color) is identical.

---

### User Story 3 - Refined Letter History List (Priority: P2)

A user browsing their letter history sees a card-based list that matches the visual design of the Work Orders list. Each letter card uses consistent shadows, borders, spacing, and typography from the application design system. Status indicators (if present) use the same badge pattern.

**Why this priority**: The history list is the secondary view users access frequently. Visual parity here completes the perception of a unified application design.

**Independent Test**: Can be fully tested by viewing the letter history tab with multiple letters and comparing card styling, spacing, and information layout against Work Order list items.

**Acceptance Scenarios**:

1. **Given** a user has previously generated letters, **When** they view the Letter History tab, **Then** each letter is displayed in a card with the same shadow, border, and padding treatment as Work Order list items.
2. **Given** a user views a letter card, **When** they examine the content layout, **Then** the title typography, secondary text colors, and date formatting follow the same hierarchy as Work Order cards.
3. **Given** a user pulls down on the history list, **When** the refresh completes, **Then** the pull-to-refresh indicator uses the application accent color.

---

### User Story 4 - Consistent Button and Action Styling (Priority: P2)

All action buttons on the Letters V2 screen (generate PDF, preview, save, delete, add CC) follow the same styling patterns as Work Orders. Primary actions use the accent color with white text, secondary/outlined actions use the border color scheme, and destructive actions use the danger color. Loading states show a spinner replacing button text.

**Why this priority**: Buttons are the primary call-to-action elements. Consistent styling reduces cognitive load and reinforces the design language.

**Independent Test**: Can be fully tested by triggering each button type (primary, secondary, destructive) and observing styling, loading states, and disabled states.

**Acceptance Scenarios**:

1. **Given** a user views the letter form, **When** they see the primary action button (e.g., Generate PDF), **Then** it uses the accent background color, white text, rounded border radius, and standard padding matching Work Orders buttons.
2. **Given** a user initiates a long-running action (PDF generation), **When** the operation is in progress, **Then** the button shows a small circular progress indicator with white color and is non-interactive.
3. **Given** a user views a destructive action (delete letter), **When** they see the button or icon, **Then** it uses the application danger color scheme.
4. **Given** a button action is unavailable, **When** the user views that button, **Then** it appears in a visually muted/disabled state.

---

### User Story 5 - Proper Empty and Loading States (Priority: P3)

When the letter history list is empty or data is loading, the screen displays polished empty-state and loading-state visuals matching the Work Orders patterns. Empty states show a centered icon with a descriptive message using theme colors. Loading states show a properly styled progress indicator.

**Why this priority**: Empty and loading states are edge cases that still contribute to the overall polish and professionalism of the interface.

**Independent Test**: Can be fully tested by viewing the history tab with no letters (empty state) and during initial data fetch (loading state).

**Acceptance Scenarios**:

1. **Given** a user has no generated letters, **When** they navigate to the Letter History tab, **Then** they see a centered icon and message using theme text colors (not hardcoded grey).
2. **Given** data is being fetched, **When** the user views the screen, **Then** a loading indicator appears centered on the screen using the application accent color.

---

### Edge Cases

- What happens when the user rotates the device or resizes the browser window during form editing? The layout must remain stable and inputs must not lose focus or content.
- How does the screen behave when the WYSIWYG HTML editor iframe is active alongside the new styled form fields? The editor container must retain its existing styling and resize behavior without conflict.
- What happens when the user has an extremely long letter title or recipient name? Text must truncate with ellipsis or wrap gracefully following the same pattern as Work Orders.
- How does the bottom sheet for letter details behave when iOS keyboard is active? The sheet must account for keyboard insets in its padding.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Letters V2 screen header MUST display a rounded back-button container with the same background, border radius, border width, and icon styling as the Work Orders header.
- **FR-002**: The tab system MUST replace the current segmented control with a custom tab widget that shows an active state with a bottom border or highlight, matching the Work Orders tab pattern.
- **FR-003**: All text input fields MUST use the application theme's standard input decoration (filled background, consistent border radius, standard border width, accent-colored focus border).
- **FR-004**: The screen MUST implement iOS PWA keyboard handling with deferred scroll-into-view (brief delay for keyboard animation) using smooth scrolling with 0.3 alignment for all focusable form fields.
- **FR-005**: All primary action buttons MUST use the accent color background, white foreground, consistent border radius, and standard padding matching Work Orders buttons.
- **FR-006**: All secondary/outlined buttons MUST use the theme border color, consistent border radius, and primary text color foreground.
- **FR-007**: Long-running operations (PDF generation, letter saving) MUST display a loading indicator inside the action button and disable the button during the operation.
- **FR-008**: Letter history cards MUST use theme-consistent card styling with proper shadows, borders, and padding matching Work Order list items.
- **FR-009**: Empty states MUST display a centered icon and descriptive message using theme text colors, not hardcoded color values.
- **FR-010**: All color references MUST use the application's centralized color theme properties. No hardcoded color values are permitted in the refactored code, except where the WYSIWYG editor iframe HTML requires them.
- **FR-011**: The screen MUST preserve all existing functionality: letter creation, editing, deletion, preview, PDF generation, payment certificate linking, signature management, and CC list management.
- **FR-012**: The screen MUST maintain full RTL (right-to-left) support for Arabic content within form fields and the editor.
- **FR-013**: The WYSIWYG rich text editor integration MUST remain fully functional with no changes to its iframe HTML content or resize behavior.
- **FR-014**: Bottom sheets (letter detail view) MUST account for keyboard insets by adding appropriate padding to avoid content being hidden behind the on-screen keyboard.
- **FR-015**: Typography throughout the screen MUST follow the application's established type scale for titles, body text, and labels.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A side-by-side visual comparison of the Letters V2 screen and Work Orders screen shows identical header layout, back button styling, and title typography with no distinguishable differences.
- **SC-002**: Tab switching on Letters V2 uses the same interaction pattern (active indicator, animation, typography changes) as Work Orders, verified by visual inspection on both desktop and iOS PWA.
- **SC-003**: 100% of form input fields on the Letters V2 screen use the shared application input decoration with no field-specific style overrides or hardcoded colors.
- **SC-004**: On iOS PWA, tapping any form field results in the field being scrolled into visible view after the keyboard appears, matching the Work Orders scroll behavior.
- **SC-005**: All letter history cards use theme-defined colors, shadows, and spacing with zero hardcoded color values in the refactored widget code.
- **SC-006**: All existing letter functionality (create, edit, delete, preview, generate PDF, link certificates, manage signatures, manage CC list) works without regression after the refactor.
- **SC-007**: The WYSIWYG HTML editor loads, renders content, supports editing, and resizes correctly with no functional changes.
- **SC-008**: Button loading states are visually identical to Work Orders loading states (spinner size, color, disabled appearance).
- **SC-009**: Users experience no layout shifts, content jumps, or visual glitches when navigating to, interacting with, or leaving the Letters V2 screen.

## Assumptions

- The existing centralized color theme and styling classes already provide all necessary color tokens and styling primitives needed for this refactor. No new theme tokens need to be created.
- The Work Orders screen patterns (header, tabs, form styling, card layout) are considered the canonical reference for the application design system. Any ambiguity is resolved by matching Work Orders exactly.
- The WYSIWYG editor iframe uses inline HTML/CSS that is intentionally outside the application theme system and will not be refactored.
- The existing letter service and all backend APIs remain unchanged. This is a purely frontend visual refactor.
- The refactor targets the same platforms currently supported: web (desktop browsers) and iOS PWA. No new platform support is being added.
- RTL layout direction is already handled by existing directional widgets and text alignment on form fields. This pattern will be preserved.
- The three-phase implementation approach (Phase 1: layout/tabs, Phase 2: form styling, Phase 3: history/polish) allows incremental delivery where each phase produces a functional screen.
