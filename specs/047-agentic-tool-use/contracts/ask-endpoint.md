# Contract: POST /manuals/ask (Updated)

**Feature**: 047-agentic-tool-use

## Request (unchanged)

```
POST /manuals/ask
Content-Type: application/json

{
  "question": "string (required, max 2000 chars)",
  "manual_id": "string | null (optional UUID)",
  "user_email": "string (required)",
  "model": "string | null (optional)",
  "history": [{"question": "string", "answer": "string"}],
  "session_summary": "string | null"
}
```

## Response (extended — backward compatible)

Existing fields remain unchanged. New fields are additive.

```json
{
  "answer": "string",
  "grounded": true,
  "sources": [
    {
      "manual_title": "string",
      "chunk_text": "string",
      "distance": 0.45
    }
  ],
  "model": "gemma4:e2b",
  "duration_seconds": 12.3,
  "session_summary": "string | null",
  "manuals_consulted": ["Manual A", "Manual B"],
  "has_conflicts": false,

  "agentic": true,
  "tools_used": [
    {
      "tool_name": "work_orders",
      "success": true,
      "has_data": true
    },
    {
      "tool_name": "manuals",
      "success": true,
      "has_data": true
    },
    {
      "tool_name": "compare",
      "success": true,
      "has_data": true
    }
  ]
}
```

### New fields

| Field | Type | Present | Description |
|-------|------|---------|-------------|
| `agentic` | bool | Always | `true` if the agentic loop was used, `false` if question was handled by direct pipeline |
| `tools_used` | list | Only when `agentic: true` | Array of tool call summaries |

### tools_used entry

| Field | Type | Description |
|-------|------|-------------|
| `tool_name` | string | `work_orders`, `manuals`, or `compare` |
| `success` | bool | Whether tool executed without error |
| `has_data` | bool | Whether tool returned non-empty results |

## Error responses (unchanged)

All existing error responses remain the same. No new error codes.
