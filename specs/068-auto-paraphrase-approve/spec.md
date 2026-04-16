# Feature Specification: Auto-Paraphrase on Admin Approve

**Feature Branch**: `068-auto-paraphrase-approve`
**Created**: 2026-04-16
**Status**: Draft
**Input**: User description: "auto-paraphrase-on-admin-approve — when admin clicks Approve on a pending Ask-the-AI answer, auto-generate 3–5 question paraphrases via the AI provider resolver, let admin review/edit/delete in a modal, and bulk-insert them as separate verified Q&A rows sharing the same approved answer text"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Approve with Auto-Generated Variants (Priority: P1)

An admin is in the Review tab of the Ask-the-AI admin screen and clicks **Approve** on a pending answer. Instead of the entry being saved silently as a single row, a modal opens showing the original question plus 3–5 auto-generated paraphrased variants rendered as editable chips. Each chip has an inline text editor and an **X** to delete. An **Add variant** button lets the admin type a custom phrasing. When the admin clicks **Save all**, every remaining chip (including the original) is persisted as a verified Q&A entry pointing at the same approved answer, so any future technician asking any of those phrasings gets the same instant verified answer.

**Why this priority**: The primary workflow. Every new admin approval goes through here. Without it, the feature delivers no value.

**Independent Test**: Seed one pending answer, click Approve as admin, confirm the modal opens within a few seconds with multiple editable variant chips, edit one, delete one, add one, click Save all, then verify that a technician asking any of the saved phrasings receives an instant verified answer with the verified badge.

**Acceptance Scenarios**:

1. **Given** a pending answer exists in the Review tab, **When** the admin clicks Approve, **Then** a variants modal opens within 3 seconds showing the original question and 3–5 paraphrased variants as editable chips.
2. **Given** the variants modal is open, **When** the admin edits a chip, deletes another chip, and adds a custom variant, **Then** the modal reflects the changes without affecting other chips.
3. **Given** the admin clicks Save all with N chips visible, **When** the save completes, **Then** N verified Q&A entries exist, all pointing at the same approved answer text, and the pending answer is marked resolved.
4. **Given** the saved variants exist, **When** a technician later asks any of those phrasings, **Then** the system returns the verified answer via the existing direct-match fast path and displays the Verified Answer badge.
5. **Given** the admin clicks Cancel on the modal, **When** the modal closes, **Then** no rows are inserted and the pending answer remains in its original pending state.

---

### User Story 2 - Retro-Expand Existing Verified Entries (Priority: P2)

An admin opens the Verified tab and sees the existing bank of already-verified Q&A entries (roughly 16 at time of writing). A new **Generate variants** control (per-row and/or a top-level "Generate variants for all") lets the admin expand an existing verified entry with paraphrases without re-verifying it. The same editable modal appears; on Save all, new verified rows are inserted that share the existing row's approved answer.

**Why this priority**: One-shot catch-up work that unlocks the cache-hit benefit for already-accumulated knowledge. Valuable but not blocking — the P1 flow alone improves future approvals.

**Independent Test**: Pick one existing verified entry, click Generate variants, confirm the modal opens with paraphrases, save, then ask a variant phrasing as a technician and confirm instant verified response.

**Acceptance Scenarios**:

1. **Given** a verified entry is listed in the Verified tab, **When** the admin triggers Generate variants for it, **Then** the same variants modal opens and, on Save all, new verified rows are inserted sharing that entry's approved answer.
2. **Given** an admin triggers a bulk "Generate variants for all" action, **When** the action runs, **Then** the system processes entries one at a time with admin review between each (or with an explicit bulk-confirm option), and per-entry failures do not abort the whole run.

---

### User Story 3 - Graceful Degradation When AI Providers Fail (Priority: P3)

An admin clicks Approve but paraphrase generation fails (all configured AI providers — cloud and local fallback — are unavailable or return errors). The system does not block the approval. The modal still opens, showing only the original question as a chip, with a clear non-blocking notice that automatic variants could not be generated. The admin can still add custom variants manually or simply click Save all to persist the single original entry — matching the existing pre-feature behavior.

**Why this priority**: Resilience. Ensures this feature never degrades the existing verified-answer workflow when external AI services are down.

**Independent Test**: Simulate all AI providers failing, click Approve, confirm the modal opens with only the original question and a visible notice, then Save all and confirm a single verified row is inserted exactly as the pre-feature flow would have produced.

**Acceptance Scenarios**:

1. **Given** all AI providers fail to generate paraphrases, **When** the admin clicks Approve, **Then** the modal opens with only the original question and a visible notice that variants could not be generated.
2. **Given** paraphrase generation fails, **When** the admin clicks Save all with only the original question, **Then** exactly one verified Q&A row is inserted (same result as the pre-feature Approve path).

---

### Edge Cases

