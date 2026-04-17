# Quickstart: AI Assistant Answer Streaming (SSE)

**Feature Branch**: `079-sse-answer-streaming`

## What This Feature Does

Streams AI-generated answers token-by-token from the backend to the Flutter frontend using Server-Sent Events (SSE). Users see words appearing in real-time instead of waiting 15-60 seconds for the complete response.

## Key Files to Modify

### Backend
- `backend/requirements.txt` — Add `sse-starlette>=1.6.1`
- `backend/services/ai_providers/base.py` — Add `generate_stream()` abstract method
- `backend/services/ai_providers/local_ollama.py` — Implement Ollama streaming
- `backend/services/ai_providers/gemini.py` — Implement Gemini streaming
- `backend/services/ai_providers/groq.py` — Implement Groq streaming
- `backend/services/ai_providers/mistral.py` — Implement Mistral streaming
- `backend/services/ollama_generator.py` — Add `generate_stream()` async generator
- `backend/services/ai_providers/resolver.py` — Add `generate_stream()` with fallback
- `backend/services/manual_rag_service.py` — Add `ask_stream()` that yields tokens
- `backend/routers/manuals.py` — Add `POST /manuals/ask/stream` SSE endpoint

### Frontend
- `frontend/lib/services/manual_assistant_service.dart` — Add `askQuestionStream()` method
- `frontend/lib/screens/manual_assistant/chat_tab.dart` — Wire streaming into send flow
- `frontend/lib/screens/manual_assistant/widgets/answer_card.dart` — Support progressive text rendering

### Infrastructure
- `server/nginx/flutter_app.conf` — Add SSE location block with `proxy_buffering off`

## How to Test Locally

1. Start the backend: `cd backend && uvicorn main:app --reload`
2. Start the frontend: `cd frontend && flutter run -d chrome`
3. Open the AI Assistant tab, type a question
4. Observe tokens streaming in progressively
5. Test the Stop button mid-stream
6. Test with network interruption (DevTools → Network → Offline)

## Architecture Decision

The streaming path runs alongside the existing non-streaming endpoint — not a replacement. Both endpoints share the same RAG pipeline (embed → rewrite → HyDE → retrieve → rerank). Only the final generation step differs: non-streaming awaits the complete result, streaming yields token-by-token via SSE.

The agentic path (tool-calling questions) does not support progressive streaming in v1. If tools are needed, the full answer is generated first, then sent as a single SSE data event.
