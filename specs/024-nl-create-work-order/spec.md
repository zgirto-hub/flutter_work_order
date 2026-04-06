# Feature Specification: Natural Language Work Order Creation

**Feature Branch**: `024-nl-create-work-order`  
**Created**: 2026-04-06  
**Status**: Draft  
**Input**: User description: "Natural language work order creation with AI auto-fill. On the Add Work Order screen, a single text input (or voice via existing mic button) lets users describe a work order in plain language. The AI parses the sentence and auto-fills all form fields: title, description, department, type, location, and priority. Also cleans up grammar and expands shorthand/abbreviations into proper descriptions. Uses the existing AI assist backend endpoint. User reviews the auto-filled form, adjusts if needed, and submits. Works with both typed and voice-dictated input. Supports Arabic and English input."

## Clarifications

### Session 2026-04-06

- Q: Should AI parsing use a new endpoint or extend the existing `/ai/suggest`? → A: New endpoint (e.g., `POST /ai/parse-work-order`), separate from the existing suggest feature.
- Q: How should the UI indicate which fields were auto-filled? → A: Highlight auto-filled fields with a temporary visual indicator (e.g., colored border) and scroll to the first filled field.
- Q: Should AI parsing auto-trigger after voice dictation or require explicit tap? → A: Always require explicit Generate button tap — user reviews transcription first.
- Q: Should AI responses be constrained to valid types/statuses or freeform? → A: Constrained — AI must return only valid values from provided lists of types, statuses, and departments.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Type a Sentence and Auto-Fill Work Order (Priority: P1)

A field technician opens the Add Work Order screen and sees a prominent text input area at the top labeled something like "Describe your work order...". They type a plain-language sentence such as "broken AC unit in room 205, urgent" and tap a submit/generate button. The system sends the text to the AI service, which parses it and returns structured data. The form fields are auto-filled: title becomes "Broken AC Unit", description becomes a professional expanded version, location becomes "Room 205", type is set to "Technical", and status is set based on the urgency. The technician reviews the filled form, makes any adjustments, and submits the work order.

**Why this priority**: This is the core value proposition — reducing a multi-field form into a single natural language input. It dramatically speeds up work order creation for field workers.

**Independent Test**: Can be fully tested by opening the Add Work Order screen, typing a sentence in the input area, tapping generate, and verifying all form fields are populated with extracted and expanded data.

**Acceptance Scenarios**:

1. **Given** the user is on the Add Work Order screen, **When** they type "broken AC unit in room 205, urgent" and tap the generate button, **Then** the system fills title, description, location, type, and status fields with AI-extracted values.
2. **Given** the AI has auto-filled all fields, **When** the user reviews the form, **Then** all fields are editable and the user can adjust any value before submitting.
3. **Given** the user types a sentence that lacks certain details (e.g., no location mentioned), **When** the AI processes it, **Then** the fields with missing information are left empty for the user to fill manually.
4. **Given** the AI service is processing the request, **When** the user waits, **Then** a loading indicator is shown and the generate button is disabled to prevent duplicate requests.

---

### User Story 2 - Voice Dictation to Auto-Fill (Priority: P2)

A field technician with dirty or gloved hands taps the microphone button on the natural language input area, speaks a sentence like "make a new work order regarding clearing CADAS-IMS operator queue", and the system transcribes the speech and then sends it to the AI for parsing and auto-fill — all in one flow.

**Why this priority**: Combines the voice dictation feature (022) with AI parsing for a completely hands-free work order creation experience. High value for field workers but depends on US1 being complete.

**Independent Test**: Can be tested by tapping the mic on the input area, speaking a work order description, and verifying the transcribed text is sent to AI and all form fields are populated.

**Acceptance Scenarios**:

1. **Given** the user is on the Add Work Order screen, **When** they tap the mic button on the input area and speak a work order description, **Then** the speech is transcribed into the input area in real-time.
2. **Given** the speech has been transcribed into the input area, **When** the user reviews the transcription and taps the Generate button, **Then** the transcribed text is sent to the AI and form fields are auto-filled.

---

### User Story 3 - Arabic Language Input (Priority: P2)

A technician whose primary language is Arabic types or dictates a work order description in Arabic. The AI correctly parses the Arabic text, extracts structured fields, and fills the form — with the description expanded in Arabic.

**Why this priority**: Essential for the bilingual workforce. The system must handle Arabic input natively, not just English.

**Independent Test**: Can be tested by typing an Arabic sentence in the input area, tapping generate, and verifying the form fields are correctly populated with Arabic content.

**Acceptance Scenarios**:

1. **Given** the user types a work order description in Arabic, **When** they tap the generate button, **Then** the AI parses the Arabic text and fills all applicable form fields with Arabic content.
2. **Given** the user dictates in Arabic using the mic button, **When** the AI processes the transcribed Arabic text, **Then** the form fields are filled with properly formatted Arabic text.

---

### User Story 4 - Grammar Cleanup and Shorthand Expansion (Priority: P3)

A technician types a rough, abbreviated sentence like "fix elev stuck 3rd flr bldg B asap". The AI expands this into proper professional language: title "Fix Stuck Elevator", description "Elevator stuck on the 3rd floor of Building B. Requires immediate attention.", location "3rd Floor, Building B", type "Technical".

**Why this priority**: Adds polish to the feature by handling the messy, abbreviated input that field workers commonly use. Not critical for MVP but significantly improves output quality.

