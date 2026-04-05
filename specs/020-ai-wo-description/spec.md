# Feature Specification: AI-Assisted Work Order Description

**Feature Branch**: `020-ai-wo-description`  
**Created**: 2026-04-05  
**Status**: Draft  
**Input**: User description: "Add an AI 'Suggest' button to the description field in the work order create/edit screen. When tapped, it calls a local Ollama instance via a new FastAPI endpoint and returns a 2-4 sentence professional description based on the work order title, location, and type. User can accept or dismiss."

## Clarifications

### Session 2026-04-05

- Q: Which Ollama model is installed on the server? → A: `gemma4:e2b` (Gemma 4 E2B, ~7.2 GB). Ollama is enabled on boot via systemd.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Generate Description for New Work Order (Priority: P1)

A user creating a new work order fills in the title, location, and type fields, then taps the "Suggest" button next to the empty description field. The system generates a professional 2-4 sentence description based on the entered context and automatically fills it into the description field.

**Why this priority**: This is the core value proposition — reducing the time and effort needed to write professional work order descriptions. Most usage will occur on new work orders where the description is blank.

**Independent Test**: Can be fully tested by creating a new work order, entering a title/location/type, tapping Suggest, and verifying a professional description appears in the field.

**Acceptance Scenarios**:

1. **Given** a new work order with title, location, and type filled in and description empty, **When** the user taps the Suggest button, **Then** a loading indicator appears on the button, the AI generates a description, and it is placed directly into the description field without any confirmation prompt.
2. **Given** a new work order with only a title filled in (location and type optional), **When** the user taps Suggest, **Then** the system generates a description using the available context.
3. **Given** a new work order with the title field empty, **When** the user views the form, **Then** the Suggest button is visible but disabled and cannot be tapped.

---

### User Story 2 - Replace Existing Description with AI Suggestion (Priority: P2)

A user editing an existing work order wants to improve the description. They tap the Suggest button, and since the description field already contains text, the system shows a confirmation prompt with the new suggestion. The user can choose to replace the existing text or dismiss the suggestion.

**Why this priority**: Editing existing descriptions is a secondary but important flow. The confirmation step protects users from accidentally overwriting their work.

**Independent Test**: Can be tested by opening a work order with an existing description, tapping Suggest, verifying the bottom sheet appears with Replace and Dismiss options, and confirming each option works correctly.

**Acceptance Scenarios**:

1. **Given** a work order with existing description text, **When** the user taps Suggest and the AI returns a suggestion, **Then** a bottom sheet appears showing the suggested description with "Replace" and "Dismiss" actions.
2. **Given** the suggestion bottom sheet is displayed, **When** the user taps "Replace", **Then** the existing description is replaced with the AI suggestion and the bottom sheet closes.
3. **Given** the suggestion bottom sheet is displayed, **When** the user taps "Dismiss", **Then** the existing description is preserved unchanged and the bottom sheet closes.

---

### User Story 3 - Graceful Handling of AI Service Unavailability (Priority: P3)

The AI service may be temporarily unavailable or slow. When this happens, the user should receive clear, non-disruptive feedback and retain full ability to write descriptions manually.

**Why this priority**: Reliability and graceful degradation ensure the feature doesn't block core work order functionality when the AI backend is down.

**Independent Test**: Can be tested by making the AI service unavailable, tapping Suggest, and verifying the error message appears without disrupting the form.

**Acceptance Scenarios**:

1. **Given** the AI service is unreachable, **When** the user taps Suggest, **Then** a floating snackbar displays a user-friendly error message and the description field remains unchanged and fully editable.
2. **Given** the AI service takes longer than 60 seconds to respond, **When** the timeout is reached, **Then** the loading state is cleared, a timeout error message is shown via floating snackbar, and the user can retry or type manually.
3. **Given** the AI service returns an error, **When** the error is received, **Then** the Suggest button returns to its normal state and the user can retry.

---

### Edge Cases

- What happens when the user taps Suggest multiple times rapidly? The button must be disabled while a request is in progress to prevent duplicate calls.
- What happens when the user navigates away while a suggestion is loading? The request should be cancelled or its result ignored.
- What happens when the AI returns an empty or unusable response? The system should show an error message rather than filling the field with blank text.
- What happens when the user lacks edit permissions? The Suggest button must be hidden entirely, not just disabled.
- How does the Suggest button interact with the existing auto-save? The auto-save timer must not be disrupted; AI-filled text should be captured by the next auto-save cycle naturally.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a "Suggest" button adjacent to the description field on the work order create/edit screen.
- **FR-002**: System MUST generate a professional 2-4 sentence description using the work order's title, location, and type as context inputs.
- **FR-003**: System MUST fill the description field directly when it is empty, without requiring user confirmation.
- **FR-004**: System MUST present a confirmation prompt (bottom sheet with Replace/Dismiss options) when the description field already contains text.
- **FR-005**: System MUST show a loading state on the Suggest button while the AI request is in progress.
- **FR-006**: System MUST disable the Suggest button when the title field is empty or when a request is already in progress.
- **FR-007**: System MUST hide the Suggest button when the user does not have edit permissions or when the user role has not yet loaded.
- **FR-008**: System MUST NOT disable or interfere with the description text field at any point during the AI suggestion flow.
- **FR-009**: System MUST return a service-unavailable status (not a generic server error) when the AI backend is unreachable.
- **FR-010**: System MUST enforce a 60-second timeout on AI generation requests.
- **FR-011**: System MUST strip conversational preamble from AI responses (e.g., lines starting with "Here", "Sure", or similar filler phrases) before presenting the suggestion.
- **FR-012**: System MUST display errors via a floating snackbar notification.
- **FR-013**: System MUST NOT interfere with the existing auto-save functionality on the work order form.
- **FR-014**: System MUST use only the application's existing color system for all UI elements related to this feature.

### Key Entities

- **AI Suggestion Request**: Represents a request to generate a description, containing the work order title (required), location (optional), and type (optional).
- **AI Suggestion Response**: The generated professional description text returned by the AI service.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can generate a professional work order description in under 65 seconds (including AI processing time), compared to the typical 2-5 minutes spent writing one manually.
- **SC-002**: 90% of AI-generated descriptions are accepted by users without manual editing on first use.
- **SC-003**: When the AI service is unavailable, users receive error feedback within 5 seconds and can continue working without interruption.
- **SC-004**: The Suggest button is discoverable — users find and use it without external guidance or training.
- **SC-005**: The feature does not degrade form submission speed or auto-save reliability.

## Assumptions

- The AI service (Ollama with `gemma4:e2b` model) is deployed and running on the same server as the backend, accessible at localhost. Ollama is enabled on boot via systemd.
- The AI endpoint is internal-only and does not require authentication, as it is not exposed to external traffic.
- English is the only language needed for AI-generated descriptions (Arabic prompting is out of scope).
- The existing work order form structure (title, location, type, description fields) will not change during this feature's development.
- Users have sufficient network connectivity to reach the backend server (same assumption as all other app functionality).
- Response caching is not needed for the initial release; each Suggest tap makes a fresh request.
- Streaming responses are not needed; the full description is returned in a single response.

## Out of Scope

- Streaming/real-time AI responses
- Arabic language prompting or multilingual support
- Caching of AI suggestions
- Customizable AI prompts or model selection by users
- AI suggestions for fields other than the description
