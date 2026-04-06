# Feature Specification: Voice-to-Work-Order Dictation

**Feature Branch**: `022-voice-work-order`  
**Created**: 2026-04-06  
**Status**: Draft  
**Input**: User description: "Voice-to-work-order feature for field technicians. On the Add Work Order screen, a microphone button lets users dictate the work order title and description hands-free using the device's speech-to-text capability. The recorded speech is transcribed in real-time and populates the title and description fields. Supports Arabic and English. Works on mobile browsers (PWA). No backend changes needed — uses the Web Speech API or Flutter's speech_to_text package client-side."

## Clarifications

### Session 2026-04-06

- Q: Should dictation work only on the Add Work Order screen, or also on Edit? → A: Both Add and Edit Work Order screens.
- Q: On Edit screen, how should dictated text interact with existing content? → A: Always append after existing content.
- Q: Should dictation handle spoken punctuation commands via custom logic? → A: No; rely on speech engine's built-in punctuation handling.
- Q: What should happen when dictation fails due to low connectivity? → A: Show brief inline message guiding user to type instead.
- Q: Should dictation be available on fields beyond title and description? → A: No; title and description only.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Dictate Work Order Description (Priority: P1)

A field technician is on-site with dirty or gloved hands and needs to create or update a work order. They open the Add or Edit Work Order screen, tap the microphone button next to the description field, and speak their description aloud. The speech is transcribed in real-time and appears in the description field. They review the text, make any corrections manually, and submit the work order.

**Why this priority**: This is the core use case — hands-free description entry is the primary value proposition for field technicians who cannot easily type on a mobile device while working.

**Independent Test**: Can be fully tested by opening the Add Work Order screen, tapping the mic button on the description field, speaking a sentence, and verifying the transcribed text appears in the field.

**Acceptance Scenarios**:

1. **Given** the user is on the Add or Edit Work Order screen, **When** they tap the microphone button next to the description field and speak, **Then** the spoken words appear in the description field in real-time as they speak.
2. **Given** the user is dictating into the description field, **When** they stop speaking or tap the microphone button again, **Then** recording stops and the transcribed text remains in the field for review and editing.
3. **Given** the user has dictated text into the description field, **When** they manually edit the transcribed text, **Then** they can freely modify, add to, or delete portions of the transcribed content.

---

### User Story 2 - Dictate Work Order Title (Priority: P2)

A field technician taps the microphone button next to the title field and dictates a short work order title. The transcribed text populates the title field.

**Why this priority**: Title dictation is valuable but secondary since titles are typically short and easier to type than longer descriptions.

**Independent Test**: Can be fully tested by tapping the mic button on the title field, speaking a short phrase, and verifying it appears in the title field.

**Acceptance Scenarios**:

1. **Given** the user is on the Add or Edit Work Order screen, **When** they tap the microphone button next to the title field and speak, **Then** the spoken words appear in the title field in real-time.
2. **Given** the user is dictating into the title field, **When** they finish speaking and stop, **Then** the transcribed text stays in the title field ready for submission or manual editing.

---

### User Story 3 - Dictate in Arabic (Priority: P2)

A field technician whose primary language is Arabic uses the dictation feature. The system recognizes Arabic speech and transcribes it correctly into the target field with proper right-to-left text rendering.

**Why this priority**: The application serves a bilingual user base; Arabic support is essential for adoption by Arabic-speaking technicians who make up a significant portion of the workforce.

**Independent Test**: Can be fully tested by switching the app language to Arabic, tapping the mic button, speaking in Arabic, and verifying the transcribed Arabic text appears correctly in the field.

**Acceptance Scenarios**:

1. **Given** the user has the app set to Arabic, **When** they tap the microphone button and speak in Arabic, **Then** the system transcribes their Arabic speech correctly into the field.
2. **Given** the user has the app set to English, **When** they tap the microphone button and speak in English, **Then** the system transcribes their English speech correctly into the field.

