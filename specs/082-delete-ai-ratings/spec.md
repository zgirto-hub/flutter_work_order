# Feature Specification: Delete Review/Rating from Ask-the-AI

**Feature Branch**: `082-delete-ai-ratings`
**Created**: 2026-04-18
**Status**: Draft
**Input**: User description: "Delete review/rating from Ask-the-AI — technician undo, admin single-rating delete on Review tab, admin whole-Q&A bulk delete on Train AI tab. Must preserve verified-answer cache when linked ratings are removed."

## Clarifications

### Session 2026-04-18

- Q: Should bulk-delete have a size-based safeguard (cap, typed confirmation) beyond the standard confirmation dialog? → A: No extra safeguard — the existing confirmation dialog (showing count and "cannot be undone") is sufficient.
- Q: When a delete request fails with a real error (not the idempotent 404 path), what does the user see and what happens to the local UI state? → A: Error snackbar is shown and the local UI state is rolled back so it matches the server (the rating/card reappears as before the tap). The user can retry.
- Q: How is the tap-same-thumb-to-undo gesture signaled to technicians so they actually find it? → A: A one-time snackbar hint is shown the first time a technician records a rating, reading (in effect) "Tap the thumb again to remove your rating." It auto-dismisses and is not shown again for that user.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Technician undoes a mistaken rating (Priority: P1)

A technician asked the AI assistant a question, tapped thumbs-up or thumbs-down by mistake (or changed their mind), and wants to clear that rating so it is no longer counted. Today there is no way to undo, so misclicks pollute both the review queue (bad thumbs-down) and the "From Real Usage" suggestions (bad thumbs-up).

**Why this priority**: Misclicks on the chat screen are the single most frequent source of noise in both admin queues (review + Train AI). Giving technicians a self-service undo shrinks the admin triage load and restores user trust in the rating control. It is also the most visible, everyday touch-point.

**Independent Test**: Open the chat tab, ask any question, tap the same thumb twice on the returned answer, and confirm the thumb de-selects and a "Rating removed" confirmation appears. Reopen the chat and verify the rating does not reappear in the admin Review tab (for thumbs-down) or the Train AI "From Real Usage" list (for thumbs-up).

**Acceptance Scenarios**:

1. **Given** a technician has just rated an AI answer with thumbs-down, **When** they tap the same thumbs-down button again, **Then** the thumb de-selects, a "Rating removed" confirmation appears, and the answer no longer shows up in the admin Review tab on refresh.
2. **Given** a technician has just rated an AI answer with thumbs-up, **When** they tap the same thumbs-up button again, **Then** the thumb de-selects and, if this was the only positive rating for that Q&A, the corresponding "From Real Usage" suggestion no longer appears on reload.
3. **Given** a technician rated an answer thumbs-down, **When** they tap the opposite thumbs-up, **Then** existing behavior is preserved — a new positive rating is recorded and the earlier negative rating remains (the technician may undo the earlier one separately if they wish).
4. **Given** a technician is viewing an answer they did not rate, **When** they look at the rating controls, **Then** no undo action is shown (nothing to undo).

---

### User Story 2 - Admin dismisses a bogus flagged answer (Priority: P2)

A negative rating appears in the admin Review tab because a technician flagged an AI answer, but the admin judges the rating itself to be invalid (e.g. user misunderstood the answer, misclicked, test data). Today the only options are "Approve" (keep as correct answer) or "Correct" (write a better answer), neither of which fits. The admin needs a way to dismiss the flag so the answer leaves the queue without any corrective action being taken.

**Why this priority**: Bogus negative ratings clog the review queue and force admins to choose between two wrong actions (approve a bad answer, or invent a "correction" for a non-problem). This removes a clear friction point for admins and is the first workflow improvement with no current workaround.

**Independent Test**: As an admin, open the Review tab, locate a flagged answer, tap the "Delete" action on its card, confirm the dialog, and verify the card disappears from the list and the "Needs Review" badge count decrements by one. Reload the tab and confirm the answer does not return.

**Acceptance Scenarios**:

