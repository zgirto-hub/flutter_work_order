# Contract: GET /api/manuals/verified-answers/{qa_id}/variants

Fetch the variant set (sibling rows sharing `rating_id`) for a verified-answer entry. Used by the Verified tab's "Generate variants" button to pre-populate the modal with "saved" chips.

## Authorization

Admin-only. Uses the existing `user_email` query-parameter gating pattern already in place for `PUT/DELETE /api/manuals/verified-answers/{qa_id}`. The backend verifies the caller is an admin via the same helper used by surrounding endpoints.

## Request

```
GET /api/manuals/verified-answers/{qa_id}/variants?user_email={email}
```

### Path parameters

| Name | Type | Description |
|---|---|---|
| `qa_id` | uuid | The `validated_qa.id` of the entry the admin clicked in the Verified tab. |

### Query parameters

| Name | Type | Required | Description |
|---|---|---|---|
| `user_email` | string | yes | Admin's email; used for authorization + audit. |

## Response

### 200 OK

```json
{
  "qa_id": "<uuid>",
  "rating_id": "<uuid-or-null>",
  "question_text": "the original question from the clicked entry",
  "validated_answer": "the shared answer body",
  "variants": [
    { "id": "<uuid>", "question_text": "Where are the locations for each LA network?" },
    { "id": "<uuid>", "question_text": "What are the locations for every LA network?" }
  ]
}
```

- `variants` always contains at least one row (the clicked entry itself). Order is stable but unspecified (sort by `question_text` for determinism).
- `rating_id` MAY be `null` for legacy entries; the PUT endpoint will backfill on first save.
- `validated_answer` is included so the frontend can render the read-only answer body in the modal if the UX chooses to.

### 401 / 403

Unauthorized caller or non-admin email.

### 404 Not Found

No row with the given `qa_id`.

## Error envelope

Follows the existing FastAPI convention used by sibling endpoints in `backend/routers/manuals.py`:

```json
{ "detail": "error message" }
```

## Invariants

- This endpoint is read-only. It MUST NOT create a `rating_id` for legacy entries, trigger embeddings, or write to audit logs.