---

### User Story 4 - Visual Feedback During Dictation (Priority: P3)

While dictating, the technician sees clear visual feedback that recording is active — such as the microphone button changing color or showing an animation — so they know the system is listening.

**Why this priority**: Important for usability but not core functionality; users need confidence the system is capturing their speech.

**Independent Test**: Can be tested by starting dictation and observing that the microphone button visually changes state to indicate active recording.

**Acceptance Scenarios**:

1. **Given** the user taps the microphone button, **When** recording begins, **Then** the microphone button visually indicates active recording state (e.g., color change, pulsing animation).
2. **Given** recording is active, **When** the user stops dictation, **Then** the microphone button returns to its default idle state.

---

### Edge Cases

- What happens when the user's device does not support speech recognition? The microphone button should be hidden or disabled, and no error is shown.
- What happens when the user denies microphone permission? A clear message instructs the user to grant microphone access in their device settings.
- What happens when dictation produces no recognizable speech (background noise, silence)? The field remains unchanged and the recording stops gracefully after a reasonable timeout.
- What happens when the user starts dictation on one field while another field's dictation is still active? The previous field's dictation stops and the new field's dictation begins.
- What happens during a network interruption if the speech recognition service requires connectivity? A brief inline message informs the user that speech recognition is temporarily unavailable and guides them to type instead.
- What happens when the user dictates very long text? The transcribed text respects any existing character limits on the field, and the user is notified if the limit is reached.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a microphone button adjacent to both the title and description fields on the Add and Edit Work Order screens.
- **FR-002**: System MUST transcribe spoken speech in real-time and populate the associated text field as the user speaks.
- **FR-003**: System MUST support speech recognition in both English and Arabic languages.
- **FR-004**: System MUST automatically select the speech recognition language based on the current app language setting.
- **FR-005**: System MUST allow the user to stop dictation by tapping the microphone button again.
- **FR-006**: System MUST provide clear visual feedback indicating when dictation is actively recording.
- **FR-007**: System MUST allow users to manually edit transcribed text after dictation completes.
- **FR-008**: System MUST append dictated text to any existing content in the field rather than replacing it.
- **FR-009**: System MUST gracefully handle the absence of speech recognition support by hiding or disabling the microphone button.
- **FR-010**: System MUST prompt the user for microphone permission if not already granted, and display guidance if permission is denied.
- **FR-011**: System MUST stop dictation automatically after a period of silence (reasonable timeout).
- **FR-012**: System MUST ensure only one field can be actively recording at a time.
- **FR-013**: System MUST display a brief inline message when dictation fails due to network connectivity issues, guiding the user to type manually instead.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Field technicians can create a work order description hands-free in under 60 seconds for a typical 2-3 sentence description.
- **SC-002**: Speech-to-text transcription accuracy is at least 85% for clear speech in both English and Arabic in a normal-noise environment.
- **SC-003**: Real-time transcription feedback appears within 1 second of the user speaking.
- **SC-004**: 90% of field technicians can successfully use the dictation feature on their first attempt without instructions.
- **SC-005**: The dictation feature works on modern mobile browsers (Chrome, Safari) used in the PWA without requiring app installation.

## Assumptions

- Field technicians have devices with working microphones (standard on all modern smartphones).
- The device's browser supports the Web Speech API or an equivalent client-side speech recognition capability.
- The app's existing language setting (English/Arabic toggle) is used to determine the dictation language — no separate language picker is needed for dictation.
- Network connectivity is available when using dictation, as most browser-based speech recognition services require an internet connection.
- The existing Add and Edit Work Order screen layouts can accommodate a microphone button next to the title and description fields without a major redesign.
- No backend changes are required — all speech processing happens client-side in the browser.
- Dictation appends to existing field content so users can combine typed and dictated input.
- Punctuation in transcribed text is handled by the speech recognition engine's built-in capabilities; no custom punctuation command processing is needed.
