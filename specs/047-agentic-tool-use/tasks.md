# Tasks: Agentic Tool Use (Layer 5)

**Input**: Design documents from `/specs/047-agentic-tool-use/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not explicitly requested — test tasks omitted. Validation is manual via the AI chat interface per quickstart.md.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Web app**: `backend/` (Python/FastAPI), `frontend/` (Dart/Flutter)

---

## Phase 1: Setup

**Purpose**: Create the new backend module and define the tool manifest

- [X] T001 Create `backend/services/agentic_tools.py` with module docstring, imports (`import time, re, json, logging` from stdlib; `from db import supabase`; `from services.ollama_generator import generate`; `from services.manual_rag_service import ask as manual_rag_ask`), and module-level logger
- [X] T002 Define the tool manifest string constant `TOOL_MANIFEST` in `backend/services/agentic_tools.py` — a plain-text block describing 3 tools for injection into the LLM system prompt. Each tool entry must include: tool name, description, parameter names with types and whether required/optional. Tools: (1) `work_orders` — params: `work_order_number` (int, optional), `status` (str, optional), `equipment_type` (str, optional), `technician_name` (str, optional), `date_from` (str, optional), `date_to` (str, optional); (2) `manuals` — params: `query` (str, required); (3) `compare` — params: `work_order_data` (str, required), `manual_procedure` (str, required). Include formatting instructions telling the model to output `TOOL_CALL: <tool_name>` followed by `PARAMS: <json>` on the next line when it wants to call a tool, or to output a plain answer if no tool is needed
- [X] T003 Implement the tool-call parser function `parse_tool_call(response_text: str) -> tuple[str | None, dict | None]` in `backend/services/agentic_tools.py`. Use regex to find the first `TOOL_CALL: <name>` line and the subsequent `PARAMS: <json>` line. Return `(tool_name, params_dict)` if found, or `(None, None)` if the response contains no tool call (meaning it's a direct answer). Handle malformed JSON gracefully — if PARAMS line exists but JSON is invalid, return `(None, None)` and log a warning. Only accept tool names from the set `{"work_orders", "manuals", "compare"}`; reject unknown tool names

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Implement the three tool executors and the agentic loop — these are required by ALL user stories

**CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Implement `async def execute_work_orders_tool(params: dict) -> dict` in `backend/services/agentic_tools.py`. This function queries the Supabase `work_orders` table using the existing `supabase` client from `db.py`. Build a query selecting: `job_no, status, description, type, department_id, assigned_technician_id, created_at, closed_at, signature_status`. Apply filters from params: if `work_order_number` present, filter `.eq("job_no", value)`; if `status` present, filter `.eq("status", value)`; if `equipment_type` present, filter `.ilike("type", f"%{value}%")`; if `technician_name` present, join with `users` table and filter by `full_name` ilike; if `date_from`/`date_to` present, filter `.gte("created_at", date_from)` / `.lte("created_at", date_to)`. Limit results to 20 rows via `.limit(20)`. Join `departments(name)` and `users!assigned_technician_id(full_name)` to get department_name and technician_name. Return dict: `{"success": True, "data": [list of formatted WO dicts], "truncated": len(results) == 20, "count": len(results)}`. Each WO dict: `{"job_no", "status", "description", "type", "department", "technician", "created_at", "closed_at", "signature_status"}`. On exception, return `{"success": False, "data": [], "error": str(e)}`
- [X] T005 [P] Implement `async def execute_manuals_tool(params: dict, manual_id_filter=None, model=None, history=None, session_summary=None) -> dict` in `backend/services/agentic_tools.py`. This function calls the existing `manual_rag_service.ask()` with `params["query"]` as the question, passing through `manual_id_filter`, `model`, `history`, and `session_summary`. Return dict: `{"success": True, "data": {"answer": result["answer"], "sources": result.get("sources", []), "grounded": result.get("grounded", False)}}`. On exception (EmbedderUnavailableError, GeneratorUnavailableError, any other), return `{"success": False, "data": {}, "error": str(e)}`
- [X] T006 [P] Implement `async def execute_compare_tool(params: dict, model: str | None = None) -> dict` in `backend/services/agentic_tools.py`. This function builds a comparison prompt containing: (a) the work order data from `params["work_order_data"]`, (b) the manual procedure from `params["manual_procedure"]`, (c) instructions asking the model to produce a structured comparison with an overall verdict ("matches" or "discrepancy found") followed by a numbered list of specific items checked with match/mismatch per item. Call `generate(prompt, model=model, timeout=30.0)` (shorter timeout since this is a sub-call within the 60s budget). Return dict: `{"success": True, "data": {"comparison": generated_text}}`. On exception, return `{"success": False, "data": {}, "error": str(e)}`
- [X] T007 Implement `async def execute_tool(tool_name: str, params: dict, **kwargs) -> dict` dispatcher in `backend/services/agentic_tools.py`. This function routes to the appropriate executor: `"work_orders"` → `execute_work_orders_tool(params)`, `"manuals"` → `execute_manuals_tool(params, **kwargs)`, `"compare"` → `execute_compare_tool(params, model=kwargs.get("model"))`. For unknown tool_name, return `{"success": False, "error": f"Unknown tool: {tool_name}"}`
- [X] T008 Implement `async def run_agentic_loop(question: str, manual_id_filter=None, model=None, history=None, session_summary=None) -> dict` in `backend/services/agentic_tools.py`. This is the core agentic loop. Steps: (1) Record `start_time = time.time()`. Initialize `tool_calls_log = []`, `call_count = 0`, `MAX_CALLS = 3`, `TIMEOUT = 60.0`. (2) Build the initial prompt: system section with `TOOL_MANIFEST`, then conversation history (format each turn as `User: {q}\nAssistant: {a}`), then the current question. If `session_summary` is provided, include it as context before the question. (3) Call `generate(prompt, model=model, timeout=45.0)`. (4) Parse the response with `parse_tool_call()`. (5) If no tool call found → this is the final answer. Return the result dict. (6) If tool call found → execute it via `execute_tool()`, append `{"tool_name", "success", "has_data": bool(result.get("data"))}` to `tool_calls_log`, increment `call_count`. (7) Append tool result to the prompt as `TOOL_RESULT [{tool_name}]: {json.dumps(result)}` and loop back to step 3. (8) If `call_count >= MAX_CALLS` or `time.time() - start_time > TIMEOUT`, append a final instruction "You have used all available tool calls. Generate your final answer now using the information gathered above." and call `generate()` one last time for the final answer. (9) Return dict: `{"answer": final_answer, "tools_used": tool_calls_log, "agentic": len(tool_calls_log) > 0}`. Note: the returned dict should also include standard fields from the manuals pipeline when the manuals tool was called (sources, grounded, model, etc.). If manuals tool was called, merge its result fields into the response. If only work_orders or compare tools were used, set `grounded: False, sources: []`.
- [X] T009 Add a fallback path to `run_agentic_loop`: if the initial `generate()` call fails (Ollama down, model error, timeout), catch the exception, log a warning, and fall back to calling `manual_rag_service.ask()` directly (the pre-agentic path). Return its result with `"agentic": False, "tools_used": []` appended. This ensures backward compatibility even if the agentic layer is broken

**Checkpoint**: All three tool executors and the agentic loop are implemented. Ready for user story integration.

---

## Phase 3: User Story 1 — Direct Manual Question (No Tools Needed) (Priority: P1) MVP

**Goal**: Questions that don't need tools are answered directly, with no regression from the existing pipeline.

**Independent Test**: Ask "What is the procedure for engine oil change?" — response should match pre-agentic quality, `agentic` field in response should be `false` or `tools_used` should be empty.

### Implementation for User Story 1

- [X] T010 [US1] Modify `ask_question` in `backend/routers/manuals.py` to route through the agentic loop. Replace the direct call to `manual_rag_service.ask(...)` (lines ~313-319) with a call to `from services.agentic_tools import run_agentic_loop` then `result = await run_agentic_loop(question, manual_id_filter, model=request.model, history=history, session_summary=request.session_summary)`. The rest of the endpoint (error handling, logging, response) remains unchanged since `run_agentic_loop` returns a compatible dict
- [X] T011 [US1] Verify that when Gemma receives a manual-only question with the tool manifest in the prompt, it still generates a direct answer without outputting any `TOOL_CALL:` block. If during testing the model always tries to call tools even for simple questions, adjust the `TOOL_MANIFEST` prompt to include a clear instruction: "If the question can be answered from your knowledge or the conversation context alone, answer directly WITHOUT calling any tool. Only use tools when you need external data you don't already have."
- [X] T012 [US1] Ensure the response dict from `run_agentic_loop` for the no-tool path includes all fields the frontend currently expects: `answer`, `grounded`, `sources`, `model`, `duration_seconds`, `session_summary`. For the no-tool path specifically: when `parse_tool_call` returns `(None, None)` on the first call, the model's direct answer should be treated as equivalent to a `manual_rag_service.ask()` call. **Implementation detail**: in the no-tool path of `run_agentic_loop`, after getting a direct answer from `generate()`, call `manual_rag_service.ask()` anyway to get grounded sources and proper pipeline output — but replace its answer with the agentic model's direct answer only if the model's answer is richer. **Alternatively** (simpler, recommended): if no tool call is detected, just fall through to `manual_rag_service.ask()` directly and return its result with `"agentic": False, "tools_used": []`. This ensures 100% backward compatibility

**Checkpoint**: Manual-only questions work exactly as before. Response format unchanged. `agentic: false` in metadata.

---

## Phase 4: User Story 2 — Work Order Lookup via Tool (Priority: P1)

**Goal**: Users can ask about work orders and get live data from the database via the AI chat.

**Independent Test**: Ask "What is the status of work order 1042?" — response should contain the actual work order data from Supabase. Ask "Show me pending work orders" — response should list actual pending WOs.

### Implementation for User Story 2

- [X] T013 [US2] Test the work_orders tool executor end-to-end: in `run_agentic_loop`, when the model outputs `TOOL_CALL: work_orders` with params like `{"work_order_number": 1042}`, verify that `execute_work_orders_tool` correctly queries Supabase and returns the formatted result. Debug by adding `logger.info(f"Tool call: work_orders, params: {params}, result count: {len(result['data'])}")` in the executor
- [X] T014 [US2] Handle the case where `execute_work_orders_tool` returns `{"success": True, "data": [], "count": 0}` (no matching work orders). When this result is fed back to the model, the model should generate an answer like "No work order found matching your criteria." Verify by asking about a non-existent work order number. If the model hallucinates data despite the empty result, add to the tool result feedback: `"NOTE: No results found. You MUST tell the user that no matching work orders were found. Do NOT make up data."`
- [X] T015 [US2] Handle truncation: when `execute_work_orders_tool` returns `{"truncated": True}`, append to the tool result feedback: `"NOTE: Results were limited to 20. There may be more matching work orders. Inform the user that results were truncated."` Verify by asking a broad query like "Show me all work orders"
- [X] T016 [US2] Verify the Supabase join query in `execute_work_orders_tool` works correctly with the existing table schema. The `work_orders` table has `department_id` (FK to `departments`) and `assigned_technician_id` (FK to `users`). Use `.select("*, departments(name), users!work_orders_assigned_technician_id_fkey(full_name)")` or the appropriate FK name. Test by checking that the returned dicts contain readable `department` and `technician` names, not UUIDs

**Checkpoint**: Work order queries via the AI chat return accurate live data. Empty results handled gracefully. Truncation communicated.

---

## Phase 5: User Story 3 — Multi-Tool Chain (Priority: P1)

**Goal**: Questions requiring cross-referencing work orders with manual procedures are answered in a single interaction using chained tool calls (work_orders → manuals → compare).

**Independent Test**: Ask "Does work order 1042 follow the CADAS inspection procedure?" — response should show evidence of all 3 tool calls and present a structured comparison.

### Implementation for User Story 3

- [X] T017 [US3] Verify that the agentic loop correctly chains multiple tool calls. When the model calls `work_orders` first, receives the result, then decides to call `manuals`, receives that result, and then calls `compare` — each tool result must be appended to the conversation and the model must see all prior results when deciding the next action. In `run_agentic_loop`, after each tool execution, the prompt grows by appending `TOOL_RESULT [tool_name]: <result_json>` followed by "Based on the tool results above, decide your next action: call another tool or provide your final answer."
- [X] T018 [US3] Handle the compare tool's input assembly. When the model calls `TOOL_CALL: compare`, it needs to pass `work_order_data` and `manual_procedure` as params. The model may format these from previous tool results. If the model struggles to pass the right data, add instructions in the `TOOL_MANIFEST` for the compare tool: "For work_order_data, summarize the key facts from the work_orders tool result. For manual_procedure, summarize the relevant procedure from the manuals tool result."
- [X] T019 [US3] Verify the compare tool's output is structured. The `execute_compare_tool` sends a prompt to `generate()` asking for verdict + per-item breakdown. Test that the generated comparison is coherent and structured. If the output is too verbose or unstructured, refine the comparison prompt in `execute_compare_tool` to be more prescriptive: "Output format: VERDICT: [matches/discrepancy found], then a numbered list: 1. [Item]: [match/mismatch] - [detail]"
- [X] T020 [US3] Handle partial chain failures: if the work_orders tool succeeds but the manuals tool fails (e.g., embedder unavailable), the model should still generate a useful answer explaining what it could and couldn't find. Verify by testing with a question that triggers both tools when the manual corpus is empty. The model should report the work order data and note that manual search returned no results

**Checkpoint**: Multi-tool chains work end-to-end. Compare tool produces structured output. Partial failures handled gracefully.

---

## Phase 6: User Story 4 — Manual Search via Agentic Tool (Priority: P2)

**Goal**: When the agentic model decides a question requires manual search, the manuals tool triggers the full Layer 1-4 pipeline and the answer quality matches the pre-agentic baseline.

**Independent Test**: Ask a technical manual question like "What are the hydraulic system maintenance intervals?" — the manuals tool should fire, and the response should include grounded sources from the RAG pipeline.

### Implementation for User Story 4

- [X] T021 [US4] Verify that when `execute_manuals_tool` calls `manual_rag_service.ask()`, the full pipeline (query rewrite → HyDE → vector search → reranking → cross-manual synthesis) executes. Check by adding a log line in `execute_manuals_tool`: `logger.info(f"Manuals tool: grounded={result.get('grounded')}, sources={len(result.get('sources', []))}")`. The manuals tool result should contain `sources` and `grounded` status
- [X] T022 [US4] Merge manuals tool result fields into the final `run_agentic_loop` response. When the manuals tool was called and succeeded, copy `sources`, `grounded`, `manuals_consulted`, `has_conflicts` from the manuals tool result into the top-level response dict. This ensures the frontend receives the same source citations it expects
- [X] T023 [US4] Handle the edge case where the model decides to call the manuals tool AND another tool in the same session. The `sources` in the final response should come from the manuals tool call. If both work_orders and manuals tools are called, the response should include both `sources` (from manuals) and `tools_used` (listing both tools)

**Checkpoint**: Agentic-routed manual queries produce identical quality to direct pipeline queries. Sources and grounding metadata preserved.

---

## Phase 7: User Story 5 — Loop Safety and Transparency (Priority: P2)

**Goal**: The system enforces a 3-call limit and 60-second timeout. Response metadata shows which tools were called.

**Independent Test**: Verify the `tools_used` array appears in responses when tools are called. Verify the 3-call limit by observing multi-tool chains don't exceed 3.

### Implementation for User Story 5

- [X] T024 [US5] Add the 60-second timeout check in `run_agentic_loop`. At the top of each loop iteration (before calling `generate()`), check `if time.time() - start_time > TIMEOUT`. If exceeded, skip the generate call and immediately build a final answer from all tool results gathered so far by calling `generate()` with a forced-answer prompt: "TIME LIMIT REACHED. Generate your final answer now using only the information gathered from tool calls above." with a short timeout of 10 seconds
- [X] T025 [US5] Verify the `tools_used` metadata is correctly populated. After `run_agentic_loop` returns, the response dict must include `"tools_used": [{"tool_name": "work_orders", "success": true, "has_data": true}, ...]` and `"agentic": true`. If no tools were called, `"tools_used": []` and `"agentic": false`
- [X] T026 [US5] Add activity log detail for tool usage. In `backend/routers/manuals.py`, update the existing `log_activity` call (around line 358) to include tool information in the `detail` field. Change from `f"grounded={result.get('grounded', False)}, sources={len(result.get('sources', []))}"` to `f"grounded={result.get('grounded', False)}, sources={len(result.get('sources', []))}, agentic={result.get('agentic', False)}, tools={[t['tool_name'] for t in result.get('tools_used', [])]}"`. This ensures tool usage is auditable in the activity log
- [X] T027 [US5] Handle individual tool execution errors gracefully in the agentic loop. In `execute_tool`, if any executor raises an unexpected exception, catch it and return `{"success": False, "data": {}, "error": str(e)}`. When this failure result is fed back to the model, prepend: `"TOOL ERROR: {tool_name} failed with: {error}. Continue with other tools or answer with available information."` The model should not re-attempt the failed tool (the call still counts toward the 3-call limit)

**Checkpoint**: Safety limits enforced. Metadata present. Errors handled gracefully. Activity log includes tool usage.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Frontend integration and final cleanup

- [X] T028 [P] Update `frontend/lib/services/ai_assist_service.dart` to parse the new `agentic` (bool) and `tools_used` (list) fields from the `/manuals/ask` response. Add these as optional fields on the response model/map. If `tools_used` is present and non-empty, store it so the UI can display it
- [X] T029 [P] Update the AI chat UI widget (find the widget that displays the assistant's response in the manual assistant screen) to show a small "Tools used" indicator when `tools_used` is non-empty. Display as a subtle row of chip/badge widgets below the answer showing each tool name (e.g., "work_orders", "manuals", "compare"). This is informational only — no interaction needed
- [ ] T030 Run the full quickstart.md validation: test each of the 5 test questions listed in `specs/047-agentic-tool-use/quickstart.md` and verify expected tool call behavior matches. Document any prompt tuning needed for the `TOOL_MANIFEST` to get reliable tool-call decisions from Gemma
- [ ] T031 Review and tune the `TOOL_MANIFEST` prompt based on testing. Common issues to address: (a) model calling tools unnecessarily for simple questions — add stronger "answer directly when possible" instructions; (b) model formatting PARAMS incorrectly — add examples in the manifest; (c) model not calling compare tool when it should — add a hint like "If the user asks whether a work order follows a procedure, you should use all three tools: work_orders, then manuals, then compare"

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (T001-T003) — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 — first story to verify end-to-end integration
- **US2 (Phase 4)**: Depends on Phase 2 — can run in parallel with US1 (different concerns)
- **US3 (Phase 5)**: Depends on Phase 2. Practically benefits from US2 (work_orders tool) and US4 (manuals tool) being validated first
- **US4 (Phase 6)**: Depends on Phase 2 — can run in parallel with US1 and US2
- **US5 (Phase 7)**: Depends on Phase 2 — can run in parallel with other stories but best done after at least one tool-using story is validated
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: Independent — tests the no-tool path
- **US2 (P1)**: Independent — tests the work_orders tool only
- **US3 (P1)**: Practically depends on US2 + US4 being working (needs work_orders and manuals tools)
- **US4 (P2)**: Independent — tests the manuals tool only
- **US5 (P2)**: Independent — tests safety and metadata (works with any tool path)

### Within Each User Story

- Integration with router (T010) before behavioral validation
- Core path before edge cases
- Tool executor correctness before prompt tuning

### Parallel Opportunities

- T005 and T006 can run in parallel (different tool executors, different files — but same file, so actually sequential within agentic_tools.py)
- T013-T016 (US2) can run in parallel with T021-T023 (US4) since they test different tools
- T028 and T029 (frontend) can run in parallel with backend tasks since they touch different codebases
- US1, US2, US4, US5 can all start after Phase 2 in parallel

---

## Parallel Example: Phase 2 (Foundational)

```bash
# These touch different functions in the same file, so run sequentially:
Task T004: Implement execute_work_orders_tool in backend/services/agentic_tools.py
Task T005: Implement execute_manuals_tool in backend/services/agentic_tools.py
Task T006: Implement execute_compare_tool in backend/services/agentic_tools.py
Task T007: Implement execute_tool dispatcher in backend/services/agentic_tools.py
Task T008: Implement run_agentic_loop in backend/services/agentic_tools.py
Task T009: Add fallback path in backend/services/agentic_tools.py
```

## Parallel Example: After Foundational

```bash
# These can run in parallel (different concerns):
Agent A (US1): T010-T012 — Router integration + no-tool path
Agent B (US2): T013-T016 — Work orders tool validation
Agent C (US4): T021-T023 — Manuals tool validation
# Then:
Agent D (US3): T017-T020 — Multi-tool chain (after US2 + US4 validated)
Agent E (US5): T024-T027 — Safety and transparency
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T009)
3. Complete Phase 3: US1 — No-tool path (T010-T012)
4. **STOP and VALIDATE**: Ask manual-only questions, verify no regression
5. This is deployable — worst case, the agentic layer falls through to existing pipeline

### Incremental Delivery

1. Setup + Foundational → Agentic loop exists
2. US1 → No regression verified → Safe to deploy
3. US2 → Work order queries work → Major new capability live
4. US3 → Multi-tool chains work → Differentiating feature live
5. US4 → Manuals tool verified → Full backward compatibility confirmed
6. US5 → Safety + transparency → Production-ready
7. Polish → Frontend metadata display → Complete

---

## Notes

- All new backend code goes in a single new file: `backend/services/agentic_tools.py`
- Only one existing file is modified: `backend/routers/manuals.py` (T010, T026)
- Frontend changes are minimal and additive (T028, T029)
- The `TOOL_MANIFEST` prompt (T002) is the most critical piece — it determines how well Gemma decides when and which tools to call. Expect iterative tuning (T031)
- The fallback path (T009) is essential for safety — if the agentic layer breaks, the system reverts to pre-agentic behavior automatically
- Commit after each phase completion for safe rollback points
