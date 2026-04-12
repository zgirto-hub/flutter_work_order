# Tasks: Chunk Reranking by Similarity Score

**Input**: Design documents from `/specs/044-chunk-rerank-scoring/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Tests**: No test tasks — not requested in spec. Manual testing via quickstart.md.

**Organization**: Tasks target a single file (`backend/services/manual_rag_service.py`). Organized by user story for traceability and independent verification.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `backend/` at repository root
- All changes in this feature are in `backend/services/manual_rag_service.py`

---

## Phase 1: Setup (Constants & Configuration)

**Purpose**: Add the named constants that all user stories depend on

- [X] T001 Add `MAX_CHUNK_DISTANCE` and `MAX_PROMPT_CHUNKS` constants to `backend/services/manual_rag_service.py`

**Details for T001**:
- Open `backend/services/manual_rag_service.py`
- After the existing `_SI_CACHE_TTL = 60.0` line (around line 20), add:
  ```python
  # Chunk reranking thresholds (spec 044)
  # MAX_CHUNK_DISTANCE: cosine distance ceiling; 0.30 distance = 0.70 similarity
  MAX_CHUNK_DISTANCE = 0.30
  # MAX_PROMPT_CHUNKS: max chunks sent to LLM after filtering
  MAX_PROMPT_CHUNKS = 3
  ```
- Do NOT modify any functions yet — just add the constants
- The existing `MAX_SOURCE_DISTANCE = 0.45` inside the `ask()` function will be removed in a later task

**Checkpoint**: Constants exist at module level. No behavior change yet.

---

## Phase 2: User Story 1 — Filter and Rerank Chunks (Priority: P1) 🎯 MVP

**Goal**: After pgvector retrieves 5 candidate chunks, filter out those with distance > 0.30 (similarity < 0.70), keep at most the top 3, and send only those to the language model.

**Independent Test**: Ask a specific technical question about an uploaded manual. The answer should be focused and reference only highly relevant content. Check backend logs for the filtering debug message showing how many chunks were retained.

### Implementation for User Story 1

- [X] T002 [US1] Add chunk filtering and slicing logic after pgvector retrieval in the `ask()` function of `backend/services/manual_rag_service.py`

**Details for T002**:
- In the `ask()` function, find the block after the pgvector RPC call (after `chunks_data = rpc_response.data or []` around line 387)
- After the existing early-return check for empty `chunks_data` (lines 391-396), insert the reranking step:
  ```python
  # --- Chunk reranking (spec 044) ---
  # Filter: keep only chunks within the distance threshold
  qualified_chunks = [
      c for c in chunks_data
      if c.get("distance", 1.0) <= MAX_CHUNK_DISTANCE
  ]
  # Slice: take at most MAX_PROMPT_CHUNKS (already sorted by distance ascending from RPC)
  qualified_chunks = qualified_chunks[:MAX_PROMPT_CHUNKS]

  logger.info(
      "Chunk reranking: %d retrieved → %d passed threshold (≤%.2f) → %d sent to LLM",
      len(chunks_data),
      len([c for c in chunks_data if c.get("distance", 1.0) <= MAX_CHUNK_DISTANCE]),
      MAX_CHUNK_DISTANCE,
      len(qualified_chunks),
  )
  ```
- IMPORTANT: The `chunks_data` list from pgvector is already sorted by distance ascending (closest first), so no re-sorting is needed. The filter + slice is sufficient.

- [X] T003 [US1] Update the prompt-building loop to use `qualified_chunks` instead of `chunks_data` in `backend/services/manual_rag_service.py`

**Details for T003**:
- Find the prompt-building section (around lines 398-419) where `retrieved_chunks` string and `sources` list are assembled
- Remove the `MAX_SOURCE_DISTANCE = 0.45` line (around line 401)
- Change the loop from iterating over `chunks_data` to iterating over `qualified_chunks`
- Since all qualified chunks already passed the distance threshold, ALL of them are valid sources — remove the `if distance <= MAX_SOURCE_DISTANCE:` conditional
- The updated loop should look like:
  ```python
  retrieved_chunks = ""
  sources = []
  for i, chunk in enumerate(qualified_chunks):
      manual_title = chunk.get("manual_title", "Unknown")
      source_page = chunk.get("source_page")
      content = chunk.get("content", "")
      retrieved_chunks += f"[Source {i + 1}: {manual_title}, page {source_page or '—'}]\n{content}\n---\n"
      sources.append(
          {
              "manual_id": chunk.get("manual_id"),
              "manual_title": manual_title,
              "chunk_index": chunk.get("chunk_index", 0),
              "source_page": source_page,
              "content_preview": content[:500],
          }
      )
  ```
- The `distance` variable is no longer needed in the loop since filtering already happened

**Checkpoint**: The core reranking is working. Ask a question with known relevant content — only top chunks should be used. Check logs for the filtering message.

---

## Phase 3: User Story 2 — Graceful "Not Found" When No Chunks Qualify (Priority: P2)

**Goal**: When all retrieved chunks score below the 0.70 similarity threshold (distance > 0.30), return the "information not found" response immediately without calling the language model.

**Independent Test**: Ask a completely unrelated question (e.g., "What is the capital of France?") when the knowledge base contains only aviation maintenance manuals. The system should return "not found" without invoking Ollama.

### Implementation for User Story 2

- [X] T004 [US2] Add early return for zero qualifying chunks after the reranking step in `backend/services/manual_rag_service.py`

**Details for T004**:
- After the reranking step added in T002 (after the `logger.info(...)` call), add:
  ```python
  if not qualified_chunks:
      return {
          "answer": "This information is not in the available manuals.",
          "grounded": False,
          "sources": [],
      }
  ```
- This MUST go BEFORE the prompt-building loop and BEFORE the `generate()` call
- This mirrors the existing early return for empty `chunks_data` (lines 391-396) but handles the case where pgvector returned results but none were relevant enough
- Note: The existing early return for `not chunks_data` (empty pgvector response) should remain untouched — it handles a different case (no chunks at all in the database)

**Checkpoint**: Ask an unrelated question. Verify the response is "not found" and that no Ollama generation call was made (no generation timing in response). Check logs showing "0 sent to LLM".

---

## Phase 4: User Story 3 — Source Attribution Matches Qualifying Chunks (Priority: P3)

**Goal**: Sources in the response correspond exactly to the chunks that were sent to the language model — no phantom sources from discarded chunks.

**Independent Test**: Ask a question and verify the `sources` array in the response has at most 3 entries, all corresponding to high-scoring chunks.

### Implementation for User Story 3

- [X] T005 [US3] Verify source assembly uses `qualified_chunks` and remove any legacy source-filtering logic in `backend/services/manual_rag_service.py`

**Details for T005**:
- This should already be handled by T003 (the loop now iterates `qualified_chunks` and adds ALL of them as sources)
- Verify that no other code path in `ask()` still references the old `MAX_SOURCE_DISTANCE` constant
- Verify the `final_sources` assembly (around lines 452-469) still works correctly — it reads from the `sources` list, which now only contains qualifying chunks
- The `compute_highlight()` call in the final_sources loop should work unchanged since it operates on content/answer text
- No code changes should be needed if T003 was done correctly — this task is a verification step

**Checkpoint**: Ask a question with known relevant content. Verify the `sources` array length matches the number of qualifying chunks (≤ 3). Verify each source's `content_preview` corresponds to a high-relevance chunk.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanup and validation

- [X] T006 Remove any dead code or unused imports related to the old source-filtering approach in `backend/services/manual_rag_service.py`

**Details for T006**:
- Search for any remaining references to `MAX_SOURCE_DISTANCE` — it should be completely gone
- Ensure there are no orphaned comments referencing "All 5 chunks go into the prompt" (the old comment at line 399)
- The `distance` variable should not be extracted in the source-building loop anymore (it was only used for the old threshold check)
- Do NOT remove or modify anything outside the `ask()` function and the new module-level constants

- [X] T007 Run end-to-end validation following `specs/044-chunk-rerank-scoring/quickstart.md`

**Details for T007**:
- Start the backend: `cd backend && uvicorn main:app --reload`
- Test 1: Upload a manual with known content (if not already present)
- Test 2: Ask a question with a clear answer in the manual → expect grounded response with ≤ 3 sources
- Test 3: Ask an unrelated question → expect "not found" response with empty sources
- Test 4: Check backend logs for `Chunk reranking:` messages showing correct filtering counts
- Test 5: Verify response includes `model` and `duration_seconds` fields (existing behavior preserved)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — add constants first
- **Phase 2 (US1)**: Depends on Phase 1 — uses the constants
- **Phase 3 (US2)**: Depends on Phase 2 — the early return goes after the filtering logic from T002
- **Phase 4 (US3)**: Depends on Phase 2 (T003) — verification that source assembly is correct
- **Phase 5 (Polish)**: Depends on all previous phases

### User Story Dependencies

- **US1 (P1)**: Core reranking — standalone after constants are added
- **US2 (P2)**: Zero-qualifying early return — builds on US1's filtering step
- **US3 (P3)**: Source verification — validates US1's source assembly change

### Execution Order (Sequential — Single File)

Since all tasks modify the same file (`backend/services/manual_rag_service.py`), they MUST be executed sequentially:

```
T001 → T002 → T003 → T004 → T005 → T006 → T007
```

No parallel opportunities exist because all tasks touch the same file.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001: Add constants
2. Complete T002 + T003: Filter, slice, and update prompt loop
3. **STOP and VALIDATE**: Test with a real question — verify fewer chunks in prompt, focused answer
4. This alone delivers the core value: better answers from filtered chunks

### Incremental Delivery

1. T001 → Constants ready
2. T002 + T003 → Core reranking working (MVP — US1 complete)
3. T004 → Graceful "not found" for irrelevant questions (US2 complete)
4. T005 → Source attribution verified (US3 complete)
5. T006 + T007 → Cleanup and end-to-end validation

---

## Notes

- All changes are in a **single file**: `backend/services/manual_rag_service.py`
- No database migrations needed
- No frontend changes needed
- No new dependencies needed
- The pgvector RPC returns chunks already sorted by distance ascending — no Python re-sorting required
- Distance metric: cosine distance where 0.0 = identical, 2.0 = opposite; threshold 0.30 = 0.70 similarity
- After implementation, have the reviewing LLM read the full modified `ask()` function and verify against spec.md acceptance scenarios
