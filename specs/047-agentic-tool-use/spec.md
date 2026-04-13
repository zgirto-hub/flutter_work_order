# Feature Specification: Agentic Tool Use (Layer 5)

**Feature Branch**: `047-agentic-tool-use`  
**Created**: 2026-04-13  
**Status**: Draft  
**Input**: User description: "Agentic tool use (Layer 5) for the manual assistant AI pipeline. Gemma decides which tools to call based on the user question before generating an answer."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Direct Manual Question (No Tools Needed) (Priority: P1)

A user asks a general knowledge question or a simple manual-related question that the AI can answer directly from its training or from manual context alone. The system recognizes no tools are needed and responds immediately without invoking any tool calls.

**Why this priority**: This is the most common case. Most questions are pure manual lookups. The agentic layer must not regress existing behavior — when no tools are needed, the assistant must respond as fast as it does today.

**Independent Test**: Ask "What is the procedure for engine oil change?" with manuals uploaded. The response should come from manual chunks as it does today, with no tool calls visible in the pipeline debug output.

**Acceptance Scenarios**:

1. **Given** a user asks a question answerable from manuals, **When** the assistant processes the question, **Then** it answers using the existing Layer 1-4 pipeline without invoking any tools and the response quality is unchanged.
2. **Given** a user asks a general greeting or off-topic question, **When** the assistant processes it, **Then** it responds directly without tool calls.

---

### User Story 2 - Work Order Lookup via Tool (Priority: P1)

A user asks about a specific work order (e.g., "What is the status of work order 1042?" or "Show me open work orders for Ahmed"). The assistant recognizes this requires the work_orders tool, calls it with the appropriate filters, and presents the results in a readable answer.

**Why this priority**: This is the core new capability — bridging work order data with the manual assistant. It delivers immediate, tangible value by letting users query live operational data through the AI chat interface.

**Independent Test**: Ask "What is the status of work order 1042?" and verify the assistant calls the work_orders tool, retrieves the correct record from the database, and presents the status in natural language.

**Acceptance Scenarios**:

1. **Given** a user asks about a specific work order by number, **When** the assistant processes the question, **Then** it calls the work_orders tool with the work order number filter and returns the correct status and details.
2. **Given** a user asks for work orders by status (e.g., "Show me all pending work orders"), **When** the assistant processes the question, **Then** it calls the work_orders tool with the status filter and returns matching results.
3. **Given** a user asks about a work order that does not exist, **When** the work_orders tool returns no results, **Then** the assistant clearly states the work order was not found and does not fabricate data.

---

### User Story 3 - Multi-Tool Chain: Work Order + Manual + Compare (Priority: P1)

A user asks a question that requires cross-referencing work order data with manual procedures, such as "Does work order 1042 follow our CADAS inspection procedure?" The assistant autonomously chains multiple tool calls: first retrieves the work order, then searches the relevant manual procedure, then uses the compare tool to identify discrepancies.

**Why this priority**: This is the differentiating capability of the agentic layer. It demonstrates intelligent multi-step reasoning that no single tool can provide, and it directly supports compliance and quality assurance workflows.

**Independent Test**: Ask "What is the status of work order 1042 and does it match our CADAS procedure?" Verify the assistant calls work_orders tool, then manuals tool, then compare tool, and produces a synthesized answer highlighting any discrepancies.

**Acceptance Scenarios**:

1. **Given** a user asks to compare a work order against a manual procedure, **When** the assistant processes the question, **Then** it calls the work_orders tool first, then the manuals tool, then the compare tool, and synthesizes the results into a clear answer.
2. **Given** the compare tool identifies discrepancies, **When** the assistant presents results, **Then** it clearly lists what matches and what differs between the work order and the procedure.
3. **Given** any tool in the chain returns no results, **When** the assistant continues processing, **Then** it reports which specific data was unavailable and does not hallucinate the missing information.

---

### User Story 4 - Manual Search via Agentic Tool (Priority: P2)

A user asks a question that the assistant determines requires searching manuals. The assistant invokes the manuals tool, which triggers the full existing Layer 1-4 pipeline (query rewriting, HyDE, vector search, reranking, cross-manual synthesis). The response is identical in quality to the current non-agentic flow.

**Why this priority**: Ensures backward compatibility. The manuals tool wraps the existing pipeline so that when the agentic layer routes a question to manuals, it gets the same high-quality retrieval and synthesis.

**Independent Test**: Ask a technical manual question and verify the manuals tool triggers the full RAG pipeline and the answer quality matches the pre-agentic baseline.

**Acceptance Scenarios**:

1. **Given** a user asks a question requiring manual search, **When** the assistant routes it through the manuals tool, **Then** the full Layer 1-4 pipeline executes and the response includes grounded sources.
2. **Given** the manuals tool finds no relevant chunks, **When** the assistant generates a response, **Then** it states that no relevant manual content was found.

---

### User Story 5 - Loop Safety and Transparency (Priority: P2)

The system enforces a maximum of 3 tool calls per question to prevent infinite loops or runaway costs. Each tool call and its result are logged for debugging and transparency. The user sees a well-formed final answer regardless of how many tools were invoked.

**Why this priority**: Safety and observability are essential for a production agentic system. Without loop limits, a malformed question could trigger unbounded tool calls.

**Independent Test**: Submit a question that could theoretically trigger more than 3 tool calls. Verify the system stops after 3, produces the best answer it can from available results, and logs the tool call history.

**Acceptance Scenarios**:

1. **Given** a question triggers tool calls, **When** the 3-call limit is reached, **Then** the assistant stops calling tools and generates a final answer using results gathered so far.
2. **Given** any tool call fails or times out, **When** the assistant encounters the error, **Then** it skips that tool gracefully and continues with remaining tools or answers with available information.
3. **Given** tool calls are made, **When** the response is returned, **Then** the response includes metadata indicating which tools were called and their outcomes.

---

### Edge Cases

- What happens when a user's question is ambiguous about whether it needs tools (e.g., "Tell me about inspection procedures" — could be manual-only or could need work order context)? The assistant defaults to the simpler interpretation (manual search only) unless the question explicitly references work orders or operational data.
- How does the system handle a question referencing a work order number that looks valid but does not exist? The work_orders tool returns an empty result and the assistant reports "No work order found with that number."
- What happens when the AI model is overloaded and cannot parse the tool manifest? The system falls back to direct answering using the existing Layer 1-4 pipeline, treating the question as a manual-only query.
- What happens when the work_orders tool returns many results (e.g., "Show me all work orders")? Results are capped at 20 records and the assistant informs the user that results were truncated.
- How does the system behave when the user asks a follow-up question that references a previous tool call result? The existing conversation history mechanism (history and session_summary fields) carries prior context, allowing the assistant to understand references to previous results.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST present the AI model with a tool manifest describing available tools (work_orders, manuals, compare) and their parameters before generating an answer.
- **FR-002**: System MUST allow the AI model to decide whether to call zero, one, or multiple tools based on the user's question.
- **FR-003**: The work_orders tool MUST query the work_orders table and support filtering by: work order number, status, equipment type, technician name, and date range. The tool MUST return these fields per record: work order number, status, description, equipment type, technician name, department, created date, resolved date, and signature status.
- **FR-004**: The manuals tool MUST invoke the existing Layer 1-4 RAG pipeline (query rewriting, HyDE, vector search, reranking, cross-manual synthesis) and return relevant manual content.
- **FR-005**: The compare tool MUST accept a work order result and a manual procedure, send them to the AI model for comparison, and return a structured output: an overall verdict ("matches" or "discrepancy found") plus a list of specific items checked with match/mismatch status per item.
- **FR-006**: System MUST enforce a maximum of 3 tool calls per user question to prevent infinite loops.
- **FR-013**: System MUST enforce a 60-second wall-clock timeout for the entire agentic loop (from question receipt to final answer). If the timeout is reached, the system MUST return the best answer possible from results gathered so far and indicate that processing was truncated.
- **FR-007**: When a tool returns no results, the system MUST report this to the AI model so it can communicate the absence clearly to the user without fabricating data.
- **FR-008**: When the AI model determines no tools are needed, the system MUST answer the question directly without any tool invocation.
- **FR-009**: The agentic loop MUST execute within the existing ask_question endpoint, maintaining backward compatibility with the current request/response contract.
- **FR-010**: Each tool call result MUST be fed back to the AI model as context for deciding subsequent tool calls or generating the final answer.
- **FR-011**: The response MUST include metadata about which tools were called (tool name and whether they returned results) for debugging and transparency.
- **FR-012**: The work_orders tool MUST limit results to a reasonable maximum (e.g., 20 records) when queries could return large result sets, and inform the user if results were truncated.

### Key Entities

- **Tool Manifest**: A structured description of available tools, their names, descriptions, and parameter schemas, provided to the AI model in the system prompt.
- **Tool Call**: A single invocation of a tool by the AI model, consisting of the tool name and parameters parsed from the model's output.
- **Tool Result**: The data returned by a tool execution, fed back into the AI model as context.
- **Agentic Loop**: The iterative process where the model receives a question, optionally calls tools, receives results, and either calls another tool or generates a final answer (up to the 3-call limit).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can ask work-order-related questions and receive accurate answers from live data within the same chat interface used for manual queries.
- **SC-002**: Multi-step questions (e.g., comparing a work order against a procedure) are answered in a single user interaction without requiring the user to manually look up data in separate systems.
- **SC-003**: The system never fabricates work order data — when a record is not found, 100% of responses explicitly state the absence.
- **SC-004**: Existing manual-only questions continue to be answered with the same quality and response structure as before the agentic layer was added (no regression).
- **SC-005**: No question triggers more than 3 tool calls, regardless of complexity or ambiguity.
- **SC-006**: When tools are used, the response includes transparency metadata so administrators can audit what data sources contributed to the answer.

## Clarifications

### Session 2026-04-13

- Q: Should the agentic tool loop have a per-question wall-clock timeout? → A: 60-second timeout — allows multi-tool chains to complete on constrained hardware while preventing indefinite hangs.
- Q: What work order fields should the work_orders tool return? → A: Operational set — number, status, description, equipment type, technician, department, created/resolved dates, signature status.
- Q: How should the compare tool structure its output? → A: Structured — overall verdict (matches/discrepancy) plus per-item breakdown with match/mismatch status.

## Assumptions

- The existing Layer 1-4 pipeline (query rewriting, HyDE, reranking, rolling summary, cross-manual synthesis) is stable and will be wrapped by the manuals tool without modification.
- The AI model (Gemma via Ollama) can parse structured tool manifests and generate structured tool call requests when prompted with appropriate formatting.
- The work_orders table is accessible from the backend via the existing Supabase client and requires no new database schema changes.
- The compare tool's comparison is performed by the same AI model (Gemma) using a dedicated prompt, not by deterministic code.
- Users interacting with the assistant have appropriate permissions to view work order data (permission checks are handled by the existing auth layer).
- Follow-up questions referencing previous tool results rely on the existing conversation history mechanism (history and session_summary fields).
