# Tasks: AI Assistant Answer Streaming (SSE)

**Input**: Design documents from `/specs/079-sse-answer-streaming/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Not explicitly requested. Test tasks omitted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Web app**: `backend/` (Python/FastAPI), `frontend/` (Flutter/Dart), `server/nginx/` (Nginx config)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add the sse-starlette dependency and verify the project builds.

- [ ] T001 Add `sse-starlette>=1.6.1` to `backend/requirements.txt`. Place it alphabetically near the existing `starlette` entry. Do NOT remove or modify any existing dependencies.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add streaming capability to the AI provider layer (base class, all 4 providers, resolver). These are blocking prerequisites — the SSE endpoint and frontend streaming depend on this layer being complete.

**CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T002 Add `generate_stream()` abstract method to the provider base class in `backend/services/ai_providers/base.py`. Add this method to the `AIProvider` ABC:

```python
from typing import AsyncIterator

async def generate_stream(self, prompt: str, context_chunks: List[str]) -> AsyncIterator[str]:
    """Yield answer tokens one chunk at a time. Default falls back to non-streaming."""
    answer = await self.generate(prompt, context_chunks)
    yield answer
```

Make it a concrete method with a default fallback (not abstract), so existing providers continue to work without modification. Providers that support native streaming will override it.

- [ ] T003 [P] Add `generate_stream()` async generator to `backend/services/ollama_generator.py`. Add a new function below the existing `generate()`:

```python
async def generate_stream(prompt: str, model: str | None = None, timeout: float = 180.0):
    """Yield token chunks from Ollama streaming API."""
    use_model = model or get_default_model()
    async with httpx.AsyncClient(timeout=timeout) as client:
        async with client.stream(
            "POST",
            f"{OLLAMA_URL}/api/generate",
            json={"model": use_model, "prompt": prompt, "stream": True, "keep_alive": OLLAMA_KEEP_ALIVE},
        ) as response:
            response.raise_for_status()
            async for line in response.aiter_lines():
                if not line.strip():
                    continue
                data = json.loads(line)
                token = data.get("response", "")
                if token:
                    yield token
                if data.get("done"):
                    break
```

Handle `httpx.TimeoutException` → raise `GeneratorTimeoutError`. Handle status 500/404 → raise `GeneratorModelError` (same patterns as existing `_generate_direct`).

- [ ] T004 [P] Implement `generate_stream()` override in `backend/services/ai_providers/local_ollama.py`. Override the base class method to delegate to the new `ollama_generator.generate_stream()`:

```python
async def generate_stream(self, prompt: str, context_chunks: List[str]):
    from services.ollama_generator import generate_stream as ollama_stream
    async for token in ollama_stream(prompt):
        yield token
```

- [ ] T005 [P] Implement `generate_stream()` override in `backend/services/ai_providers/gemini.py`. Override the base class method using Gemini's streaming API. Build the `full_prompt` the same way as the existing `generate()` method (reuse the same prompt template with context chunks). Then use `generate_content()` with `stream=True`:

```python
async def generate_stream(self, prompt: str, context_chunks: List[str]):
    if not self._api_key:
        raise GeneratorModelError("gemini", "missing_credentials")
    from google.generativeai import GenerativeModel
    import asyncio
    model_id = await self._get_model_id()
    model = GenerativeModel(model_id)
    full_prompt = (  # same prompt construction as generate()
        "You are a technical synthesis expert for civil aviation maintenance.\n"
        "You have received relevant information from technical manuals below.\n\n"
        + "\n\n".join(f"[Context {i + 1}]\n{chunk}" for i, chunk in enumerate(context_chunks))
        + f"\n\nQUESTION: {prompt}\n\n"
        + "Please provide a clear, accurate answer based on the context provided."
    )
    # Gemini sync streaming wrapped in thread
    def _stream():
        return model.generate_content(full_prompt, stream=True)
    response = await asyncio.to_thread(_stream)
    for chunk in response:
        if chunk.text:
            yield chunk.text
