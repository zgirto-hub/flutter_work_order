# API Contract: AI Suggest Description

**Endpoint**: `POST /api/ai/suggest`
**Auth**: None (internal-only endpoint)

## Request

**Content-Type**: `application/json`

```json
{
  "title": "Broken AC unit in Building A",
  "location": "Building A, Room 101",
  "type": "HVAC"
}
```

| Field    | Type   | Required | Constraints            |
|----------|--------|----------|------------------------|
| title    | string | Yes      | Non-empty after trim   |
| location | string | No       | May be null or empty   |
| type     | string | No       | May be null or empty   |

## Response

### 200 OK — Success

```json
{
  "description": "A malfunctioning air conditioning unit has been reported in Building A, Room 101. The HVAC system requires inspection and repair to restore proper climate control. Immediate attention is recommended to prevent further discomfort and potential equipment damage."
}
```

| Field       | Type   | Description                            |
|-------------|--------|----------------------------------------|
| description | string | Professional 2-4 sentence description  |

### 422 Unprocessable Entity — Validation Error

Returned when `title` is missing or empty.

```json
{
  "detail": [
    {
      "loc": ["body", "title"],
      "msg": "field required",
      "type": "value_error.missing"
    }
  ]
}
```

### 502 Bad Gateway — Model Error

Returned when Ollama returns an error or an empty/unusable response.

```json
{
  "detail": "AI model returned an empty response"
}
```

### 503 Service Unavailable — Ollama Unreachable

Returned when the backend cannot connect to Ollama or the request times out (60s).

```json
{
  "detail": "AI service is currently unavailable"
}
```

## Timeout Behavior

- Backend enforces a 60-second timeout on the Ollama HTTP call
- Frontend enforces a 65-second timeout on the HTTP call to the backend (buffer for network overhead)
- On timeout, backend returns 503; frontend shows floating snackbar error

## Preamble Stripping

The backend strips conversational filler from the AI response before returning. Lines starting with these prefixes (case-insensitive) are removed from the beginning of the response:
- "Here"
- "Sure"
- "Of course"
- "Certainly"
- "Below"
- "I'd"
- "I would"

If all lines are stripped, the original response is returned as-is (safety net).
