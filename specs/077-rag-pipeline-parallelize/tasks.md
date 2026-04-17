# Tasks: RAG Pipeline Latency Optimization

**Input**: Design documents from `/specs/077-rag-pipeline-parallelize/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md
**Executor**: opencode LLM

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `backend/services/manual_rag_service.py` (primary file)
- No frontend, migration, or new file changes

---

## Phase 1: Setup

**Purpose**: No project setup needed — this is a single-file optimization. Skip to Phase 2.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add the `_is_direct_lookup()` helper function that US1 and US2 both depend on.

**⚠️ CRITICAL**: US1 (HyDE skip) depends on this helper being available.

- [x] T001 Add `_is_direct_lookup(query: str) -> bool` helper function in `backend/services/manual_rag_service.py`, placed just above the `ask()` function (around line 580). This function uses regex pattern matching to detect queries containing specific technical identifiers. It returns `True` if ANY of these patterns match (case-insensitive):
  1. **IP addresses**: `r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'` — any dotted-quad IPv4
  2. **Server hostnames**: `r'\b[a-z]{2,5}\d?-(ops|cont|mux)\b'` — matches patterns like `as1-ops`, `cs2-cont`, `efg-mux`, `eaip1-ops`, `cims1-cont`, `proxy1-ops`, etc.
  3. **Component names with numbers**: `r'\b(AIDA|ATS|CISECA|IMS|eAIP|Mux|EFG)\s*\d+\b'` — matches "AIDA 1", "ATS 2", "CISECA 1", "Mux 1", etc. Note: requires a number after the name (bare "AIDA" or "ATS" without a number should NOT match — those are too ambiguous)
  Import `re` at the top of the file if not already imported. Add a module-level compiled pattern `_DIRECT_LOOKUP_RE` for performance. Log the decision: `logger.info("[direct-lookup] query=%s, is_direct=%s", query[:80], result)`.

**Checkpoint**: Helper function ready. No behavioral change yet — existing pipeline untouched.

---

## Phase 3: User Story 1 — Faster Answers for Simple Factual Queries (Priority: P1) 🎯 MVP

**Goal**: Skip HyDE for direct factual lookups (hostnames, IPs, component names), saving ~15-20s per query.

**Independent Test**: Ask "what is as1-cont ip address?" via `/manuals/ask`. Response should have `hyde_ms` as `null` or `0` and total pipeline time should be noticeably faster than the ~55s baseline.

### Implementation for User Story 1

- [x] T002 [US1] Modify the `ask()` function in `backend/services/manual_rag_service.py` to skip HyDE when `_is_direct_lookup()` returns `True`. Current code (around lines 892-898):
  ```python
  # Current sequential code:
  with _StageTimer(breakdown, "hyde_ms"):
      _layer2_hyde_text = await _generate_hypothetical_answer(search_query)
  embed_input = _layer2_hyde_text if _layer2_hyde_text else search_query
  with _StageTimer(breakdown, "embed_ms"):
      _layer2_embedding = await embed_single(embed_input)
  ```
  Change to:
  ```python
  # Skip HyDE for direct lookups (spec 077)
  if _is_direct_lookup(search_query):
      _layer2_hyde_text = None
      breakdown["hyde_ms"] = 0
      logger.info("[spec-077] Skipping HyDE for direct lookup query")
  else:
      with _StageTimer(breakdown, "hyde_ms"):
          _layer2_hyde_text = await _generate_hypothetical_answer(search_query)
  embed_input = _layer2_hyde_text if _layer2_hyde_text else search_query
  with _StageTimer(breakdown, "embed_ms"):
      _layer2_embedding = await embed_single(embed_input)
  ```
  IMPORTANT: Do NOT change anything else in the `ask()` function yet. The rewrite stage, validated QA checks, embedding, retrieval, generation, and all response formatting must remain exactly as-is. Only the HyDE section changes.

**Checkpoint**: Direct factual queries now skip HyDE. Multi-turn queries still run sequentially (US2 addresses that next).

---

## Phase 4: User Story 2 — Faster Answers for Complex Multi-Turn Questions (Priority: P2)

**Goal**: Parallelize query rewrite and HyDE generation using `asyncio.gather()` for multi-turn conversations, saving ~10-15s.

**Independent Test**: Start a conversation ("how to restart CADAS-ATS?"), then ask a follow-up ("what about the logs?"). The combined rewrite + HyDE wall-clock time should be roughly equal to the slower stage (not the sum of both).

### Implementation for User Story 2

