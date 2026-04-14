# API Contracts: Verified Answers

Base path: `/manuals`

---

## GET /manuals/verified-answers

**Auth**: Admin-only (`_admin_check(user_email)`)

### Query Parameters

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| user_email | string | yes | — | Email for admin check |
| search | string | no | null | Case-insensitive ilike filter on question_text |
| limit | integer | no | 50 | Page size |
| offset | integer | no | 0 | Pagination offset |

### Response 200

```json
{
  "items": [
    {
      "id": "uuid",
      "question_text": "string",
      "validated_answer": "string",
      "equipment_type": "string | null",
      "fault_code": "string | null",
      "validated_by": "string",
      "validated_at": "ISO 8601",
      "thumbs_up_count": 0,
      "thumbs_down_count": 0,
      "is_reflagged": false,
      "updated_at": "ISO 8601"
    }
  ],
  "count": 42
}
```

### Error Responses

| Status | Condition |
|--------|-----------|
| 403 | user_email is not an admin |
| 500 | Database error |

---

## PUT /manuals/verified-answers/{qa_id}

**Auth**: Admin-only (`_admin_check(editor_email)`)

### Path Parameters

| Param | Type | Description |
|-------|------|-------------|
| qa_id | string (UUID) | validated_qa row ID |

### Request Body

```json
{
  "question_text": "string (optional)",
  "validated_answer": "string (optional)",
  "editor_email": "string (required)"
}
```

At least one of `question_text` or `validated_answer` must be provided.

### Response 200

Returns the full updated row (same shape as GET items).

### Error Responses

| Status | Condition |
|--------|-----------|
| 403 | editor_email is not an admin |
| 404 | qa_id not found |
| 504 | Embedder timeout during re-embedding (question_text changed) |
| 500 | Database or other error |

### Side Effects

- If `question_text` changed: re-generates `question_embedding`, re-extracts `equipment_type` and `fault_code`
- Always updates `updated_at`
- Logs activity: `log_activity(editor_email, "manual", "edited_verified_answer", ...)`

---

## DELETE /manuals/verified-answers/{qa_id}

**Auth**: Admin-only (`_admin_check(editor_email)`)

### Path Parameters

| Param | Type | Description |
|-------|------|-------------|
| qa_id | string (UUID) | validated_qa row ID |

### Query Parameters

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| editor_email | string | yes | Email for admin check and audit logging |

### Response 200

```json
{
  "status": "deleted",
  "id": "uuid"
}
```

### Error Responses

| Status | Condition |
|--------|-----------|
| 403 | editor_email is not an admin |
| 404 | qa_id not found |
| 500 | Database error |

### Side Effects

- Hard-deletes the validated_qa row
- Resets linked `answer_ratings.review_status` to `'pending'`
- Logs activity: `log_activity(editor_email, "manual", "deleted_verified_answer", ...)`
