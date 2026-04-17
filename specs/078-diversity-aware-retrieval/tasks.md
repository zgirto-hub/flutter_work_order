# Tasks: Diversity-Aware Retrieval Strategy

**Input**: Design documents from `/specs/078-diversity-aware-retrieval/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md
**Implementor**: opencode
**Reviewer**: Claude Code (superpowers code review)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: No new files or dependencies needed. This feature modifies one existing file.

- [X] T001 Read and understand the current `retrieve_chunks_per_document()` function in `backend/services/document_search_service.py` (lines 12-113). Note: this is the ONLY function to modify. Do NOT modify `search_document_chunks()` (line 116) — it is unused in the pipeline.

**Checkpoint**: Understand current behavior before making changes.

---

## Phase 2: Foundational — Diversity Selection Helper

**Purpose**: Create the core diversity selection logic as a private helper function.

- [X] T002 Add a private helper function `_diversity_select()` in `backend/services/document_search_service.py` (add it between the existing module-level constants at line 9 and the `retrieve_chunks_per_document` function at line 12). The function signature MUST be:

```python
def _diversity_select(
    chunks_by_document: dict[str, list[dict]],
    top_docs_count: int = 3,
    max_chunks_per_doc: int = 3,
    diversity_floor_threshold: float = 0.60,
) -> dict[str, list[dict]]:
```

Implementation requirements:
1. For each document, compute a document relevance score = sum of the top-3 chunk **similarity** values (NOT distance). Each chunk dict already has a `"similarity"` key.
2. Rank documents by their aggregate score descending. Break ties by highest individual chunk similarity (most precise match wins).
3. Select the top `top_docs_count` documents as "winning" documents.
4. Apply diversity floor: for any document NOT in the winning set, if its highest chunk similarity >= `diversity_floor_threshold`, add exactly 1 chunk (the highest-scoring one) as a "floor" entry.
5. From each winning document, keep up to `max_chunks_per_doc` chunks sorted by similarity descending.
6. Merge winning chunks and floor chunks into a single `dict[str, list[dict]]` (document_id → chunks).
7. Log at INFO level: document scores, which documents won, which got floor slots. Use the existing `logger` already defined in the file.
8. Return the result dict.

**Checkpoint**: `_diversity_select()` exists and is a pure function (no DB calls, no side effects besides logging).

---

## Phase 3: User Story 1 — Single-Topic Dedup (Priority: P1) MVP

**Goal**: Single-topic queries return clean, non-redundant context from the most relevant document.

**Independent Test**: Run `python backend/tests/test_rag_quality.py --category 11` — MHS System Diagnosis questions should pass without duplicating frequentis_system_diagnosis chunks.

- [X] T003 [US1] Modify `retrieve_chunks_per_document()` in `backend/services/document_search_service.py` to increase the initial RPC `match_count` from `10` to `20` (line 23). This gives the diversity algorithm more candidates to work with.

- [X] T004 [US1] Modify `retrieve_chunks_per_document()` in `backend/services/document_search_service.py` to call `_diversity_select()` after the initial chunk grouping. Replace the current document ranking logic (lines 56-69, the `qualified_docs` section that caps at `max_chunks_per_doc` and ranks by average distance) with a call to `_diversity_select()`. Pass through the function's existing `max_chunks_per_doc` and `max_documents` parameters. The updated function signature should add new keyword arguments:

```python
async def retrieve_chunks_per_document(
    embedding_str: str,
    max_chunks_per_doc: int = MAX_CHUNKS_PER_DOCUMENT,
    max_documents: int = MAX_DOCUMENTS_FOR_SYNTHESIS,
    top_docs_count: int = 3,
    diversity_floor_threshold: float = 0.60,
) -> dict[str, list[dict]]:
```

The existing call-site in `manual_rag_service.py:991` passes no keyword arguments, so backward compatibility is preserved automatically.

- [X] T005 [US1] Verify by running `python backend/tests/test_rag_quality.py --category 1 --category 2` that direct retrieval and procedural questions still pass. Compare results against the previous baseline (50/51 = 98%).

**Checkpoint**: Single-topic dedup works. Overlapping documents no longer dominate results.

---

## Phase 4: User Story 2 — Cross-Manual Preservation (Priority: P1)

**Goal**: Cross-manual synthesis queries still get chunks from multiple relevant documents thanks to the diversity floor.

**Independent Test**: Run `python backend/tests/test_rag_quality.py --category 3` — all 5 cross-manual synthesis questions should pass.

- [X] T006 [US2] Verify cross-manual synthesis by running `python backend/tests/test_rag_quality.py --category 3`. All 5 questions MUST pass. If any fail, adjust `diversity_floor_threshold` (try 0.55 or 0.50) until cross-manual questions pass without regressing single-topic questions.

- [X] T007 [US2] Run the FULL test suite `python backend/tests/test_rag_quality.py` and compare against the baseline. The overall score MUST be >= 98% (50/51 or better on the expanded 68-question suite). Save the results JSON for review.

**Checkpoint**: Both single-topic dedup AND cross-manual synthesis work together.

---

## Phase 5: User Story 3 — Backward Compatibility (Priority: P2)

**Goal**: Existing call-sites work without modification.

**Independent Test**: The RAG pipeline still answers questions correctly end-to-end.

- [X] T008 [US3] Verify that `manual_rag_service.py:991` (`chunks_by_doc = await retrieve_chunks_per_document(embedding_str)`) still works without passing any new keyword arguments. Test by asking a question via the API: `curl -sk https://zorin.taila92fe8.ts.net/api/manuals/ask -X POST -H "Content-Type: application/json" -d '{"question":"How do I check disk usage on AIDA-NG?","user_email":"test@test.com","history":[]}'` — the response should be grounded with relevant sources.

