# Data Model: AI Assistant Answer Streaming (SSE)

**Feature Branch**: `079-sse-answer-streaming`  
**Date**: 2026-04-17

## Entities

This feature introduces no persistent database entities. All data is transient (in-flight only).

### Stream Token Event (transient)

A single fragment of generated answer text delivered from server to client during active streaming.

| Field    | Type   | Description                        |
|----------|--------|------------------------------------|
| data     | string | Raw text fragment (1+ characters)  |

- No persistence. Exists only in the SSE event stream.
- Delivered as `data: <text>\n\n` in SSE format.
- Multiple token events are sent per answer (one per model output chunk).

### Stream Metadata Event (transient)

A single terminal event sent after all token events, containing answer metadata.

| Field                  | Type          | Description                                    |
|------------------------|---------------|------------------------------------------------|
| sources                | list of dict  | Retrieved source chunks (same schema as existing /manuals/ask `sources` field) |
| grounded               | bool          | Whether the answer was grounded in retrieved context |
| confidence             | string        | "high", "medium", or "low"                     |
| total_tokens           | int           | Total tokens generated in the answer           |
| done                   | bool          | Always `true` — signals stream completion      |
| provider_used          | string        | Provider key ("local", "gemini", "groq", "mistral") |
| provider_display_name  | string        | Human-readable provider name                   |
| fallback_used          | bool          | Whether fallback to Ollama was triggered        |
| is_verified            | bool          | Whether a validated QA match was used           |
| verified_source        | dict or null  | Verified QA source details if applicable        |
| latency_breakdown      | dict          | Same schema as existing endpoint (embed_ms, hyde_ms, etc.) |
| session_summary        | string or null| Updated session summary for conversation memory |
| manuals_consulted      | list of dict  | Manuals used in synthesis                       |
| agentic                | bool          | Whether agentic tools were used                 |
| tools_used             | list of dict  | Tool call details if agentic                    |
| retrieval_info         | dict or null  | System detection and filter info                |

- Delivered as `event: metadata\ndata: <json>\n\n` in SSE format.
- Exactly one metadata event per stream.
- Sent only after all token events have been emitted.

### Stream Error Event (transient)

Sent when the generation fails mid-stream or cannot start.

| Field   | Type   | Description                              |
|---------|--------|------------------------------------------|
| error   | string | Error code (e.g., "generator_timeout")   |
| message | string | Human-readable error message             |
| partial | bool   | Whether partial answer was already sent  |

- Delivered as `event: error\ndata: <json>\n\n` in SSE format.
- At most one error event per stream, terminates the connection.

## Database Changes

None. No migrations required.

## State Transitions

Stream lifecycle (client-side):

```
idle → loading (retrieval) → streaming (tokens arriving) → complete (metadata received)
                                    ↓                            ↓
                              cancelled (user stop)        error (connection lost)
```

- `idle`: No active query. Ask button enabled.
- `loading`: Question submitted, retrieval pipeline running. Spinner visible.
- `streaming`: Tokens arriving. Blinking cursor visible. Stop button enabled.
- `complete`: Metadata received. Sources panel visible. Ask button re-enabled.
- `cancelled`: User tapped Stop. Partial answer visible. Ask button re-enabled.
- `error`: Connection failed. Error message visible. Ask button re-enabled.
