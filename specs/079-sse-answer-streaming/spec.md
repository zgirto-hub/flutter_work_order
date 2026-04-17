# Feature Specification: AI Assistant Answer Streaming (SSE)

**Feature Branch**: `079-sse-answer-streaming`  
**Created**: 2026-04-17  
**Status**: Draft  
**Input**: User description: "Stream LLM tokens from the backend to the Flutter frontend in real-time using Server-Sent Events (SSE), so the user sees words appearing as the model generates them."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Real-Time Answer Streaming (Priority: P1)

A user opens the AI Assistant, types a question about equipment maintenance, and submits it. Instead of waiting 15-60 seconds staring at a loading spinner before seeing the complete answer all at once, the user sees words appearing progressively within a few seconds of the retrieval phase completing. The experience feels conversational and responsive, similar to modern AI chat interfaces. Once the full answer has streamed in, source references and a confidence indicator appear below the answer.

**Why this priority**: This is the core value proposition of the feature. Without streaming delivery, no other story matters. Streaming directly addresses the perceived latency problem that makes the AI Assistant feel slow and unresponsive.

**Independent Test**: Can be fully tested by submitting any question to the AI Assistant and observing that tokens appear progressively rather than all at once. Delivers immediate perceived performance improvement.

**Acceptance Scenarios**:

1. **Given** a user is on the AI Assistant screen with no active query, **When** they type a question and tap "Ask", **Then** the first words of the answer begin appearing within 3 seconds of the retrieval phase completing, and text continues to accumulate smoothly until the full answer is displayed.
2. **Given** a question has been submitted and the retrieval phase is running, **When** the retrieval completes and streaming begins, **Then** a visual cursor/indicator shows that the answer is still being generated.
3. **Given** the answer has finished streaming completely, **When** the final metadata arrives, **Then** the streaming indicator disappears, and the source references panel and confidence badge become visible below the answer.

---

### User Story 2 - Mid-Stream Cancellation (Priority: P2)

A user submits a question but realizes they asked the wrong thing, or the answer is going in an irrelevant direction. They tap a "Stop" button to cancel the stream mid-generation. The answer text accumulated so far remains visible, the streaming indicator stops, and the input is re-enabled so they can ask a new question. No errors or broken UI states result from the cancellation.

**Why this priority**: Cancellation is essential for user control. Without it, users are locked into waiting for an irrelevant answer to finish streaming, which is worse than the current non-streaming experience where at least they can navigate away.

**Independent Test**: Can be tested by submitting a question, waiting for tokens to begin appearing, then tapping "Stop". The partial answer should remain visible and the UI should return to a ready state.

**Acceptance Scenarios**:

1. **Given** an answer is actively streaming with partial text visible, **When** the user taps the "Stop" button, **Then** streaming stops immediately, the partial answer text remains visible, the streaming indicator disappears, and the "Ask" button is re-enabled.
2. **Given** a user has cancelled a streaming answer, **When** they type a new question and tap "Ask", **Then** a new streaming session begins normally without any residual state from the cancelled query.

---

### User Story 3 - Graceful Error Handling During Streaming (Priority: P3)

A user submits a question and streaming begins, but partway through the connection drops (network issue, server restart, etc.). The user sees a clear error message indicating the stream was interrupted, along with whatever partial answer was received. They can retry the question without refreshing the page.

**Why this priority**: Error resilience ensures the streaming feature degrades gracefully rather than leaving users in a broken state. This is important for trust and usability but is lower priority than the core streaming and cancellation flows.

**Independent Test**: Can be tested by simulating a network interruption during an active stream (e.g., toggling airplane mode or killing the server mid-response). The UI should show an error state rather than hanging indefinitely.

**Acceptance Scenarios**:

1. **Given** an answer is actively streaming, **When** the connection is lost mid-stream, **Then** the partial answer text remains visible, an error message indicates the stream was interrupted, and the "Ask" button is re-enabled.
2. **Given** a stream error has occurred, **When** the user submits a new question, **Then** the new query streams normally without requiring a page refresh.

---

### Edge Cases

- What happens when the AI model returns an empty response (no tokens at all)?
- How does the system handle extremely long answers that produce thousands of tokens?
- What happens if the user navigates away from the AI Assistant screen while streaming is active?
- What happens when metadata arrives but sources list is empty?
- How does the system behave if the server sends malformed SSE events?
- What happens if the user rapidly submits multiple questions (double-tap)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST stream answer tokens progressively to the user interface as they are generated by the language model, rather than waiting for the complete response.
- **FR-002**: System MUST display a visual streaming indicator (e.g., blinking cursor) while tokens are actively arriving, and remove it when streaming completes.
- **FR-003**: System MUST display source references and confidence information only after the complete answer has been delivered, not during streaming.
- **FR-004**: System MUST provide a "Stop" control that allows the user to cancel an active stream at any time.
- **FR-005**: System MUST disable the question input and submit button while a stream is active, preventing duplicate submissions.
- **FR-006**: System MUST preserve all existing non-streaming question-answering functionality unchanged, ensuring backward compatibility for any callers relying on the original endpoint.
- **FR-007**: System MUST support streaming for all configured AI providers (both local and cloud-based models) without requiring the user to select a streaming mode.
- **FR-008**: System MUST handle connection failures during streaming gracefully, showing partial results and an error message rather than a blank or frozen screen.
- **FR-009**: System MUST use the same authentication mechanism for streaming as for non-streaming requests.
- **FR-010**: System MUST complete all retrieval and ranking stages before beginning to stream the generation output (retrieval is not streamed, only generation).

### Key Entities

- **Stream Event (Token)**: A fragment of the generated answer text, delivered incrementally as it is produced. Has no persistence; exists only in transit between server and client.
- **Stream Event (Metadata)**: A single event delivered after all tokens, containing source references (list of document citations), confidence score (0-1 float), total token count (integer), and a completion flag.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: First answer tokens appear on screen within 3 seconds of the retrieval phase completing, compared to the current 15-60 second full wait.
- **SC-002**: Text accumulates visibly and smoothly during streaming with no perceptible freezes or jumps of more than 1 second between visible token updates.
- **SC-003**: Cancelling a stream returns the UI to a ready state within 1 second, with no lingering errors or frozen elements.
- **SC-004**: 100% of questions that succeed on the non-streaming endpoint also succeed on the streaming endpoint, producing equivalent answer content.
- **SC-005**: Connection failures during streaming display an error message within 5 seconds of the interruption, without requiring a page refresh to recover.

## Assumptions

- Users access the AI Assistant via the PWA on modern browsers that support chunked HTTP responses and SSE parsing.
- The existing retrieval pipeline (query rewrite, HyDE, vector search, reranking) remains unchanged; only the final generation step switches to streaming delivery.
- The AI provider (local or cloud model) supports a streaming/iterative generation mode.
- Network conditions are generally stable; streaming is not expected to handle severe packet loss gracefully beyond basic timeout and error detection.
- Only the "Ask the AI" knowledge endpoint is in scope for streaming; other AI features (analytics, NL search) remain non-streaming.
- The existing authentication and authorization system applies identically to streaming requests.
