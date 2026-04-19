# Feature Specification: Verified Answer Variants

**Feature Branch**: `085-verified-answer-variants`
**Created**: 2026-04-18
**Status**: Draft
**Input**: User description: "Verified Answer Variants: Add a 'Generate variants' button to the existing Edit dialog in the Verified Answers tab (admin UI in Ask the AI). Clicking it opens the existing variants modal pre-filled with (a) all sibling verified-answer rows sharing the clicked entry's shared-rating group (marked visually as 'saved'), and (b) ~4 fresh AI paraphrases (marked visually as 'new'). On Save all, the submitted list fully replaces the stored variant set for that group (full-replace semantics). All variants continue to share the same answer and shared-rating group; new/changed variants get fresh embeddings. Legacy entries with no shared-rating group get one assigned on first save. If paraphrase generation fails, open the modal with existing siblings only plus a notice banner."

## Clarifications

### Session 2026-04-18

- Q: When the embedding service fails or times out during Save all, how should the system behave? → A: Fail the whole save atomically — no stored rows change, the admin sees an error message and can retry.
- Q: How should the backend reconcile submitted variants against stored rows (match for update vs insert vs delete)? → A: Text-based matching — whitespace-trimmed, case-insensitive. Editing a variant's text counts as delete-old + insert-new (per-variant thumbs counts reset).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Broaden semantic reach of a verified answer with AI paraphrases (Priority: P1)

An admin reviewing a verified answer in the "Verified" tab wants the AI to match a wider range of phrasings to this same answer without rewriting it. From the row's Edit dialog, the admin clicks "Generate variants." A modal appears showing every question phrasing already on file for this verified answer (marked "saved") plus about four fresh AI-paraphrased phrasings (marked "new"). The admin accepts the useful paraphrases, edits wording as needed, and presses Save all. Future user questions matching any of those phrasings now return the same verified answer.

**Why this priority**: This is the core value of the feature — letting admins cheaply grow the matching coverage of a single curated answer. Without this, broadening coverage means manually re-entering the same answer under different questions.

**Independent Test**: Admin opens a verified entry, clicks Generate variants, approves one AI paraphrase, saves. A user asking a question semantically similar to that paraphrase receives the same verified answer. Fully testable in isolation.

**Acceptance Scenarios**:

1. **Given** an existing verified answer with two saved question variants, **When** the admin clicks "Generate variants," **Then** the modal opens showing the two saved variants marked as saved plus approximately four new AI-paraphrased candidates marked as new, with the original answer not modified.
2. **Given** the modal is open with saved and new variants, **When** the admin presses Save all with the existing two saved variants plus two of the four new candidates, **Then** the stored variant set contains exactly those four question phrasings, all linked to the same verified answer and the same shared-rating group.
3. **Given** the stored variant set now contains four phrasings, **When** a user asks a question that matches one of the newly saved phrasings via the verified-answer fast path, **Then** the user receives the existing verified answer without any new editing by the admin.

---

### User Story 2 - Remove a stale or incorrect variant (Priority: P2)

An admin notices one of the stored question variants for a verified answer is misleading or no longer accurate. The admin opens the variants modal, removes that chip, and presses Save all. The removed phrasing is dropped from the stored set, and the remaining variants continue to map to the verified answer.

**Why this priority**: Variant curation (removal) is required to keep the verified-answer corpus clean; without it, the feature can only grow and never prune. Still secondary to P1 because creation is the primary admin workflow.

**Independent Test**: Admin opens a verified entry with three stored variants, removes one, saves. Asking a question matching the removed phrasing no longer short-circuits to the verified answer; asking one that matches the remaining two still does.

**Acceptance Scenarios**:

1. **Given** a verified answer with three saved variants, **When** the admin removes one saved chip and presses Save all, **Then** the stored variant set contains exactly the two remaining phrasings.
2. **Given** the admin removed every variant in the modal, **When** the admin attempts to Save all, **Then** the Save button is disabled (a verified answer must retain at least one question variant).

---

### User Story 3 - Generate variants when AI paraphrasing is unavailable (Priority: P3)

The AI paraphrasing service is temporarily unavailable (model server down, rate-limited, or errored). The admin should still be able to manage the variant set manually without the feature being blocked.

**Why this priority**: Graceful degradation. Lower priority because it's an error-path story, not a daily workflow.

**Independent Test**: Simulate paraphrase generation failure. Admin clicks Generate variants; modal opens with saved siblings plus a clear notice that AI paraphrases are unavailable. Admin can still add, edit, remove, and save variants manually.

**Acceptance Scenarios**:

1. **Given** the AI paraphrase service returns an error or times out, **When** the admin clicks "Generate variants," **Then** the modal opens showing saved variants only, with a visible notice banner explaining that AI paraphrases are unavailable and that the admin can still curate variants manually.
2. **Given** the notice banner is showing, **When** the admin adds a manual variant chip and presses Save all, **Then** the manual variant is saved alongside the existing siblings with no loss of any saved variant.

---

### Edge Cases

