# Contract — `DELETE /manuals/ratings/{rating_id}`

Single-rating delete. Used by the chat tab (technician undo) and the Review tab (admin delete of a flagged answer).

## Route

`DELETE /manuals/ratings/{rating_id}?user_email={email}`

Registered in [backend/routers/manuals.py](../../backend/routers/manuals.py) near the existing `POST /manuals/rate-answer` handler (feature branch 082).

## Path parameters

| Name | Type | Constraints |
|---|---|---|
| `rating_id` | UUID | Primary key of `answer_ratings`. Not validated by regex at router level — Supabase handles shape errors as no-match. |

## Query parameters

| Name | Type | Required | Notes |
|---|---|---|---|
| `user_email` | string | yes | Caller identity. Must be the original `rater_email` on the row OR an admin. |

## Request body

None.

## Responses

### 200 OK — deleted (or already gone)

```json
{"status": "deleted", "existed": true}
```

- `existed: true` means a row was removed on this call.
- `existed: false` means no row matched (already deleted, or never existed). Frontend treats this identically to `true` — the outcome matches intent.

Side effects (in order, only when `existed: true`):
1. `UPDATE validated_qa SET rating_id = NULL WHERE rating_id = {rating_id}` (runs even on 0-row match — cheap and idempotent).
2. `DELETE FROM answer_ratings WHERE id = {rating_id}`.
3. Activity log write:
   - If `user_email == rater_email`: `action="unrated_answer"`, `target_label=question_text[:80]`, `detail=<original rating value>`.
   - Else (admin path): `action="admin_deleted_rating"`, `target_label=question_text[:80]`, `detail=<original rater_email>`.

### 403 Forbidden — not authorized

```json
{"detail": {"error": "forbidden"}}
```

Returned when `user_email` is neither the row's `rater_email` nor an admin. Authorization check runs *before* the NULL step. No side effects. No activity log entry.

### 500 Internal Server Error

```json
{"detail": {"error": "delete_failed", "message": "<detail>"}}
```

Returned on database errors. Wrapping matches the style already in use in the router.

## Authorization rules

Resolved in the router before any write:

1. Fetch row: `SELECT rater_email, rating, question_text FROM answer_ratings WHERE id = $rating_id`.
2. If row missing: skip auth (caller only learns `existed: false`). No need to check admin because the operation is a no-op regardless.
3. If row present and `rater_email == user_email`: authorized (self-undo path).
4. Else: run `_admin_check(user_email)`. If it raises, return 403.

Note: "check admin only if not own" avoids an extra `users` query for the common self-undo path.

## Contract tests (pytest)

The following must pass before the endpoint is considered complete. Tests live in `backend/tests/routers/test_manuals_delete_rating.py` (new file).

| ID | Scenario | Setup | Expectation |
|---|---|---|---|
| T1 | Rater deletes own rating | Insert `answer_ratings` with `rater_email='tech@x'`. | `DELETE …?user_email=tech@x` → 200, `existed=true`; row gone; activity row with `action='unrated_answer'` present. |
| T2 | Admin deletes someone else's | Insert `answer_ratings` with `rater_email='tech@x'`. `admin@x` is admin. | `DELETE …?user_email=admin@x` → 200, `existed=true`; row gone; activity row with `action='admin_deleted_rating'`, `detail='tech@x'`. |
| T3 | Non-rater non-admin forbidden | `rater_email='a@x'`; caller `b@x` is non-admin. | `DELETE …?user_email=b@x` → 403. Row still present. No activity row. |
| T4 | Idempotent — already gone | Delete the row directly in setup. | `DELETE …?user_email=<rater>` → 200, `existed=false`. No activity row. |
| T5 | Preserves `validated_qa` | Insert `answer_ratings` + one `validated_qa` row whose `rating_id` references it. | `DELETE …` → 200; `answer_ratings` row gone; `validated_qa` row still present; its `rating_id` is NULL. |
| T6 | Idempotency against unknown UUID | Use a random UUID that has no row. | 200, `existed=false`. No side effects. Authorization check is skipped (no row to own). |
| T7 | Concurrent delete | Two sequential deletes of the same `rating_id`. | Both return 200; first has `existed=true`, second has `existed=false`. |