```

Handle exceptions the same way as the existing `generate()` — scrub API key from error messages, detect quota errors.

- [ ] T006 [P] Implement `generate_stream()` override in `backend/services/ai_providers/groq.py`. Override using the Groq SDK's streaming chat completions. Read the existing `generate()` method first to match the prompt format and error handling. Pattern:

```python
async def generate_stream(self, prompt: str, context_chunks: List[str]):
    if not self._api_key:
        raise GeneratorModelError("groq", "missing_credentials")
    from groq import AsyncGroq
    full_prompt = (  # same construction as generate()
        ...
    )
    client = AsyncGroq(api_key=self._api_key)
    stream = await client.chat.completions.create(
        model=GROQ_MODEL,
        messages=[{"role": "user", "content": full_prompt}],
        stream=True,
    )
    async for chunk in stream:
        content = chunk.choices[0].delta.content
        if content:
            yield content
```

- [ ] T007 [P] Implement `generate_stream()` override in `backend/services/ai_providers/mistral.py`. Override using the Mistral SDK's streaming chat completions. Read the existing `generate()` method first to match the prompt format and error handling. Follow the same pattern as Groq (OpenAI-compatible streaming).

- [ ] T008 Add `generate_stream()` to the resolver in `backend/services/ai_providers/resolver.py`. This is the main function the endpoint will call. It must:
  1. Resolve the active provider via `get_active_provider_key()`
  2. Try the provider's `generate_stream()` with a timeout on the first chunk (30s)
  3. Yield tokens as they arrive
  4. On failure: if not already Ollama, fall back to Ollama's `generate_stream()`
  5. Track `generator_ms` in `latency_breakdown` (start timer before first yield, record after last yield)
  6. Return fallback info via a mutable dict parameter (since generators can't return tuples)

Signature:
```python
async def generate_stream(
    prompt: str,
    context_chunks: List[str],
    user_email: str | None = None,
    latency_breakdown: dict | None = None,
    stream_meta: dict | None = None,  # mutable dict to receive provider_key, display_name, fallback_used, fallback_info
) -> AsyncIterator[str]:
```

The `stream_meta` dict gets populated with `provider_key`, `display_name`, `fallback_used`, `fallback_info` so the caller can include them in the metadata event. Initialize `stream_meta` keys at the start, update them if fallback occurs.

**Checkpoint**: Provider streaming layer complete. All 4 providers can stream tokens. Resolver handles fallback.

---

## Phase 3: User Story 1 — Real-Time Answer Streaming (Priority: P1) MVP

**Goal**: User submits a question and sees tokens appearing progressively in the AnswerCard.

**Independent Test**: Submit a question in the AI Assistant. Tokens should appear within ~3s of retrieval completing, accumulating smoothly until the full answer is displayed. Sources panel appears after streaming completes.

### Implementation for User Story 1

- [ ] T009 [US1] Add `ask_stream()` async generator to `backend/services/manual_rag_service.py`. This function runs the existing retrieval pipeline (embed, rewrite, HyDE, retrieve, rerank) to completion first, collecting all the metadata (sources, grounded, confidence, retrieval_info, etc.). Then instead of calling `resolver.generate()`, it calls `resolver.generate_stream()` and yields tokens. After all tokens are yielded, it yields a final `None` sentinel to signal completion. The caller collects metadata from a mutable dict.

Place the function near the existing `ask()` function. It should accept the same parameters as `ask()`. For the retrieval pipeline stages, extract them into a shared helper or duplicate the retrieval logic (prefer extraction if clean). The key difference: instead of `answer = await resolver.generate(prompt, chunks, ...)`, do:
```python
stream_meta = {}
async for token in resolver.generate_stream(prompt, chunks, user_email, latency_breakdown, stream_meta):
    yield token