1. **Given** the admin is viewing the Review tab with at least one flagged answer, **When** they tap "Delete" on a card and confirm the dialog, **Then** the card is removed from the list and the "Needs Review" badge decreases by one.
2. **Given** the flagged answer was previously promoted into the verified-answer cache by another admin, **When** the admin deletes its negative rating, **Then** the verified entry remains searchable and continues to serve as the verified answer for equivalent questions.
3. **Given** the admin opens the delete confirmation dialog, **When** they cancel instead of confirming, **Then** the rating is preserved and the card stays in the queue.
4. **Given** the admin has already deleted a rating and another admin still has the stale row on screen, **When** the second admin also triggers delete, **Then** the action still reports success (no error) and the card is removed from their view on refresh.

---

### User Story 3 - Admin permanently removes a From-Real-Usage suggestion (Priority: P3)

The Train AI tab's "From Real Usage" list groups positive ratings from technicians into Q&A suggestions an admin can promote to the verified cache. If a Q&A is unsuitable (off-topic, sensitive, duplicate), admins need a way to clear it permanently. Today the "Dismiss" button only hides the suggestion locally, and it reappears on reload.

**Why this priority**: Lower frequency than P1/P2 and admins have a partial workaround (ignore it), but it is a persistent irritant because dismissals do not stick. Fixing it cleans up the long-term signal quality of the Train AI workflow.

**Independent Test**: As an admin, open the Train AI tab, pick a "From Real Usage" suggestion, open its overflow menu, tap "Delete permanently", confirm the dialog, and verify the suggestion disappears. Reload the tab and confirm it does not reappear.

**Acceptance Scenarios**:

1. **Given** the admin is viewing a "From Real Usage" suggestion card, **When** they open the overflow menu and tap "Delete permanently" and confirm, **Then** the card disappears from the list and does not return on reload.
2. **Given** the suggestion groups N positive ratings, **When** the admin opens the confirmation dialog, **Then** the dialog shows the count N and states the action cannot be undone.
3. **Given** one of the bundled ratings had been promoted to the verified-answer cache, **When** the admin deletes the suggestion, **Then** the verified cache entry remains available and keeps serving equivalent questions.
4. **Given** the admin wants to hide the suggestion temporarily without deleting, **When** they tap the regular "Dismiss" button, **Then** existing non-persistent dismissal behavior is preserved (suggestion reappears on reload).

---

### Edge Cases

