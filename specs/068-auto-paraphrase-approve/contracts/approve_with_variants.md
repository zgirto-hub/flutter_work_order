# Contract: POST /api/manuals/review-answer-with-variants

**Auth**: Admin only.

## Purpose

Atomically approve a pending answer and insert N verified_qa rows — one per admin-approved variant (including the original question) — all sharing the same validated answer, rating_id, and source metadata. This is the batch counterpart to the existing single-row `/api/manuals/review-answer`.

## Request — Review-tab flow (approve)

```json
{
  "rating_id": "<uuid of answer_ratings row>",
  "action": "approve",
  "corrected_answer": null,
  "variants": [
    "what is aida ng username and password?",
    "how do I log in to aida ng?",
    "password of AIDA NG system"
  ]
}
```

## Request — Verified-tab retro-expansion flow

```json
{
  "rating_id": "<uuid — may be any existing validated_qa.rating_id or null>",
  "action": "retro_expand",
  "existing_validated_qa_id": "<uuid of the existing verified row being expanded>",
  "variants": [
    "original question text here",
    "paraphrase 1",
    "paraphrase 2"
  ]
}
```

- `action` ∈ { `approve`, `correct`, `retro_expand` }.
- `variants` (array, length ≥ 1): every string gets its own row. First element is conventionally the original question but this is not enforced by the server.
- `corrected_answer` is required iff `action == "correct"`.
- `existing_validated_qa_id` is required iff `action == "retro_expand"`; the server reuses that row's `validated_answer`, `rating_id`, `manual_ids`, and `source_chunks` as the shared fields for the new variant rows.

## Field validation

- Each variant string: trimmed; whitespace-only entries rejected from the array **before** insertion (FR-014). If the resulting list is empty after trimming, return 400.
- Duplicate detection: none. Admin is the filter (FR-016).
- Max length per variant: 500 chars.
- Max variants per request: 10 (guards against pathological payloads; admin never needs more).

## Response — 200 OK

```json
{
  "inserted_count": 3,
  "validated_qa_ids": ["<uuid>", "<uuid>", "<uuid>"],
  "rating_id": "<uuid>",
  "status": "approved"
}
```

## Error responses

- `400 Bad Request` — empty variants after trimming, invalid action, missing corrected_answer when required, missing existing_validated_qa_id when required.
- `401 / 403` — non-admin.
- `404 Not Found` — referenced rating_id or existing_validated_qa_id does not exist.
- `500 Internal Server Error` — embedding generation failed for all variants (rare: local Ollama down). Partial inserts MUST NOT occur (FR-013); server computes all embeddings first, then performs the single batch INSERT.

## Atomicity contract (FR-013)

1. Server resolves shared fields (validated_answer, rating_id, manual_ids, source_chunks, equipment_type, fault_code) once.
2. Server computes embeddings for all variants sequentially. If any embedding call fails, the request aborts with 500 — no inserts.
3. Server performs a single `supabase.table("validated_qa").insert([row1, ...]).execute()` — atomic at the SQL statement level.
4. Server updates `answer_ratings.review_status` (approve/correct flows only).
5. Server fire-and-forgets one audit-log entry summarising the batch.

Steps 2 and 3 together give all-or-nothing semantics for the variant rows themselves. Steps 4–5 are post-insert bookkeeping and follow the existing spec 048 pattern.

## Side effects

- N rows inserted into `validated_qa`, all sharing `rating_id`, `validated_answer`, `validated_by`, `validated_at`, `manual_ids`, `source_chunks`.
- One update to `answer_ratings.review_status` (for `approve`/`correct`; no-op for `retro_expand`).
- One activity log row via `log_activity`.
- No changes to any existing row (retro_expand inserts new rows only; the existing `existing_validated_qa_id` row is untouched — variants join it via shared `rating_id` / `validated_answer`).
