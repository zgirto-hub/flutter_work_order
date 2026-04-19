# Feature Specification: Thumbs-Down Reason & Comment

**Feature Branch**: `087-thumbs-down-reason`
**Created**: 2026-04-19
**Status**: Draft
**Input**: User description: "Capture optional reason and free-text comment when a technician clicks thumbs-down on an AI assistant answer."

## Clarifications

### Session 2026-04-19

- Q: Server-side hard cap on comment length? → A: 2000 characters.
- Q: Can a rater re-open the feedback prompt after dismissing? → A: One-shot — dismissing the sheet ends the opportunity for this rating; to add a reason later the rater must un-rate and re-rate.
- Q: Activity log entry for feedback save? → A: Emit a new `rated_answer_feedback` event on successful save, with the reason in the detail field.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Technician picks a reason and leaves a comment after a bad answer (Priority: P1)

A technician asks the AI assistant a question and gets a wrong or unhelpful answer. They tap the thumbs-down icon. The rating is recorded immediately. A bottom sheet slides up asking "What went wrong?" with five reason chips and a short comment field. The technician picks "Outdated", types "This answer is from the 2022 revision — panel was re-commissioned in 2024", and taps Save. The review team later opens the Review tab and sees the technician's feedback attached to the flagged answer.

**Why this priority**: This is the core value of the feature. Without it, the Review tab continues to show "bad answers" with no diagnostic context, and admin throughput is the stated bottleneck.

**Independent Test**: A single technician rates an AI answer with thumbs-down, selects a reason, adds a comment, saves. An admin opens the Review tab and sees the reason chip and comment preview on the same rating row. Feature delivers value standalone.

**Acceptance Scenarios**:

1. **Given** an AI answer is displayed in the chat, **When** the technician taps thumbs-down, **Then** the rating is saved within 2 seconds and a "What went wrong?" bottom sheet appears.
2. **Given** the bottom sheet is open, **When** the technician selects a reason chip and taps Save, **Then** the reason and (if any) comment are attached to the rating and the sheet closes.
3. **Given** the bottom sheet is open, **When** the technician types a comment longer than ~500 characters, **Then** the counter turns red and Save is still enabled (soft limit; the app trims or warns but does not block).
4. **Given** an admin opens the Review tab, **When** a rating has a reason and comment, **Then** the colored reason chip and comment preview are visible on the card without expanding it.

---

### User Story 2 - Technician dismisses the reason prompt (Priority: P1)

A technician taps thumbs-down while moving on to something else. They swipe the bottom sheet away or tap Skip. The negative rating still lands in the system — only the reason is left blank.

**Why this priority**: Same P1 — this is critical because dropping the rating itself would be a regression. The sentiment signal (👎) must never be lost even when the user doesn't want to explain.

**Independent Test**: Tap thumbs-down, dismiss the sheet without picking a reason. Verify the rating row exists in the backend with NULL reason and NULL comment, and still appears in the Review tab (with a "No reason given" indicator).

**Acceptance Scenarios**:

1. **Given** the bottom sheet appears after thumbs-down, **When** the technician swipes it down without interacting, **Then** the rating remains saved with NULL reason/comment.
2. **Given** the bottom sheet appears, **When** the technician taps Skip, **Then** the sheet closes and the rating remains saved with NULL reason/comment.
3. **Given** an admin opens the Review tab, **When** a rating has NULL reason, **Then** the card shows a muted "No reason given" chip in place of the colored reason chip.

---

### User Story 3 - Technician changes their mind and un-rates (Priority: P2)

A technician who previously gave thumbs-down (with or without a reason) taps the thumbs-down icon a second time to remove their rating. The rating row — including any stored reason/comment — is deleted. The Review tab no longer shows this entry.

**Why this priority**: P2 because it's an existing behavior that must not regress, but no new user-facing surface is introduced. The feature must avoid breaking the un-rate flow.