- [x] T003 [US2] Refactor the `ask()` function in `backend/services/manual_rag_service.py` to run rewrite and HyDE in parallel when both are needed. The current flow is:
  1. Line ~742: `search_query = await _rewrite_query(question, history)` (sequential)
  2. Lines ~892-898: HyDE + embed (sequential, after rewrite completes)
  
  Change the orchestration so that when conversation history IS present AND the query is NOT a direct lookup, rewrite and HyDE run concurrently via `asyncio.gather()`. Here is the exact logic:

  **After the post-rewrite validated QA check section (around line 876 "Layer 2" comment), replace the HyDE block with:**

  ```python
  # --- Layer 2: Document chunk search (spec 072, spec 074, spec 077) ---
  from services.document_search_service import (
      retrieve_chunks_per_document,
      build_direct_generation_prompt,
  )
  from services.ai_providers.resolver import generate as provider_generate

  _layer2_hyde_text = None
  _layer2_embedding = None
  provider_used = "local"
  fallback_used = False
  provider_display_name = "Local (Ollama)"

  try:
      # Spec 077: Skip HyDE for direct lookups
      if _is_direct_lookup(search_query):
          _layer2_hyde_text = None
          breakdown["hyde_ms"] = 0
          logger.info("[spec-077] Skipping HyDE for direct lookup query")
      else:
          with _StageTimer(breakdown, "hyde_ms"):
              _layer2_hyde_text = await _generate_hypothetical_answer(search_query)
      
      embed_input = _layer2_hyde_text if _layer2_hyde_text else search_query
      with _StageTimer(breakdown, "embed_ms"):
          _layer2_embedding = await embed_single(embed_input)
  ```

  **BUT ALSO**, move the rewrite + HyDE to run in parallel. The tricky part: rewrite currently runs at line ~742 (BEFORE validated QA post-rewrite check), and HyDE runs much later at line ~894 (AFTER validated QA). We CANNOT move HyDE earlier because if validated QA hits, we skip HyDE entirely.

  **Therefore, the parallel optimization applies ONLY when we reach the Layer 2 section (validated QA didn't hit)**. At that point, the rewrite has already completed. So the parallelization is actually between HyDE and the EMBEDDING of the rewrite result — but that's only ~1-5s savings.

  **ACTUALLY — the real parallelization opportunity**: Move the rewrite call AND HyDE call to happen concurrently BEFORE the validated QA post-rewrite check. Then use the rewrite result for validated QA check, and the HyDE result later for embedding. Here's how:

  Replace the current sequential flow (lines ~742-898) with this structure:

  **Step A**: Right after the pre-rewrite validated QA check (line ~737), determine if we need parallel execution:
  ```python
  # Spec 077: Parallel rewrite + HyDE when both are needed
  _needs_rewrite = bool(history)
  _needs_hyde = not _is_direct_lookup(question)  # Use original question for detection
  
  if _needs_rewrite and _needs_hyde:
      # Run both in parallel
      async def _timed_rewrite():
          with _StageTimer(breakdown, "rewrite_ms"):
              return await _rewrite_query(question, history)
      
      async def _timed_hyde():
          with _StageTimer(breakdown, "hyde_ms"):
              return await _generate_hypothetical_answer(question)
      
      rewrite_result, hyde_result = await asyncio.gather(
          _timed_rewrite(), _timed_hyde(), return_exceptions=True
      )
      
      # Handle rewrite result
      if isinstance(rewrite_result, Exception):
          logger.warning("[spec-077] Parallel rewrite failed: %s", rewrite_result)
          search_query = question
      else:
          search_query = rewrite_result
      
      # Handle HyDE result  
      if isinstance(hyde_result, Exception):
          logger.warning("[spec-077] Parallel HyDE failed: %s", hyde_result)
          _parallel_hyde_text = None
      else:
          _parallel_hyde_text = hyde_result
  elif _needs_rewrite:
      # Rewrite only (direct lookup — skip HyDE)
      with _StageTimer(breakdown, "rewrite_ms"):
          search_query = await _rewrite_query(question, history)
      _parallel_hyde_text = None
      breakdown["hyde_ms"] = 0
      logger.info("[spec-077] Skipping HyDE for direct lookup query")
  elif _needs_hyde:
      # No history — skip rewrite, run HyDE only
      search_query = question
      # HyDE will run later in Layer 2 section (existing flow)
      _parallel_hyde_text = None  # Sentinel: run HyDE in Layer 2
  else:
      # No history + direct lookup — skip both
      search_query = question
      _parallel_hyde_text = None
      breakdown["hyde_ms"] = 0
      breakdown["rewrite_ms"] = 0
      logger.info("[spec-077] Skipping both rewrite and HyDE")
  ```

  **Step B**: The follow-up system detection (lines ~748-757) remains unchanged — it uses `search_query` which is now set.

  **Step C**: The post-rewrite validated QA check (lines ~763-874) remains unchanged — it uses `search_query`.

  **Step D**: In the Layer 2 section, use the pre-computed HyDE result if available:
  ```python
  try:
      # Use pre-computed HyDE from parallel execution if available
      if _parallel_hyde_text is not None:
          _layer2_hyde_text = _parallel_hyde_text
      elif not _is_direct_lookup(search_query):
          # HyDE wasn't run in parallel (no history case) — run it now
          with _StageTimer(breakdown, "hyde_ms"):
              _layer2_hyde_text = await _generate_hypothetical_answer(search_query)
      else:
          _layer2_hyde_text = None
          if breakdown.get("hyde_ms") is None:
              breakdown["hyde_ms"] = 0
      
      embed_input = _layer2_hyde_text if _layer2_hyde_text else search_query
      with _StageTimer(breakdown, "embed_ms"):
          _layer2_embedding = await embed_single(embed_input)
  ```

  **CRITICAL REQUIREMENTS**:
  - Do NOT change the pre-rewrite validated QA check (lines 633-737) — it must still use `question` (original)
  - Do NOT change the post-rewrite validated QA check logic — it must still use `search_query`
  - Do NOT change anything after the embedding step — retrieval, generation, response formatting all remain the same
  - Import `asyncio` at the top of the file if not already imported
  - The `_StageTimer` context manager must still be used for each stage (works correctly in concurrent coroutines since each writes to a different key)
  - All existing error handling and fallback paths must be preserved

**Checkpoint**: Both optimizations active. Direct lookups skip HyDE. Multi-turn queries run rewrite + HyDE in parallel.

---

## Phase 5: User Story 3 — Accurate Latency Reporting (Priority: P3)

**Goal**: Ensure `latency_breakdown` correctly reflects parallel execution and skipped stages.

**Independent Test**: Ask a question and check the `latency_breakdown` object in the response. When rewrite + HyDE ran in parallel, `total_ms` should be less than `rewrite_ms + hyde_ms`. When HyDE was skipped, `hyde_ms` should be `0`.

### Implementation for User Story 3

- [x] T004 [US3] Verify and adjust latency reporting in `backend/services/manual_rag_service.py`. Check that:
  1. When HyDE is skipped: `breakdown["hyde_ms"]` is set to `0` (not `None`) — this was done in T002/T003 but verify it's consistent across all code paths
  2. When rewrite is skipped (no history): `breakdown["rewrite_ms"]` should remain `None` (existing behavior) or be set to `0` — pick `0` for consistency with HyDE skip, and set it in all skip paths
  3. When both run in parallel: each `_StageTimer` correctly measures its own wall-clock time independently — verify by reading the `_StageTimer` implementation and confirming it uses `time.perf_counter()` start/stop per instance
  4. Add a log line at the end of the Layer 2 section (before the response return) that outputs the full breakdown for debugging: `logger.info("[spec-077] latency_breakdown=%s", {k: v for k, v in breakdown.items() if v is not None})`
  No structural changes — just verification and minor consistency fixes.

**Checkpoint**: Latency breakdown is accurate and consistent across all execution paths.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final verification and cleanup.

- [x] T005 Review all changes in `backend/services/manual_rag_service.py` for:
  1. No duplicate imports (`asyncio`, `re` — add only if not already present)
  2. No orphaned code from the old sequential flow
  3. All `logger.info` messages use the `[spec-077]` prefix for easy log filtering
  4. The `_DIRECT_LOOKUP_RE` compiled regex is at module level (not inside a function)
  5. No changes to function signatures — `ask()`, `_rewrite_query()`, `_generate_hypothetical_answer()` keep the same signatures
- [x] T006 Run quickstart.md validation: start the backend and test these queries via the frontend AI assistant:
  1. Direct lookup: "what is as1-cont ip address?" — expect `hyde_ms: 0`, answer found
  2. Direct lookup with IP: "what is 172.31.11.1?" — expect `hyde_ms: 0`
  3. Ambiguous query: "how to restart the server?" — expect HyDE to run (hyde_ms > 0)
  4. Multi-turn: Ask "how to restart CADAS-ATS?" then follow up with "what about the logs?" — expect both `rewrite_ms` and `hyde_ms` > 0, total_ms faster than baseline
  5. Verified QA hit: Ask a previously validated question — expect early return, no HyDE

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 2 (Foundational)**: No dependencies — start immediately
- **Phase 3 (US1)**: Depends on T001 (`_is_direct_lookup` helper)
- **Phase 4 (US2)**: Depends on T001 (`_is_direct_lookup` helper). Can run in parallel with US1 but modifies the same code section, so run sequentially: T001 → T002 → T003
- **Phase 5 (US3)**: Depends on T002 and T003 (needs all paths implemented)
- **Phase 6 (Polish)**: Depends on all previous phases

### Execution Order (Sequential — Single File)

Since all tasks modify the same file (`manual_rag_service.py`), they MUST run sequentially:

```
T001 → T002 → T003 → T004 → T005 → T006
```

No parallel opportunities exist because all tasks touch the same file.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001 (helper function)
2. Complete T002 (HyDE skip for direct lookups)
3. **STOP and VALIDATE**: Test direct lookup queries — should be ~15-20s faster
4. Deploy if ready — this alone provides significant value

### Full Implementation

1. T001 → T002 → MVP deployed
2. T003 (parallel rewrite + HyDE) → incremental speedup for multi-turn
3. T004 → T005 → T006 → polish and verify

---

## Notes

- All changes are in a single file: `backend/services/manual_rag_service.py`
- No database migrations, no frontend changes, no new dependencies
- The `asyncio` module should already be imported (check first)
- The `re` module may need to be added
- Commit after each task for easy rollback
- Test with real queries on the deployed server to measure actual latency improvement
