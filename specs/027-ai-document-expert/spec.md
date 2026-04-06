# Feature Specification: AI Arabic/English Document Expert

**Feature Branch**: `027-ai-document-expert`  
**Created**: 2026-04-06  
**Status**: Draft  
**Input**: User description: "AI-powered bilingual document expert assistant integrated into the letter composer that rewrites, corrects, and professionally elevates formal letter content using the local Ollama/Gemma model."

## Clarifications

### Session 2026-04-06

- Q: Who can access the AI document expert panel? → A: Available to all users who can access the letter form (no role restriction)
- Q: What format does the AI return (plain text, HTML, or markdown)? → A: HTML — AI returns formatted HTML matching the editor's structure
- Q: When does the system check Ollama availability? → A: Check once when the AI panel is expanded; cache result for the session

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Improve Draft Letter Text (Priority: P1)

A letter composer opens the letter form, types a rough Arabic draft in the editor, then expands the AI assistant panel below the editor. They select "تحسين وتنسيق" (Improve), confirm the language is set to Arabic, and click submit. Within 15 seconds, the AI returns a professionally rewritten version in formal governmental Arabic displayed in a result area below. The user reviews it, clicks "Apply" to replace the editor content, and continues editing.

**Why this priority**: This is the core value proposition — transforming rough drafts into professional formal letters. Most users will use this action first and most frequently.

**Independent Test**: Can be fully tested by typing any Arabic text in the letter editor, triggering improve, and verifying the result replaces editor content when applied.

**Acceptance Scenarios**:

1. **Given** a user has typed Arabic text in the letter editor, **When** they select "تحسين وتنسيق" and submit, **Then** the AI returns a professionally rewritten version in formal Arabic within 15 seconds
2. **Given** the AI result is displayed, **When** the user clicks "Apply", **Then** the editor content is replaced with the AI output
3. **Given** the AI result is displayed, **When** the user clicks "Discard" or collapses the panel, **Then** the original editor content remains unchanged

---

### User Story 2 - Correct Grammar and Spelling (Priority: P1)

A user has written a letter body but is unsure about grammar and diacritics. They expand the AI panel, select "تصحيح نحوي" (Correct Grammar), and submit. The AI returns a corrected version with minimal rewrites — fixing only grammar, spelling, and diacritics without changing the overall structure or meaning.

**Why this priority**: Grammar correction is the second most common need and delivers immediate, low-risk value since it preserves the user's original structure.

**Independent Test**: Can be tested by entering text with known grammar errors and verifying corrections are applied without structural changes.

**Acceptance Scenarios**:

1. **Given** a user has text with grammar errors in the editor, **When** they select "تصحيح نحوي", **Then** the AI returns text with corrections applied but structure preserved
2. **Given** the corrected text is shown, **When** the user applies it, **Then** only grammar/spelling/diacritics changes are reflected in the editor

---

### User Story 3 - Generate Letter from Notes (Priority: P2)

A user needs to write a formal letter but only has brief notes or bullet points about the subject. They type their notes into the optional instructions field in the AI panel, select "توليد من ملاحظات" (Generate from Notes), and submit. The AI generates a complete professional letter body based on the notes.

**Why this priority**: Generating from scratch saves significant time for users who struggle with formal letter writing, but is used less frequently than improving existing text.

**Independent Test**: Can be tested by providing brief notes in the instructions field and verifying a complete formal letter body is generated.

**Acceptance Scenarios**:

1. **Given** a user has entered notes in the instructions field, **When** they select "توليد من ملاحظات", **Then** the AI generates a complete formal letter body
2. **Given** the editor already has content and the user generates from notes, **When** they click "Apply", **Then** the editor content is replaced with the generated letter

---

### User Story 4 - Translate Between Arabic and English (Priority: P2)

A user has a letter body in Arabic and needs an English translation (or vice versa). They toggle the language selector to the target language (AR or EN), select "ترجمة" (Translate), and submit. The AI returns the translated text maintaining formal register.

**Why this priority**: Translation is a distinct use case that enables bilingual correspondence, valuable but less frequent than improvement/correction.

**Independent Test**: Can be tested by entering Arabic text, setting target language to EN, and verifying the output is a formal English translation.

**Acceptance Scenarios**:

1. **Given** Arabic text in the editor and target language set to EN, **When** the user selects "ترجمة", **Then** the AI returns a formal English translation
2. **Given** English text in the editor and target language set to AR, **When** the user selects "ترجمة", **Then** the AI returns a formal Arabic translation