**Independent Test**: Give a thumbs-down, add a reason/comment, save. Re-tap thumbs-down to un-rate. Confirm the rating row and its reason/comment are gone from the database and from the Review tab.

**Acceptance Scenarios**:

1. **Given** the technician already gave a thumbs-down with reason and comment, **When** they tap thumbs-down again, **Then** the rating row is deleted and no stale reason/comment remains.
2. **Given** the technician un-rated an entry, **When** they open the AI chat again, **Then** the thumb icon on that message shows the un-rated state.

---

### User Story 4 - Admin triages flagged answers by reason (Priority: P2)

An admin opens the Review tab and sees multiple flagged answers. Each card shows a colored reason chip so the admin can decide which to tackle first — e.g. prioritize "Inaccurate" items, or batch-handle all "Outdated" items in one pass.

**Why this priority**: P2 — the spec's value multiplier for admins. The underlying data is captured by P1; this story ensures it's visible at list level, not hidden behind a click.

**Independent Test**: Seed three ratings with three different reasons. Open the Review tab. Verify each card shows the correct colored chip inline, and the first ~100 chars of any comment appear in muted italic preview without expanding the card.

**Acceptance Scenarios**:

1. **Given** the Review tab shows a list of flagged ratings, **When** an admin scrolls, **Then** each card displays a reason chip whose color matches its reason category.
2. **Given** a rating has a comment, **When** the card is in collapsed state, **Then** a preview of the first ~100 chars is visible as muted italic text; full comment shows when the card is expanded.

---

### Edge Cases

- **Rating saves but the reason PATCH fails**: If the network drops between the initial thumbs-down (row saved) and the Save button (PATCH with reason/comment), the rating remains saved with NULL reason. The user sees an error toast; for this release a failed Save leaves the rating as a no-reason 👎 (no automatic retry).
- **Double-tap Save within the same sheet session**: The PATCH is idempotent — last write wins. Duplicate requests on the same rating produce no corruption.
- **User dismisses then regrets it**: There is no re-open affordance. The user's recourse is to tap thumbs-down a second time (un-rate), tap it a third time (re-rate), and pick a reason in the fresh sheet. A new rating row is created in the process.
- **Someone else tries to edit a rating's reason**: The PATCH endpoint validates that the caller's email matches the row's `rater_email`. Mismatch → rejected and no change.
- **Thumbs-up is clicked**: No bottom sheet appears. No reason or comment is stored even if sent accidentally.
- **Re-flagged verified answer** (from the automatic reflag threshold on `validated_qa`): These entries surface in the Review tab but were not generated by a single user's 👎 with a reason. They show the muted "No reason given" chip; no user-supplied reason is associated.
- **Legacy rows from before this feature**: All existing `answer_ratings` rows have NULL reason/comment. They render the "No reason given" chip and continue to work unchanged in the Review tab.
- **Comment exceeds soft limit**: The counter color changes to indicate over-limit, but the user can still save between ~500 and 2000 characters. Submissions over 2000 characters are rejected server-side with an error.
- **Rating is deleted by an admin via the existing bulk-delete flow**: The reason and comment are deleted with the row. No orphan data.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST immediately persist a thumbs-down rating without blocking on any reason input, so that the negative sentiment signal is never lost.
- **FR-002**: The system MUST present an optional prompt ("What went wrong?") to the rater immediately after a thumbs-down is saved, offering five reason options: Inaccurate, Incomplete, Outdated, Wrong source, Unclear.
- **FR-003**: The rater MUST be able to attach an optional free-text comment to accompany the reason.
- **FR-004**: The rater MUST be able to dismiss the prompt (skip or swipe away) without it affecting the stored rating. Once dismissed, the prompt MUST NOT re-appear for the same rating; to add a reason afterwards the rater must un-rate and re-rate.
- **FR-005**: The system MUST record the selected reason and comment against the existing rating row only when the rater explicitly saves them, and the Save action MUST require a reason to be selected.
- **FR-006**: The system MUST allow only the original rater to add or change the reason and comment on their own rating; any other user's attempt to change that rating's feedback MUST be rejected.
- **FR-007**: When a rater un-rates (removes their thumbs-down), the system MUST delete the rating along with any associated reason and comment; no separate cleanup step is required.
- **FR-008**: The system MUST display each rating's reason as a color-coded visual chip on the Review tab without the admin needing to expand the card.
- **FR-009**: The system MUST display a preview of the first ~100 characters of the comment (when present) on the Review-tab card, with the full comment visible on expansion.
- **FR-010**: The system MUST display ratings with no reason (legacy rows or skipped prompts) with a muted "No reason given" chip, preserving visual consistency.
- **FR-011**: The reason and comment MUST be informational only — they MUST NOT influence the existing Review tab approve/correct workflow, the automatic reflagging threshold, or any downstream pipeline that consumes rating data.
- **FR-012**: Thumbs-up ratings MUST NOT trigger the reason prompt, and any reason or comment values sent on a positive rating MUST be discarded silently.
- **FR-013**: The system MUST validate that stored reasons match one of the five allowed categories; unknown reason values MUST be rejected.
- **FR-014**: The system MUST enforce a server-side maximum comment length of 2000 characters as a hard cap (requests exceeding this are rejected), while the client presents the ~500 character limit as a soft advisory with a live counter.
- **FR-015**: On each successful feedback save, the system MUST emit a `rated_answer_feedback` activity-log event recording the rater's email, the rating ID, and the chosen reason in the detail field. A save that only clears reason/comment (edge case) MUST still emit the event so the audit trail captures the change.

