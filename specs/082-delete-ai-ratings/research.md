# Phase 0 Research — Delete Review/Rating from Ask-the-AI

Purpose: resolve every `NEEDS CLARIFICATION` raised during Technical Context and document the key decisions that shape Phase 1 design. All findings here should be reflected in `data-model.md`, `contracts/`, and `quickstart.md`.

## Decisions

### D1. Orphan-then-delete ordering

**Decision**: The two new backend endpoints MUST perform `UPDATE validated_qa SET rating_id = NULL WHERE rating_id = $deleted` *before* `DELETE FROM answer_ratings WHERE id = $deleted`. Bulk-delete applies the same ordering against every matched `answer_ratings.id`.

**Rationale**: The spec's critical data rule is that a verified-answer cache entry (`validated_qa` row) survives deletion of its originating rating. Nulling the link first keeps the data consistent even though the FK has been dropped (migration `20260418110000`) — there is no database-level cascade to rely on, so we have to do it in app code. Doing it in the right order also future-proofs against re-introducing the FK later (which would otherwise block the delete).

**Alternatives considered**:
- *Rely on the dropped FK — just delete.* Rejected: leaves dangling UUIDs on `validated_qa.rating_id`, which pollutes Train AI re-approve flows that copy `rating_id` forward (see `review_answer_multi` in `backend/services/validated_qa_service.py`). Cleanup is cheap and explicit; skipping it is a YAGNI violation in the wrong direction.
- *Re-add the FK with `ON DELETE SET NULL`.* Rejected: the FK was deliberately dropped in spec 080 follow-up so that Train AI can use synthetic grouping UUIDs (primary + variants sharing a `rating_id` that has no `answer_ratings` row). Reintroducing the FK would break that path.

### D2. Idempotency — 404 treated as success

**Decision**: `DELETE /manuals/ratings/{rating_id}` returns `200 {"status": "deleted", "existed": <bool>}` whether or not the row was present. The frontend treats both responses identically (remove from list, show "Rating removed" snackbar). `POST /manuals/ratings/bulk-delete` returns `200 {"deleted_count": N}` including `N = 0`.

**Rationale**: The spec explicitly requires that concurrent deletes and double-taps resolve cleanly. Returning `200` with `existed: false` is simpler for the frontend than gating on a `404` path and avoids race conditions where two admin tabs both click delete.

**Alternatives considered**:
- *True 404 on missing row.* Rejected: forces every caller to branch on "is 404 actually success here?" — error-prone and invites inconsistent UX.
- *204 No Content on success.* Rejected: the endpoint body carries useful info (`existed`, `deleted_count`) for telemetry and for admin UIs that may want to say "nothing to delete".

### D3. Authorization model

**Decision**: Authorization is evaluated by the backend using the existing `user_email` query param pattern used throughout `backend/routers/manuals.py`. For single-rating delete: caller is authorized if `(rater_email == user_email)` OR the existing `_admin_check(user_email)` passes. For bulk delete: only `_admin_check` is required.

**Rationale**: Matches the rest of the RAG feature surface (e.g., `/manuals/flagged-answers`, `/manuals/review-answer`, `/manuals/real-usage-suggestions`) so operators don't have to learn a new auth shape. No new middleware; no new tables. The spec's clarifications confirmed identity comes from the existing email-based flow.

**Alternatives considered**:
- *Supabase Auth JWT verification inside the endpoint.* Rejected: the backend uses the Supabase service-role key and the broader codebase treats `user_email` as the trust boundary at the router layer (constitution III explicitly notes this).
- *RLS-only enforcement.* Rejected: same reason — the service role bypasses RLS; authorization must be explicit in the router.

### D4. Idempotency semantics for bulk delete

**Decision**: Bulk delete matches by *exact* `question_text` + `answer_text`, using the same grouping key the `/manuals/real-usage-suggestions` endpoint uses. A match returning zero rows is `200 {"deleted_count": 0}` (success, frontend removes card from list anyway).

**Rationale**: The spec's clarification pinned this behavior. Exact match is what the admin sees on the card, and is what the list aggregation (see `real_usage_suggestions` in `backend/routers/manuals.py`, lines 1417–1431) uses for grouping. No fuzzy matching needed.

