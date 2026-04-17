# Feature Specification: Train the AI Tab — 3-Stage Learning Pipeline

**Feature Branch**: `080-train-ai-tab`  
**Created**: 2026-04-17  
**Status**: Draft  
**Input**: User description: "Add a Train the AI tab to the Manual Assistant screen (admin-only) that seeds and grows the validated_qa cache using three complementary sources: manuals (bootstrap), real technician usage (self-improving), and a staleness review queue to keep cached answers current."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bootstrap Cache from Manuals (Priority: P1)

An admin navigates to the Train the AI tab, selects a maintenance manual from a dropdown, and clicks "Generate Q&A Candidates." The system reads the manual's content chunks and auto-generates practical question-and-answer pairs that a technician might realistically ask. The admin reviews each candidate, edits if needed, approves the good ones, rejects the rest, and clicks "Save All Approved." The system saves each approved pair to the verified answer cache along with English and Arabic paraphrase variants, dramatically expanding cache coverage in minutes rather than hours of manual entry.

**Why this priority**: This is the core value proposition — bulk-seeding the cache from existing manuals is the fastest way to cover ~80% of daily technician queries. Without this, the cache must be built one entry at a time.

**Independent Test**: Can be fully tested by selecting any processed manual, generating candidates, approving at least one, and verifying the saved entries appear in the verified answers list with correct variant embeddings.

**Acceptance Scenarios**:

1. **Given** an admin is on the "From Manuals" section with a processed manual selected, **When** they click "Generate Q&A Candidates," **Then** the system generates up to 20 candidate Q&A pairs with a progress indicator showing count progress.
2. **Given** generated candidates are displayed, **When** the admin approves 5 candidates and clicks "Save All Approved," **Then** 5 primary entries are saved to the cache, each with 4 English + 3 Arabic paraphrase variants (35 total embeddings), and a success summary is shown.
3. **Given** a candidate card is displayed, **When** the admin clicks "Edit," **Then** both the question and answer fields become editable inline.
4. **Given** a candidate card is displayed, **When** the admin clicks "Reject," **Then** the card is dismissed with a slide animation.
5. **Given** no candidates are approved, **When** the admin views the bottom bar, **Then** the "Save All Approved" button is disabled.
6. **Given** a manual has no content chunks, **When** the admin tries to generate candidates, **Then** an error message instructs them to process the manual first.
7. **Given** some chunks already have close matches in the cache (similarity >= 0.85), **When** candidates are generated, **Then** those chunks are skipped and the skipped count is reported.

---

### User Story 2 - Promote Real Usage to Cache (Priority: P2)

An admin navigates to the "From Real Usage" section and sees a list of questions that real technicians asked the AI assistant which received multiple positive ratings but are not yet in the verified cache. The admin reviews each suggestion, optionally edits the answer, and adds it to the cache with one tap. This creates a self-improving feedback loop where the best AI answers are automatically surfaced for promotion.

**Why this priority**: This complements the manual bootstrap by capturing questions the manuals didn't anticipate — real technician language, edge cases, and practical scenarios. It requires no manual effort beyond approval.

**Independent Test**: Can be tested by verifying that positively-rated answers (2+ ratings) not already in the cache appear as suggestions, and that approving one creates a cache entry with paraphrase variants.

**Acceptance Scenarios**:

1. **Given** technicians have asked questions that received 2+ positive ratings, **When** the admin opens "From Real Usage," **Then** those questions appear as suggestion cards ordered by rating count (highest first).
2. **Given** a suggestion card is displayed, **When** the admin clicks "Add to Cache," **Then** the entry is saved with English and Arabic paraphrase variants (same 4-step flow as manual bootstrap).
3. **Given** a suggestion card is displayed, **When** the admin clicks "Edit then Add," **Then** the question and answer become editable, and saving runs the full cache-add flow.
4. **Given** a suggestion card is displayed, **When** the admin clicks "Dismiss," **Then** the card is removed from the list without deleting the underlying ratings.
5. **Given** multiple suggestions exist, **When** the admin clicks "Approve All," **Then** a confirmation dialog appears, and on confirmation all visible suggestions are added to the cache.
6. **Given** no positively-rated uncached questions exist, **When** the admin opens "From Real Usage," **Then** an empty state message explains that suggestions will appear as technicians use the assistant.
7. **Given** a question was already added to the cache, **When** the admin refreshes the list, **Then** that question no longer appears in suggestions.

---

### User Story 3 - Review Stale Cache Entries (Priority: P3)

An admin sees a badge count on the "Needs Review" segment indicating some cached answers may be outdated because their source manual was re-uploaded or reprocessed. They navigate to the section, review each flagged entry, and either confirm it's still valid, edit and reconfirm it, or remove it and its variants from the cache. This ensures the cache stays accurate as manuals evolve.

**Why this priority**: Staleness detection prevents technicians from receiving outdated answers. While less frequent than the initial bootstrap, it's essential for long-term cache reliability.

**Independent Test**: Can be tested by re-processing a manual that has cached entries derived from it, then verifying those entries appear in the "Needs Review" queue with the correct staleness warning.

**Acceptance Scenarios**:

