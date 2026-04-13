# Feature Specification: Feedback Loop AI Assistant

**Feature Branch**: `048-feedback-loop-ai-assistant`  
**Created**: 2026-04-13  
**Status**: Draft  
**Input**: User description: "Feedback loop system for the manual assistant AI pipeline. After every answer the assistant gives, the technician can rate it (thumbs up / thumbs down) directly in the Flutter chat interface. Thumbs down answers are flagged for review. A senior engineer (admin role) sees a review queue in the Manual Assistant screen showing all flagged answers with the original question, the AI answer, and the source chunks used. The senior engineer can either write a corrected answer or approve the AI answer as correct. Validated answers (both approved and corrected) are stored in Supabase as a validated_qa table with metadata. When a new question arrives, check the validated_qa table for a semantically similar question using pgvector cosine similarity. If a match is found with similarity above 0.90, return the validated answer directly. If similarity is between 0.75 and 0.90, include the validated answer as a high-priority context chunk."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Technician Rates an AI Answer (Priority: P1)

A technician asks a question in the manual assistant chat and receives an AI-generated answer. Below each answer, the technician sees a thumbs-up and thumbs-down button. The technician taps one of the buttons to indicate whether the answer was helpful. The rating is recorded and the button state updates to show which rating was given. A thumbs-down rating flags the question-answer pair for senior engineer review.

**Why this priority**: Rating is the entry point of the entire feedback loop. Without technician ratings, no answers get flagged, no reviews happen, and no validated answers accumulate. This is the foundational interaction that feeds every other part of the system.

**Independent Test**: Can be fully tested by asking a question in the chat, receiving an answer, and tapping the thumbs-up or thumbs-down button. Delivers immediate value by capturing technician satisfaction data.

**Acceptance Scenarios**:

1. **Given** a technician has received an AI answer in the chat, **When** they tap the thumbs-down button, **Then** the button visually indicates it was selected, the rating is saved, and the question-answer pair is flagged for review.
2. **Given** a technician has received an AI answer in the chat, **When** they tap the thumbs-up button, **Then** the button visually indicates it was selected and the positive rating is saved.
3. **Given** a technician has already rated an answer, **When** they tap the other rating button, **Then** the previous rating is replaced with the new one (toggle behavior).
4. **Given** a technician has rated an answer, **When** they scroll back to that message in the same session, **Then** the rating button state is preserved.

---

### User Story 2 - Senior Engineer Reviews Flagged Answers (Priority: P2)

A senior engineer (admin role) opens the Manual Assistant screen and sees a "Review Queue" tab alongside the existing Chat and Knowledge tabs. This tab shows all question-answer pairs that received thumbs-down ratings and have not yet been reviewed. Each entry displays the original question, the AI-generated answer, and the source chunks that were used. The senior engineer can either approve the AI answer as correct or write a corrected answer to replace it. Once reviewed, the entry is removed from the queue and stored as a validated question-answer pair.

**Why this priority**: The review queue is the mechanism through which senior expertise enters the system. Without it, flagged answers accumulate with no resolution and validated answers are never created.

**Independent Test**: Can be tested by flagging answers (from Story 1), then logging in as an admin user and reviewing them in the Review Queue tab. Delivers value by enabling expert oversight of AI quality.

**Acceptance Scenarios**:

1. **Given** an admin user opens the Manual Assistant screen, **When** flagged answers exist, **Then** the Review Queue tab shows a badge count of pending items and displays each flagged entry with the question, AI answer, and source chunks.
2. **Given** an admin is viewing a flagged entry, **When** they tap "Approve", **Then** the AI answer is stored as a validated answer, the entry is removed from the queue, and the thumbs-up count is incremented.
3. **Given** an admin is viewing a flagged entry, **When** they write a corrected answer and tap "Save Correction", **Then** the corrected answer replaces the AI answer in the validated record, the entry is removed from the queue, and metadata is recorded (who validated, when).
4. **Given** a non-admin user opens the Manual Assistant screen, **When** they look at the tabs, **Then** the Review Queue tab is not visible.
5. **Given** an admin is reviewing an entry, **When** they view the source chunks, **Then** each chunk shows the manual title, page number, and a content preview so they can verify the AI's reasoning.

---

### User Story 3 - System Returns a Validated Answer for a Matching Question (Priority: P3)