---

### User Story 5 - Graceful Degradation When AI Unavailable (Priority: P3)

The AI service (Ollama) is offline or unreachable. The user opens the letter form and sees the AI panel action buttons are disabled with a tooltip indicating the service is unavailable. The rest of the letter form works normally.

**Why this priority**: Important for robustness but is a negative-path scenario that doesn't deliver direct user value.

**Independent Test**: Can be tested by stopping the Ollama service and verifying buttons show disabled state with appropriate tooltip.

**Acceptance Scenarios**:

1. **Given** the Ollama service is unavailable (503), **When** the user views the AI panel, **Then** action buttons are disabled with tooltip "خدمة الذكاء الاصطناعي غير متاحة"
2. **Given** the AI service is unavailable, **When** the user interacts with the rest of the letter form, **Then** all non-AI functionality works normally

---

### Edge Cases

- What happens when the editor body is empty and the user triggers "Improve" or "Correct"? The system should show a message prompting the user to enter text first.
- What happens when the AI returns an empty or malformed response? The system should show an error message and keep the original content intact.
- What happens if the user triggers a new AI action while a previous request is still pending? The pending request should be cancelled before starting the new one.
- What happens when the editor content is extremely long (>5000 words)? The system should send it as-is and handle any timeout gracefully with an error message.
- What happens when the user provides instructions in the free-text field but the editor is empty for non-generate actions? The system should use whatever text is available (instructions field content) or prompt to enter text.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a collapsible AI assistant panel below the rich text editor in the letter form
- **FR-002**: System MUST expose six AI actions: "تحسين وتنسيق" (Improve), "تصحيح نحوي" (Correct Grammar), "توليد من ملاحظات" (Generate from Notes), "ترجمة" (Translate), "تلخيص" (Concise), "توسيع" (Elaborate)
- **FR-003**: System MUST provide an explicit AR/EN toggle button that sets the output language for the AI response
- **FR-004**: System MUST extract the full editor body content as input for AI processing
- **FR-005**: System MUST provide an optional free-text instructions field where users can add context or specific directions for the AI
- **FR-006**: System MUST display the AI result in a separate read-only text area below the action buttons
- **FR-007**: System MUST provide an "Apply" button that replaces the editor content with the AI result
- **FR-008**: System MUST preserve the original editor content until the user explicitly applies the AI result
- **FR-009**: System MUST show a loading indicator while the AI request is in progress
- **FR-010**: System MUST disable action buttons with tooltip "خدمة الذكاء الاصطناعي غير متاحة" when the AI service is unavailable (detected on panel expand)
- **FR-011**: System MUST process AI requests as single batch responses (not streaming)
- **FR-012**: System MUST cancel any pending AI request when the user triggers a new action
- **FR-013**: System MUST validate that editor content is non-empty before allowing Improve, Correct, Translate, Concise, or Elaborate actions
- **FR-014**: System MUST use formal governmental Arabic writing style as the default AI persona for all actions
- **FR-015**: System MUST be accessible to all users who can access the letter form, with no additional role restrictions
- **FR-016**: AI responses MUST be returned as HTML content compatible with the iframe editor's structure
- **FR-017**: System MUST check Ollama service availability once when the AI panel is expanded and cache the result for the duration of the session

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users receive a professionally rewritten version of their text within 15 seconds of submitting a request
- **SC-002**: Users can accept or discard AI suggestions without losing their original draft at any point
- **SC-003**: All six AI actions (Improve, Correct, Generate, Translate, Concise, Elaborate) produce contextually appropriate output in the selected language
- **SC-004**: The AI panel is discoverable and usable without training — users can complete their first AI-assisted rewrite within 30 seconds of opening the panel
- **SC-005**: The feature degrades gracefully when the AI service is offline, with clear visual indication and no impact on other letter form functionality
- **SC-006**: No regressions to existing letter generation, preview, or history functionality

## Assumptions

- The Ollama/Gemma AI service (gemma4:e2b) is running and accessible from the backend server at a known URL
- The existing letter editor uses an iframe-based rich text editor that supports postMessage for content injection and extraction
- Users are primarily composing formal civil aviation correspondence in Arabic, with occasional English correspondence
- The existing AI backend pattern (ai_assist.py) can be extended with a new endpoint without architectural changes
- Single batch (non-streaming) responses are acceptable for the expected document lengths (typically under 2000 words)
- No persistent storage of AI suggestions is needed — results are ephemeral and exist only during the editing session