**Independent Test**: Can be tested by typing an abbreviated sentence and verifying the AI expands shorthand into professional language in all filled fields.

**Acceptance Scenarios**:

1. **Given** the user types an abbreviated sentence with shorthand, **When** the AI processes it, **Then** the description field contains properly expanded, professional language.
2. **Given** the user types with grammatical errors, **When** the AI processes it, **Then** the output fields contain grammatically correct text.

---

### User Story 5 - Department Auto-Detection (Priority: P3)

The system attempts to match the described work to the correct department from the existing department list. For example, "network switch down in server room" would be assigned to the IT department, while "water leak in bathroom" would go to Maintenance/Plumbing.

**Why this priority**: Convenient but not critical — users can easily select the department manually. AI detection may not always be accurate, so it serves as a suggestion rather than a requirement.

**Independent Test**: Can be tested by typing a department-suggestive description and verifying the department dropdown is pre-selected with the most likely match.

**Acceptance Scenarios**:

1. **Given** the user types a description that implies a specific department, **When** the AI processes it, **Then** the department field is pre-selected with the best matching department from the available list.
2. **Given** the AI cannot confidently determine a department, **When** the form is auto-filled, **Then** the department field retains its default value and the user selects manually.

---

### Edge Cases

- What happens when the AI service is unavailable or times out? A clear error message is shown and the user can fill the form manually as usual.
- What happens when the user submits an empty or very short input (e.g., single word)? The system still attempts to parse it and fills what it can, leaving other fields empty.
- What happens when the input contains no actionable work order information (e.g., "hello" or random text)? The AI returns minimal or no field suggestions, and the user is prompted to provide more detail.
- What happens when the input mentions a department that doesn't exist in the system? The department field is left at its default value.
- What happens when the user edits an auto-filled field and then re-generates from a new input? All fields are overwritten with the new AI output (since the user hasn't submitted yet).
- What happens when the user is on the Edit Work Order screen? The natural language input area is not shown — this feature is for new work order creation only, to avoid accidentally overwriting existing data.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a natural language text input area at the top of the Add Work Order screen with a clear placeholder prompt (e.g., "Describe your work order in a sentence...").
- **FR-002**: System MUST provide a "Generate" button that sends the input text to the AI service for parsing.
- **FR-003**: System MUST auto-fill the following form fields from the AI response: title, description, location, type, and status.
- **FR-004**: System MUST attempt to match and pre-select the department field based on AI analysis of the input, using the list of departments available to the user.
- **FR-005**: System MUST expand shorthand, abbreviations, and informal language into professional work order descriptions.
- **FR-006**: System MUST clean up grammar and formatting in all auto-filled text fields.
- **FR-007**: System MUST support both English and Arabic language input for AI parsing.
- **FR-008**: System MUST allow the user to edit any auto-filled field before submitting the work order.
- **FR-009**: System MUST show a loading indicator while the AI is processing the request.
- **FR-010**: System MUST display a user-friendly error message if the AI service is unavailable, with the option to fill the form manually.
- **FR-011**: System MUST integrate with the existing voice dictation feature (022) on the natural language input area, allowing users to speak their work order description.
- **FR-012**: System MUST only show the natural language input area on the Add Work Order screen (not Edit).
- **FR-013**: System MUST pass the lists of available departments, valid work order types, and valid statuses to the AI so it can only return values from these known sets.
- **FR-014**: System MUST visually highlight auto-filled fields with a temporary indicator (e.g., colored border) after AI processing, and scroll to the first filled field so the user can review.

### Key Entities

- **AI Parse Request**: The natural language text input, the user's language, and the lists of valid departments, types, and statuses sent to the AI service for constrained parsing.
- **AI Parse Response**: Structured data returned by the AI containing extracted/generated values for title, description, location, type (from valid list), department (from valid list), and status (from valid list). Fields the AI cannot determine are omitted or null.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can create a complete work order (all required fields filled) in under 30 seconds using a single sentence input, compared to 2+ minutes filling fields individually.
- **SC-002**: The AI correctly extracts at least 3 out of 5 fields (title, description, location, type, department) from a well-formed input sentence 80% of the time.
- **SC-003**: 90% of auto-filled descriptions are professional quality requiring no grammar or formatting edits by the user.
- **SC-004**: The feature works for both English and Arabic input with comparable accuracy.
- **SC-005**: AI response time is under 10 seconds for a typical single-sentence input, with a loading indicator visible throughout.

## Assumptions

- A new backend endpoint (separate from the existing `/ai/suggest`) will be created to accept free-form text and return structured work order fields.
- The AI model powering the backend can understand and parse natural language into structured work order fields with reasonable accuracy.
- Field technicians will provide at least a brief description of the issue; the AI is not expected to generate a work order from completely ambiguous input.
- The department list is fetched dynamically and passed to the AI so it can match against real department names — the AI does not need a hardcoded list.
- The natural language input area is an addition to the existing form, not a replacement — users can still fill fields manually if they prefer.
- The voice dictation integration (022) provides the transcribed text; this feature only needs to process the resulting text, not handle speech recognition directly.
- Network connectivity is required for AI processing (same as the existing AI assist feature).
- The feature is limited to the Add Work Order screen; the Edit screen is excluded to prevent accidental overwriting of existing work order data.
