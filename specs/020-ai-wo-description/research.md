# Research: AI-Assisted Work Order Description

**Feature**: 020-ai-wo-description
**Date**: 2026-04-05

## Research Tasks

### 1. Ollama HTTP API for Chat Completions

**Decision**: Use Ollama's `/api/generate` endpoint with `stream: false`

**Rationale**: The `/api/generate` endpoint is the simplest for single-turn text generation. With `stream: false`, the entire response is returned in one JSON payload containing a `response` field. No need for chat history or multi-turn conversation.

**Request format**:
```json
POST http://localhost:11434/api/generate
{
  "model": "gemma4:e2b",
  "prompt": "...",
  "stream": false
}
```

**Response format**:
```json
{
  "model": "gemma4:e2b",
  "response": "The generated text...",
  "done": true
}
```

**Alternatives considered**:
- `/api/chat` — more complex, requires message array format, unnecessary for single-turn generation
- Streaming (`stream: true`) — explicitly out of scope per spec

### 2. httpx Async Client for Backend-to-Ollama Communication

**Decision**: Use `httpx.AsyncClient` with a 60-second timeout

**Rationale**: httpx is already in `requirements.txt` (v0.28.1) and supports async natively, which aligns with FastAPI's async endpoints. The existing codebase uses `urllib` for OneSignal calls (synchronous), but httpx is the better choice here because the Ollama call may take up to 60 seconds and blocking the event loop would degrade other endpoint responsiveness.

**Pattern**:
```python
async with httpx.AsyncClient(timeout=60.0) as client:
    resp = await client.post(OLLAMA_URL, json=payload)
```

**Error handling**:
- `httpx.ConnectError` / `httpx.ConnectTimeout` → HTTP 503
- `httpx.ReadTimeout` → HTTP 503 with timeout message
- Ollama returns non-200 → HTTP 502

**Alternatives considered**:
- `urllib.request` (used elsewhere in codebase) — synchronous, would block event loop for up to 60s
- `aiohttp` — not in requirements, httpx already available

### 3. Preamble Stripping Strategy

**Decision**: Strip leading lines that start with common conversational prefixes

**Rationale**: Gemma models occasionally prefix responses with filler like "Here is a professional description:" or "Sure, here's a description for your work order:". These should be removed before returning to the user.

**Implementation**:
- Split response into lines
- Drop leading lines matching prefixes: "Here", "Sure", "Of course", "Certainly", "Below", "I'd"
- Also strip lines that are empty after prefix removal
- Rejoin remaining lines
- If result is empty after stripping, return original (safety net)

**Alternatives considered**:
- Regex-based approach — harder to maintain, same outcome
- System prompt to prevent preamble — unreliable with smaller models, defense-in-depth approach is better (use system prompt AND strip)

### 4. Flutter Service HTTP Pattern

**Decision**: Follow existing `NotificationService` pattern — stateless class, `http.post()`, `AppConfig.baseUrl`

**Rationale**: All existing services use the same pattern: import `http` package, construct URL from `AppConfig.baseUrl`, parse JSON response. No need to introduce new patterns.

**Pattern**:
```dart
class AiAssistService {
  Future<String> suggestDescription({required String title, String? location, String? type}) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/ai/suggest'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({...}),
    ).timeout(Duration(seconds: 65)); // slightly longer than backend timeout
    // parse response
  }
}
```

**Alternatives considered**:
- Using `httpx` Dart package — not in project, unnecessary
- Adding retry logic — out of scope per YAGNI

### 5. UI Integration Point

**Decision**: Add Suggest button as a `TextButton.icon` positioned after the description field label, visible only when `canEdit && _roleLoaded`

**Rationale**: The form already uses `TextButton.icon` for secondary actions (e.g., delete). The Suggest button is a secondary action that enhances the description field without disrupting the form layout. Positioning it near the description field makes it discoverable.

**Button states**:
- Hidden: `!canEdit || !_roleLoaded`
- Disabled: `titleController.text.trim().isEmpty || _aiLoading`
- Loading: spinner replaces icon, text changes to "Suggesting..."
- Normal: magic wand icon + "Suggest" label

**Alternatives considered**:
- Icon-only button — less discoverable
- Floating action button — too prominent for a secondary feature
- Inline within the TextFormField decoration — would complicate the field widget
