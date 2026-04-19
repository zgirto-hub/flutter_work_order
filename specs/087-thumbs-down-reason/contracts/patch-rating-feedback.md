# API Contract — `PATCH /manuals/ratings/{rating_id}/feedback`

## Purpose

Attach a reason and optional free-text comment to an existing `answer_ratings` row. Only the original rater (self-update) may modify the feedback on their own row.

## Endpoint

```
PATCH /manuals/ratings/{rating_id}/feedback
Content-Type: application/json
```

Path parameter:

| Name | Type | Notes |
|---|---|---|
| `rating_id` | UUID | The `answer_ratings.id` returned from the preceding `POST /manuals/rate-answer` call |

## Request body

```json
{
  "feedback_reason": "outdated",
  "feedback_comment": "The 2022 revision of the SOP was superseded in 2024 — this answer is stale.",
  "user_email": "ahmed.khalil@example.com"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `feedback_reason` | string enum | YES | One of: `inaccurate`, `incomplete`, `outdated`, `wrong_source`, `unclear`. Any other value → 422. |
| `feedback_comment` | string \| null | NO | 0–2000 characters (Pydantic `max_length=2000`). Over cap → 422. Empty string and null are both acceptable and treated as "no comment". |
| `user_email` | string | YES | The caller's email. Must match `answer_ratings.rater_email` for the given `rating_id`, otherwise 403. Consistent with existing `DELETE /manuals/ratings/{rating_id}` pattern. |

## Response

### `200 OK` — success

```json
{
  "status": "saved",
  "rating_id": "8f0b8b2e-…",
  "feedback_reason": "outdated",
  "feedback_comment": "The 2022 revision …"
}
```

**Side effects**:

1. The row at `answer_ratings.id = rating_id` is updated with the new `feedback_reason` and `feedback_comment`.
2. A `rated_answer_feedback` event is emitted to `user_activity_log` via `log_activity`:
   ```
   user_email:   <rater email>
   category:     'manual'
   action:       'rated_answer_feedback'
   target_label: <first 80 chars of question_text>
   detail:       <feedback_reason value>
   ```
   Logging failures are swallowed (fire-and-forget); they do NOT fail the PATCH response.

### `404 Not Found` — rating doesn't exist

```json
{ "detail": { "error": "rating_not_found" } }
```

Returned when `rating_id` does not correspond to any row in `answer_ratings`.

### `403 Forbidden` — caller is not the rater

```json
{ "detail": { "error": "not_owner" } }
```

Returned when `user_email` does not match the row's `rater_email`. No partial update is performed.

### `422 Unprocessable Entity` — validation error

Examples of what produces 422 (handled by Pydantic automatically):

- `feedback_reason` is missing or not one of the 5 allowed values
- `feedback_comment` exceeds 2000 characters
- `user_email` is missing or not a string

Response shape is FastAPI / Pydantic default; client should surface a generic "Could not save feedback" toast.

### `400 Bad Request` — rating polarity mismatch

```json
{ "detail": { "error": "not_negative_rating" } }
```

Returned when the row exists but has `rating = 'positive'`. The feedback fields are only valid for negative ratings per FR-012. Prevents accidental data on positive rows.

### `500 Internal Server Error` — database or unexpected failure

```json
{ "detail": { "error": "save_failed", "message": "<error text>" } }
```

---

## Behavior details

- **Idempotency**: repeated PATCHes with identical body produce the same end state — last write wins. No dedup token required.
- **Edge case: empty reason field**: Not allowed. Clients MUST send one of the 5 enum values. If the user wants to "clear" a reason, the only path is un-rating the original thumbs-down (which deletes the row entirely).
- **No rate limiting**: inherits existing app-wide FastAPI behavior. The client only calls this endpoint once per Save click and UI disables Save while in-flight.
- **No thumbs-up path**: the client never calls this endpoint after a thumbs-up. If it did (e.g., tampered client), server would still update the fields — but FR-012 is enforced at the earlier `save_rating()` layer, so the row's polarity never changes. As belt-and-braces, the `not_negative_rating` 400 above also blocks this.

## Client request flow (reference)

```
1. User taps 👎  ─────────────▶ POST /manuals/rate-answer { rating: 'negative', ... }
                                            │
                                            ▼
                                  Response: { id: "8f0b…", status: "saved" }
                                            │
                        Bottom sheet opens (with the rating_id in state)
                                            │
              User picks reason, optionally types comment, taps Save
                                            │
                                            ▼
2. PATCH /manuals/ratings/8f0b…/feedback { feedback_reason, feedback_comment, user_email }
                                            │
                                            ▼
                                     200 OK → dismiss sheet, show "Saved" toast
                                     4xx/5xx → keep rating, show generic error toast
```

If Step 1 fails, Step 2 never fires. If Step 2 fails, Step 1's outcome is unaffected — the 👎 remains recorded with NULL reason.
