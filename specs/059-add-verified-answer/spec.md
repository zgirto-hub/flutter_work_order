# Feature Specification: Add Verified Answer — Manual Entry

**Feature Branch**: `059-add-verified-answer`  
**Created**: 2026-04-14  
**Status**: Draft  
**Input**: User description: "Allow admins to manually create verified Q&A pairs directly in the knowledge base without going through the review queue"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin Creates a Verified Q&A Pair (Priority: P1)

An admin is preparing the knowledge base after uploading a new technical manual. They navigate to the Verified Answers tab, tap a button to add a new entry, type both the question and the answer, and submit. The new Q&A pair is immediately saved and appears at the top of the verified answers list, ready to be retrieved by the AI assistant when users ask similar questions.

**Why this priority**: This is the entire feature — without it, admins have no way to seed the knowledge base directly. Every other story is a refinement of this core flow.

**Independent Test**: Can be fully tested by opening the Verified Answers tab, tapping the add button, filling in both fields, and confirming the entry appears in the list. Delivers immediate value by enabling knowledge base seeding.

**Acceptance Scenarios**:

1. **Given** an admin is on the Verified Answers tab, **When** they tap the add button and fill in both question and answer fields and submit, **Then** the new entry appears at the top of the list immediately without a full page reload.
2. **Given** an admin opens the add dialog, **When** they leave either the question or answer field empty and attempt to submit, **Then** the system prevents submission (no request is sent).
3. **Given** an admin submits a valid Q&A pair, **When** the embedding service processes the question, **Then** the entry is stored with a searchable embedding so that future AI queries can match against it.

---

### User Story 2 - Handling Service Unavailability (Priority: P2)

An admin attempts to add a verified answer, but the embedding service is temporarily unavailable or takes too long. The system shows a specific, actionable error message so the admin knows to try again later rather than wondering if the entry was saved.

**Why this priority**: Error handling ensures a reliable user experience. Without it, admins may lose work or be confused by cryptic failures.

**Independent Test**: Can be tested by submitting a Q&A pair when the embedding service is down and verifying the error message is clear and specific.

**Acceptance Scenarios**:

1. **Given** the embedding service is unavailable or times out, **When** an admin submits a new Q&A pair, **Then** the system displays the message "Embedding timed out — please try again" (not a generic error).
2. **Given** a submission fails for any reason, **When** the error is displayed, **Then** the verified answers list remains unchanged (no partial or corrupt entry is added).

---

### Edge Cases

- What happens if an admin submits a duplicate question that already exists in verified answers? The system allows it — deduplication is not enforced, since the same question may have different valid answers depending on context.
- What happens if the admin's session expires between opening the dialog and submitting? The system returns an appropriate authentication error.
- What happens if the question or answer contains only whitespace? The system treats it as empty and prevents submission.
- What happens if the answer text is very long (e.g., multiple paragraphs)? The system accepts it — there is no maximum length enforced at the UI level.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow admin users to create a new verified Q&A pair by providing a question and answer.
- **FR-002**: System MUST require both question and answer fields to be non-empty before allowing submission.
- **FR-003**: System MUST generate a searchable embedding for the question text at creation time so it can be matched by the AI assistant.
- **FR-004**: System MUST display the newly created entry at the top of the verified answers list immediately after successful creation, without requiring a full list reload.
- **FR-005**: System MUST restrict this capability to admin users only.
- **FR-006**: System MUST show the specific error message "Embedding timed out — please try again" when the embedding service is unavailable or slow.
- **FR-007**: System MUST NOT modify, remove, or interfere with the existing review queue flow for promoting user-submitted answers.
- **FR-008**: System MUST present the add dialog in the same visual style as the existing edit dialog for verified answers.

### Key Entities

- **Verified Q&A Pair**: A question-and-answer entry in the knowledge base. Contains question text, answer text, a question embedding (for semantic search), the admin who created it, and a creation timestamp. Can be created either through the review queue (existing flow) or directly by an admin (this feature).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Admins can create a new verified Q&A pair in under 30 seconds (excluding embedding processing time).
- **SC-002**: 100% of newly created Q&A pairs are retrievable by the AI assistant via semantic search immediately after creation.
- **SC-003**: The existing review queue flow continues to work identically — zero regressions in the promote-from-review workflow.
- **SC-004**: When the embedding service is unavailable, 100% of failures show the specific timeout message rather than a generic error.

## Assumptions

- Only admin users have access to the Verified Answers tab — no additional permission checks are needed beyond what already exists.
- The embedding service (used for making questions searchable) is the same service already used by the existing edit flow for verified answers.
- The visual design of the add dialog follows the same pattern as the existing edit dialog — no new design work is required.
- The existing verified answers list supports inserting a new entry at the top without requiring a full data reload from the server.
- There is no need for bulk import of Q&A pairs — this feature handles one entry at a time. Bulk import is a separate future feature.
