# Feature Specification: Rolling Session Summary

**Feature Branch**: `045-rolling-session-summary`  
**Created**: 2026-04-13  
**Status**: Draft  
**Input**: User description: "Rolling session summary (memory compression) for the manual assistant AI pipeline. When conversation history exceeds 8 turns, compress the oldest turns into a 3-4 sentence summary using Gemma via Ollama, preserving all technical facts and topics discussed. Keep the summary as a 'memory' field and only send the last 4 raw turns to the prompt. This replaces the current approach of sending raw last 10 turns and abruptly dropping old context."

## Clarifications

### Session 2026-04-13

- Q: Should the frontend continue sending only the last 10 turns, or send all history turns? → A: Frontend sends all history turns (remove sublist truncation); backend handles compression.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Seamless Long Conversations (Priority: P1)

A technician is troubleshooting a complex engine issue using the manual assistant. They ask 12+ questions over the course of the session, progressively narrowing down the problem. After the 8th question, the system automatically compresses earlier conversation turns into a concise summary. The technician continues asking questions and the assistant still remembers technical details from the beginning of the conversation — part numbers, procedures, and specifications discussed earlier — without losing context or contradicting previous answers.

**Why this priority**: This is the core value proposition. Without accurate compression that preserves technical facts, the feature has no value.

**Independent Test**: Can be tested by conducting a 12+ turn conversation about a specific technical topic and verifying the assistant correctly references facts from early turns (before compression) in later answers.

**Acceptance Scenarios**:

1. **Given** a conversation with 9 turns of history, **When** the user asks a new question, **Then** the system compresses the oldest 5 turns into a summary and sends the summary plus last 4 raw turns to the LLM.
2. **Given** a compressed conversation where turns 1-5 discussed "hydraulic pump pressure specs", **When** the user asks "what was that pressure value we discussed earlier?", **Then** the assistant can answer using information preserved in the summary.
3. **Given** a conversation with exactly 8 turns, **When** the user asks a new question, **Then** no compression is applied (threshold is "more than 8"; compression starts at 9+ turns).

---

### User Story 2 - Transparent Compression (Priority: P1)

The compression process is invisible to the user. The frontend sends all conversation history and passes back the `session_summary` from the previous response (a small change — remove truncation, store one field, send it back), but compression logic lives entirely on the backend. The user sees no loading delays, UI changes, or behavioral differences — only that the assistant maintains better context in long conversations compared to the old approach of abruptly dropping turns after 10.

**Why this priority**: If compression causes noticeable delays or changes the user experience, adoption will suffer.

**Independent Test**: Can be tested by comparing response times for a 15-turn conversation before and after the feature, and verifying no compression logic exists in the frontend.

**Acceptance Scenarios**:

1. **Given** the frontend sends all conversation history, **When** the backend receives it, **Then** the backend handles compression internally with no compression logic on the frontend.
2. **Given** a conversation that triggers compression, **When** the user submits a question, **Then** the total response time remains acceptable (no perceptible additional delay beyond normal LLM latency).

---

### User Story 3 - Graceful Handling of Short Conversations (Priority: P2)

For conversations with 8 or fewer turns, the system behaves exactly as it does today — no compression is applied, and all raw turns are included in the prompt context. The feature only activates when there is enough history to warrant compression.

**Why this priority**: Ensures no regression for the common case of short conversations.

**Independent Test**: Can be tested by conducting a 5-turn conversation and verifying all turns appear as raw history in the prompt (no summary field).

**Acceptance Scenarios**:

1. **Given** a conversation with 5 turns, **When** the user asks a new question, **Then** all 5 turns are sent as raw history with no compression applied.
2. **Given** a conversation with exactly 8 turns, **When** the user asks a new question, **Then** no compression is applied (8 does not exceed the threshold; compression starts at 9+).

---

### Edge Cases

- What happens when the summary itself grows very long after multiple compression cycles? The system re-compresses the existing summary plus newly aged-out turns into a single updated 3-4 sentence summary.
- What happens if the compression LLM call fails (timeout, service down)? The system falls back to the current behavior — send the last 10 raw turns without compression.
- What happens if the conversation contains only very short turns (e.g., "yes", "no")? The summary should still capture the conversational flow and what was confirmed or denied.
- What happens if the user asks about something from a very early turn (turn 2 of 20)? The summary must have preserved that information; if it didn't, the assistant responds based on what it knows rather than hallucinating.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST compress conversation history when the total number of turns exceeds 8, keeping the last 4 raw turns and summarizing all older turns into a "memory" field.
- **FR-002**: System MUST generate the summary as a 3-4 sentence text that preserves all technical facts, part numbers, procedures, specifications, and topics discussed in the compressed turns.
- **FR-003**: System MUST include the summary as a distinct "memory" section in the prompt sent to the LLM for final answer generation, positioned before the raw conversation turns.
- **FR-004**: System MUST perform all compression logic on the backend only. The backend returns the `session_summary` string in the response JSON. The frontend stores it in state and sends it back as an optional field in subsequent requests, but contains no compression logic itself.
- **FR-005**: System MUST fall back to sending the last 10 raw turns (current behavior) if the compression call fails for any reason.
- **FR-006**: System MUST handle incremental compression — when a previously compressed conversation gains more turns exceeding the threshold again, the system re-compresses the existing summary plus newly aged-out turns into an updated 3-4 sentence summary.
- **FR-007**: System MUST integrate compression as a pipeline step after chunk reranking and before final answer generation.
- **FR-008**: System MUST keep the query rewrite step independent of compression — query rewriting continues to use raw recent turns regardless of whether compression has occurred.

### Key Entities

- **Session Summary (Memory)**: A compressed text representation of older conversation turns, containing all technical facts and discussion topics in 3-4 sentences. Created when turn count exceeds 8, updated incrementally as conversations grow.
- **Conversation Turn**: A question-answer pair from the user's interaction with the manual assistant. Turns are either "raw" (sent verbatim in the prompt) or "compressed" (folded into the session summary).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can conduct conversations of 20+ turns without the assistant losing context about technical facts discussed in the first 5 turns.
- **SC-002**: The compression step adds no more than 2 seconds to the overall response time per question.
- **SC-003**: The summary accurately preserves at least 90% of technical facts (part numbers, specifications, procedures) from compressed turns, as verified by manual review of 10 test conversations.
- **SC-004**: Conversations with 8 or fewer turns behave identically to the current system — no regression in response quality or timing.
- **SC-005**: If the compression service is unavailable, the system continues to function using the existing fallback behavior with no user-visible errors.

## Assumptions

- The existing Ollama instance has sufficient capacity to handle an additional LLM call per question (the compression call) without significant resource contention.
- The compression prompt is lightweight (summarizing conversation text, not performing RAG), so it completes quickly relative to the main answer generation.
- The frontend will be updated to send all history turns (removing the existing last-10 sublist truncation), but no compression logic is added to the frontend.
- The 8-turn threshold and 4 raw-turn window are fixed values, not user-configurable.
- The summary does not need to be persisted to a database — it is returned to the frontend in the response and sent back by the frontend in subsequent requests (pass-through cache). The backend only re-compresses when new turns have aged out past the 4-turn raw window.