### Key Entities *(include if feature involves data)*

- **Rating feedback**: Two optional attributes attached to an existing negative rating — a categorical reason (one of five values) and a free-text comment. These live on the rating itself; they have no independent lifecycle and are deleted when the underlying rating is removed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In every tested scenario, a thumbs-down click produces a persisted rating within 2 seconds, regardless of whether the user selects a reason or dismisses the prompt.
- **SC-002**: When a reason is saved, it appears on the Review tab card within the next refresh (admin sees the chip without expanding the card).
- **SC-003**: Admins can identify the category of each flagged answer at a glance (without opening the card) for at least 80% of flagged entries after one week of active use.
- **SC-004**: Attempts by any user other than the original rater to modify a rating's feedback are rejected 100% of the time.
- **SC-005**: Legacy flagged ratings (created before this feature) continue to display in the Review tab with no visual or functional regressions.
- **SC-006**: The existing approve/correct workflow for flagged answers completes with the same number of clicks and the same success rate as before the feature ships.

## Assumptions

- The rater is authenticated; the current email context is available at the moment the rating is made, consistent with the existing rating flow.
- Arabic localization is out of scope per the standing preference that AI-assistant-surface features don't require Arabic.
- The existing `answer_ratings` table is the correct location for the new fields; no new table is introduced because the data is 1:1 with a rating and only populated for negative ratings.
- The five reason categories are stable for the initial release. Adding or renaming reasons later will require a data-layer migration.
- The admin surface remains the existing Review tab inside the AI assistant's Train AI screen; no new admin surface is introduced.
- Existing behaviors unchanged by this spec: the automatic reflagging threshold on verified answers, the Verified Answers popularity display, the "From Real Usage" suggestion pipeline, and the stale-cache detection in "Needs Review".
- The authorization check for editing feedback is consistent with the existing authorization model for rating deletion (rater-owns-the-row).

## Out of Scope

- Thumbs-up reasons or any post-rating prompt for positive ratings.
- Admin editing of user-provided reasons or comments in the Review tab.
- Aggregation, clustering, or analytics over reasons (e.g. "top reason this week"). A future spec may build on this data.
- Retroactive backfill of reasons onto historical ratings.
- Arabic (or any non-English) localization of the prompt and chip labels.
- Changes to the automatic reflagging threshold or to how flagged answers influence the verified-answer pipeline.
