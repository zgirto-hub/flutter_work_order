# Contract: POST /api/manuals/paraphrase-variants

**Auth**: Admin only (same gate as existing `/api/manuals/review-answer` in `backend/routers/manuals.py`).

## Purpose

Generate 3–5 English paraphrased variants of a single technical question. Read-only: does not write to `validated_qa` or `answer_ratings`.

## Request

```json
{
  "question_text": "what is aida ng username and password?",
  "rating_id": "<uuid, optional>"
}
```

- `question_text` (required, string, 1..500 chars): the source question to paraphrase.
- `rating_id` (optional, uuid): present when called from Review-tab Approve flow; absent when called from Verified-tab retro-expansion. Server ignores it except for audit logging.

## Response — 200 OK

```json
{
  "variants": [
    "how do I log in to aida ng?",
    "password of AIDA NG system",
    "aida ng login credentials",
    "what credentials do I use for aida ng?"
  ]
}
```

- `variants` (array of 0..5 strings): may be empty when all providers fail (INV-3). Never contains duplicates of `question_text`. Each entry is trimmed and non-empty.

## Response — 200 OK with empty variants (provider-fail fallback)

```json
{ "variants": [] }
```

Emitted when `resolver.generate` raises for every provider in the chain, or when parsing leaves zero usable lines. Frontend uses this as the signal to show the "automatic variants could not be generated" notice.

## Error responses

- `400 Bad Request` — `question_text` missing, empty, or exceeds 500 chars.
- `401 Unauthorized` / `403 Forbidden` — non-admin caller.

No `5xx` on provider failure.

## Implementation contract (informative)

- Prompt template: see `research.md` R1.
- Parser rules: see `research.md` R1.
- Timeout budget: resolver default (per spec 063). Endpoint returns within ~3 s p95.
- Cache: none. Each call is a fresh resolver invocation. Cost is bounded by admin approval rate.
