# Contract: POST /api/manuals/ask/stream

**Type**: Server-Sent Events (SSE) endpoint  
**Auth**: Bearer token (same as /manuals/ask)  
**Content-Type (response)**: text/event-stream

## Request

Same schema as POST /manuals/ask:

```json
{
  "question": "How do I inspect the landing gear?",
  "user_email": "user@example.com",
  "manual_id": null,
  "model": null,
  "history": [
    {"question": "previous q", "answer": "previous a"}
  ],
  "session_summary": null
}
```

| Field           | Type            | Required | Description                     |
|-----------------|-----------------|----------|---------------------------------|
| question        | string          | yes      | User's question (1-2000 chars)  |
| user_email      | string          | yes      | Authenticated user's email      |
| manual_id       | string or null  | no       | Filter to specific manual       |
| model           | string or null  | no       | Model override                  |
| history         | list of objects  | no       | Conversation history            |
| session_summary | string or null  | no       | Compressed session context      |

## Response: SSE Event Stream

### Phase 1: Token Events (0 or more)

```
data: How
\n
data:  do
\n
data:  you
\n
data:  inspect
\n
```

- Default SSE event type (no `event:` line).
- `data:` contains raw text fragment. NOT JSON.
- Concatenate all data values to build the full answer.
- May be empty if model produces no output (edge case).

### Phase 2: Metadata Event (exactly 1)

```
event: metadata
data: {"sources": [...], "grounded": true, "confidence": "high", "total_tokens": 342, "done": true, "provider_used": "local", "provider_display_name": "Local (Ollama)", "fallback_used": false, "is_verified": false, "verified_source": null, "latency_breakdown": {"embed_ms": 120, "hyde_ms": 450, "rewrite_ms": 200, "retrieval_ms": 300, "rerank_ms": 150, "generator_ms": 8500, "total_ms": 9720}, "session_summary": "User asked about landing gear inspection...", "manuals_consulted": [], "agentic": false, "tools_used": [], "retrieval_info": null}
\n
```

- Event type: `metadata`
- Data is a single JSON object on one line.
- `done: true` always present — signals stream completion.
- Connection closes after this event.

### Error Event (at most 1, replaces metadata)

```
event: error
data: {"error": "generator_timeout", "message": "The assistant timed out. Please try again.", "partial": true}
\n
```

- Event type: `error`
- `partial: true` if some tokens were already sent.
- Connection closes after this event.

## Error Responses (non-streaming)

If the error occurs before streaming begins (e.g., bad request, auth failure), a standard HTTP JSON error is returned instead of an SSE stream:

| Status | Body                                                    | When                        |
|--------|---------------------------------------------------------|-----------------------------|
| 400    | `{"error": "question_required"}`                        | Empty question              |
| 400    | `{"error": "question_too_long", "limit": 2000}`        | Question exceeds 2000 chars |
| 401    | `{"error": "unauthorized"}`                             | Missing/invalid JWT         |
| 404    | `{"error": "manual_not_found"}`                         | Invalid manual_id filter    |
| 504    | `{"error": "embedder_unavailable", "message": "..."}`  | Embedding service down      |

## Trivial Input Bypass

If the question matches the trivial input pattern (greetings like "hi", "thanks", etc.), the endpoint returns the canned reply as a single data event + metadata, not a full stream. The metadata will include `"bypass": "greeting"`.

## Cancellation

Client closes the HTTP connection. Server detects disconnect and stops generation. No special event needed.
