# Tasks: RAG Latency Optimization

**Input**: Design documents from `/specs/074-rag-latency-optimization/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md
**Implementer**: opencode (Claude Code will review after implementation)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Baseline Capture)

**Purpose**: Record pre-optimization baselines so we can measure improvement

- [x] T001 Run `backend/tests/test_rag_quality.py` and save output as baseline in `specs/074-rag-latency-optimization/baseline_quality.txt`
- [x] T002 Record current pipeline timing by asking 3 test questions via `/manuals/ask` and noting `latency_breakdown` values in `specs/074-rag-latency-optimization/baseline_latency.txt`

---

## Phase 2: Foundational (Direct Generation Prompt Builder)

**Purpose**: Create the new prompt builder function that replaces sub-answers + synthesis. This MUST be complete before US1 can wire it into the pipeline.

**CRITICAL**: No user story work can begin until this phase is complete.

- [x] T003 Add `build_direct_generation_prompt(chunks_by_document, question, system_prompt)` function in `backend/services/document_search_service.py`. This function MUST:
  - Accept the same `chunks_by_document` dict that `generate_document_sub_answers()` currently receives (keys are doc IDs, values are lists of chunk dicts with `display_name`, `section_title`, `page_number`, `content`, `parent_content`)
  - Format ALL qualifying chunks from ALL documents into a single context block using the pattern: `[Document Source N]\nDocument: {display_name}\nSection: {section_title}\nPage: {page}\n\n{parent_content or content}`
  - Prepend the system prompt (`DOCUMENT_QA_SYSTEM_PROMPT` from `manual_rag_service.py`)
  - Append `QUESTION: {question}\n\nANSWER:` at the end
  - Return the complete prompt string
  - Also return a flat list of source dicts (document_id, display_name, section_title, page_number, similarity) for the response `sources` array
  - Collect `documents_consulted` list of `{"id": doc_id, "title": display_name}` dicts for the response

**Checkpoint**: `build_direct_generation_prompt()` exists and can be called — not yet wired into the pipeline.

---

## Phase 3: User Story 1 - Direct Generation (Priority: P1) MVP

**Goal**: Replace per-document sub-answers + synthesis with a single generation call. This is the biggest latency win (eliminates 3-9 LLM calls → 1).

**Independent Test**: Ask a question that hits the document pipeline. Response should arrive in <25s with correct sources.

### Implementation for User Story 1

- [x] T004 [US1] In `backend/services/manual_rag_service.py`, in the `ask()` function, replace the Layer 2 sub-answer + synthesis block (lines ~884-961, the section that calls `generate_document_sub_answers()` then `synthesize_document_answers()`) with a direct generation flow:
  1. After `chunks_by_doc` is retrieved (line ~873), call `build_direct_generation_prompt(chunks_by_doc, search_query, DOCUMENT_QA_SYSTEM_PROMPT)` to get the combined prompt and sources
  2. Make a SINGLE call to `provider_generate(prompt, [], user_email, latency_breakdown=breakdown)` — this replaces up to 9 LLM calls
  3. Check if the answer is grounded (same `_SENTINEL_PHRASES` check as current code)
  4. If grounded, build the response dict with the same schema: `answer`, `grounded`, `sources`, `confidence`, `score`, `source_type="document"`, `model`, `provider_display_name`, `duration_seconds`, `is_verified=False`, `verified_source=None`, `manuals_consulted`, `has_conflicts`, `retrieval_info`, `provider_used`, `fallback_used`, `session_summary=None`, `latency_breakdown`
  5. For `has_conflicts`, check for "CONFLICT:" or "تعارض:" in the answer (same as current `synthesize_document_answers`)
  6. The `generator_ms` field in `latency_breakdown` should capture the single generation call timing (use `_StageTimer(breakdown, "generator_ms")`)
  7. If not grounded, fall through to the existing fallback ("This information is not in the available manuals.")

- [x] T005 [US1] Remove or comment out the imports of `generate_document_sub_answers` and `synthesize_document_answers` from `manual_rag_service.py` (line ~854-858). These are no longer called.

- [x] T006 [US1] In `backend/services/document_search_service.py`, mark `generate_document_sub_answers()` and `synthesize_document_answers()` as deprecated by adding a docstring note: `"""DEPRECATED (spec 074): Replaced by build_direct_generation_prompt + single provider_generate call."""`. Do NOT delete them yet — keep for reference during review.

- [x] T007 [US1] Add a log line in the direct generation path: `logger.info("direct_generation", extra={"documents": len(chunks_by_doc), "max_score": max_score})` to satisfy FR-010 (log pipeline path).

**Checkpoint**: Ask a multi-document question. Should get a grounded answer in <25s with correct sources and `latency_breakdown.generator_ms` populated.

---

## Phase 4: User Story 2 - Overlap LLM with Non-LLM Stages (Priority: P2)

**Goal**: Ensure non-LLM work (embedding, DB retrieval) isn't blocked waiting for LLM calls when it doesn't need to be. Since Ollama serializes LLM requests, we focus on overlapping LLM with non-LLM, not parallel LLM calls.

**Independent Test**: Ask a follow-up question (with history). Verify `latency_breakdown` shows reasonable times without unnecessary sequential delays.

### Implementation for User Story 2

- [x] T008 [US2] In `backend/services/manual_rag_service.py`, in the `ask()` function, verify that after query rewrite completes, the follow-up system detection (lines ~724-732) runs immediately (it already does — this is a verification, not a code change). Document with a comment: `# System detection runs synchronously here while HyDE is about to start — no wasted time.`

