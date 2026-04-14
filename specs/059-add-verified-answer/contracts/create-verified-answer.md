# Contract: Create Verified Answer

**Endpoint**: `POST /api/manuals/verified-answers`
**Auth**: Admin only (checked via `_admin_check(editor_email)`)

## Request

```json
{
  "question_text": "string (required, non-empty after trim)",
  "validated_answer": "string (required, non-empty after trim)",
  "editor_email": "string (required, admin email)"
}
```

## Response — 200 OK

```json
{
  "id": "uuid",
  "question_text": "string",
  "validated_answer": "string",
  "equipment_type": "string | null",
  "fault_code": "string | null",
  "validated_by": "string",
  "validated_at": "ISO 8601 timestamp",
  "thumbs_up_count": 0,
  "thumbs_down_count": 0,
  "is_reflagged": false,
  "source_chunks": [],
  "manual_ids": []
}
```

## Error Responses

| Status | Condition                          | Body                                          |
|--------|------------------------------------|-----------------------------------------------|
| 403    | Non-admin `editor_email`           | `{"error": "admin_required"}`                 |
| 422    | Empty `question_text` or `validated_answer` | `{"error": "question and answer required"}` |
| 504    | Embedding service timeout          | `{"error": "embedding_timeout"}`              |
| 500    | Supabase insert failure            | `{"error": "create_failed"}`                  |

## Notes

- `equipment_type` and `fault_code` are auto-extracted from `question_text` on the backend
- `question_embedding` is generated server-side and not returned in the response
- `rating_id` is set to `NULL` (requires migration `20260415000000`)
- Response shape matches existing `GET /api/manuals/verified-answers` list item shape
