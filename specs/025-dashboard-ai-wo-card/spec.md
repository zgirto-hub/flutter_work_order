# Feature Specification: Dashboard AI Work Order Card with Draft Preview

**Feature Branch**: `025-dashboard-ai-wo-card`  
**Created**: 2026-04-06  
**Status**: Draft  
**Input**: User description: "Dashboard AI Work Order card with draft bottom sheet. Add the AI Work Order natural language input card to the Dashboard screen. Users can type or speak a work order description, tap Generate, and a bottom sheet slides up showing a draft preview of the parsed work order fields. Two actions: Create (submits directly) and Edit (navigates to full Add Work Order screen pre-filled). Reuses existing AI parse endpoint and voice dictation. The NL input card should be extracted into a shared widget. Supports Arabic and English. Available to all roles that can create work orders."

## Clarifications

### Session 2026-04-06

- Q: What happens after successful "Create" from draft bottom sheet? → A: Sheet closes, input clears, success SnackBar appears on Dashboard, stats refresh.
- Q: Are draft fields editable inline in the bottom sheet? → A: No — fields are read-only. Use the "Edit" button to navigate to the full form for changes.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Generate and Quick-Create from Dashboard (Priority: P1)

A field technician opens the app and lands on the Dashboard. At the top of the dashboard, they see an "AI Work Order" card with a text input. They type "broken AC unit in room 205, urgent" and tap Generate. A bottom sheet slides up from the bottom showing a draft preview: title "Broken AC Unit", description (expanded professional text), location "Room 205", type "Technical", status "Pending". They review the draft and tap "Create". The work order is submitted immediately, a success message appears, and the dashboard stats refresh to reflect the new work order.

**Why this priority**: This is the core value — creating a work order from the Dashboard in under 15 seconds without navigating to the full form. It eliminates the multi-step flow of navigating to Add Work Order, filling fields individually, and submitting.

**Independent Test**: Can be fully tested by opening the Dashboard, typing a sentence, tapping Generate, reviewing the draft bottom sheet, and tapping Create to verify the work order is created.

**Acceptance Scenarios**:

1. **Given** the user is on the Dashboard, **When** they type a work order description and tap Generate, **Then** a bottom sheet slides up showing a draft preview with parsed fields (title, description, location, type, department, status).
2. **Given** the draft bottom sheet is showing, **When** the user taps "Create", **Then** the work order is submitted, a success message appears, and the dashboard stats refresh.
3. **Given** the draft bottom sheet is showing, **When** the user taps outside the sheet or swipes it down, **Then** the sheet is dismissed and no work order is created.
4. **Given** the AI is processing, **When** the user waits, **Then** a loading indicator is shown and the Generate button is disabled.

---

### User Story 2 - Edit Draft Before Submitting (Priority: P2)

A technician generates a draft from the Dashboard but wants to adjust some fields (e.g., assign a technician, change the department, or add more detail to the description). They tap "Edit" on the bottom sheet. The full Add Work Order screen opens with all the AI-parsed fields pre-filled. They make their adjustments and submit from there.

**Why this priority**: Not every work order can be created with AI alone — some need manual adjustments. The Edit path provides an escape hatch to the full form without losing the AI-parsed data.

**Independent Test**: Can be tested by generating a draft, tapping Edit, and verifying the Add Work Order screen opens with all fields pre-filled from the draft.

**Acceptance Scenarios**:

1. **Given** the draft bottom sheet is showing, **When** the user taps "Edit", **Then** the full Add Work Order screen opens with all parsed fields pre-filled (title, description, location, type, department, status).
2. **Given** the user is on the pre-filled Add Work Order screen, **When** they modify any field and submit, **Then** the work order is created with the modified values.

---

### User Story 3 - Voice Dictation on Dashboard (Priority: P2)

A field technician with gloved hands taps the microphone button on the Dashboard's AI card, speaks "make a work order for clearing CADAS-IMS operator queue", reviews the transcribed text, and taps Generate. The draft bottom sheet appears with the parsed fields.

**Why this priority**: Voice input on the Dashboard extends the hands-free experience from feature 022 to the most accessible screen in the app.

**Independent Test**: Can be tested by tapping the mic button on the Dashboard AI card, speaking, verifying transcription, tapping Generate, and verifying the draft bottom sheet appears.

**Acceptance Scenarios**:

1. **Given** the user is on the Dashboard, **When** they tap the mic button on the AI card and speak, **Then** the speech is transcribed into the input field in real-time.
2. **Given** the transcribed text is in the input field, **When** the user taps Generate, **Then** the draft bottom sheet appears with parsed fields from the transcribed text.

---

### User Story 4 - Arabic Language Support (Priority: P3)

An Arabic-speaking technician selects the AR language chip on the Dashboard AI card, types or speaks in Arabic, and generates a draft. The bottom sheet shows the draft with Arabic content in all fields.

**Why this priority**: Bilingual support is important for the workforce but builds on the existing Arabic support from features 022 and 024.

**Independent Test**: Can be tested by selecting AR, typing Arabic text, tapping Generate, and verifying the draft shows Arabic content.

