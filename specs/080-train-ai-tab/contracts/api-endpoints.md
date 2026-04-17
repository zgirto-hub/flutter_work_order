# API Contracts: 080 — Train the AI Tab

**Date**: 2026-04-17  
**Branch**: `080-train-ai-tab`

All endpoints are under the existing `/manuals` router prefix.  
All new endpoints require admin role (`_admin_check(user_email)`).

---

## NEW: POST /manuals/generate-qa-candidates

Generate Q&A candidate pairs from a manual's chunks.

**Query params**: `user_email: str` (required)

**Request body**:
```json
{
  "manual_id": "uuid-string",
  "max_candidates": 20
}
```

**Success response** (200):
```json
{
  "candidates": [
    {
      "question": "How do you inspect the landing gear hydraulic system?",
      "answer": "Step 1: Verify hydraulic pressure is at...",
      "source_title": "B777 Maintenance Manual — Page 42",
      "source_chunk_ids": ["uuid-1", "uuid-2", "uuid-3"]
    }
  ],
  "total": 15,
  "skipped_cached": 5
}
```

**Error responses**:
- `403`: `{"error": "admin_required"}`
- `404`: `{"error": "not_found", "message": "Manual not found."}`
- `400`: `{"error": "no_chunks", "message": "This manual has no content chunks. Please process it first."}`

---

## NEW: GET /manuals/real-usage-suggestions

Get positively-rated questions not yet in the cache.

**Query params**: `user_email: str` (required)

**Success response** (200):
```json
{
  "suggestions": [
    {
      "question": "What is the torque spec for the nose wheel axle bolt?",
      "answer": "According to the maintenance manual, the torque specification is...",
      "rating_count": 5,
      "last_asked_at": "2026-04-15T10:30:00Z"
    }
  ]
}
```

**Error responses**:
- `403`: `{"error": "admin_required"}`

---

## NEW: GET /manuals/stale-cache-entries

Get validated_qa entries whose source manual has been updated since last verification.

**Query params**: `user_email: str` (required)

**Success response** (200):
```json
{
  "stale_entries": [
    {
      "qa_id": "uuid-string",
      "question": "How do you calibrate the altimeter?",
      "answer": "To calibrate the altimeter, follow these steps...",
      "manual_title": "B777 Avionics Manual",
      "manual_updated_at": "2026-04-16T14:00:00Z",
      "days_since_update": 1
    }
  ],
  "total": 3
}
```

**Error responses**:
- `403`: `{"error": "admin_required"}`

---

## NEW: POST /manuals/mark-cache-reviewed

Confirm, edit, or delete a stale cache entry.

**Query params**: `user_email: str` (required)

**Request body**:
```json
{
  "qa_id": "uuid-string",
  "action": "confirm",
  "updated_question": null,
  "updated_answer": null
}
```

`action` values: `"confirm"` | `"delete"`

**Success response** (200):

For `confirm`:
```json
{
  "status": "confirmed",
  "qa_id": "uuid-string",
  "verified_at": "2026-04-17T12:00:00Z"
}
```

For `delete`:
```json
{
  "status": "deleted",
  "deleted_count": 8
}
```

**Error responses**:
- `403`: `{"error": "admin_required"}`
- `404`: `{"error": "not_found", "message": "QA entry not found."}`
- `400`: `{"error": "invalid_action"}`

---

## MODIFIED: POST /manuals/paraphrase-variants

Add optional `lang` parameter for Arabic paraphrase generation.

**Query params**: `user_email: str` (required)

**Request body** (updated):
```json
{
  "question_text": "How do you inspect the landing gear?",
  "rating_id": null,
  "lang": "en"
}
```

`lang` values: `"en"` (default, existing behavior) | `"ar"` (Arabic variants)

**Success response** (200):

When `lang="en"`: 4 English paraphrase variants (unchanged behavior)
```json
{
  "variants": ["variant1", "variant2", "variant3", "variant4"]
}
```

When `lang="ar"`: 3 Arabic paraphrase variants
```json
{
  "variants": ["كيف يتم فحص عجلة الهبوط؟", "ما هي خطوات فحص معدات الهبوط؟", "كيف تفحص نظام الهبوط؟"]
}
```

---

## MODIFIED: POST /manuals/verified-answers

Extend to accept optional `source_manual_id`.

**Request body** (updated):
```json
{
  "question_text": "How do you inspect the landing gear?",
  "validated_answer": "Step 1: ...",
  "editor_email": "admin@example.com",
  "source_manual_id": "uuid-or-null"
}
```

**Response**: Unchanged — returns the created validated_qa row with `id`.

---

## Existing Endpoints Used (no changes to contract)

| Endpoint | Used in | Purpose |
|----------|---------|---------|
| `POST /manuals/review-answer-with-variants` | Step 4 of save flow | `retro_expand` action to save paraphrase variant embeddings |
| `GET /manuals/list` (via `listManuals()`) | Section A dropdown | Fetch available manuals |