- [x] T009 [US2] Verify the current stage ordering in `ask()` is already optimal for the single-GPU constraint:
  1. Validated QA pre-rewrite (DB) ✓
  2. Query rewrite (LLM, skipped if no history) ✓
  3. Validated QA post-rewrite (DB) ✓
  4. HyDE (LLM) ✓
  5. Embedding (non-LLM, uses nomic-embed — different model, may truly parallelize with Ollama LLM) ✓
  6. Retrieval (DB) ✓
  7. Direct generation (LLM) ✓
  
  If the ordering is already optimal (it should be after T004), add a comment block at the top of the Layer 2 section: `# Pipeline stage ordering optimized for single-GPU Ollama (spec 074): LLM calls are serialized, non-LLM (embed, DB) interleaved where possible.`

**Checkpoint**: Follow-up questions work correctly. `rewrite_ms` shows timing when history present, null when absent.

---

## Phase 5: User Story 3 - Skip Unnecessary Stages (Priority: P3)

**Goal**: Extend the existing fast-path pattern so simple queries avoid expensive stages.

**Independent Test**: Ask a standalone question (no history) — verify `rewrite_ms` is null. Ask a validated_qa-cached question — verify only `generator_ms` is populated.

### Implementation for User Story 3

- [x] T010 [US3] In `backend/services/manual_rag_service.py`, verify that `_rewrite_query()` already returns the original question immediately when `history` is falsy (line ~414: `if not history: return question`). If so, ensure `_StageTimer` records `rewrite_ms` as 0 or null when skipped. Currently the timer wraps the call at line ~717-718 — check if a skipped rewrite (immediate return) correctly results in `rewrite_ms` being near-zero. If it records a few ms, that's fine. Document with a comment if no change needed.

- [x] T011 [US3] Verify the validated_qa fast-path (pre-rewrite at line ~610 and post-rewrite at line ~740) already bypasses HyDE, retrieval, and generation when a high-confidence match is found (returns early with `source_type: "validated_qa"`). Confirm that `latency_breakdown` fields for skipped stages remain `None` in the response. No code change expected — just verification.

**Checkpoint**: Both fast-paths work correctly. Latency breakdown accurately reflects which stages were skipped.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup, validation, and quality verification

- [x] T012 Run `backend/tests/test_rag_quality.py` and compare results against baseline from T001. Answer quality MUST NOT degrade. If any test fails, investigate and fix the direct generation prompt before proceeding.

- [x] T013 Test 3 representative questions via the "Ask the AI" assistant and verify:
  - Response time < 25s for document-retrieval questions
  - Sources include document name, section title, page number
  - `latency_breakdown` has all fields populated correctly (generator_ms for the single call, hyde_ms, etc.)
  - `source_type` is "document" for document answers, "validated_qa" for cached answers

- [x] T014 Remove the deprecated function bodies from `backend/services/document_search_service.py` — delete `generate_document_sub_answers()` and `synthesize_document_answers()` entirely. They were marked deprecated in T006 and are no longer called after T004/T005.

- [x] T015 Clean up any unused imports in both `backend/services/manual_rag_service.py` and `backend/services/document_search_service.py`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: No dependency on Phase 1 (baselines are informational)
- **User Story 1 (Phase 3)**: Depends on Phase 2 (T003 must be complete)
- **User Story 2 (Phase 4)**: Depends on Phase 3 (pipeline must be refactored first)
- **User Story 3 (Phase 5)**: Can start after Phase 3 (independent of Phase 4)
- **Polish (Phase 6)**: Depends on Phases 3-5

### User Story Dependencies

- **User Story 1 (P1)**: Depends on T003 (foundational prompt builder). THIS IS THE MVP.
- **User Story 2 (P2)**: Depends on US1 completion (stage ordering only makes sense after sub-answers removed)
- **User Story 3 (P3)**: Depends on US1 completion (verification tasks need the refactored pipeline)

### Within Each User Story

- T004 must complete before T005-T007 (core refactor first, then cleanup)
- T008 and T009 are independent within US2
- T010 and T011 are independent within US3

### Parallel Opportunities

- T001 and T002 can run in parallel (baseline capture)
- T008 and T009 can run in parallel (US2 verification tasks)
- T010 and T011 can run in parallel (US3 verification tasks)
- T014 and T015 can run in parallel (cleanup tasks)

---

## Parallel Example: User Story 3

```bash
# These US3 tasks can run together (both are verification, different code paths):
Task T010: "Verify rewrite skip behavior in manual_rag_service.py"
Task T011: "Verify validated_qa fast-path bypass in manual_rag_service.py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: T003 (build prompt builder)
2. Complete Phase 3: T004-T007 (wire into pipeline, cleanup imports, add logging)
3. **STOP and VALIDATE**: Run test_rag_quality.py — quality must not degrade
4. Deploy if ready — this alone delivers the 60%+ latency reduction

### Incremental Delivery

1. T003 → Foundation ready
2. T004-T007 → US1 complete → Test → This is the MVP, delivers core value
3. T008-T009 → US2 complete → Verification + comments (low risk)
4. T010-T011 → US3 complete → Verification + comments (low risk)
5. T012-T015 → Polish → Final cleanup and validation

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- The core code change is T003 + T004 — everything else is verification, cleanup, or comments
- After opencode implements, Claude Code will run superpowers code review
- Commit after each phase checkpoint
- Do NOT delete deprecated functions until Phase 6 (T014) — keep for reference during review
