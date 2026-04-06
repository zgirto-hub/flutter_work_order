# Contract: POST /ai/parse-work-order

**Version**: 1.0 | **Date**: 2026-04-06

## Endpoint

`POST /ai/parse-work-order`

## Request

```json
{
  "text": "broken AC unit in room 205, urgent",
  "language": "en",
  "departments": ["General", "IT", "Maintenance", "Electrical", "Plumbing"],
  "types": ["Technical", "Inspection", "Other"],
  "statuses": ["Pending", "In Progress"]
}
```

| Field        | Type       | Required | Description                                             |
|--------------|------------|----------|---------------------------------------------------------|
| text         | string     | Yes      | Free-form natural language work order description       |
| language     | string     | Yes      | `"en"` or `"ar"` — language for AI response generation  |
| departments  | string[]   | Yes      | List of valid department names to constrain AI output    |
| types        | string[]   | Yes      | List of valid work order types to constrain AI output    |
| statuses     | string[]   | Yes      | List of valid statuses to constrain AI output            |

## Response (200 OK)

```json
{
  "title": "Broken AC Unit",
  "description": "Air conditioning unit is not functioning in Room 205. Requires immediate technical inspection and repair.",
  "location": "Room 205",
  "type": "Technical",
  "department": "Maintenance",
  "status": "Pending"
}
```

| Field       | Type         | Nullable | Description                                                  |
|-------------|--------------|----------|--------------------------------------------------------------|
| title       | string       | Yes      | Extracted/generated work order title                         |
| description | string       | Yes      | Expanded, professional work order description                |
| location    | string       | Yes      | Extracted location, null if not mentioned                    |
| type        | string       | Yes      | One of the provided `types` values, null if undetermined     |
| department  | string       | Yes      | One of the provided `departments` values, null if undetermined|
| status      | string       | Yes      | One of the provided `statuses` values, null if undetermined  |

All fields are nullable — the AI returns `null` for any field it cannot confidently determine from the input text.

## Error Responses

| Status | Body                                          | When                                    |
|--------|-----------------------------------------------|-----------------------------------------|
| 422    | `{"detail": "Text cannot be empty"}`          | `text` is empty or whitespace           |
| 503    | `{"detail": "AI service is currently unavailable"}` | Ollama connection failed or timed out |
| 502    | `{"detail": "AI model error"}`                | Model returned non-200 or unparseable response |
| 502    | `{"detail": "AI returned invalid response"}`  | Response is not valid JSON or missing expected structure |

## Example: Arabic Input

**Request:**
```json
{
  "text": "تسريب مياه في الحمام الطابق الثاني",
  "language": "ar",
  "departments": ["عام", "صيانة", "كهرباء", "سباكة"],
  "types": ["فني", "تفتيش", "أخرى"],
  "statuses": ["معلق", "قيد التنفيذ"]
}
```

**Response:**
```json
{
  "title": "تسريب مياه في الحمام",
  "description": "تم الإبلاغ عن تسريب مياه في حمام الطابق الثاني. يرجى إرسال فني سباكة للفحص والإصلاح.",
  "location": "الطابق الثاني",
  "type": "فني",
  "department": "سباكة",
  "status": "معلق"
}
```

## Notes

- This endpoint is separate from the existing `POST /ai/suggest` which generates descriptions from structured input (the reverse direction).
- The LLM prompt instructs the model to return JSON constrained to the provided valid values.
- The backend validates the response fields against the provided lists before returning — invalid values are set to null.
- Timeout matches the existing Ollama timeout (60 seconds).