# After streaming, caller reads stream_meta for provider info
```

The function should also handle the trivial input bypass (greeting detection) — if trivial, yield the canned reply as a single token and return. Similarly handle the validated_qa fast path — if a validated match is found above threshold, stream the validated answer generation.

Return metadata via a mutable dict parameter (same pattern as resolver).

- [ ] T010 [US1] Add the SSE endpoint `POST /manuals/ask/stream` in `backend/routers/manuals.py`. Add a new route handler below the existing `ask_question` handler. Use `sse_starlette.sse.EventSourceResponse` for SSE delivery.

The endpoint must:
1. Parse and validate the request (same validation as existing `ask_question`: empty check, length check, manual_id check)
2. Auth: check JWT bearer token the same way as the existing endpoint
3. Call `manual_rag_service.ask_stream()` to get the async generator
4. Wrap the generator in an async function that yields SSE events:
   - For each token: yield `{"data": token}` (default event type)
   - After all tokens: yield `{"event": "metadata", "data": json.dumps(metadata_dict)}` where metadata_dict contains sources, grounded, confidence, total_tokens, done=True, provider_used, provider_display_name, fallback_used, is_verified, verified_source, latency_breakdown, session_summary, manuals_consulted, agentic, tools_used, retrieval_info
5. Handle errors: if the generation fails mid-stream, yield `{"event": "error", "data": json.dumps({"error": "...", "message": "...", "partial": True/False})}`
6. Handle agentic path: if `agentic_tools._needs_tools(question)` returns True, run the full agentic loop (non-streaming), then send the complete answer as a single data event + metadata event
7. Log activity the same way as the existing endpoint

Important: Import `EventSourceResponse` from `sse_starlette.sse`. The response type is `EventSourceResponse(event_generator())`. Set `media_type="text/event-stream"`.

- [ ] T011 [US1] Add `askQuestionStream()` method to `frontend/lib/services/manual_assistant_service.dart`. This method opens a streaming HTTP connection to the new endpoint and exposes SSE events. It should:

1. Build the same request body as the existing `askQuestion()` method
2. Get the auth token the same way
3. Create an `http.Request('POST', uri)` with the body and headers
4. Use `http.Client().send(request)` to get a `StreamedResponse`
5. Transform the response stream: `response.stream.transform(utf8.decoder).transform(const LineSplitter())`
6. Parse SSE lines:
   - Lines starting with `data: ` → extract the data payload
   - Lines starting with `event: ` → track the event type for the next data line
   - Empty lines → end of an event (SSE spec)
7. Return a custom stream controller that emits objects representing either token chunks (String) or metadata (Map)

Suggested approach — create a helper class or use a sealed class:
```dart
class SseEvent {
  final String? token;        // non-null for token events
  final Map<String, dynamic>? metadata;  // non-null for metadata event
  final String? error;        // non-null for error event
  SseEvent.token(this.token) : metadata = null, error = null;
  SseEvent.metadata(this.metadata) : token = null, error = null;
  SseEvent.error(this.error) : token = null, metadata = null;
}
```

The method signature: `Stream<SseEvent> askQuestionStream(String question, String? manualIdFilter, {required String userEmail, String? model, List<Map<String, String>>? history, String? sessionSummary})`

Also expose a method to cancel the stream (closes the `http.Client`).

- [ ] T012 [US1] Update `frontend/lib/screens/manual_assistant/chat_tab.dart` to use streaming. Modify the `_sendQuestion()` method to:

1. Add a new state field: `bool _streaming = false;` and `http.Client? _activeClient;` for cancellation
2. When the user sends a question:
   - Add a `ChatMessage` with `loading: true` (same as current)
   - Call `_service.askQuestionStream(...)` instead of `askQuestion()`
   - Set `_streaming = true`
   - As tokens arrive, update the last message's answer text progressively using `setState()`
   - Create a partial `ManualQaAnswer` with just the answer text during streaming
   - When metadata arrives, create the full `ManualQaAnswer` from metadata + accumulated answer text
   - Set `_streaming = false`, `_loading = false`
3. Error handling: on stream error, show error message same as current
4. The loading indicator should transition from spinner (during retrieval) to streaming text (once first token arrives)

Also modify the build method:
- During `_streaming`: show the accumulated answer text in the `AnswerCard` area with a blinking cursor at the end
- After metadata: show the full `AnswerCard` with sources, confidence, etc.
- While `_loading && !_streaming`: show the existing loading spinner

- [ ] T013 [US1] Update `frontend/lib/screens/manual_assistant/widgets/answer_card.dart` to support progressive text rendering. Add an optional `isStreaming` parameter:

```dart
class AnswerCard extends StatefulWidget {
  final ManualQaAnswer answer;
  final String questionText;
  final Function(String rating)? onRate;
  final bool isStreaming;  // NEW