**Acceptance Scenarios**:

1. **Given** the user selects the AR language chip, **When** they type an Arabic description and tap Generate, **Then** the draft bottom sheet shows fields with Arabic content.

---

### User Story 5 - Shared NL Input Widget (Priority: P1)

The natural language input card (text field, language chips, mic button, generate button) is extracted into a shared widget used by both the Dashboard and the existing Add Work Order screen. This ensures consistent UI and behavior across both locations.

**Why this priority**: Critical for maintainability — duplicating the NL card UI would create divergence. This is a prerequisite for US1.

**Independent Test**: Can be tested by verifying the NL input card looks and behaves identically on both the Dashboard and the Add Work Order screen.

**Acceptance Scenarios**:

1. **Given** the shared widget is used on the Dashboard, **When** the user interacts with it, **Then** it behaves identically to the NL card on the Add Work Order screen (same text input, same language chips, same mic button, same Generate button).
2. **Given** the shared widget is used on the Add Work Order screen, **When** the user generates from it, **Then** the existing auto-fill behavior is preserved exactly as before.

---

### Edge Cases

- What happens when the AI service is unavailable? An error message is shown on the Dashboard and the user can navigate to Add Work Order manually.
- What happens when the AI returns no useful fields (e.g., user typed "hello")? The bottom sheet shows the draft with mostly empty fields. The "Create" button is disabled if the title is empty, since title is a required field.
- What happens when the user has no departments loaded yet? Departments are fetched on-demand when Generate is tapped. If the fetch fails, the AI is still called without department constraints, and the department field in the draft shows "Not assigned".
- What happens when the user taps Create and the submission fails? An error message is shown in the bottom sheet, the sheet stays open, and the user can retry or tap Edit to use the full form.
- What happens if the user creates a work order from the Dashboard and then navigates to the work order list? The new work order should appear in the list (the list refreshes on navigation).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display an AI Work Order input card on the Dashboard screen, positioned below the stats section and above Quick Actions.
- **FR-002**: The AI input card MUST include a text input field, language toggle (English/Arabic), microphone button for voice dictation, and a Generate button.
- **FR-003**: System MUST send the input text to the existing AI parse service when the user taps Generate, and display a draft preview bottom sheet with the parsed fields.
- **FR-004**: The draft bottom sheet MUST display the parsed work order fields as read-only: title, description, location, type, department, and status. Fields are not editable inline — the "Edit" button provides the editing path.
- **FR-005**: The draft bottom sheet MUST provide a "Create" button that submits the work order directly without navigating to another screen.
- **FR-006**: The draft bottom sheet MUST provide an "Edit" button that navigates to the full Add Work Order screen with all parsed fields pre-filled.
- **FR-007**: The "Create" button MUST be disabled if the work order title is empty (title is required for submission).
- **FR-008**: After successful creation via the "Create" button, the system MUST close the bottom sheet, clear the input field, show a success SnackBar on the Dashboard, and refresh the dashboard statistics.
- **FR-009**: The AI input card MUST be available to all user roles that can create work orders.
- **FR-010**: The NL input card UI MUST be extracted into a shared widget used by both the Dashboard and the Add Work Order screen, ensuring consistent behavior.
- **FR-011**: The Add Work Order screen MUST accept pre-fill parameters for all work order fields (title, description, location, type, department, status) to support the "Edit" flow from the dashboard draft.
- **FR-012**: System MUST show a loading indicator on the Generate button while the AI service is processing.
- **FR-013**: System MUST display user-friendly error messages if the AI service fails or times out.

### Key Entities

- **AI Draft**: A transient preview of parsed work order fields (title, description, location, type, department, status) displayed in the bottom sheet before creation or editing. Not persisted — exists only in memory during the review flow.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can create a work order from the Dashboard in under 15 seconds using a single sentence input (type → generate → create).
- **SC-002**: 80% of users who generate a draft from the Dashboard proceed to create or edit the work order (low abandonment rate).
- **SC-003**: The draft bottom sheet displays parsed fields within 10 seconds of tapping Generate.
- **SC-004**: The shared NL input widget behaves identically on both the Dashboard and Add Work Order screen with zero visual or functional differences.
- **SC-005**: Work orders created via the Dashboard "Create" button are fully valid and appear in the work order list immediately.

## Assumptions

- The existing AI parse endpoint (from feature 024) is available and returns structured work order fields. No backend changes are needed.
- The existing voice dictation feature (from feature 022) provides the mic button widget that can be reused on the Dashboard.
- Department, type, and status lists can be fetched or are known at the time of generation. Departments are fetched on-demand from the existing department service.
- The allowed work order types ("Technical", "Inspection", "Other") and statuses ("Pending", "In Progress", "Closed") are the same constants used throughout the app.
- Job numbers for new work orders are generated client-side using the existing timestamp-based pattern.
- The Dashboard is the app's landing screen and is accessible to all authenticated users.
- Network connectivity is required for AI parsing (same as existing features 022 and 024).
- The "Create" flow on the Dashboard handles the same work order creation logic as the Add Work Order screen (same service, same validation).
