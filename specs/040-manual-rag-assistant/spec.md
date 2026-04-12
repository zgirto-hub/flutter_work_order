# Feature Specification: System Manual RAG Assistant

**Feature Branch**: `040-manual-rag-assistant`
**Created**: 2026-04-11
**Status**: Draft
**Input**: User description: "System Manual RAG Assistant — standalone chat screen where any user can ask questions about uploaded system manuals and receive answers grounded in manual content, with sources cited."

## Clarifications

### Session 2026-04-11

- Q: What is the intended corpus scope for this feature — equipment/maintenance manuals only, any technical document the user considers a "manual", or deliberately open? → A: Any technical document the user considers a "manual" (including equipment manuals, procedure guides, and the work order application's own user guide, if a user chooses to upload it). The system does not restrict subject matter; corpus curation is the user's responsibility.
- Q: What per-manual size/scale limit should the system enforce? → A: Medium — up to ~500 pages or 20 MB per manual, whichever is hit first.
- Q: When a user scopes a question to a single manual via the filter and the answer exists only in a different, unselected manual, what should the assistant do? → A: Honor the filter strictly — return the standard "not in the available manuals" response with no hint about other manuals. Clearing the filter is the user's explicit way to search everything.
- Q: How rich should source citations be — plain preview, preview with highlighted matching text, or open the original document with in-place highlighting? → A: Preview with highlighted matching text inside the chunk preview already shown on the answer card (manual title + page + preview with the sentences actually used visually emphasized). Opening the original document is explicitly deferred to a follow-up spec. Line numbers are explicitly NOT added — they are only meaningful for plain-text/Markdown and would mislead users for PDF/DOCX where lines are a rendering artifact, not a property of the document.
- Q: Should the spec set a total corpus ceiling, and how should the system behave when it is reached? → A: Dual guarantee — the system MUST support at least 100 manuals within the per-manual cap (testable user guarantee), AND MUST reject any upload that would push total persisted corpus data in the database past a configurable size threshold (default 400 MB) with a clear "corpus full — delete a manual to make room" message. The 400 MB ceiling applies only to the database-side retrieval representation (metadata rows + chunk text + embeddings); original files on disk are governed separately by FR-019 and by the per-manual cap.
- Q: Where should the original uploaded manual file be stored on the server? → A: Originals MUST be saved to `backend/uploaded_files/manuals/` on the server filesystem, following the existing project convention (the `backend/uploaded_files/` tree is already used by signatures, letters, and editor images). This directly reverses the prior no-retention rule. The chunked retrieval representation in Postgres MUST still be built and kept in addition to the on-disk original. Stored originals serve as a durable source for future re-indexing, audit, and any future in-app viewer; they must be removed when their parent manual is deleted.
- Q: Now that originals are retained on disk, should the previously deferred in-app document viewer (tap a citation → open the original with in-place highlighting) come back into scope for this feature? → A: No — keep deferred. The retention prerequisite is satisfied, but the viewer is still deferred to a follow-up spec for scope-management reasons so the core RAG loop can ship first. The Sources section on answer cards continues to use the in-preview highlight behavior from FR-012a. Retaining the original on disk is still valuable for re-indexing, audit, and the future viewer.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ask a question against uploaded manuals (Priority: P1)

A technician working on equipment opens the Manual Assistant, types a question in their preferred language (Arabic or English), and receives an answer drawn strictly from content in the uploaded manuals, along with a citation showing which manual and page the answer came from.

**Why this priority**: This is the core value of the feature — the reason the screen exists. Without it, uploading manuals has no purpose. Delivering this story alone already produces a working, shippable assistant.

**Independent Test**: With at least one manual already uploaded, a user opens the Manual Assistant chat, submits a question whose answer is contained in that manual, and verifies that (a) the answer reflects the manual's actual content, (b) at least one source citation is displayed, and (c) a question whose answer is not in any uploaded manual produces a clear "not in the available manuals" response rather than a fabricated answer.

**Acceptance Scenarios**:

1. **Given** at least one manual is uploaded and a user is on the Manual Assistant chat tab, **When** the user submits a question whose answer exists in that manual, **Then** the assistant returns an answer based on the manual's content and displays at least one source citation identifying the manual title and page number.
2. **Given** at least one manual is uploaded, **When** the user submits a question whose answer does not exist in any uploaded manual, **Then** the assistant replies that the information is not in the available manuals and does not fabricate content.
3. **Given** the user writes their question in Arabic, **When** the assistant replies, **Then** the reply is in Arabic; and the same holds in reverse for English.
4. **Given** a manual is uploaded and the user has selected it from the manual filter, **When** they ask a question, **Then** only content from the selected manual is considered — even if the answer exists in a different, unselected manual, in which case the standard "not in the available manuals" response is returned with no hint that another manual may contain the answer.
5. **Given** the user has not selected a specific manual, **When** they ask a question, **Then** all uploaded manuals are searched.
6. **Given** a question is being processed, **When** the assistant is retrieving and generating the answer, **Then** a loading indicator is shown until the answer is returned or an error is reported.

---

### User Story 2 - Upload a manual so it becomes queryable (Priority: P1)

A user opens the Manuals tab, uploads a new manual file (PDF, DOCX, plain text, or Markdown), gives it a title, and — once processing completes — the manual immediately becomes available as a source for the chat assistant.

**Why this priority**: P1 because Story 1 cannot be demonstrated without content. These two stories together form the minimum viable feature.

**Independent Test**: A user uploads a supported document, sees the new manual appear in the manuals list with its title, uploader, and upload date, and can then ask a question about its contents in the chat tab and receive a grounded answer.

**Acceptance Scenarios**:

1. **Given** the user is on the Manuals tab, **When** they tap the upload control, select a supported file, enter a title, and confirm, **Then** the manual is processed and appears in the manuals list with title, file name, uploader, and upload date.
2. **Given** a manual upload is in progress, **When** processing is ongoing, **Then** the user is shown progress/loading feedback and is prevented from assuming the upload is complete until it is.
3. **Given** a manual has been uploaded successfully, **When** the user switches to the Chat tab and asks a question whose answer is in that manual, **Then** the answer reflects the newly uploaded content.
4. **Given** the user attempts to upload an unsupported file type, **When** the system detects the type, **Then** the upload is rejected with a clear explanation of the supported formats.
5. **Given** the user attempts to upload a file that cannot be parsed (e.g., empty, corrupt, or image-only scanned PDF with no extractable text), **When** the system detects that no usable text can be extracted, **Then** the upload is rejected with a clear message and no partial manual is left behind.
6. **Given** the total persisted corpus is already at or above the configured size ceiling (default 400 MB) and the user attempts to upload a new manual, **When** the upload is submitted, **Then** the upload is rejected before any chunks are persisted, the user sees an actionable "library full — delete a manual to make room" message, and the existing corpus remains intact.

---

### User Story 3 - Manage (list and delete) existing manuals (Priority: P2)

A user views the full list of uploaded manuals and can delete an individual manual they no longer want available as a source. Once deleted, the manual and its content are no longer used to answer questions.

**Why this priority**: P2 because the system is usable without delete — but over time, stale or superseded manuals must be removable to keep answers trustworthy.

**Independent Test**: A user deletes a manual from the Manuals tab via the delete control, confirms in the confirmation dialog, and verifies that (a) the manual disappears from the list and (b) follow-up questions in the Chat tab can no longer cite content from the deleted manual.

**Acceptance Scenarios**:

1. **Given** the user is viewing the Manuals tab with at least one manual, **When** they choose to delete a specific manual, **Then** a confirmation dialog is shown before deletion proceeds.
2. **Given** the user confirms deletion, **When** the deletion completes, **Then** the manual is removed from the list and its content is no longer retrievable by the chat assistant.
3. **Given** the user cancels the confirmation dialog, **When** the dialog closes, **Then** the manual remains intact and available.

---

### User Story 4 - See which part of a manual an answer came from (Priority: P2)

When reading an answer, the user can expand a "Sources" section to see the manual(s) and specific section(s)/page(s) the assistant used to produce that answer, so they can verify it or go read the original.

**Why this priority**: P2 because Story 1 already shows basic source info, but a richer, verifiable citation experience significantly raises trust. It is the main defense against over-reliance on the model.

**Independent Test**: After receiving any grounded answer, the user taps/expands the Sources section and sees at least the source manual's title and the page number (if available) of each retrieved section, along with a short preview of that section's text.

**Acceptance Scenarios**:

1. **Given** an answer card has been rendered, **When** the user expands the Sources section, **Then** the user sees each source with its manual title, page number (when available), and a short content preview in which the sentence(s) actually used to support the answer are visually highlighted.
2. **Given** no matching manual content was found for a question, **When** the assistant returns the "not in the available manuals" response, **Then** the Sources section is either empty or not shown, and the user is not misled into thinking sources exist.

---

### Edge Cases

- A user asks a question before any manual has been uploaded: the assistant must respond with a clear message that no manuals are available yet and direct them to the Manuals tab, rather than attempting to answer from general knowledge.
- A user uploads a very large manual: the system must still process it, or fail cleanly with a user-visible explanation, rather than hanging indefinitely.
- A user uploads two manuals with the same title: both must remain distinguishable in the list (e.g., by file name and upload date) and in source citations.
- A user asks a very long or multi-part question: the assistant should still produce a single grounded answer or explain that some parts cannot be answered from the manuals.
- Upload is interrupted (network loss, app closed mid-upload): no half-processed manual should remain visible; the user must be able to retry cleanly.
- A user deletes a manual while a question is being processed against it: either the in-flight answer completes with existing sources or it errors cleanly; the user is never shown a broken citation pointing to a now-deleted manual.
- A user with no prior familiarity opens the feature: the empty states in both Chat and Manuals tabs must explain what to do next.
- Mixed-language manuals (e.g., an English manual with Arabic annotations): the assistant should still retrieve and cite the relevant section regardless of question language.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a dedicated Manual Assistant screen accessible from the main application navigation to all authenticated users regardless of role.
- **FR-002**: The Manual Assistant screen MUST expose two distinct views: a conversational Chat view and a Manuals management view.
- **FR-003**: Users MUST be able to upload a manual by selecting a file, providing a human-readable title, and confirming the upload.
- **FR-004**: The system MUST accept manual uploads in PDF, DOCX, plain text, and Markdown formats, and MUST reject any other file type with a clear message.
- **FR-004a**: The system MUST reject any upload that exceeds the per-manual size limit of 500 pages or 20 MB, whichever is hit first, before embedding or persistence begins, and MUST display a clear message stating the limit and why the upload was refused. No partial manual may be left behind.
- **FR-004b**: The system MUST support a corpus of at least 100 manuals, each uploaded within the per-manual size limit, without degrading normal query behavior.
- **FR-004c**: The system MUST reject any new manual upload that would cause total persisted corpus data in the database (metadata rows + chunk text + embeddings) to exceed a configurable size ceiling (default 400 MB). Original files retained on disk per FR-019 are NOT counted against this database ceiling; their worst-case disk footprint is implicitly bounded by the per-manual cap (FR-004a) and the minimum-capacity guarantee (FR-004b) and is operator-managed. When an upload is rejected for this reason, the user MUST see a clear, actionable message (for example: "The manual library is full. Delete an existing manual to make room and try again."). No partial manual may be left behind. The ceiling MUST be configurable by an operator without a code change.
- **FR-005**: The system MUST extract the textual content of an uploaded manual and prepare it for retrieval such that the assistant can later answer questions using the manual's content.
- **FR-006**: The system MUST preserve source location information (at minimum the page number when available) for each extracted segment of a manual, so that answers can be cited back to a specific place in the original document.
- **FR-007**: Users MUST be able to view a list of all uploaded manuals, including at minimum each manual's title, original file name, upload date, and the name of the user who uploaded it.
- **FR-008**: Users MUST be able to delete an individual manual, after confirming via a dialog, and deletion MUST remove all of that manual's content from use by the assistant.
- **FR-009**: Users MUST be able to submit a natural-language question to the assistant in the Chat view via a text input and send action.
- **FR-010**: The assistant MUST answer questions using only the content of the uploaded manuals; if the answer is not contained in the uploaded manuals, it MUST explicitly say so and MUST NOT fabricate an answer.
- **FR-011**: The assistant MUST reply in the same language as the user's question, supporting at least Arabic and English.
- **FR-012**: Each assistant answer MUST be accompanied by the sources (manual title, page number when available, and a short preview of the cited section) it relied on, displayed in a collapsible section on the answer.
- **FR-012a**: Within each source's preview text, the system MUST visually highlight the sentence(s) that most closely support the generated answer, so that the user can verify the answer against its evidence without reading the full chunk. If no highlight can be confidently determined, the preview MUST still render as plain text rather than omitting the source.
- **FR-012b**: Source citations MUST NOT include a line number. Page number (when available for PDF; may be absent for DOCX/TXT/MD) is the finest supported location unit for this version. Opening the original uploaded document in an in-app viewer with in-place highlighting is explicitly out of scope for this spec and deferred to a follow-up feature for scope-management reasons only — the retention prerequisite is satisfied by FR-019, so the deferral is a scope choice, not a technical blocker.
- **FR-013**: Users MUST be able to optionally scope a question to a single selected manual, or leave the scope open so all manuals are considered. When a manual is selected, the assistant MUST consider only that manual's content; if no answer is found there, the assistant MUST return the standard "not in the available manuals" response and MUST NOT reveal, hint at, or cite content from any unselected manual.
- **FR-014**: The Chat view MUST show a visible loading indicator from the time the question is submitted until the answer is returned or an error is shown.
- **FR-015**: If an answer cannot be generated (e.g., the assistant service is unreachable), the system MUST show a user-friendly error message in the chat thread and MUST NOT leave the UI in a stuck loading state.
- **FR-016**: When no manuals have been uploaded, the Chat view MUST display a clear empty state that directs the user to upload a manual before asking questions.
- **FR-017**: When no manuals have been uploaded, the Manuals view MUST display a clear empty state that guides the user to the upload action.
- **FR-018**: The system MUST allow multiple manuals to coexist (e.g., one per equipment type) and MUST be able to retrieve across all of them when no single manual is selected.
- **FR-019**: The system MUST retain the original uploaded manual file on the server filesystem under `backend/uploaded_files/manuals/`, following the existing project convention for uploaded files. The persisted retrieval representation (chunk text + embeddings + metadata rows in the database) MUST be maintained in addition to the original file; neither representation replaces the other. The stored original MUST be removed from disk when its parent manual is deleted (see FR-022).
- **FR-019a**: Stored original manual files MUST use a collision-safe naming scheme (for example, the manual's unique identifier combined with its original file extension) so that two uploads sharing the same original file name cannot overwrite one another on disk. The original file name supplied by the user MUST still be recorded in the database for display purposes per FR-007.
- **FR-019b**: If an upload fails at any step after the original file has been written to disk but before the database records are fully committed, the system MUST remove the orphaned on-disk file so that no stored original exists without a corresponding manual record. Conversely, if database records are created successfully but the original file cannot be written, the entire upload MUST be rejected and any partial database records rolled back.
- **FR-020**: The system MUST record which user uploaded each manual so that accountability and attribution are preserved.
- **FR-021**: Questions submitted while a previous question is still being processed MUST be handled without corrupting the conversation (e.g., by disabling the send action or queuing cleanly) so the user cannot accidentally produce interleaved or lost responses.
- **FR-022**: Deleting a manual MUST cascade so that no residual citations or retrievable content from that manual remain usable after deletion, AND the original file stored on disk under `backend/uploaded_files/manuals/` MUST be removed as part of the same operation. If the on-disk file is already missing or cannot be removed for an environmental reason, deletion of the database records MUST still proceed and the inconsistency MUST be surfaced to the operator (e.g., via server logs) so that orphaned files can be reconciled manually.

### Key Entities

- **Manual**: A document uploaded by a user to serve as a knowledge source. Key attributes: title, original file name, uploader identity, upload timestamp, and a reference to the retained original file stored under the server's uploaded-files area (see FR-019). A manual has many Manual Sections.
- **Manual Section**: A retrievable unit of text extracted from a manual, with enough granularity to be cited back to a specific location. Key attributes: the text content, an ordering index within the parent manual, and the source page number when available. Belongs to exactly one Manual.
- **Question**: A natural-language query submitted by a user, optionally scoped to a single Manual. Not persisted across sessions in this version.
- **Answer**: The assistant's grounded response to a Question. Includes the answer text and the list of Manual Sections used as sources (for display as citations). Not persisted across sessions in this version.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user with no prior training can upload a manual and receive their first grounded answer to a question about its contents in under 3 minutes from first opening the Manual Assistant screen.
- **SC-002**: For questions whose answers are present in an uploaded manual, at least 90% of answers returned by the assistant during acceptance testing cite at least one correct source section from the correct manual.
- **SC-003**: For questions whose answers are not present in any uploaded manual, at least 95% of responses during acceptance testing explicitly state that the information is not in the available manuals rather than producing a fabricated answer.
- **SC-004**: Users receive the first visible response (answer or error) within 15 seconds of submitting a question, where each manual in the corpus conforms to the per-manual size limit (≤500 pages / ≤20 MB) and the question is under 200 words.
- **SC-005**: 100% of uploads of supported file types that contain extractable text result in a manual that is immediately queryable from the Chat view.
- **SC-006**: 100% of uploads of unsupported file types, or files with no extractable text, are rejected with a user-visible explanation and leave no partial manual behind.
- **SC-007**: After a manual is deleted, 100% of subsequent questions return zero citations from that manual.
- **SC-007a**: The system reliably supports at least 100 coexisting manuals (each within the per-manual size cap) with no measurable degradation in the SC-004 response-time target.
- **SC-007b**: When the corpus size ceiling is reached, 100% of attempted uploads are rejected with the user-facing "library full" message before any chunks are persisted, and the existing corpus remains unchanged.
- **SC-008**: Users are able to verify an assistant's answer by navigating from a cited source back to the correct manual and page in under 30 seconds.
- **SC-009**: The assistant replies in the same language as the question (Arabic or English) in at least 95% of sampled interactions.

## Assumptions

- Users accessing the Manual Assistant are already authenticated into the application; no separate sign-in is required for this feature.
- Any authenticated user, regardless of role, can upload, view, delete, and query manuals in this initial version. Per-manual access control is out of scope.
- The corpus is intentionally open in subject matter: a "manual" in this feature is any technical document the user uploads and considers relevant — equipment manuals, maintenance/procedure guides, or the work order application's own user guide are all valid. The system does not restrict, categorize, or validate the subject matter of uploaded documents; corpus curation is the user's responsibility.
- As a consequence of the open corpus scope, a question about application features (e.g., "how do I clear the operator queue?") will only produce a grounded answer if a user has uploaded a document that describes that feature. Otherwise the standard "not in the available manuals" response applies — even when the user knows the application itself supports the action.
- Manuals are assumed to be text-extractable. Scanned image-only PDFs without embedded text are out of scope for this version and may be rejected; OCR will be addressed in a later feature.
- The primary languages supported are Arabic and English, matching the existing application's user base.
- Users may upload the same or similar manuals multiple times; deduplication is out of scope. Users are expected to manage duplicates via delete.
- Manuals are treated as immutable once uploaded. To update a manual, the user deletes the old version and uploads the new one; version history is out of scope for this version.
- Individual manuals are capped at 500 pages or 20 MB (whichever is hit first); anything larger is rejected at upload time per FR-004a. Performance targets (SC-004) assume manuals within this cap.
- The feature relies on the existing application infrastructure for authentication, user identity, and navigation.
- Conversation history (previous questions and answers) is not required to persist across sessions in this version; each session starts with a fresh chat thread.
- The assistant is expected to be used in an advisory capacity by technical staff. It is not positioned as an authoritative replacement for the manuals themselves, and its answers are always accompanied by citations so users can verify against the source.

## Out of Scope

- Per-work-order manual context injection (future: merge with the Work Order Assistant).
- OCR for scanned, image-only PDFs.
- Per-manual access control or role-based visibility.
- Manual version history or in-place manual updates (delete + re-upload is the current workflow).
- Cross-session persistence of chat history.
- In-app viewer of the original uploaded document with in-place highlighting of cited regions. Deferred for scope-management reasons only — FR-019 retains the original file on disk, so this feature is no longer technically blocked; it remains out of this feature's scope and is captured as a follow-up spec so the core RAG loop can ship first.
- Line numbers in citations (not meaningful for PDF/DOCX, where lines are a rendering artifact).