- **Duplicate or near-duplicate variants**: Admin is the sole filter; the system does not auto-deduplicate. If the admin leaves two identical chips, both are persisted.
- **Empty or whitespace-only variant chip**: Chips containing only whitespace MUST be skipped on Save all rather than persisted as empty questions.
- **Admin removes every chip including the original**: Save all MUST be disabled when zero valid chips remain.
- **Variant text too long**: Each variant MUST be limited to a reasonable single-sentence length; clearly over-long pasted content is rejected client-side.
- **AI returns fewer than 3 variants**: Whatever subset succeeded is shown; the admin can Add variant to top up.
- **AI returns more than 5 variants**: The modal shows at most 5 generated variants; additional ones are dropped. The admin can still Add variant manually.
- **Non-English pending question**: Out of scope for v1. The modal SHOULD surface only the original and a notice explaining multi-language paraphrasing is not yet supported.
- **Bulk retro-expansion partial failure**: A single entry's paraphrase failure MUST NOT abort the rest of the batch.
- **Network timeout on Save all**: All-or-nothing behavior for a single modal's Save action; partial inserts must not leave the system inconsistent.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When an admin approves a pending answer in the Review tab, the system MUST generate 3–5 paraphrased variants of the original question using the existing AI provider resolver (with its built-in fallback chain) before opening the variants modal.
- **FR-002**: The variants modal MUST display the original question plus each generated variant as an editable chip with inline editing and a delete control.
- **FR-003**: The variants modal MUST provide an Add variant control that appends an empty editable chip for custom phrasings.
- **FR-004**: The variants modal MUST provide a Save all action that persists every remaining non-empty chip as a separate verified Q&A row, all sharing the same approved answer text.
- **FR-005**: The variants modal MUST provide a Cancel action that closes the modal without persisting anything and leaves the pending answer in its prior state.
- **FR-006**: When paraphrase generation fails for any reason, the system MUST still open the modal with only the original question plus a visible notice, and MUST NOT block the admin from saving that single entry.
- **FR-007**: Each persisted variant MUST have its own question text and its own independently computed search embedding so the existing direct-match fast path can match it.
- **FR-008**: All variants saved from a single modal interaction MUST share the same approved answer text and MUST share thumbs-up/down rating tracking (no per-variant rating surfaces are created).
- **FR-009**: The Verified tab MUST offer a way to retro-generate variants for an existing verified entry, reusing the same modal UX.
- **FR-010**: The Verified tab MUST offer a bulk retro-expansion action where a single entry's failure MUST NOT abort the batch.
- **FR-011**: The variants modal MUST open within 3 seconds of the admin's Approve click under normal provider conditions.
- **FR-012**: The paraphrase generation pathway MUST be read-only relative to stored Q&A data — it MUST NOT write, alter, or side-effect any verified Q&A rows until the admin clicks Save all.
- **FR-013**: Save all MUST be atomic at the per-modal level: either every valid chip is persisted or none are.
- **FR-014**: Empty or whitespace-only chips MUST be skipped silently on Save all rather than persisted.
- **FR-015**: The system MUST NOT change existing similarity thresholds or the runtime retrieval pipeline; this feature only adds more static verified-question rows at verify time.
- **FR-016**: The system MUST NOT auto-deduplicate variants; the admin is the filter.
- **FR-017**: The Correct-with-edit admin path (where the admin edits the answer before approving) MUST continue to use the existing single-row path and MUST NOT trigger paraphrase generation in v1.

### Key Entities *(include if feature involves data)*

- **Verified Q&A Entry**: One approved question/answer pair that the system treats as a fast-path cache hit. After this feature, multiple entries can share the same approved answer text; each still carries its own question text and its own search embedding.
- **Variant Draft**: Transient, in-modal representation of a candidate question phrasing. Has editable text and a delete state; never persisted until Save all.
- **Approval Session**: The admin's interaction with a single pending (or retro-expanded) answer, spanning paraphrase request → modal review → Save all or Cancel. One session produces zero rows (cancel / fail-then-empty), one row (fallback path), or N rows (normal path).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The variants modal opens within 3 seconds of the admin's Approve click in at least 95% of approvals under normal provider conditions.
- **SC-002**: At least 70% of auto-generated variants are kept (not deleted) by admins on Save all — signaling generated paraphrases preserve meaning.
- **SC-003**: After rollout, the share of technician questions resolved through the verified-answer fast path (instant, with verified badge) increases by at least 2x compared to the pre-feature baseline on the same question stream.
- **SC-004**: When all AI providers are unavailable, 100% of admin Approve attempts still succeed and persist the original question as a single verified entry (no hard blocks).
- **SC-005**: Admins can retro-expand the existing ~16 verified entries through the Verified tab flow within a single working session without developer involvement.
- **SC-006**: Technician-perceived answer latency on previously-verified topics asked in natural phrasings drops from the current RAG-path range (roughly 20+ seconds) into the verified-answer fast-path range (under a few seconds) for the majority of newly-covered phrasings.

## Assumptions

- The existing AI provider resolver already provides a fallback chain (cloud primary → local fallback) that this feature can reuse without change.
- The existing verified-answer storage can hold multiple rows sharing identical answer text without schema changes.
- The existing rating/thumbs mechanism can be pointed at a shared answer identity so all variants under one answer collectively accumulate feedback without per-variant UI.
- English is the only language targeted in v1; Arabic or mixed-language paraphrase generation is deferred to a future spec.
- Admins are trusted to curate; the system does not enforce semantic similarity checks between variants.
- Retro-expansion in the Verified tab operates on entries one at a time with admin review; a fully-automated "no review" bulk mode is out of scope.
- The runtime retrieval pipeline and its similarity thresholds remain unchanged; cache-hit improvements come entirely from increased coverage of question phrasings at verify time.
- Admin traffic volume is low enough that cloud-provider paraphrase costs are negligible at expected verification rates.