**Alternatives considered**:
- *Delete by aggregated key (question only).* Rejected: could remove unrelated answers that happen to share a question text. Spec prohibits over-reaching deletes.

### D5. Activity-log actions

**Decision**: Three new `action` values under category `"manual"`:

| Action | Emitted when | target_label | detail |
|---|---|---|---|
| `unrated_answer` | rater deletes their own rating | question_text[:80] | rating value (`positive`/`negative`) |
| `admin_deleted_rating` | admin deletes someone else's single rating | question_text[:80] | `rater_email` of original rater |
| `admin_bulk_deleted_ratings` | admin bulk delete of a Q&A group | question_text[:80] | `count=N` |

**Rationale**: Matches the `log_activity(user_email, category, action, target_label, detail)` signature already in use (see `rated_answer`, `reviewed_answer` in the same file). `manual` is the existing category for AI-assistant events. `detail` carries the discriminating information needed to audit the exact action.

**Alternatives considered**:
- *Single `deleted_rating` action with actor role encoded in detail.* Rejected: makes admin oversight dashboards harder to filter; three distinct actions is cleaner to query.

### D6. One-time undo hint (chat)

**Decision**: On the first rating recorded per user (after deploy), the chat tab shows a snackbar lasting 4 seconds: "Tap the thumb again to remove your rating." Persistence uses `SharedPreferences` key `rating_undo_hint_shown_<user_email>` (matches the per-user preference pattern used by `ThemeController` for `fontScale`).

**Rationale**: FR-009a. SharedPreferences is already in use; no new dependency. The per-email key scope matches the pattern of "do not show a user-scoped hint twice." Text is simple enough to flip under RTL via the default Material snackbar (Arabic translation to be added by the frontend edit; the widget itself already renders RTL text correctly).

**Alternatives considered**:
- *Long-press tooltip.* Rejected during /speckit.clarify — the user explicitly chose snackbar (option B).
- *Permanent label under the thumb.* Rejected: visual clutter, not localized to the undo action.

### D7. Failure-path UX and rollback

**Decision**: On a non-idempotent failure (network error, 5xx, explicit 403), the hosting screen:
1. Shows an error snackbar (`"Could not remove rating — please try again."` or the equivalent per surface).
2. Restores the pre-tap local state: in chat, `_selectedRating` is reset and `_ratingId` is restored; in Review tab, the card is re-inserted at its original index; in Train AI, the suggestion card is re-inserted at its original index.

**Rationale**: FR-025a. Matches the project's "Explicit Over Automatic" constitution principle and the "no auto-save" work-order edit memory: when the server says no, the client reflects the server. Rolling back by index (vs. full refetch) is faster and consistent with how the other admin tabs handle mutations.

**Alternatives considered**:
- *Keep optimistic state + reconcile on next refresh.* Rejected during /speckit.clarify (option B was rejected). Users want immediate truth.
- *Modal retry dialog.* Rejected during /speckit.clarify (option C was rejected). Too heavy for a background-operation failure.

### D8. Confirmation dialog texts (RTL-ready)

**Decision**: Use Flutter `showDialog` + `AlertDialog` with `TextDirection.rtl` wrapper when the question/answer content is Arabic — matching the existing RTL pattern in `ReviewEntryCard` and `UsageSuggestionCard`. Strings (English baseline; Arabic translation handled by the widget layer the same way existing admin dialogs already do):

- Review tab single delete: title "Delete rating?"; body "This thumbs-down will be removed and the answer will leave the review queue. The verified-answer cache (if any) is unaffected."; primary destructive button "Delete" (red); secondary "Cancel".
- Train AI bulk delete: title "Delete permanently?"; body "Permanently delete N positive ratings for this question? It will stop appearing here. Cannot be undone."; primary destructive button "Delete permanently" (red); secondary "Cancel".

**Rationale**: Preserves the exact wording the user specified. Reuses the AlertDialog + RTL pattern already in both surfaces, so no new widget pattern enters the codebase (YAGNI).

## Open items

None. All `NEEDS CLARIFICATION` from Technical Context are resolved here.
