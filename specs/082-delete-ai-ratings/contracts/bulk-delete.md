# Contract — `POST /manuals/ratings/bulk-delete`

Admin-only. Deletes every `answer_ratings` row matching the exact `(question_text, answer_text)` pair. Used by the Train AI tab's "From Real Usage" overflow-menu "Delete permanently" action.

## Route

`POST /manuals/ratings/bulk-delete?user_email={email}`

Registered in [backend/routers/manuals.py](../../backend/routers/manuals.py) near the existing `GET /manuals/real-usage-suggestions` handler.

## Query parameters

| Name | Type | Required | Notes |
|---|---|---|---|
| `user_email` | string | yes | Caller identity. MUST be an admin. |

## Request body

```json
{
  "question_text": "<exact string>",
  "answer_text": "<exact string>"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `question_text` | string | yes | Must exactly match the row's `question_text`. |
| `answer_text` | string | yes | Must exactly match the row's `answer_text`. |

## Responses

### 200 OK — success (including zero matches)

```json
{"deleted_count": 12}
```

- `deleted_count` is the number of `answer_ratings` rows removed on this call.
- `deleted_count: 0` is a successful no-op (the card still disappears from the admin's list — that matches intent).

Side effects (in order):

1. `SELECT id FROM answer_ratings WHERE question_text = $1 AND answer_text = $2` — collect matched IDs.
2. `UPDATE validated_qa SET rating_id = NULL WHERE rating_id = ANY($matched_ids)`.
3. `DELETE FROM answer_ratings WHERE id = ANY($matched_ids)`.
4. Activity log: `action="admin_bulk_deleted_ratings"`, `target_label=question_text[:80]`, `detail="count=<N>"`. Written even when N = 0 (so admins have a record of the dismissal).

If no IDs matched, steps 2 and 3 are skipped; step 4 still runs.

### 403 Forbidden — non-admin

```json
{"detail": {"error": "admin_required"}}
```

Returned when `_admin_check(user_email)` fails. No side effects.

### 422 Unprocessable Entity — missing fields

```json
{"detail": [<pydantic validation errors>]}
```

Returned by FastAPI when `question_text` or `answer_text` is absent. No side effects.

### 500 Internal Server Error

```json
{"detail": {"error": "bulk_delete_failed", "message": "<detail>"}}
```

Wrapping matches the style already in use.

## Pydantic request model

```python
class BulkDeleteRatingsRequest(BaseModel):
    question_text: str
    answer_text: str
```

Defined in `backend/routers/manuals.py` alongside existing request models.

## Contract tests (pytest)

Tests live in `backend/tests/routers/test_manuals_bulk_delete.py` (new file).

| ID | Scenario | Setup | Expectation |
|---|---|---|---|
| B1 | Admin deletes full group | Insert 3 `answer_ratings` with the same (q, a). `admin@x` is admin. | `POST …?user_email=admin@x` body `{q, a}` → 200, `deleted_count=3`. All three rows gone. Activity row with `detail='count=3'`. |
| B2 | Zero matches | Empty table (or different (q, a)). | 200, `deleted_count=0`. Activity row with `detail='count=0'`. |
| B3 | Non-admin forbidden | `user_email=tech@x` (non-admin). | 403. No side effects. No activity row. |
| B4 | Preserves `validated_qa` | 2 ratings matching (q, a); one `validated_qa` row whose `rating_id` references one of them. | 200, `deleted_count=2`. `validated_qa` row still present; its `rating_id` is NULL. |
| B5 | Partial overlap does not leak | Two pairs: (q, a1) with 3 rows and (q, a2) with 2 rows. Bulk delete (q, a1). | 200, `deleted_count=3`. The (q, a2) rows still present. |
| B6 | Missing fields | Body `{"question_text": "..."}` (no `answer_text`). | 422. No side effects. |