A technician asks a question in the manual assistant chat. Before the system runs its full AI pipeline (query rewriting, hypothetical answer generation, retrieval, and generation), it first checks whether a semantically similar question has already been validated by a senior engineer. If a very close match is found (above 0.90 similarity), the validated answer is returned directly without invoking the AI model, resulting in a faster and more reliable response. If a moderate match is found (between 0.75 and 0.90), the validated answer is included as a high-priority reference that the AI model considers alongside retrieved manual chunks.

**Why this priority**: This is the payoff of the entire feedback loop — the system gets smarter over time. However, it requires validated answers to exist first (Stories 1 and 2), making it naturally the third priority.

**Independent Test**: Can be tested by validating an answer (from Story 2), then asking a semantically similar question and verifying the response is the validated answer (for high similarity) or that the validated answer influences the AI response (for moderate similarity).

**Acceptance Scenarios**:

1. **Given** a validated answer exists for "How to replace the hydraulic pump on Boeing 737?", **When** a technician asks "What is the procedure for hydraulic pump replacement on a 737?", **Then** the system returns the validated answer directly without calling the AI model, and the response is labeled as a "Verified Answer".
2. **Given** a validated answer exists for "Landing gear inspection procedure", **When** a technician asks a moderately similar question like "What should I check during gear maintenance?", **Then** the AI model generates a response that incorporates the validated answer as a high-priority context source, and the source attribution includes the validated answer.
3. **Given** no validated answer matches the question above the 0.75 threshold, **When** a technician asks a question, **Then** the system proceeds through the normal AI pipeline with no change in behavior.
4. **Given** a validated answer is returned directly (above 0.90 match), **When** the technician views the response, **Then** the response indicates it is a verified answer sourced from expert validation, not AI-generated.

---

### User Story 4 - Feedback Metrics Accumulate Over Time (Priority: P4)

As technicians continue to rate answers and senior engineers continue to review flagged ones, the system accumulates rating counts on validated answers. Each validated answer tracks how many times it received a thumbs-up and how many times it received a thumbs-down across all instances where it was served. This data helps identify which validated answers are performing well and which may need re-review.

**Why this priority**: Metrics accumulation is valuable for long-term system health monitoring but does not block any core functionality. It enhances the review process by surfacing answers that may need updating.

**Independent Test**: Can be tested by serving the same validated answer to multiple technicians, having them rate it, and verifying the cumulative counts update correctly.

**Acceptance Scenarios**:

1. **Given** a validated answer has been served 5 times and received 4 thumbs-up and 1 thumbs-down, **When** an admin views this entry in the review queue or validated answers list, **Then** they see the cumulative rating counts (4 up, 1 down).
2. **Given** a validated answer receives a new thumbs-down after being previously approved, **When** the thumbs-down count exceeds a threshold relative to total ratings, **Then** the answer is re-flagged for review so a senior engineer can reassess it.

---

### Edge Cases

- What happens when a technician rates an answer but loses connectivity before the rating is saved? The system should show an error indication on the rating button and allow the technician to retry.
- What happens when two admins attempt to review the same flagged entry simultaneously? The first submission wins; the second admin sees a message indicating the entry has already been reviewed and is refreshed.
- What happens when a validated answer is returned directly but the underlying manual content has since been updated? Validated answers should include a reference to the manual version (manual IDs used) so that admins can periodically re-validate answers when manuals are re-uploaded.
- What happens when the question embedding fails during the similarity check? The system falls back to the standard AI pipeline without interruption.
- What happens when the validated_qa table is empty (no validated answers yet)? The similarity check returns no matches and the system proceeds through the normal pipeline with zero additional latency.
- What happens when a technician asks a question that matches a validated answer at exactly 0.90 similarity? The system treats 0.90 as the lower bound for direct return (inclusive), returning the validated answer directly.
- What happens when a corrected answer is very long? The text input for corrections should support multi-line entry but enforce a reasonable character limit consistent with typical manual procedures.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display a thumbs-up and thumbs-down rating button beneath each AI-generated answer in the chat interface.
- **FR-002**: System MUST allow technicians to submit exactly one rating (thumbs-up or thumbs-down) per answer, with the ability to change their rating before navigating away.
- **FR-003**: System MUST flag any question-answer pair that receives a thumbs-down rating for senior engineer review.
- **FR-004**: System MUST provide a "Review Queue" tab in the Manual Assistant screen visible only to users with the admin role.
- **FR-005**: The Review Queue MUST display each flagged entry with: the original question text, the AI-generated answer, the source chunks used (manual title, page number, content preview), and the timestamp of the question.
- **FR-006**: Admin users MUST be able to approve an AI answer as correct from the review queue, storing it as a validated answer.
- **FR-007**: Admin users MUST be able to write a corrected answer to replace the AI answer, storing the correction as the validated answer.
- **FR-008**: Validated answers MUST be stored with the following metadata: question text, validated answer text, equipment type (extracted from question), fault code (if present in question), procedure referenced, manual IDs used as sources, validated-by user identifier, validation timestamp, cumulative thumbs-up count, cumulative thumbs-down count.
- **FR-009**: System MUST embed the question text of each validated answer for semantic similarity search.
- **FR-010**: When a new question arrives, the system MUST check for semantically similar validated questions before running query rewriting or hypothetical answer generation.
- **FR-011**: If a validated answer match is found with similarity at or above 0.90, the system MUST return the validated answer directly without invoking the AI generation model.
- **FR-012**: If a validated answer match is found with similarity between 0.75 (inclusive) and 0.90 (exclusive), the system MUST include the validated answer as a high-priority context chunk that ranks above all retrieved manual chunks.
- **FR-013**: If no validated answer match is found above 0.75 similarity, the system MUST proceed through the standard AI pipeline with no behavioral change.
- **FR-014**: Directly returned validated answers (above 0.90 match) MUST be visually distinguished in the chat interface with a "Verified Answer" label.
- **FR-015**: System MUST increment the thumbs-up or thumbs-down count on a validated answer each time it is served and subsequently rated by a technician.
- **FR-016**: System MUST record a rating activity log entry when a technician rates an answer, following the existing activity logging pattern.
- **FR-017**: System MUST record a review activity log entry when an admin approves or corrects a flagged answer.
- **FR-018**: The review queue MUST support scrolling through all pending items with newest entries appearing first.
- **FR-019**: System MUST automatically extract equipment type and fault code from the question text when creating a validated answer record.