- **Technician tries to delete someone else's rating**: The action is refused; only the original rater or an admin may remove a rating.
- **Concurrent deletion of the same rating**: Two users (e.g. two admin tabs, or rater + admin) tap delete on the same rating at the same time — the second caller is treated as a success (the rating is already gone, the outcome matches intent).
- **Bulk delete that matches zero ratings**: Safe no-op — the action succeeds, reports zero removed, and the suggestion disappears from the list (which was the user's goal anyway).
- **Rating linked to a verified cache entry**: The verified entry is preserved. Only the link between the deleted rating and the verified entry is severed. Equivalent-question lookup continues to return the verified answer.
- **Re-flagged answer**: If an answer has multiple negative ratings (flagged-again pattern) and the admin deletes only one, the answer may remain in the queue or have its re-flagged status recomputed on next load. This is expected — the delete scope is one rating, not the full flag history.
- **Right-to-left content**: Confirmation dialogs render correctly for Arabic question and answer text, matching the existing RTL pattern used elsewhere in the Review and Train AI tabs.
- **Nothing to undo**: A technician viewing an answer they never rated sees no undo affordance.
- **Rater identity changes**: If a technician logs in as a different user, they cannot undo ratings created under the previous identity (those belong to a different rater).
- **Non-idempotent delete failure**: On network error, 5xx, or permission denied, the UI shows an error snackbar and rolls back to the pre-tap state (rating/card reappears). No silent success, no divergent optimistic state.

## Requirements *(mandatory)*

### Functional Requirements

**Rating removal — common behavior**

- **FR-001**: The system MUST allow an AI answer rating to be removed so that it no longer contributes to the review queue, the "From Real Usage" suggestion list, or any aggregate rating counts.
- **FR-002**: Rating removal MUST be permanent. There is no soft-delete, no undo-of-undo, and no retention of deleted rating records.
- **FR-003**: When a rating that is linked to an entry in the verified-answer cache is removed, the verified-answer entry MUST be preserved and remain searchable. Only the link from the verified entry back to the removed rating is cleared.
- **FR-004**: Removing a rating MUST NOT alter the behavior of verified-answer lookup for equivalent questions.

**Technician undo (chat)**

- **FR-005**: A technician MUST be able to remove their own previously recorded rating on an AI answer from within the chat.
- **FR-006**: The undo gesture MUST be tapping the currently-selected thumb a second time on the same answer.
- **FR-007**: After undo, the rating control MUST visually return to an unrated state, and a confirmation message ("Rating removed.") MUST appear.
- **FR-008**: Tapping the opposite thumb (switching the vote) MUST preserve existing behavior: a new rating is recorded; the prior rating is not auto-removed. The technician may undo the prior rating separately if desired.
- **FR-009**: A technician MUST NOT be able to remove a rating that was recorded by a different user.
- **FR-009a**: The first time a technician records a rating in the chat (per user), the system MUST show a one-time snackbar hint that the gesture to remove a rating is to tap the same thumb again. The hint MUST auto-dismiss and MUST NOT be shown again for that user on subsequent ratings. The hint text MUST render correctly in right-to-left mode.

**Admin single-rating delete (Review tab)**

- **FR-010**: An admin MUST be able to delete any single rating that appears in the Review tab directly from the flagged-answer card, via a "Delete" action alongside the existing "Approve" and "Correct" actions.
- **FR-011**: The "Delete" action MUST be visually distinct as a destructive action (e.g. red) and MUST require confirmation before proceeding.
- **FR-012**: The confirmation dialog MUST state that the answer will leave the review queue and that the verified-answer cache, if any, is unaffected.
- **FR-013**: After successful deletion, the card MUST be removed from the list and the "Needs Review" badge count MUST decrement by one without requiring a manual refresh.

**Admin whole-Q&A bulk delete (Train AI → From Real Usage)**

- **FR-014**: An admin MUST be able to permanently delete a "From Real Usage" suggestion card so that it does not reappear on reload.
- **FR-015**: The permanent-delete action MUST be placed in an overflow menu on the suggestion card, not as the default button, to reduce the chance of an accidental destructive tap.
- **FR-016**: The existing "Dismiss" button MUST remain and MUST retain its current local-hide ("not now") behavior so admins still have a non-destructive hide option.
- **FR-017**: Permanent delete MUST remove every rating that groups into the suggestion (identified by the same question-and-answer pairing the list uses).
- **FR-018**: The confirmation dialog MUST show the count of ratings that will be removed, MUST state that the suggestion will stop appearing, and MUST state the action cannot be undone.
- **FR-019**: Bulk delete that matches zero ratings MUST report success (no error) and MUST still remove the suggestion from the visible list.
- **FR-019a**: Bulk delete MUST NOT impose a size cap, typed-count re-entry, or any safeguard beyond the standard confirmation dialog. The dialog's count + "cannot be undone" wording is the sole pre-delete guard.

**Authorization**

- **FR-020**: A technician MAY remove only ratings they themselves recorded.
- **FR-021**: An admin MAY remove any single rating and MAY bulk-delete any suggestion group.
- **FR-022**: Non-admin users MUST NOT have access to either admin surface (Review tab delete, Train AI permanent-delete).
- **FR-023**: Unauthorized delete attempts MUST be rejected with a clear indication that the caller lacks permission.

**Idempotency and concurrency**

- **FR-024**: Attempting to delete a rating that has already been removed MUST be treated as success (the intended outcome is met).
- **FR-025**: Concurrent delete attempts on the same rating MUST NOT produce a visible error to either caller.
- **FR-025a**: On a non-idempotent delete failure (network error, server error, or permission denied — i.e. anything that is not the "already gone" success path), the UI MUST (a) show an error snackbar describing the failure and (b) roll back any optimistic local state so the rating/card reappears exactly as it was before the tap. The user MAY then retry.

**Accessibility and localization**

- **FR-026**: All confirmation dialogs and snackbars MUST render correctly in right-to-left mode for Arabic question and answer content, matching the existing RTL behavior of the Review and Train AI tabs.

**Audit**

- **FR-027**: Every rating removal MUST be recorded in the system activity log with enough detail to distinguish (a) a rater removing their own rating, (b) an admin deleting a single rating belonging to someone else, and (c) an admin performing a bulk delete on a Q&A group.
- **FR-028**: The activity log entry for a bulk delete MUST include the question text and the number of ratings removed.

### Key Entities *(include if feature involves data)*

- **AI Answer Rating**: One technician's thumbs-up or thumbs-down on one AI-generated answer, attributed to a rater identity. It is the unit that gets removed in all three flows.
- **Verified-Answer Cache Entry**: An admin-approved question/answer pair promoted for reuse as an authoritative response to equivalent future questions. May carry an optional reference to the rating that originally surfaced it. Survives removal of that rating.
- **Review-Queue Entry**: A thumbs-down rating presented to admins for disposition (approve / correct / delete). One rating maps to one queue entry.
- **Real-Usage Suggestion**: An aggregation of thumbs-up ratings on the same question-and-answer pairing, shown in the Train AI tab. Disappears when all underlying ratings are removed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Technicians who misclick a rating can clear it in under 5 seconds without leaving the chat screen.
- **SC-002**: 100% of delete actions taken by a rater on their own rating or by an admin on any rating succeed on the first attempt (excluding permission-denied and network failures).
- **SC-003**: After rating removal, the affected answer disappears from the admin Review tab on next refresh in 100% of cases.
- **SC-004**: After permanent-delete of a "From Real Usage" suggestion, that suggestion does not reappear on any subsequent reload.
- **SC-005**: Verified-answer cache entries remain retrievable after their originating rating is deleted in 100% of cases (no regression in verified-answer search hits attributable to this feature).
- **SC-006**: Admin review-queue triage time per item decreases measurably once the Delete action is available — targeted 30% reduction in median admin dwell-time per flagged answer within the first month of rollout.
- **SC-007**: Misclick-driven entries in the Review tab and From-Real-Usage list drop by at least 50% within the first month, as measured by the ratio of ratings removed by the original rater to total ratings recorded.
- **SC-008**: Zero verified-answer cache entries are accidentally removed as a side effect of rating deletion during the first three months post-launch.

## Assumptions

- User identity for determining "own rating" is the same email-based identity used by the existing rating-submission flow; no new authentication mechanism is introduced.
- Admin privilege is determined by the existing admin role flag on the user record; no new permission grants or role configuration are added for this feature.
- Deletes are final and intentional; no grace period, no trash, no per-user delete quota, and no rate limiting are required for v1.
- Switching thumb direction (up ↔ down) continues to create a new rating alongside the old one, rather than atomically replacing it. Users who care about the prior rating can undo it first. This matches today's behavior and is intentional.
- No dedicated admin screen listing all ratings is needed; the three surfaces above (chat undo, Review tab delete, Train AI permanent delete) fully cover the known workflows.
- "Exact match" question/answer pairing used by the existing "From Real Usage" grouping is a sufficient key for bulk delete; no fuzzy grouping or semantic clustering is required.
- Cascading removal in the opposite direction (deleting a verified-cache entry) is out of scope for this feature and already handled elsewhere.
- Soft-delete, audit-recoverable delete, and an "undo of the undo" are explicitly out of scope.

## Out of Scope

- Cascading deletion of verified-answer cache entries when their originating rating is removed.
- Atomic "switch thumb" replace flow in the chat (tapping the opposite thumb continues to add a new rating without touching the old one).
- A dedicated admin-only screen for browsing or bulk-managing all ratings.
- Per-user rating quotas or rate limits.
- Soft delete, trash/recycle bin, restore, or any undo-of-undo affordance.
- Changes to the embedding-based verified-answer lookup (lookup is unaffected by this feature).