**Checkpoint**: End-to-end pipeline works with no changes to callers.

---

## Phase 6: Polish & Cross-Cutting

**Purpose**: Final validation and cleanup.

- [X] T009 Run `python backend/tests/test_rag_quality.py --verify` to check for subtle hallucinations with the new retrieval strategy. No new hallucinations should appear.

- [X] T010 Review all logging output from `_diversity_select()` — confirm it logs document scores, winning docs, and floor docs at INFO level without being excessively verbose.

- [X] T011 Commit all changes with a descriptive message referencing spec 078.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — read and understand code
- **Phase 2 (Foundational)**: Depends on Phase 1 — write the helper function
- **Phase 3 (US1)**: Depends on Phase 2 — wire helper into retrieve function
- **Phase 4 (US2)**: Depends on Phase 3 — verify floor works for cross-manual
- **Phase 5 (US3)**: Depends on Phase 3 — verify backward compat
- **Phase 6 (Polish)**: Depends on all previous phases

### User Story Dependencies

- **US1 (P1)**: Depends on foundational `_diversity_select()` only
- **US2 (P1)**: Depends on US1 being complete (same function)
- **US3 (P2)**: Can be verified after US1; independent of US2

### Parallel Opportunities

- T006 and T008 can run in parallel (different verification paths)
- T009 and T010 can run in parallel (different validation concerns)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Read existing code
2. Complete Phase 2: Write `_diversity_select()` helper
3. Complete Phase 3: Wire into `retrieve_chunks_per_document()` and test
4. **STOP and VALIDATE**: Run category 1-2 tests

### Incremental Delivery

1. T001-T002 → Helper function ready
2. T003-T005 → Single-topic dedup verified (MVP!)
3. T006-T007 → Cross-manual synthesis verified
4. T008 → Backward compatibility verified
5. T009-T011 → Polish and commit

---

## Notes

- **Target file**: `backend/services/document_search_service.py` — this is the ONLY file that needs code changes
- **Do NOT modify**: `search_document_chunks()` (line 116) — it is imported but never called in the pipeline
- **Do NOT modify**: The Supabase RPC function — no SQL changes needed
- **Do NOT modify**: `manual_rag_service.py` — the call-site at line 991 stays unchanged
- The test file `backend/tests/test_rag_quality.py` was already updated with questions for all 13 documents
- Commit after each phase checkpoint
