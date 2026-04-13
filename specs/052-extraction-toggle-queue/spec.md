# Feature Specification: WO Entity Extraction — Admin Toggle & AI Priority Queue

**Feature Branch**: `052-extraction-toggle-queue`  
**Created**: 2026-04-13  
**Status**: Draft  
**Input**: User description: "Entity Extraction Admin Toggle and AI Priority Queue"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin Disables Entity Extraction During Outage (Priority: P1)

An administrator notices the AI model is overloaded or entity extraction is producing incorrect results. They navigate to Admin Settings and flip a single toggle to disable extraction globally. All work order saves continue working normally — they just no longer trigger extraction jobs. When the issue is resolved, the admin re-enables the toggle and extraction resumes.

**Why this priority**: Without a kill switch, the only way to disable extraction is a code deploy. This is the core safety mechanism that protects production stability.

**Independent Test**: Can be fully tested by toggling the setting ON/OFF and verifying that WO saves do or do not trigger extraction jobs.

**Acceptance Scenarios**:

1. **Given** entity extraction is enabled, **When** the admin toggles it OFF, **Then** subsequent work order saves do not trigger any extraction jobs
2. **Given** entity extraction is disabled, **When** the admin toggles it ON, **Then** subsequent work order saves trigger extraction jobs as expected
3. **Given** the toggle has never been set, **When** the system starts, **Then** entity extraction defaults to disabled (safe default)

---

### User Story 2 - User-Facing AI Stays Responsive During Extraction Bursts (Priority: P1)

A technician saves 5 work orders in quick succession (with extraction enabled). Meanwhile, a supervisor opens the AI assistant and asks a question. Despite 5 pending extraction jobs, the supervisor's search query is processed first because user-facing AI has higher priority than background extraction. The supervisor experiences no noticeable delay.

**Why this priority**: This directly addresses the core concurrency problem — background extraction starving user-facing AI. Equal priority to the toggle because both are required for a safe, usable system.

**Independent Test**: Can be tested by enqueuing multiple extraction jobs and then submitting a user-facing AI request, verifying the user request completes before pending extraction jobs.

**Acceptance Scenarios**:

1. **Given** 5 extraction jobs are queued, **When** a user submits a RAG search query, **Then** the search query is processed before any remaining extraction jobs
2. **Given** no jobs are queued, **When** a user submits a RAG search query, **Then** the query processes immediately with no added latency from the queue mechanism
3. **Given** an extraction job is currently running, **When** a user submits a search query, **Then** the search query runs immediately after the current job finishes (does not wait behind other extraction jobs)

---

### Edge Cases

- What happens when the toggle is switched OFF while extraction jobs are already queued? Already-enqueued jobs complete normally; no new jobs are accepted.
- What happens if the AI model is unreachable when a queued job runs? The job fails via the caller's existing httpx timeout (60s–120s), logs the error, and does not retry or block subsequent jobs. No additional queue-level timeout is enforced.
- What happens if a user-facing AI request fails? The error is returned to the user as it is today; the queue moves on to the next job.
- What happens during system restart? The in-memory queue is empty on startup; no persistence is needed since extraction can re-run on next WO save.
- What happens if many extraction jobs queue up rapidly? Jobs process one at a time in priority order; the queue is bounded by WO save rate in practice.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a global toggle setting to enable or disable entity extraction
- **FR-002**: The toggle MUST default to disabled (OFF) when first created
- **FR-003**: When the toggle is OFF, work order saves MUST NOT trigger extraction jobs
- **FR-004**: When the toggle is ON, work order saves MUST enqueue extraction as a low-priority background job
- **FR-005**: System MUST process all AI requests through a shared queue that serializes access to the AI model, integrated at the service level (`ollama_generator` and `ollama_embedder`) so all callers are automatically covered
- **FR-006**: User-facing AI requests (search, insights, RAG assistant, manual operations) MUST have higher priority than background extraction jobs
- **FR-007**: The queue MUST drain all high-priority jobs before processing any low-priority jobs
- **FR-008**: User-facing AI requests MUST await their result (synchronous from the caller's perspective)
- **FR-009**: Extraction jobs MUST be fire-and-forget (caller does not wait for result)
- **FR-010**: The queue worker MUST process exactly one job at a time (no concurrent AI model calls)
- **FR-011**: Admin settings screen MUST display the entity extraction toggle with a descriptive label and explanation
- **FR-012**: Toggle state changes MUST take effect immediately for subsequent WO saves (no restart required)
- **FR-013**: System MUST NOT introduce any new external dependencies
- **FR-014**: The work order save response time MUST NOT be affected by the queue mechanism
- **FR-015**: Queue worker MUST log job processing events (start, complete, error) for observability

### Key Entities

- **System Setting**: A key-value configuration pair (key name, string value, last updated timestamp) used for global feature toggles. The entity extraction toggle is one instance of this.
- **AI Job**: A unit of work submitted to the priority queue, characterized by its priority level (high for user-facing, low for background), the callable task to execute, and a mechanism to deliver the result back to the caller when awaited.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Admin can toggle entity extraction ON/OFF within 2 seconds from the settings screen
- **SC-002**: When extraction is OFF, work order save latency is unchanged compared to current behavior
- **SC-003**: When extraction is ON, work order save latency remains unchanged (extraction is fully asynchronous)
- **SC-004**: During a burst of 5+ pending extraction jobs, a user-facing AI query completes within the same timeframe as when no extraction jobs are queued
- **SC-005**: Zero new external service dependencies introduced
- **SC-006**: Toggle state defaults to OFF on first deployment, requiring explicit admin action to enable

## Clarifications

### Session 2026-04-13

- Q: Should the queue wrap all Ollama calls at the service level or only specific router-level calls? → A: Service-level — queue wraps `ollama_generator` and `ollama_embedder` so all callers are automatically serialized through a single integration point.
- Q: Should the queue enforce a maximum execution time per job? → A: No queue-level timeout — rely on existing per-caller httpx timeouts (60s–120s) already configured in each Ollama call site.
- Q: Should the extraction status chip (P3) be included in spec 052 or deferred? → A: Deferred — not in scope for 052; may be added in a future spec if needed.

## Assumptions

- The `system_settings` table may or may not already exist; if not, it will be created as a generic key-value store reusable for future settings
- AI model calls happen through two service modules (`ollama_generator` and `ollama_embedder`); some routers also make direct httpx calls to Ollama — all paths must be unified through the queue
- The server runs a single process (no horizontal scaling), so an in-memory queue is sufficient
- Work order save volume is low enough that an unbounded in-memory queue will not cause memory issues
- The AI model runs locally on the same server as the backend
- Spec 049 (entity extraction) is merged and functional before this work begins
- Ollama callers that will be automatically serialized via service-level queue: `ai_search.py`, `ai_insights.py`, `ai_assist.py`, `manuals.py`, `manual_rag_service.py`, `agentic_tools.py`, `entity_extractor.py`, `validated_qa_service.py` (routers with direct httpx calls must be refactored to use the shared services)