### Key Entities

- **Answer Rating**: A technician's evaluation of a single AI-generated answer. Contains the question text, the AI answer text, the source chunks used, the rating (positive or negative), the rater's identity, and the timestamp. A negative rating creates a review flag.
- **Flagged Answer**: A question-answer pair that received a negative rating and is awaiting senior engineer review. Contains all information from the rating plus review status (pending, approved, corrected). Removed from the queue once reviewed.
- **Validated QA Pair**: An expert-approved question-answer pair stored for future reuse. Contains the question text, the validated answer (either the original AI answer or a corrected version), an embedding of the question for similarity search, extracted metadata (equipment type, fault code, procedure, manual references), validation provenance (who validated, when), and cumulative rating counts. This is the core knowledge asset that makes the system smarter over time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Technicians can rate any AI answer with a single tap, completing the rating action in under 1 second.
- **SC-002**: Admin users can review and resolve a flagged answer (approve or correct) in under 2 minutes per entry.
- **SC-003**: When a validated answer matches a new question above the 0.90 similarity threshold, the response is returned in under 1 second (compared to the typical 5-15 second AI pipeline).
- **SC-004**: After 50 validated answers are accumulated, at least 10% of incoming questions receive a direct validated answer (above 0.90 match), reducing AI model usage proportionally.
- **SC-005**: 100% of thumbs-down rated answers appear in the admin review queue within 5 seconds of rating submission.
- **SC-006**: Validated answers served directly maintain a thumbs-up rate of 85% or higher, confirming expert-validated quality.
- **SC-007**: The review queue is accessible only to admin-role users; non-admin users see no indication of its existence.

## Assumptions

- The existing admin role detection is sufficient to gate access to the review queue; no new role or permission is needed.
- The existing text embedding infrastructure is adequate for computing similarity between question texts in the validated answers store.
- The existing vector similarity search infrastructure can be reused for validated answer matching with a new search index.
- Equipment type and fault code extraction from question text can be accomplished with reasonable accuracy using pattern matching (e.g., aircraft model numbers, ATA chapter codes) supplemented by AI extraction during the validation step; perfect extraction is not required as these fields serve as optional metadata for filtering and reporting.
- The similarity thresholds (0.90 for direct return, 0.75 for high-priority context) are initial values that may be tuned based on real-world usage; the system should make these configurable.
- Ratings are per-session and per-answer; the same technician asking the same question in a different session generates a new rateable answer.
- The review queue does not require real-time push updates; polling or refresh-on-tab-switch is acceptable.
- The existing activity logging system will be extended to cover rating and review actions without requiring a new logging infrastructure.
- Manual re-uploads do not automatically invalidate validated answers, but the stored manual IDs allow admins to identify potentially stale answers.