1. **Given** a manual was re-uploaded after some of its Q&A pairs were cached, **When** the admin opens "Needs Review," **Then** those entries appear with a warning showing how many days since the manual was updated.
2. **Given** a stale entry is displayed, **When** the admin clicks "Still Valid," **Then** the entry's verified timestamp is updated and it disappears from the stale list.
3. **Given** a stale entry is displayed, **When** the admin clicks "Edit & Reconfirm," **Then** both fields become editable, and saving re-embeds the question and updates the verified timestamp.
4. **Given** a stale entry is displayed, **When** the admin clicks "Remove from Cache," **Then** a confirmation dialog warns this cannot be undone, and on confirmation the entry plus all its paraphrase variants are deleted.
5. **Given** no stale entries exist, **When** the admin opens "Needs Review," **Then** a green checkmark empty state confirms all cached answers are up to date.
6. **Given** stale entries exist, **When** the admin views the tab navigation, **Then** the "Needs Review" segment shows a badge with the stale count.

---

### Edge Cases

- What happens when the AI generates invalid JSON during Q&A candidate generation? The candidate is silently skipped and generation continues with the next batch.
- What happens when a manual is deleted while candidates are being reviewed? The save operation handles the missing source gracefully and still saves the Q&A pair.
- What happens when two admins generate candidates for the same manual simultaneously? Each session operates independently; deduplication via embedding similarity prevents duplicate cache entries.
- What happens when the "Approve All" action in Section B partially fails (e.g., network error mid-batch)? Successfully saved entries remain; the user is informed of how many succeeded and how many failed.
- What happens when a stale entry's source manual has been deleted? The entry should still appear in the review queue with a note that the source manual no longer exists.
- What happens when the admin dismisses a suggestion in Section B, then reloads? The dismiss is UI-only (in-memory) — the suggestion reappears on next page load if it still qualifies.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a "Train the AI" tab visible only to admin users in the Manual Assistant screen.
- **FR-002**: System MUST allow admins to select a manual and generate up to 20 Q&A candidate pairs from its content chunks.
- **FR-003**: System MUST skip chunks that already have close matches (>= 0.85 cosine similarity) in the verified answer cache during candidate generation.
- **FR-004**: System MUST display each generated candidate with editable question and answer fields, source reference, and approve/edit/reject actions.
- **FR-005**: System MUST save approved candidates to the cache with English paraphrase variants (4) and Arabic paraphrase variants (3) for each entry.
- **FR-006**: System MUST show a progress indicator during candidate generation displaying the current count.
- **FR-007**: System MUST surface positively-rated questions (2+ ratings) not yet in the cache as promotion suggestions in the "From Real Usage" section.
- **FR-008**: System MUST exclude questions from real-usage suggestions if they already have close matches (>= 0.80 similarity) in the verified answer cache.
- **FR-009**: System MUST detect stale cache entries by comparing the source manual's last update timestamp against the entry's last verified timestamp.
- **FR-010**: System MUST display a badge count on the "Needs Review" segment when stale entries exist.
- **FR-011**: System MUST allow admins to confirm, edit-and-reconfirm, or delete stale cache entries (including all paraphrase variants).
- **FR-012**: System MUST show confirmation dialogs before destructive actions (removing from cache, bulk approving).
- **FR-013**: System MUST display loading states on all asynchronous actions.
- **FR-014**: System MUST support Arabic RTL layout in all sections.
- **FR-015**: System MUST restrict all training-related operations to admin users only, returning unauthorized errors for non-admin callers.
- **FR-016**: System MUST maintain an in-memory session history in the "From Manuals" section showing summaries of completed save operations.
- **FR-017**: System MUST track which manual a cached answer was derived from to enable staleness detection.

### Key Entities

- **Q&A Candidate**: A generated question-answer pair derived from manual content chunks, awaiting admin review. Contains the question text, answer text, source chunk references, and approval status.
- **Validated QA Entry**: A verified question-answer pair in the cache, including its primary embedding and paraphrase variant embeddings. Tracks when it was last verified and which manual it originated from.
- **Usage Suggestion**: A positively-rated question-answer pair from real technician usage that has not yet been promoted to the cache. Includes rating count and last-asked date.
- **Stale Entry**: A validated QA entry whose source manual has been updated more recently than the entry was last verified, indicating the answer may need review.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An admin can generate and save 20 Q&A pairs from a manual (including all paraphrase variants) in under 10 minutes of active review time.
- **SC-002**: Each saved Q&A pair produces 8 total cache entries (1 primary + 4 English variants + 3 Arabic variants), maximizing cache hit rate across languages.
- **SC-003**: The system correctly identifies and surfaces stale entries within one page load after a manual is re-processed.
- **SC-004**: Real-usage suggestions surface only questions with 2+ positive ratings that are not already in the cache (zero false duplicates at >= 0.80 similarity).
- **SC-005**: Non-admin users cannot see the Train the AI tab or access any training-related operations.
- **SC-006**: After bootstrapping 3-5 manuals (60-100 Q&A pairs), cache hit rate for common technician queries improves measurably compared to manual-only entry.

## Assumptions

- Manuals have already been processed and chunked before training can occur (the system does not process manuals as part of this feature).
- The existing paraphrase variant and verified answer save infrastructure is functional and reliable.
- The AI generation model can produce valid JSON responses for Q&A candidate generation with reasonable reliability (malformed responses are gracefully skipped).
- Positive ratings in the system indicate answer quality suitable for cache promotion (no rating fraud or gaming concerns).
- Admins review and approve candidates with domain knowledge — the system facilitates but does not replace human judgment.
- The existing embedding model and similarity search infrastructure supports the similarity thresholds specified (0.85 for cache dedup, 0.80 for usage suggestion filtering).
- Manual re-upload/reprocessing already updates the manual's timestamp, enabling staleness detection without additional trigger logic.
