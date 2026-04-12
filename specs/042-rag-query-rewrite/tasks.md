# Tasks: RAG Query Rewrite

**Input**: Design documents from `/specs/042-rag-query-rewrite/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Web app**: `backend/services/`, `backend/routers/`
- Single file modification: `backend/services/manual_rag_service.py`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: No setup tasks needed — all infrastructure already exists (Ollama, FastAPI, httpx, conversation history passing).

*Phase skipped — nothing to initialize.*

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The rewrite function that all user stories depend on.

**IMPORTANT CONTEXT FOR IMPLEMENTING LLM**: Read `backend/services/manual_rag_service.py` fully before making changes. The `ask()` function starts at line 249. The embedding call `question_embedding = await embed_single(question)` is at line 269. The `_build_prompt()` helper is at line 35. The `history` parameter is a `list[dict]` where each dict has keys `question` (str) and `answer` (str). The existing `generate()` function in `backend/services/ollama_generator.py` accepts `(prompt: str, model: str | None, timeout: float)` and returns a `str`.

- [x] T001 Add `_rewrite_query()` async helper function in `backend/services/manual_rag_service.py`

  **What to do**: Add a new private async function `_rewrite_query(question: str, history: list[dict] | None) -> str` immediately before the `ask()` function (before line 249). This function:

  1. If `history` is None/empty, return `question` unchanged (no rewrite needed for first-turn).
  2. Take the last 3 entries from `history` (i.e., `history[-3:]`).
  3. Format them into a conversation block like:
     ```
     User: {turn['question']}
     Assistant: {turn['answer']}
     ```
  4. Build a rewrite prompt with this system instruction:
     ```
     You are a search query rewriter. Given a conversation history and a follow-up question, rewrite the follow-up question into a single self-contained search query. The rewritten query must:
     - Resolve all pronouns and references (e.g., "it", "that", "the second point") using the conversation context
     - Be a complete, standalone question that would make sense without any conversation history
     - Preserve the original language (Arabic or English)
     - Be concise (one sentence)
     
     Reply with ONLY the rewritten query. No explanation, no preamble.
     ```
     Then append the conversation history block and the follow-up question.
  5. Call `generate(prompt, timeout=10.0)` from `services.ollama_generator` (import at top of function like the existing pattern: `from services.ollama_generator import generate`).
  6. Strip the result. If the result is empty after stripping, return the original `question`.
  7. Wrap the entire function body in `try/except Exception` — on any exception, log a warning using `import logging; logger = logging.getLogger(__name__)` and return the original `question`.

  **File**: `backend/services/manual_rag_service.py`
  **Insert location**: Before the `ask()` function definition (before line 249)

- [x] T002 Integrate `_rewrite_query()` into `ask()` flow in `backend/services/manual_rag_service.py`

  **What to do**: In the `ask()` function, add one line immediately before the existing `question_embedding = await embed_single(question)` call (line 269). The new line calls `_rewrite_query()` and uses its result for embedding only:

  ```python
  search_query = await _rewrite_query(question, history)
  ```

  Then change line 269 from:
  ```python
  question_embedding = await embed_single(question)
  ```
  to:
  ```python
  question_embedding = await embed_single(search_query)
  ```

  **CRITICAL**: Do NOT change the `_build_prompt(retrieved_chunks, question, history)` call at line 323. It must continue using the original `question` variable, not `search_query`. The rewritten query is only for retrieval (embedding + vector search). Answer generation must use the user's original question.

  **File**: `backend/services/manual_rag_service.py`
  **Modify location**: Inside `ask()`, around line 269

**Checkpoint**: Foundation complete — the rewrite function exists and is wired into the pipeline. All user story behaviors now depend on this working correctly.

---

## Phase 3: User Story 1 — Contextual Follow-Up Questions Resolve Correctly (Priority: P1) MVP

**Goal**: Follow-up questions with pronouns/references ("what about the second point?", "tell me more about that") get rewritten into explicit queries before retrieval, producing relevant search results.

**Independent Test**: Open "Ask the AI" in the app. Ask "What is the inspection interval for the APU?" Wait for an answer. Then ask "Tell me more about that." The answer should be about APU inspections, not a generic response. Also ask "What about the second point?" after a multi-point answer and verify relevance.

### Implementation for User Story 1

- [x] T003 [US1] Verify first-turn passthrough behavior in `backend/services/manual_rag_service.py`

  **What to do**: Confirm that `_rewrite_query()` returns the original question unchanged when `history` is None or empty. This is already handled by the early return in T001, but verify by reading the function and tracing the flow. If the early return is missing, add it. No new code should be needed if T001 was done correctly — this is a verification task.

  **Acceptance check**: When a user sends their first message (no history), the system behaves identically to the current production behavior. The original question goes directly to `embed_single()`.

  **File**: `backend/services/manual_rag_service.py`

- [x] T004 [US1] Verify the rewrite prompt handles topic-switching correctly in `backend/services/manual_rag_service.py`

  **What to do**: Review the rewrite prompt text in `_rewrite_query()`. Confirm that the system instruction does NOT tell the model to "always incorporate history context" — it should only resolve references. If the user asks about APU, then asks about landing gear (a new topic), the rewrite should produce a query about landing gear, not force APU context into it. The prompt instruction "Resolve all pronouns and references" is correct — if there are no references to resolve, the model should return the new question largely unchanged. No code change should be needed if the prompt from T001 is correct.

  **Acceptance check**: A question like "What is the landing gear inspection procedure?" asked after APU questions should NOT be rewritten to include "APU" context.

  **File**: `backend/services/manual_rag_service.py`

**Checkpoint**: User Story 1 complete. Follow-up questions with references now retrieve relevant documents. First-turn questions are unaffected. Topic switches work correctly.

---

## Phase 4: User Story 2 — Transparent Rewriting With No Latency Perception (Priority: P2)

**Goal**: The rewrite step is invisible to the user. The original question text is shown in the conversation, not the rewritten version. Latency overhead is under 2 seconds typical.

**Independent Test**: Time the response with a follow-up question. Compare to a first-turn question (no rewrite). The difference should be under 2 seconds. Verify the conversation UI shows the user's original question text.

### Implementation for User Story 2

- [x] T005 [US2] Confirm original question is preserved in answer generation prompt in `backend/services/manual_rag_service.py`

- [x] T006 [US2] Verify rewrite timeout is set to 10 seconds in `backend/services/manual_rag_service.py`

  **What to do**: Confirm the `generate()` call inside `_rewrite_query()` uses `timeout=10.0`. This ensures the rewrite doesn't stall the pipeline. On the current server, Gemma e2b responds to short prompts in 1-3 seconds, so typical added latency will be well under 2 seconds.

  **Acceptance check**: The `generate()` call in `_rewrite_query()` passes `timeout=10.0`.

  **File**: `backend/services/manual_rag_service.py`

**Checkpoint**: User Story 2 complete. Rewriting is invisible to the user and adds minimal latency.

---

## Phase 5: User Story 3 — Graceful Fallback on Rewrite Failure (Priority: P3)

**Goal**: If Ollama is down or the rewrite call fails, the system falls back to the original query silently. The user always gets an answer.

**Independent Test**: Stop the Ollama service temporarily, send a follow-up question, verify the system still returns an answer (using the raw query for retrieval).

### Implementation for User Story 3

- [x] T007 [US3] Verify try/except fallback in `_rewrite_query()` in `backend/services/manual_rag_service.py`

  **What to do**: Confirm that the entire body of `_rewrite_query()` is wrapped in `try/except Exception` and that on any exception, it:
  1. Logs a warning (e.g., `logger.warning("Query rewrite failed, using original query: %s", e)`)
  2. Returns the original `question` string

  Also confirm that an empty response from `generate()` (after stripping) returns the original question — this handles the case where Ollama returns an empty string.

  **Acceptance check**: When Ollama is unreachable, the `ask()` function still proceeds with the original question and returns an answer. No error is surfaced to the user.

  **File**: `backend/services/manual_rag_service.py`

**Checkpoint**: All user stories complete. The pipeline handles happy path (rewrite succeeds), first-turn (no history), and failure (Ollama down) correctly.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final verification and cleanup.

- [ ] T008 End-to-end manual test following `specs/042-rag-query-rewrite/quickstart.md`

  **What to do**: Follow the 5-step test plan in `quickstart.md`:
  1. Start a conversation in "Ask the AI"
  2. Ask a topic question (e.g., "What is the APU inspection interval?")
  3. Ask a follow-up with a reference (e.g., "Tell me more about that")
  4. Verify the answer is relevant to the original topic
  5. Test a first-turn question with no history — should work identically to current behavior

  Report any issues found.

- [ ] T009 Verify no regressions in existing pipeline behavior

  **What to do**: Test that the following still work after the change:
  - First question with no history returns a relevant answer
  - Manual filtering (`manual_id` parameter) still works
  - Grounded/ungrounded detection still works
  - Source highlighting still works
  - The "not in available manuals" sentinel response still works

  **File**: `backend/services/manual_rag_service.py` (read-only verification)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Skipped — nothing needed.
- **Foundational (Phase 2)**: T001 → T002 (must be sequential — T002 calls function from T001)
- **User Story 1 (Phase 3)**: Depends on Phase 2 (T001, T002). T003, T004 are verification tasks.
- **User Story 2 (Phase 4)**: Depends on Phase 2. T005, T006 are verification tasks. Can run in parallel with US1 verification.
- **User Story 3 (Phase 5)**: Depends on Phase 2. T007 is a verification task. Can run in parallel with US1/US2 verification.
- **Polish (Phase 6)**: Depends on all user stories. T008, T009 are sequential end-to-end tests.

### User Story Dependencies

- **User Story 1 (P1)**: Depends only on Phase 2. No cross-story dependencies.
- **User Story 2 (P2)**: Depends only on Phase 2. Independent of US1.
- **User Story 3 (P3)**: Depends only on Phase 2. Independent of US1/US2.

### Within Each User Story

- All US verification tasks (T003-T007) can run after Phase 2 is complete.
- T003 and T004 (US1) can run in parallel.
- T005 and T006 (US2) can run in parallel.

### Parallel Opportunities

- After Phase 2 (T001 + T002): all verification tasks T003–T007 can run in parallel.
- T008 and T009 (Polish) are sequential end-to-end checks.

---

## Parallel Example: After Phase 2

```bash
# After T001 + T002 are complete, launch all verification tasks in parallel:
Task T003: "Verify first-turn passthrough behavior"
Task T004: "Verify topic-switching behavior"
Task T005: "Confirm original question preserved in prompt"
Task T006: "Verify rewrite timeout"
Task T007: "Verify try/except fallback"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: T001 (add `_rewrite_query()`) → T002 (wire into `ask()`)
2. Complete Phase 3: T003, T004 (verify core behavior)
3. **STOP and VALIDATE**: Test with a multi-turn conversation in "Ask the AI"
4. If working → deploy

### Incremental Delivery

1. T001 + T002 → Core rewrite wired in (MVP foundation)
2. T003 + T004 → US1 verified (follow-up questions work)
3. T005 + T006 → US2 verified (transparency and latency confirmed)
4. T007 → US3 verified (fallback works)
5. T008 + T009 → Full regression check

### LLM Execution Guide

**For the implementing LLM**: Execute T001 and T002 in sequence. These are the only tasks that write code. T003–T007 are verification/review tasks — read the code written in T001/T002 and confirm it satisfies each acceptance check. T008–T009 require running the app and testing manually (describe what to test if you cannot run the app).

**Single file modified**: `backend/services/manual_rag_service.py`. No other files are touched.

---

## Notes

- All implementation is in a SINGLE file: `backend/services/manual_rag_service.py`
- T001 and T002 are the only code-writing tasks — everything else is verification
- The rewritten query is ephemeral (in-memory only, not persisted)
- The existing `generate()` function is reused — no new Ollama integration code needed
- After implementation, restart the backend service: `sudo systemctl restart document_server.service`
