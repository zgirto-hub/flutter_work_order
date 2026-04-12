# Quickstart: Rolling Session Summary

**Feature**: 045-rolling-session-summary  
**Date**: 2026-04-13

## What This Feature Does

Adds intelligent conversation memory to the manual assistant. Instead of abruptly dropping old conversation turns after 10, the system compresses older turns into a concise summary that preserves technical facts. Users get better context retention in long troubleshooting sessions.

## Architecture

```
Frontend (Flutter)                    Backend (FastAPI)
─────────────────                    ─────────────────
ChatTab sends ALL                    manuals.py receives history
history turns +                      + session_summary
optional session_summary                    │
        │                                   ▼
        │                            manual_rag_service.ask()
        ▼                                   │
  POST /manuals/ask                  ┌──────┴──────────────────┐
  {history: [...],                   │ 1. Query rewrite (last 3)│
   session_summary: "..."}          │ 2. HyDE generation       │
                                     │ 3. Embedding             │
        ▲                            │ 4. Vector search (top 5) │
        │                            │ 5. Chunk reranking       │
  Response includes                  │ 6. ★ COMPRESS HISTORY ★  │
  {answer: "...",                    │ 7. Build prompt          │
   session_summary: "..."}          │ 8. Generate answer       │
        │                            │ 9. Groundedness check    │
  ChatTab stores                     └─────────────────────────┘
  _sessionSummary
```

## Key Files to Modify

| File | Change |
|------|--------|
| `backend/services/manual_rag_service.py` | Add `_compress_history()` function; update `_build_prompt()` to accept memory; integrate compression into `ask()` pipeline; return `session_summary` in response |
| `backend/routers/manuals.py` | Add optional `session_summary` field to `AskRequest`; include `session_summary` in response JSON |
| `frontend/lib/screens/manual_assistant/chat_tab.dart` | Remove `.sublist(_history.length - 10)` truncation; store `_sessionSummary` from response; send it back in requests |
| `frontend/lib/services/manual_assistant_service.dart` | Add `sessionSummary` parameter to `askQuestion()`; parse it from response |

## How Compression Works

1. Frontend sends all conversation history + optional `session_summary` from previous response
2. Backend checks: if `len(history) > 8`, compression is needed
3. If `session_summary` was provided and covers the old turns: reuse it (no LLM call)
4. If no summary or new turns aged out: compress (existing summary + new old turns) via Ollama
5. Result: 3-4 sentence summary string
6. Prompt assembly: `[system] → [chunks] → [MEMORY: summary] → [HISTORY: last 4 turns] → [QUESTION]`
7. Response includes `session_summary` — frontend stores it for next request
8. If compression fails: fall back to `history[-10:]` (current behavior)

## Compression Prompt Template

```
Summarize the following technical conversation between a user and an assistant.
Produce exactly 3-4 sentences. Preserve ALL technical facts: part numbers,
specifications, procedures, measurements, and component names.
Do not add information not present in the conversation.

CONVERSATION:
User: {turn1.question}
Assistant: {turn1.answer}
...

SUMMARY:
```

## Testing

1. Start a chat session in the manual assistant
2. Ask 9+ questions about a specific technical topic (e.g., hydraulic system maintenance)
3. After the 9th question, verify the assistant still remembers details from early questions
4. Check backend logs for `[COMPRESS]` log entries showing the generated summary
5. Test failure fallback: stop Ollama, ask a question in a 10+ turn conversation, verify it still works (falls back to last 10 turns)