- **Legacy entries with no shared-rating group**: Some verified answers were created before shared-rating grouping existed and have no group id. On first Save all from this flow, the system assigns a fresh shared-rating group to the entry so that newly added variants can link to it.
- **Duplicate phrasings in submitted list**: If two chips have identical (whitespace-trimmed, case-insensitive) text, the system stores only one; it does not create duplicate variant rows.
- **Variant text unchanged but edit-dialog answer edited separately**: The variants modal concerns itself only with question phrasings; edits to the answer body remain the responsibility of the existing Edit dialog. Saving variants must not overwrite an unrelated answer edit.
- **Length ceiling**: Any variant longer than 500 characters is rejected by the Save action; the admin must shorten or delete it before saving.
- **Modal closed without saving**: Cancel or close discards all changes; the stored variant set is unchanged.
- **Entry already has many siblings (e.g., 10+)**: The modal still loads and renders them; the admin can scroll.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Edit dialog for a verified answer MUST expose a "Generate variants" action that opens the variants modal for that entry.
- **FR-002**: When the variants modal opens, it MUST display all question variants currently stored for the selected verified answer (siblings sharing its shared-rating group), each marked as "saved."
- **FR-003**: When the variants modal opens, it MUST additionally display AI-generated paraphrase candidates for the selected question, each marked as "new," visually distinguishable from saved variants.
- **FR-004**: If AI paraphrase generation fails or times out, the modal MUST still open with saved variants only and MUST show a visible notice that AI paraphrases are unavailable.
- **FR-005**: Admins MUST be able to add, edit, and remove variant chips in the modal before saving.
- **FR-006**: On Save all, the system MUST apply full-replace semantics against the stored variant set for that verified answer's shared-rating group. Reconciliation is by textual identity, using whitespace-trimmed, case-insensitive comparison: submitted texts matching a stored row are kept; submitted texts with no match are inserted; stored rows with no matching submitted text are deleted. Editing a saved variant's text therefore manifests as delete-old + insert-new, and any per-variant metrics (such as thumbs-up/down counts on that specific phrasing) will not carry across an edit.
- **FR-007**: All variants for a single verified answer MUST continue to share the same answer body and the same shared-rating group after a save.
- **FR-008**: Inserted or edited variants MUST receive fresh semantic-search embeddings so they participate in future verified-answer matching.
- **FR-008a**: If the embedding service fails, times out, or errors for any variant during Save all, the system MUST abort the entire save operation atomically — no inserts, updates, or deletes are persisted — and surface an actionable error to the admin so the save can be retried.
- **FR-009**: If the selected verified answer has no shared-rating group (legacy data), the system MUST assign one on the first save from this flow so future variants can link to it.
- **FR-010**: The modal MUST prevent saving if the resulting variant set would be empty (at least one question phrasing must remain).
- **FR-011**: The modal MUST reject individual variants longer than 500 characters.
- **FR-012**: The system MUST deduplicate variants that are textually identical after whitespace-trimming and case-folding, so that no two stored variants for the same verified answer carry the same phrasing.
- **FR-013**: The existing Edit dialog (question + answer fields) MUST remain functionally unchanged; the variants flow is additive only.
- **FR-014**: Cancel, close, or dismissal of the variants modal MUST not alter the stored variant set.
- **FR-015**: Every save of variants MUST be recorded in the existing audit log, identifying the admin, the verified answer, and the net change (variants added, updated, removed).

### Key Entities *(include if feature involves data)*

- **Verified Answer**: A curated question-plus-answer record used by the assistant's verified-answer fast path. Identified by a shared-rating group so that multiple question phrasings can map to the same answer.
- **Variant**: A single stored question phrasing belonging to a verified answer's shared-rating group. Carries its own embedding but the same answer body as its siblings.
- **Shared-Rating Group**: A grouping identifier that links sibling variants together. Created automatically for new verified answers; assigned on first variants-save for legacy entries that lack one.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An admin can broaden a verified answer with two additional phrasings in under 60 seconds from clicking the row to the modal closing on Save all.
- **SC-002**: When the AI paraphrase service is healthy, the variants modal opens within 5 seconds of clicking "Generate variants" and presents at least three paraphrase candidates in at least 90% of attempts.
- **SC-003**: After saving a set of N variants, a user question matching any of those N phrasings returns the expected verified answer in the assistant chat with no admin intervention.
- **SC-004**: The Edit dialog's existing question and answer editing flow retains 100% of its prior behavior (no regressions in answer editing, deletion, or rating counts).
- **SC-005**: When paraphrase generation fails, admins can still complete variant management manually; no flow is blocked by the failure.
- **SC-006**: After a full-replace save, the stored variant set for the target verified answer exactly matches the non-empty list submitted from the modal — no extra, no missing.

## Assumptions

- The existing variants modal UI ("Save verified answer" with editable chips, add/remove, save-all) is reused unchanged except for the saved-vs-new visual marker.
- The existing AI paraphrase service already accepts a question and returns approximately four paraphrases; its contract is unchanged.
- The existing verified-answer storage already supports multiple rows sharing one shared-rating group and one answer body (spec 068). This feature only adds a reconcile-on-save operation on top.
- Admin authorization is handled by the existing admin-only gating on the Verified Answers tab; no new permission model is introduced.
- Embedding generation for new/edited variants uses the existing embedding service; no new model is introduced.
- Audit logging reuses the existing activity-log pipeline.
- Desktop and PWA web are the primary target surfaces; mobile-specific layout tuning is not in scope.
- Arabic-language variants are out of scope for UI language-handling concerns (per project convention for AI-assistant features).
