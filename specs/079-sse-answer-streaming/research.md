# Research: AI Assistant Answer Streaming (SSE)

**Feature Branch**: `079-sse-answer-streaming`  
**Date**: 2026-04-17

## R1: Generation Call Chain — Where to Insert Streaming

**Decision**: Add a parallel `generate_stream()` method alongside the existing `generate()` on every layer, keeping the non-streaming path completely unchanged.

**Rationale**: The generation call chain is:
1. `routers/manuals.py:ask_question` → `agentic_tools.run_agentic_loop`
2. → `manual_rag_service.ask` → `ai_providers.resolver.generate`
3. → `provider.generate()` → ollama_generator / gemini SDK / groq SDK / mistral SDK

Each layer returns a complete `str`. Rather than modifying this chain (risky — breaks existing callers), we add a new `generate_stream()` async generator at the provider base class, resolver, and ollama_generator levels. The new SSE endpoint short-circuits the agentic loop and calls the RAG pipeline stages (embed, rewrite, HyDE, retrieve, rerank) synchronously, then streams only the final generation.

**Alternatives considered**:
- Modify existing `generate()` to always stream internally, buffer for non-streaming callers. Rejected: too invasive, risk of breaking 4 providers + fallback logic.
- WebSocket instead of SSE. Rejected: SSE is simpler, unidirectional (server→client), sufficient for this use case, and doesn't require a persistent connection protocol.

## R2: Ollama Streaming API

**Decision**: Use `httpx.AsyncClient.stream("POST", ...)` with `stream: true` in the JSON body. Iterate NDJSON lines; each line is a JSON object with a `response` field containing the token chunk.

**Rationale**: Ollama's `/api/generate` endpoint natively supports streaming. When `stream: true`, it returns newline-delimited JSON (NDJSON). Each chunk: `{"response": "token", "done": false}`. Final chunk: `{"response": "", "done": true, "total_duration": ..., "eval_count": ...}`. The current code uses `stream: False` (ollama_generator.py:55).

**Implementation pattern**:
```python
async with httpx.AsyncClient(timeout=timeout) as client:
    async with client.stream("POST", f"{OLLAMA_URL}/api/generate",
        json={"model": model, "prompt": prompt, "stream": True, "keep_alive": keep_alive}
    ) as response:
        async for line in response.aiter_lines():
            data = json.loads(line)
            if data.get("response"):
                yield data["response"]
```

## R3: Gemini Streaming API

**Decision**: Use `generate_content_stream()` (sync) wrapped in `asyncio.to_thread()`, or the async variant if available. Each chunk has `.text` with the token fragment.

**Rationale**: The `google-generativeai` SDK's `GenerativeModel` supports:
- `generate_content(prompt, stream=True)` — returns an iterator of `GenerateContentResponse` chunks
- Each chunk has `.text` property with the generated text fragment
- The current code (gemini.py:60) uses `generate_content_async()` without streaming

**Implementation pattern**:
```python
model = GenerativeModel(model_id)
response = model.generate_content(full_prompt, stream=True)
for chunk in response:
    if chunk.text:
        yield chunk.text
```

## R4: SSE Delivery with sse-starlette

**Decision**: Add `sse-starlette>=1.6.1` to requirements.txt. Use `EventSourceResponse` for the streaming endpoint.

**Rationale**: FastAPI's built-in `StreamingResponse` can deliver SSE, but `sse-starlette` provides proper SSE framing (event types, data fields, retry directives) with less boilerplate. It is the standard choice for FastAPI SSE endpoints. Not currently in requirements.txt.

**SSE event format**:
- Token events: `data: <token_text>\n\n` (default event type)
- Metadata event: `event: metadata\ndata: {"sources": [...], "confidence": 0.85, "total_tokens": 342, "done": true, ...}\n\n`

## R5: Flutter SSE Client — Chunked HTTP Response Parsing

**Decision**: Use `http.Client().send(request)` to get a `StreamedResponse`, then parse the byte stream for SSE lines. No new package needed.

**Rationale**: The `http` package (already in pubspec) supports streaming via `Client.send(StreamedRequest)` → `StreamedResponse`. The response's `stream` property is a `ByteStream` that can be transformed line-by-line. SSE lines are parsed by checking for `data:` and `event:` prefixes.

**Implementation pattern**:
```dart
final client = http.Client();
final request = http.StreamedRequest('POST', uri);
// ... set headers, write body ...
final response = await client.send(request);
response.stream
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .listen((line) {
        if (line.startsWith('data: ')) {
            // token chunk or metadata JSON
        }
    });
```

## R6: Nginx Proxy Buffering

**Decision**: Add a dedicated `location = /api/manuals/ask/stream` block with `proxy_buffering off`, `proxy_cache off`, and `X-Accel-Buffering: no` header.

**Rationale**: Nginx buffers proxy responses by default. For SSE, this means tokens accumulate in Nginx's buffer and are delivered in bursts rather than in real-time. Setting `proxy_buffering off` disables this behavior for the SSE endpoint. This is a critical infrastructure requirement — without it, streaming is completely negated. The user explicitly called this out as a constraint.

## R7: Scope Limitation — Agentic Path Not Streamed

**Decision**: Only the non-agentic (direct RAG) path supports streaming in this spec. If the question triggers the agentic loop (`_needs_tools()` returns True), the SSE endpoint falls back to non-streaming behavior (runs the full agentic loop, then sends the complete answer as a single SSE data event followed by metadata).

**Rationale**: The agentic loop calls `generate()` multiple times (up to 3 iterations with tool calls). Streaming token-by-token across multiple LLM calls would require complex state management and would not match user expectations (they'd see partial tool-calling prompts). This is a reasonable v1 limitation. The user still gets the complete answer; they just don't see progressive tokens for agentic questions.

## R8: Fallback Behavior During Streaming

**Decision**: If the primary provider's streaming call fails, fall back to Ollama streaming (not non-streaming). If Ollama streaming also fails, send an SSE error event.

**Rationale**: The existing resolver has robust fallback logic (resolver.py:79-111). For streaming, we replicate this: try primary provider's `generate_stream()`, catch timeout/error, try Ollama's `generate_stream()`. If both fail, emit `event: error\ndata: {"message": "..."}\n\n`.

## R9: Groq and Mistral Streaming

**Decision**: Add `generate_stream()` to Groq and Mistral providers using their respective SDK streaming APIs.

**Rationale**: All 4 providers must support streaming (FR-007). Groq uses the OpenAI-compatible SDK with `stream=True`. Mistral uses the Mistral SDK with `stream=True`. Both return async iterators of chat completion chunks.

**Groq pattern**:
```python
stream = await client.chat.completions.create(..., stream=True)
async for chunk in stream:
    if chunk.choices[0].delta.content:
        yield chunk.choices[0].delta.content
```

**Mistral pattern**: Similar OpenAI-compatible streaming interface.