  const AnswerCard({
    super.key,
    required this.answer,
    this.questionText = '',
    this.onRate,
    this.isStreaming = false,  // NEW
  });
```

When `isStreaming` is true:
- Show the answer text as-is (it's being built up progressively by the parent)
- Append a blinking cursor indicator (a small animated `|` or `▊` character) after the text
- Hide the sources expansion tile, rating controls, and latency footer (they'll appear when streaming completes)
- Hide the verified badge

When `isStreaming` is false: render everything exactly as it does today (no changes to existing behavior).

For the blinking cursor, use a simple `AnimatedOpacity` or `AnimationController` that toggles opacity between 0 and 1 on a 500ms interval.

- [ ] T014 [US1] Add the Nginx SSE location block in `server/nginx/flutter_app.conf`. Add a new location block BEFORE the existing `location = /api/manuals/ask` block (so it appears above it in the file). The new block must be for the exact path `/api/manuals/ask/stream`:

```nginx
# SSE streaming for Ask-the-AI — requires proxy buffering disabled
location = /api/manuals/ask/stream {
    proxy_pass http://127.0.0.1:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Connection '';
    proxy_http_version 1.1;

    # CRITICAL: disable buffering for SSE
    proxy_buffering off;
    proxy_cache off;
    add_header X-Accel-Buffering "no" always;

    add_header Access-Control-Allow-Origin "*" always;
    add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
    add_header Pragma "no-cache" always;

    if ($request_method = "OPTIONS") {
        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Allow-Methods "POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "*" always;
        add_header Content-Length 0;
        return 204;
    }

    proxy_connect_timeout 10s;
    proxy_send_timeout    300s;
    proxy_read_timeout    300s;
}
```

Key SSE-specific directives: `proxy_buffering off`, `proxy_cache off`, `X-Accel-Buffering: no`, `Connection ''`, `proxy_http_version 1.1`.

**Checkpoint**: User Story 1 complete. User can submit a question and see tokens streaming progressively. Sources appear after completion. The non-streaming endpoint is untouched.

---

## Phase 4: User Story 2 — Mid-Stream Cancellation (Priority: P2)

**Goal**: User can tap a "Stop" button to cancel streaming mid-generation.

**Independent Test**: Submit a question, wait for tokens to appear, tap Stop. Partial answer remains visible, UI returns to ready state.

### Implementation for User Story 2

- [ ] T015 [US2] Add cancel/stop button to the chat UI in `frontend/lib/screens/manual_assistant/chat_tab.dart`. Modify the input area at the bottom of the screen:

1. When `_streaming` is true, replace the "Ask" (send) button with a "Stop" button (red square icon, like media stop)
2. The "Stop" button's `onPressed` calls a `_cancelStream()` method that:
   - Closes the `_activeClient` (the `http.Client` used for the streaming request)
   - Sets `_streaming = false`, `_loading = false`
   - Keeps the current partial answer text in the `ChatMessage` (do not clear it)
   - Creates a `ManualQaAnswer` from the partial text with sensible defaults (empty sources, grounded=false)
   - Updates the `_messages` list with the partial answer
   - Re-enables the text input and Ask button
3. The text input should be disabled (`enabled: !_loading`) during streaming, same as during loading
4. After cancellation, the user can immediately type and submit a new question

- [ ] T016 [US2] Ensure clean cancellation on the Dart side in `frontend/lib/services/manual_assistant_service.dart`. When the `http.Client` is closed mid-stream:
  - The `StreamedResponse.stream` should emit a done event or error
  - The stream controller in `askQuestionStream()` must handle `ClientException` or similar without throwing an unhandled error
  - Add a `cancel()` method that closes the active client and cleans up the stream subscription
  - Ensure no dangling `Future`s or listeners after cancel

**Checkpoint**: User Story 2 complete. Users can cancel streaming at any time. Partial answer is preserved.

---

## Phase 5: User Story 3 — Graceful Error Handling During Streaming (Priority: P3)

**Goal**: Connection failures during streaming show partial results and an error message, not a frozen screen.

**Independent Test**: Start a question, then simulate network loss (DevTools → Offline). Error message should appear, partial answer preserved, Ask button re-enabled.

### Implementation for User Story 3

- [ ] T017 [US3] Add error event handling to the SSE parser in `frontend/lib/services/manual_assistant_service.dart`. When the stream receives an `event: error` SSE event, parse the JSON data and emit an `SseEvent.error(message)` through the stream. When the HTTP connection drops unexpectedly (socket error, timeout), also emit an error event with a generic "Connection lost" message. Ensure the stream controller is properly closed after emitting the error.

- [ ] T018 [US3] Handle streaming errors in the chat UI in `frontend/lib/screens/manual_assistant/chat_tab.dart`. In the stream listener:

1. When an `SseEvent.error` is received:
   - Keep the partial answer text visible (if any tokens were received)
   - Show an error banner/message below the partial answer (e.g., amber/red container with "Stream interrupted: {message}. Tap Ask to retry.")
   - Set `_streaming = false`, `_loading = false`
   - Re-enable the Ask button and text input
2. When the stream completes without a metadata event (unexpected disconnect):
   - Same behavior as error — show a "Connection lost" message
   - Preserve partial text
3. After an error, submitting a new question should work normally without page refresh
4. Update the `ChatMessage` model if needed to support a partial answer + error state simultaneously (e.g., add an `error` field that can coexist with a non-null `answer`)

**Checkpoint**: All user stories complete. Streaming works, cancellation works, error recovery works.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases, audit logging, and cleanup.

- [ ] T019 [P] Handle edge cases in `backend/routers/manuals.py` SSE endpoint: empty model response (no tokens at all) should send a "No answer generated" data event + metadata with empty answer. Rapid resubmission is already handled by frontend disabling the input during streaming.

- [ ] T020 [P] Ensure activity logging in the SSE endpoint in `backend/routers/manuals.py` matches the existing endpoint: call `log_activity()` with the same parameters (user_email, category="file", action="asked_manual", etc.) and log fallback events the same way.

- [ ] T021 [P] Handle navigation-away cleanup in `frontend/lib/screens/manual_assistant/chat_tab.dart`. In the `dispose()` method, if `_streaming` is true, close the `_activeClient` to abort the stream. This prevents orphaned HTTP connections when the user navigates to a different screen.

- [ ] T022 Copy the updated Nginx config to `nginx_flutter_app.conf` at repository root (this is the duplicate copy). Ensure both `server/nginx/flutter_app.conf` and `nginx_flutter_app.conf` have the identical SSE location block added in T014.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on T001 (sse-starlette in requirements) — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion (all provider streaming must work)
- **User Story 2 (Phase 4)**: Depends on Phase 3 (T012 — chat_tab streaming must exist to add cancel button)
- **User Story 3 (Phase 5)**: Depends on Phase 3 (T011 — SSE parser must exist to add error handling)
- **Polish (Phase 6)**: Depends on all user stories

### User Story Dependencies

- **User Story 1 (P1)**: Depends only on Foundational phase — this is the MVP
- **User Story 2 (P2)**: Depends on US1 (extends the streaming UI with cancel)
- **User Story 3 (P3)**: Depends on US1 (extends the SSE parser with error handling)
- US2 and US3 are independent of each other and can be done in parallel after US1

### Within Each Phase

- T003, T004, T005, T006, T007 are all [P] — different provider files, can be done in parallel
- T009 and T014 are independent of each other (backend service vs nginx config)
- T011 and T014 are independent (frontend service vs nginx config)

### Parallel Opportunities

```
Phase 2 parallelism:
  T003 + T004 + T005 + T006 + T007 (all provider streaming — different files)
  Then T008 (resolver depends on providers)

Phase 3 parallelism:
  T009 (backend RAG stream) + T014 (nginx config) — independent
  T011 (frontend service) depends on T010 (endpoint must exist)
  T012 + T013 — depend on T011 (need the service method)
```

---

## Parallel Example: Foundational Phase

```
# Launch all provider streaming tasks together (different files):
Task T003: "Add generate_stream() to backend/services/ollama_generator.py"
Task T004: "Implement generate_stream() in backend/services/ai_providers/local_ollama.py"
Task T005: "Implement generate_stream() in backend/services/ai_providers/gemini.py"
Task T006: "Implement generate_stream() in backend/services/ai_providers/groq.py"
Task T007: "Implement generate_stream() in backend/services/ai_providers/mistral.py"

# Then sequentially:
Task T008: "Add generate_stream() to resolver (depends on all providers)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002-T008) — provider streaming layer
3. Complete Phase 3: User Story 1 (T009-T014) — full streaming end-to-end
4. **STOP and VALIDATE**: Test streaming in browser, verify tokens appear progressively
5. Deploy if ready — cancellation and error handling can follow

### Incremental Delivery

1. Setup + Foundational → streaming infrastructure ready
2. Add User Story 1 → Test streaming → Deploy (MVP!)
3. Add User Story 2 → Test cancellation → Deploy
4. Add User Story 3 → Test error recovery → Deploy
5. Polish → Edge cases, logging, cleanup → Final deploy

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- The non-streaming endpoint `/manuals/ask` must remain untouched throughout — do not modify its behavior
- `sse-starlette` must be installed on the server before deployment (`pip install -r requirements.txt`)
- Nginx config must be deployed and reloaded (`sudo nginx -t && sudo systemctl reload nginx`) for SSE to work in production
