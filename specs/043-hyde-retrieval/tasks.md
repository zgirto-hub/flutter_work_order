# Tasks: HyDE Retrieval for Manual Assistant

**Input**: Design documents from `/specs/043-hyde-retrieval/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Tests**: Not explicitly requested — test tasks omitted. Validation is via manual testing per quickstart.md.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Context for implementer**: You are modifying a single file: `backend/services/manual_rag_service.py`. The existing RAG pipeline in the `ask()` function (line ~304) currently does: query rewrite → embed query → pgvector search → generate answer. You are inserting a HyDE step between query rewrite and embed. Read the entire file before making changes.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: No setup needed — this feature modifies an existing file with no new dependencies.

*(No tasks in this phase)*

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Read and understand the existing code before making changes.

- [X] T001 Read the entire `backend/services/manual_rag_service.py` file. Understand the `ask()` function pipeline: `_rewrite_query()` at line ~328, `embed_single()` at line ~332, pgvector RPC at line ~348, `_build_prompt()` at line ~386, `generate()` at line ~392. Note that `_build_prompt()` uses the original `question` parameter, not `search_query`.

- [X] T002 Read `backend/services/ollama_generator.py` to understand the `generate()` function signature: `generate(prompt: str, model: str | None = None, timeout: float = 180.0) -> str`. Note the `GeneratorTimeoutError` and `GeneratorModelError` exceptions. You will call this function from your new HyDE function with a custom timeout.

- [X] T003 Read `backend/services/ollama_embedder.py` to understand `embed_single(text: str) -> List[float]`. This is what you will call with the HyDE output instead of the raw query.

**Checkpoint**: You understand the existing pipeline and where HyDE fits in.

---

## Phase 3: User Story 1 - Vague Question Gets Relevant Results (Priority: P1) 🎯 MVP

**Goal**: Add the `_generate_hypothetical_answer()` function and wire it into the `ask()` pipeline so that vague questions produce better vector search results.

**Independent Test**: Ask a vague question via `POST /manuals/ask` (e.g., "what do I need to know about landing gear?") and check server logs for "HyDE generated hypothetical answer". Verify the answer references relevant manual sections.

### Implementation for User Story 1

- [X] T004 [US1] Add the `_generate_hypothetical_answer()` async function in `backend/services/manual_rag_service.py`, placed between the existing `_rewrite_query()` function (ends ~line 301) and the `ask()` function (starts ~line 304). The function must:

  **Signature**: `async def _generate_hypothetical_answer(query: str) -> str | None`

  **Prompt to send to the LLM** (use a triple-quoted string variable `hyde_prompt`):
  ```
  You are a technical writer for civil aviation maintenance manuals.
  Given the following question, write a short passage (1-2 paragraphs) that would appear in a civil aviation technical manual answering this question.
  Write in the same language as the question (Arabic or English).
  Do not add any preamble, disclaimer, or explanation. Write ONLY the manual passage.

  QUESTION: {query}

  MANUAL PASSAGE:
  ```

  **Implementation details**:
  - Import `generate` from `services.ollama_generator` (use local import like `_rewrite_query` does)
  - Call `await generate(hyde_prompt, timeout=15.0)` — do NOT pass a `model` parameter (use the default model, same as final answer generation)
  - Strip the result. If the stripped result is empty, log `logger.warning("HyDE generation returned empty, falling back to direct query embedding")` and return `None`
  - On success, log `logger.info("HyDE generated hypothetical answer (%d chars)", len(result))` and return the stripped result
  - Wrap the entire body in a try/except that catches `Exception`. On any exception, log `logger.warning("HyDE generation failed, falling back to direct query embedding: %s", e)` and return `None`

- [X] T005 [US1] Modify the `ask()` function in `backend/services/manual_rag_service.py` to call `_generate_hypothetical_answer()` and use its output for embedding. Find the section after `search_query = await _rewrite_query(question, history)` (line ~328) and before `question_embedding = await embed_single(search_query)` (line ~332). Insert the HyDE call between them:

  ```python
  # HyDE: generate hypothetical answer for better embedding
  hyde_text = await _generate_hypothetical_answer(search_query)
  embed_input = hyde_text if hyde_text else search_query
  ```

  Then change the existing `embed_single(search_query)` call to `embed_single(embed_input)`:
  ```python
  question_embedding = await embed_single(embed_input)
  ```

  **CRITICAL**: Do NOT change anything else in the `ask()` function. The `_build_prompt(retrieved_chunks, question, history)` call at line ~386 must still use the original `question` variable (not `search_query`, not `hyde_text`). This is already the case — just verify you don't accidentally change it.

**Checkpoint**: At this point, every question to `POST /manuals/ask` goes through HyDE. Vague questions should retrieve more relevant chunks. Check server logs for the HyDE info/warning messages.

---

## Phase 4: User Story 2 - Follow-Up Question with Query Rewrite + HyDE (Priority: P2)

**Goal**: Verify that the pipeline composes correctly: query rewrite resolves pronouns first, then HyDE generates a hypothetical answer from the rewritten query.

**Independent Test**: Start a conversation (send a question with history), then send a follow-up with pronouns. Check logs show both "rewrite" and "HyDE" steps executing in sequence.

### Implementation for User Story 2

- [X] T006 [US2] No code changes needed — this story is satisfied by the T004-T005 implementation because `_generate_hypothetical_answer(search_query)` already receives the output of `_rewrite_query()`. Verify by reading the `ask()` function and confirming:
  1. `search_query = await _rewrite_query(question, history)` runs first
  2. `hyde_text = await _generate_hypothetical_answer(search_query)` runs second with the rewritten query
  3. When `history` is empty, `_rewrite_query` returns the original question unchanged, and HyDE runs on it directly

  If the ordering is correct, mark this task complete. If not, fix the ordering so rewrite always precedes HyDE.

**Checkpoint**: Multi-turn conversations work correctly with both query rewrite and HyDE in sequence.

---

## Phase 5: User Story 3 - Graceful Fallback When HyDE Fails (Priority: P2)

**Goal**: Confirm that HyDE failures are handled gracefully — the system falls back to embedding the query directly without any user-visible error.

**Independent Test**: Temporarily break the HyDE prompt (e.g., set timeout to 0.001) and verify the system still returns answers. Check logs for the fallback warning.

### Implementation for User Story 3

- [X] T007 [US3] No additional code changes needed — fallback is already built into T004 and T005:
  - T004: `_generate_hypothetical_answer()` returns `None` on any failure
  - T005: `embed_input = hyde_text if hyde_text else search_query` falls back to `search_query` when `hyde_text` is `None`

  Verify by reading the code and confirming:
  1. Every exception in `_generate_hypothetical_answer()` is caught and returns `None`
  2. Empty responses return `None`
  3. The `ask()` function uses `search_query` as fallback when `hyde_text` is `None`

  If all three are confirmed, mark this task complete.

**Checkpoint**: The system is resilient to HyDE failures.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and cleanup.

- [ ] T008 Run quickstart.md validation: Start the FastAPI server, ensure Ollama is running with gemma4:e2b and nomic-embed-text. Send a vague question via `POST /manuals/ask` (e.g., `{"question": "what do I need to know about landing gear?", "user_email": "test@test.com"}`). Confirm:
  1. Server logs show "HyDE generated hypothetical answer (N chars)"
  2. Response contains a grounded answer with relevant sources
  3. `duration_seconds` in response is reasonable (existing time + <5s for HyDE)

- [ ] T009 Verify no regressions: Send a specific factual question (e.g., `{"question": "What is the torque specification for AN3-7A bolts?", "user_email": "test@test.com"}`). Confirm the answer quality is at least as good as before (HyDE should not degrade specific queries).

- [ ] T010 Verify multi-turn works: Send a question with conversation history (include `history` array in the request). Confirm both query rewrite and HyDE execute (check logs for both messages).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Empty — skip
- **Foundational (Phase 2)**: T001-T003 are read-only; complete before any code changes
- **User Story 1 (Phase 3)**: T004-T005 — the only code changes. Depends on Phase 2 understanding.
- **User Story 2 (Phase 4)**: T006 — verification only. Depends on Phase 3.
- **User Story 3 (Phase 5)**: T007 — verification only. Depends on Phase 3.
- **Polish (Phase 6)**: T008-T010 — manual testing. Depends on all user stories.

### User Story Dependencies

- **User Story 1 (P1)**: Core implementation. No dependencies on other stories.
- **User Story 2 (P2)**: Verification only. Depends on US1 being implemented (T004-T005).
- **User Story 3 (P2)**: Verification only. Depends on US1 being implemented (T004-T005).

### Within Each User Story

- T004 (new function) must complete before T005 (wiring into ask())
- T006 and T007 can run in parallel after T005

### Parallel Opportunities

- T001, T002, T003 (reading files) can all run in parallel
- T006 and T007 (verification) can run in parallel after T005
- T008, T009, T010 (testing) must run sequentially (they share the server)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Read existing code (T001-T003)
2. Complete Phase 3: Implement HyDE function + wire into pipeline (T004-T005)
3. **STOP and VALIDATE**: Test with a vague question, check logs
4. If working, proceed to verification phases

### Full Delivery

1. T001-T003: Understand existing code
2. T004: Write `_generate_hypothetical_answer()` function
3. T005: Wire it into `ask()` pipeline
4. T006-T007: Verify composition and fallback (parallel)
5. T008-T010: End-to-end testing

---

## Notes

- This is a **single-file change** to `backend/services/manual_rag_service.py`
- The only new code is ~30 lines: the `_generate_hypothetical_answer()` function and 2 lines in `ask()`
- No new files, no new dependencies, no migrations, no frontend changes
- The API contract (`POST /manuals/ask` request/response) is unchanged
- The hypothetical answer is NEVER returned to the user — it is only used for embedding
- The original user question is ALWAYS used in the final answer prompt
