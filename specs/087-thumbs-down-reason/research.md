# Phase 0 Research — Thumbs-Down Reason & Comment

All `NEEDS CLARIFICATION` markers from the spec were resolved via `/speckit.clarify` on 2026-04-19. This document records the design decisions made during brainstorming and clarification, plus the alternatives that were considered and rejected. No open research items remain.

---

## Decision 1: Store reason and comment on `answer_ratings` (not a new table)

**Decision**: Add two nullable columns directly to the existing `answer_ratings` table: `feedback_reason` (TEXT with CHECK constraint on 5 enum values) and `feedback_comment` (TEXT).

**Rationale**:
- The data is strictly 1:1 with a rating; it has no independent lifecycle.
- Only ~15–25 % of ratings will have reasons (negative ratings only, and even then optional), but nullable columns cost nothing at rest in Postgres.
- The Review-tab list query (`get_flagged_answers`) already does `select("*")` on `answer_ratings`. Adding columns is zero-JOIN work.
- Deletion cascades for free — when a rating is deleted (un-rate or admin bulk-delete), the reason/comment go with it. No orphan data.

**Alternatives considered**:
- **Separate `rating_feedback` table (1:1 with `answer_ratings`)**: Cleaner separation of concerns, but adds a JOIN to every Review-tab read and a second INSERT on every 👎 Save. For two fields that only exist when one rating type is chosen, the ceremony is not justified.
- **JSONB `feedback_meta` column**: Flexible for future fields (e.g., would accommodate "Other" custom reason strings), but loses the CHECK-constraint validation on reason, forces JSON parsing/key probing in every read site, and saves nothing today when we have exactly two fields.

---

## Decision 2: `PATCH` endpoint for the reason save (not a richer `rate-answer`)

**Decision**: Add a new endpoint `PATCH /manuals/ratings/{rating_id}/feedback` that accepts `{ feedback_reason, feedback_comment, user_email }` and updates the row only when `user_email` matches the row's `rater_email`. The existing `POST /manuals/rate-answer` endpoint is left unchanged.

**Rationale**:
- Preserves the two-phase flow: the thumbs-down click persists the rating immediately (FR-001); the optional reason arrives asynchronously via a second network call. Splitting the endpoint keeps the "sentiment never lost" invariant intact — even if the PATCH times out or the user dismisses, the rating is already safe.
- PATCH semantics match: we are updating two optional fields on an existing resource.
- Ownership validation is a single equality check, consistent with the existing `DELETE /manuals/ratings/{rating_id}` handler that already compares caller email to `rater_email`.

**Alternatives considered**:
- **Pass reason/comment on the initial `POST /manuals/rate-answer`**: Would force the client to wait for the bottom-sheet response before firing the rating, which contradicts FR-001's "never lost" guarantee, OR would require a follow-up update call anyway — i.e. we'd land in the same place.
- **Single "bloated" endpoint with action verbs**: More API surface complexity, worse REST hygiene, no benefit.

---

## Decision 3: Bottom-sheet UI (not a center dialog or inline expansion)

**Decision**: Present the reason-capture UI as a Flutter `showModalBottomSheet` slide-up, styled consistently with existing `bottom_sheet_widgets.dart` patterns. The sheet contains five chips in a `Wrap`, a multiline comment field with character counter, and two buttons (`Skip`, `Save`).

**Rationale**:
- The Flutter-web app already uses bottom-sheets heavily for contextual prompts (existing `variants_modal.dart`, `bottom_sheet_widgets.dart`). Users are trained on the pattern.
- Swipe-to-dismiss is native to `showModalBottomSheet` and directly serves FR-004 ("the rater MUST be able to dismiss the prompt"). No extra code to support the "Skip" gesture.
- Screen real estate: on both mobile and desktop widths a bottom-sheet is less disruptive than a centered dialog that blocks the answer the user is rating.

