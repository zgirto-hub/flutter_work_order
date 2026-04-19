# Contract: PUT /api/manuals/verified-answers/{qa_id}/variants

Full-replace reconcile of the variant set for the verified-answer entry's `rating_id` group. This is the only write path introduced by spec 085.

## Authorization

Admin-only; same pattern as the existing `PUT /api/manuals/verified-answers/{qa_id}`.

## Request

```
PUT /api/manuals/verified-answers/{qa_id}/variants
Content-Type: application/json

{
  "user_email": "admin@example.com",
  "variants": [
    "Where are the locations for each LA network?",
    "What are the locations for every LA network?",
    "How can I find the locations for all LA networks?"
  ]
}
```

### Path parameters

| Name | Type | Description |
|---|---|---|
| `qa_id` | uuid | Anchors the reconcile. If the row has `rating_id = NULL`, the server assigns a synthetic UUID before reconciling (FR-009). |

### Body fields

| Name | Type | Required | Notes |
|---|---|---|---|
| `user_email` | string | yes | Admin email; used for authorization + audit. |
| `variants` | string[] | yes | Final list of question phrasings. After the server normalizes each with `strip().casefold()` and dedupes, the resulting count MUST be ≥ 1 and each original MUST be ≤ 500 chars. |

## Semantics

1. Server loads all rows with matching `rating_id` (if target row has `rating_id = NULL`, assigns a fresh UUID first).
2. Server normalizes both stored and submitted texts via `strip().casefold()`.
3. Set difference:
   - **to_delete**: stored rows whose normalized text does not appear in the submitted set
   - **to_insert**: submitted texts whose normalized form does not appear in the stored set
4. Server computes embeddings for every `to_insert` text. If any embedding call fails or times out, the operation aborts with 503 and zero DB rows change (FR-008a).
5. Server executes DELETE (on `to_delete` ids) then INSERT (`to_insert` rows with shared `validated_answer`, `rating_id`, `manual_ids`, `source_chunks`, `validated_by=user_email`, `validated_at=now`).
6. Server writes one `user_activity_log` entry (category `admin`, action `updated_verified_answer_variants`).

## Responses

### 200 OK

```json
{
  "qa_id": "<uuid>",
  "rating_id": "<uuid>",
  "added_count": 2,
  "removed_count": 1,
  "variants": [
    { "id": "<uuid>", "question_text": "Where are the locations for each LA network?" },
    { "id": "<uuid>", "question_text": "What are the locations for every LA network?" },
    { "id": "<uuid>", "question_text": "How can I find the locations for all LA networks?" }
  ]
}
```

- `rating_id` is always non-null in the response (backfilled if the target entry was legacy).
- `variants` is the full final set after reconcile, in stable order (`question_text` ASC).

### 400 Bad Request

- `variants` is empty after normalization/dedup (FR-010 violation).
- Any variant exceeds 500 chars (FR-011 violation).

Example body: `{ "detail": "at least one variant required" }` or `{ "detail": "variant exceeds 500 characters" }`.

### 401 / 403

Unauthorized caller or non-admin email.

### 404 Not Found

No row with the given `qa_id`.

### 503 Service Unavailable

Embedding service unreachable, timed out, or returned an error. No DB rows changed. Body example: `{ "detail": "embedding service unavailable; please retry" }`.

### 500 Internal Server Error

Unexpected DB error during the write phase. Rare in practice because embeddings (the common failure mode) are pre-computed; still possible if the DB connection drops mid-delete. Because deletes run before inserts, a 500 after a partial delete leaves the stored set as a subset of the original — still a self-consistent variant set, but the client MUST refetch via GET to reconcile the UI.

## Idempotency

The endpoint is naturally idempotent under the same request body: submitting the identical variant list twice produces identical state both times (zero-delta on the second call). Safe for client-side retry on 503.
