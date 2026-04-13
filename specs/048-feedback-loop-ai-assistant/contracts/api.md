# API Contracts: Feedback Loop AI Assistant

**Branch**: `048-feedback-loop-ai-assistant` | **Date**: 2026-04-13

All endpoints are added to the existing `/manuals` router.

## POST /manuals/rate-answer

Submit a rating for an AI-generated answer.

**Request Body**:
```json
{
    "question_text": "How to replace the hydraulic pump?",
    "answer_text": "To replace the hydraulic pump, follow these steps...",
    "source_chunks": [
        {"manual_title": "Boeing 737 MRO", "source_page": 42, "content": "...preview..."}
    ],
    "rating": "positive",
    "rater_email": "tech@example.com",
    "manual_id": "uuid-or-null",
    "model_used": "qwen2.5:14b-ctx16k"
}
```

**Response** (200):
```json
{
    "id": "rating-uuid",
    "status": "saved"
}
```

**Validation**:
- `rating` must be `"positive"` or `"negative"`
- `rater_email` must be non-empty
- `question_text` and `answer_text` must be non-empty

---

## GET /manuals/flagged-answers

Get all pending flagged answers for the review queue. Admin-only.

**Query Parameters**:
- `user_email` (required): Email of the requesting user (admin check)

**Response** (200):
```json
{
    "items": [
        {
            "id": "rating-uuid",
            "question_text": "How to replace the hydraulic pump?",
            "answer_text": "To replace the hydraulic pump...",
            "source_chunks": [...],
            "rater_email": "tech@example.com",
            "created_at": "2026-04-13T10:30:00Z"
        }
    ],
    "count": 1
}
```

**Response** (403): Non-admin user.

---

## POST /manuals/review-answer

Approve or correct a flagged answer. Admin-only. Creates a validated_qa entry.

**Request Body**:
```json
{
    "rating_id": "rating-uuid",
    "action": "approve",
    "corrected_answer": null,
    "reviewer_email": "admin@example.com"
}
```

For corrections:
```json
{
    "rating_id": "rating-uuid",
    "action": "correct",
    "corrected_answer": "The correct procedure is...",
    "reviewer_email": "admin@example.com"
}
```

**Response** (200):
```json
{
    "validated_qa_id": "validated-uuid",
    "action": "approve",
    "status": "saved"
}
```

**Validation**:
- `action` must be `"approve"` or `"correct"`
- `corrected_answer` required when `action` is `"correct"`
- `reviewer_email` must belong to an admin user

---

## Modified: POST /manuals/ask

The existing `ask_question` endpoint response gains an optional field when a validated answer is returned directly.

**Additional response fields** (when validated answer matches >=0.90):
```json
{
    "answer": "The validated answer text...",
    "is_verified": true,
    "verified_source": {
        "validated_qa_id": "uuid",
        "validated_by": "admin@example.com",
        "validated_at": "2026-04-13T10:30:00Z",
        "similarity": 0.95
    },
    "sources": [],
    "grounded": true,
    "tools_used": []
}
```

When validated answer matches 0.75-0.90, the response is unchanged — the validated answer is injected internally as context. No new response fields.