**Alternatives considered**:
- **Center dialog (`AlertDialog`)**: Feels heavier, harder to dismiss without a dedicated button, doesn't match surrounding UI.
- **Inline expansion under the chat message**: Less interruptive, but steals scroll space and the rater may not notice it. Also harder to reset cleanly once Save is pressed.

---

## Decision 4: One-shot dismissal (no "re-open the sheet later" UX)

**Decision**: The bottom sheet opens exactly once per thumbs-down action. If the rater dismisses or skips, there is no affordance (long-press, "Add reason" link, etc.) to bring it back. Recourse is un-rate → re-rate.

**Rationale** (confirmed in clarification Q2):
- Keeps the chat UI free of extra icons/ornamentation on an already-dense answer card.
- Forces the rater to commit in the moment — the feedback is most valuable when the bad answer is still fresh.
- The un-rate + re-rate recovery path already exists in the codebase; no new behavior needed for the edge case.

**Alternatives considered**: long-press on the thumb, inline "Add reason" link, auto-reopen next session — all rejected as unnecessary UI complexity given the low likelihood of regret after explicitly dismissing.

---

## Decision 5: Emit `rated_answer_feedback` activity-log event

**Decision** (confirmed in clarification Q3): On every successful PATCH, call the existing `log_activity(...)` fire-and-forget utility with `category='manual'`, `action='rated_answer_feedback'`, `target_label=<first 80 chars of question>`, `detail=<reason value>`.

**Rationale**:
- Satisfies constitution principle VI (Audit Everything) — admins need to see who wrote which comment when.
- Reuses existing infrastructure (`backend/utils/activity.py`). The existing `rated_answer` event already logs the initial 👎; the new event extends the trail with the reason.
- Non-blocking: activity logging failures MUST NOT fail the PATCH (wrapped in try/except, like existing sites).

**Alternatives considered**:
- **No logging**: row-update audit trail only. Loses visibility into when comments were added (timestamp on the row is the *rating* timestamp, not the feedback-save timestamp).
- **Extend existing `rated_answer` event**: Would require either emitting a second row (leading to noise on existing activity queries) or retroactively mutating a past log row (anti-pattern — log is append-only).
- **Log only when comment is non-empty**: Misses reason-only saves, which are the majority case per spec's UX framing.

---

## Decision 6: Comment hard cap of 2000 characters (server-enforced)

**Decision** (confirmed in clarification Q1): Server rejects requests where `feedback_comment` length > 2000. Client displays a live counter that turns red past ~500 but still permits save up to 2000.

**Rationale**:
- 2000 is 4× the soft advisory, giving headroom for longer diagnostic notes without allowing paste-bomb abuse.
- Rejection at the DB/validator boundary (Pydantic `max_length=2000`) is simpler than trimming; the client can react to a 422 response if a user somehow exceeds the cap.
- Aligns with existing Pydantic validation patterns in `routers/manuals.py`.

**Alternatives considered**: 500 (too restrictive for diagnostic notes), 1000 (reasonable but no meaningful advantage over 2000 given Postgres TEXT cost), 5000 (too generous — invites abuse without delivering user value).

---

## Decision 7: Color palette for reason chips

**Decision**: Inaccurate = red (`Colors.red.shade400`), Incomplete = orange (`Colors.orange.shade400`), Outdated = amber (`Colors.amber.shade600`), Wrong source = purple (`Colors.deepPurple.shade400`), Unclear = blue-grey (`Colors.blueGrey.shade400`), No reason given = grey (`Colors.grey.shade400`).

**Rationale**:
- Each reason gets a distinct hue on the color wheel for quick visual triage in the Review-tab list.
- The chip always carries its text label as the primary signal — color is decoration, so colorblind users are not blocked (satisfies implicit accessibility).
- Muted grey for the "No reason given" case visually de-emphasizes legacy/unfilled rows without hiding them.

**Alternatives considered**: Single accent color with different icons (harder at small sizes), severity-ranked palette (reds/oranges only — loses category distinction).

---

## Summary of Open Questions

None. All requirements in `spec.md` have unambiguous, testable answers.
