# Tasks: Cross-Manual Synthesis (Layer 4)

**Input**: Design documents from `/specs/046-cross-manual-synthesis/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Not explicitly requested — test tasks omitted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing. Tasks are written for another LLM implementer to execute step by step, with a code review after each phase.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `backend/services/`, `backend/routers/`
- **Frontend**: `frontend/lib/models/`, `frontend/lib/screens/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: No project initialization needed — this feature modifies existing files only. No new dependencies, no migrations, no new files on backend.

_(No setup tasks — skip to Foundational)_

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The per-manual chunk retrieval function that ALL user stories depend on. This is the foundation that replaces flat-pool retrieval with grouped-by-manual retrieval.

- [x] T001 Add `_retrieve_chunks_per_manual()` async function to `backend/services/manual_rag_service.py`. This function takes `embedding_str: str` (the pgvector-formatted embedding string) and returns `dict[str, list[dict]]` mapping manual_id to its qualifying chunks. Implementation: (1) query `supabase.table("manuals").select("id, title")` to get all manual IDs and titles, (2) for each manual, call `supabase.rpc("search_manual_chunks", {"q_embedding": embedding_str, "match_count": 3, "manual_id_filter": manual_id})`, (3) filter each manual's results by `MAX_CHUNK_DISTANCE` threshold (existing constant, currently 0.45), (4) discard manuals with zero qualifying chunks, (5) if more than 8 manuals have qualifying chunks, keep only the 8 with the lowest average chunk distance. Return dict keyed by manual_id, where each value is a list of chunk dicts. Each chunk dict already contains `manual_id`, `manual_title`, `chunk_index`, `source_page`, `content`, `distance` from the RPC. Log: `"Per-manual retrieval: %d manuals queried → %d with qualifying chunks"`.

- [x] T002 Add `_MAX_SYNTHESIS_MANUALS = 8` constant near the top of `backend/services/manual_rag_service.py` (next to existing `MAX_CHUNK_DISTANCE` and `MAX_PROMPT_CHUNKS` constants).

**Checkpoint**: `_retrieve_chunks_per_manual()` can be tested by calling it with a real embedding and verifying chunks are grouped by manual.

---

## Phase 3: User Story 1 — Cross-Manual Answer with Conflict Detection (Priority: P1) 🎯 MVP

**Goal**: When "All Manuals" is selected, retrieve chunks per-manual, generate sub-answers, synthesize into one answer with conflict detection and manual attribution.

**Independent Test**: Upload 2+ manuals, select "All Manuals", ask a question. Verify the answer names consulted manuals and flags any conflicts.

### Implementation for User Story 1

- [x] T003 [US1] Add `_generate_sub_answers()` async function to `backend/services/manual_rag_service.py`. Signature: `async def _generate_sub_answers(chunks_by_manual: dict[str, list[dict]], question: str, history: list[dict] | None, memory: str | None, model: str | None) -> list[dict]`. Implementation: for each manual_id in chunks_by_manual, (1) build `retrieved_chunks` string from that manual's chunks using the same format as the existing code (i.e., `[Source {i+1}: {manual_title}, page {source_page or '—'}]\n{content}\n---\n`), (2) call existing `_build_prompt(retrieved_chunks, question, history, memory)`, (3) call `await generate(prompt, model=model)`, (4) check if the answer contains the "not found" sentinel phrases (reuse the existing `sentinel_phrases` list — extract it to a module-level constant `_SENTINEL_PHRASES` for reuse), (5) return a list of dicts: `{"manual_id": str, "manual_title": str, "answer": str, "chunks": list[dict], "grounded": bool}`. Process manuals sequentially (Ollama is single-threaded per research.md R1). Log: `"Sub-answers: %d manuals → %d grounded"`.

- [x] T004 [US1] Extract the sentinel phrases list in `backend/services/manual_rag_service.py` to a module-level constant `_SENTINEL_PHRASES` (currently defined inline in the `ask()` function around line 577). Update the existing usage in `ask()` to reference this constant instead of the inline list.

- [x] T005 [US1] Add `_synthesize_answers()` async function to `backend/services/manual_rag_service.py`. Signature: `async def _synthesize_answers(sub_answers: list[dict], question: str, model: str | None) -> dict`. Implementation: (1) filter to only grounded sub-answers, (2) if zero grounded sub-answers, return `{"answer": "This information is not in the available manuals.", "synthesized": False, "manuals_consulted": [], "has_conflicts": False, "grounded": False}`, (3) if exactly one grounded sub-answer, return `{"answer": sub_answer["answer"], "synthesized": False, "manuals_consulted": [{"id": sub_answer["manual_id"], "title": sub_answer["manual_title"]}], "has_conflicts": False, "grounded": True}`, (4) if 2+ grounded sub-answers, build a synthesis prompt (see below) and call `await generate(synthesis_prompt, model=model)`, (5) detect conflicts by checking if `"⚠ CONFLICT:"` appears in the synthesized answer, (6) return `{"answer": synthesized_text, "synthesized": True, "manuals_consulted": [{"id": sa["manual_id"], "title": sa["manual_title"]} for sa in grounded_sub_answers], "has_conflicts": bool, "grounded": True}`. The synthesis prompt template: `"You are a technical synthesis expert for civil aviation maintenance.\nYou have received answers from multiple technical manuals to the same question.\n\nProduce ONE coherent answer that:\n1. Combines information from all manuals into a unified response\n2. Names each manual when attributing information (e.g., "According to [Manual Title], ...")\n3. If manuals AGREE on a point, state it once and cite all agreeing manuals\n4. If manuals CONTRADICT each other, explicitly flag the conflict:\n   "⚠ CONFLICT: [Manual A] states X, while [Manual B] states Y"\n5. Reply in the same language as the question (Arabic or English)\n\nQUESTION: {question}\n\nMANUAL ANSWERS:\n"` followed by each sub-answer formatted as `"[Manual: {title}]\n{answer}\n\n"`, ending with `"SYNTHESIZED ANSWER:"`. Log: `"Synthesis: %d sub-answers → synt... (line truncated to 2000 chars)

- [x] T006 [US1] Restructure the `ask()` function in `backend/services/manual_rag_service.py` to add the cross-manual synthesis path. The existing code up to and including the embedding step (lines ~437-448) and the compression logic (lines ~506-544) remain shared. After compression, add an if/else branch: **If `manual_id_filter` is not None** → keep the existing single-manual code path exactly as-is (lines ~450-623, everything from the `search_manual_chunks` RPC call through the return statement). **If `manual_id_filter` is None** → new cross-manual path: (1) call `chunks_by_manual = await _retrieve_chunks_per_manual(embedding_str)`, (2) if `chunks_by_manual` is empty, return the existing "not in the available manuals" response, (3) call `sub_answers = await _generate_sub_answers(chunks_by_manual, question, effective_history, memory, model)`, (4) call `synthesis = await _synthesize_answers(sub_answers, question, model)`, (5) if `not synthesis["grounded"]`, return the ungrounded response, (6) build `sources` list by collecting all chunks from all grounded sub-answers and computing highlights against `synthesis["answer"]` using the existing `compute_highlight()` function, (7) measure `duration_seconds` from `gen_start` (set before the branch) to now, (8) return `{"answer": synthesis["answer"], "grounded": True, "sources": final_sources, "model": used_model, "duration_seconds": round(gen_elapsed, 1), "session_summary": memory, "manuals_consulted": synthesis["manuals_consulted"], "has_conflicts": synthesis["has_conflicts"]}`. IMPORTANT: move `gen_start = time.monotonic()` to BEFORE the if/else branch so both paths measure total generation time.

- [x] T007 [US1] Add error handling for partial sub-answer failures in `_generate_sub_answers()` in `backend/services/manual_rag_service.py`. Wrap each per-manual `generate()` call in a try/except. If a `GeneratorTimeoutError` or `Exception` occurs for one manual, log a warning `"Sub-answer generation failed for manual '%s': %s"` and skip that manual (do not add it to results). This allows synthesis to proceed with the remaining successful sub-answers. If ALL sub-answer generations fail, re-raise the last exception so the caller handles it normally.

**Checkpoint**: At this point, "All Manuals" queries should return synthesized answers with manual attribution and conflict detection. Test by uploading 2+ manuals and asking a cross-manual question. Verify `manuals_consulted` and `has_conflicts` appear in the JSON response.

---

## Phase 4: User Story 2 — Single-Manual Bypass (Priority: P1)

**Goal**: Ensure single-manual queries (specific manual selected) use the existing pipeline with zero changes to behavior or response format.

**Independent Test**: Select a specific manual, ask a question. Verify the response has no `manuals_consulted` or `has_conflicts` fields and latency matches pre-feature behavior.

### Implementation for User Story 2

- [x] T008 [US2] Verify the single-manual code path in `backend/services/manual_rag_service.py` is unchanged after the Phase 3 restructuring. Specifically confirm: (1) when `manual_id_filter` is not None, the code calls `search_manual_chunks` with the filter, applies reranking, builds prompt, generates, and returns — identical to the code before this feature, (2) the response dict does NOT include `manuals_consulted` or `has_conflicts` keys, (3) no new function calls are in the single-manual path. This is a verification task — if the restructuring in T006 accidentally modified the single-manual path, fix it now.

**Checkpoint**: Single-manual queries return identical responses to the pre-feature baseline. No new fields, no latency changes.

---

## Phase 5: User Story 3 — Source Attribution in Synthesized Answer (Priority: P2)

**Goal**: The Flutter frontend displays which manuals were consulted and warns about conflicts.

**Independent Test**: Open the PWA, ask an "All Manuals" question, verify the synthesis notice and conflict warning appear in the UI.

### Implementation for User Story 3

- [x] T009 [P] [US3] Update the `ManualQaAnswer` model in `frontend/lib/models/manual_qa_answer.dart`. Add two new fields: `final List<ManualConsulted> manualsConsulted` (default `const []`) and `final bool hasConflicts` (default `false`). Add a new class `ManualConsulted` with `final String id` and `final String title` fields, a constructor, and a `factory ManualConsulted.fromJson(Map<String, dynamic> json)` that reads `json['id']` and `json['title']`. Update `ManualQaAnswer.fromJson` to parse `manuals_consulted` (a JSON list of objects) into `manualsConsulted` and `has_conflicts` (a JSON bool) into `hasConflicts`. Handle null/absent gracefully (default to empty list and false).

- [x] T010 [US3] Update the `AnswerCard` widget in `frontend/lib/screens/manual_assistant/widgets/answer_card.dart`. Add two new conditional sections between the answer text (`Text(answer.answer, ...)`) and the model attribution (`if (answer.model != null) ...`). Section 1 — **Synthesis notice**: shown when `answer.manualsConsulted.isNotEmpty`. Render a `Container` with `padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6)`, `decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(8))`, containing a `Row` with `Icon(Icons.auto_awesome, size: 14, color: Colors.blueGrey)`, `SizedBox(width: 6)`, and a `Flexible` child with `Text('Synthesized from ${answer.manualsConsulted.length} manuals: ${answer.manualsConsulted.map((m) => m.title).join(", ")}', style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700))`. Wrap in `const SizedBox(height: 8)` above. Section 2 — **Conflict warning**: shown when `answer.hasConflicts` is true. Render a `Container` with `padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6)`, `decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8))`, containing a `Row` with `Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber.shade800)`, `SizedBox(width: 6)`, and a `Flexible` child with `Text('This answer contains conflicting information between manuals', style: TextStyle(fontSize: 11, color: Colors.amber.shade900))`. Wrap in `const SizedBox(height: 6)` above. Both sections go inside the existing `Column(children: [...])` after the answer text.

**Checkpoint**: Cross-manual answers show the synthesis notice with manual titles. When conflicts exist, the amber warning appears. Single-manual answers show no new UI elements.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Logging, edge case hardening, and validation.

- [x] T011 Add structured logging to the cross-manual synthesis pipeline in `backend/services/manual_rag_service.py`. At the start of the cross-manual branch in `ask()`, log `"Cross-manual synthesis: starting for %d manuals in corpus"`. After each stage, log timing: `"Cross-manual retrieval took %.1fs"`, `"Sub-answer generation took %.1fs for %d manuals"`, `"Synthesis took %.1fs"`. Use the existing `logger` instance.

- [x] T012 Verify end-to-end using the quickstart.md scenarios in `specs/046-cross-manual-synthesis/quickstart.md`. Run through all three test scenarios: (1) cross-manual synthesis with 2+ manuals, (2) single-manual query unchanged, (3) conflict detection with contradictory manuals. Confirm response JSON matches the contract in `specs/046-cross-manual-synthesis/contracts/ask-response.md`. Fix any issues found.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: Skipped — no setup needed
- **Phase 2 (Foundational)**: No dependencies — start immediately. BLOCKS all user stories.
- **Phase 3 (US1 — Cross-Manual Synthesis)**: Depends on Phase 2 (T001, T002)
- **Phase 4 (US2 — Single-Manual Bypass)**: Depends on Phase 3 (T006 restructures `ask()`)
- **Phase 5 (US3 — Flutter UI)**: Can start T009 in parallel with Phase 3 (different file). T010 depends on T009.
- **Phase 6 (Polish)**: Depends on Phases 3-5 all complete

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational only. This is the MVP.
- **US2 (P1)**: Depends on US1 (verification that restructuring didn't break single-manual path)
- **US3 (P2)**: T009 (model) can start in parallel with US1. T010 (UI) can start after T009.

### Within Each User Story

- T003 and T004 can run in parallel (different concerns in same file, but T004 is a small extract-constant refactor)
- T005 depends on T004 (uses `_SENTINEL_PHRASES`)
- T006 depends on T003, T005 (uses the new functions)
- T007 depends on T003 (modifies `_generate_sub_answers`)

### Parallel Opportunities

```
Phase 2:  T001 ──→ T002 (sequential, same file)
Phase 3:  T004 ──→ T003 ──→ T005 ──→ T006 ──→ T007
                                                  │
Phase 5:  T009 ─────────────────────→ T010 ───────┤
                                                  │
Phase 4:                               T008 ──────┤
                                                  ↓
Phase 6:                               T011 → T012
```

T009 (Flutter model) can run in parallel with ALL of Phase 3 (backend work).

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (T001-T002)
2. Complete Phase 3: User Story 1 (T003-T007)
3. **STOP and VALIDATE**: Test cross-manual synthesis via API (curl/Postman)
4. Verify `manuals_consulted` and `has_conflicts` in JSON response

### Incremental Delivery

1. Phase 2 → Foundation ready
2. Phase 3 (US1) → Cross-manual synthesis works in backend → **Deploy backend**
3. Phase 4 (US2) → Verify no regression → **Confidence check**
4. Phase 5 (US3) → Flutter UI shows synthesis + conflicts → **Deploy frontend**
5. Phase 6 → Polish logging + end-to-end validation

### For the Implementer LLM

Execute tasks **in order by Task ID** (T001 → T012). Each task description is self-contained with exact file paths, function signatures, and implementation details. After completing each phase checkpoint, pause for code review before proceeding to the next phase.

---

## Notes

- All backend changes are in a single file: `backend/services/manual_rag_service.py`
- All frontend changes are in two files: `manual_qa_answer.dart` and `answer_card.dart`
- No database migrations needed
- No new Python or Flutter dependencies needed
- The implementer should read the existing `ask()` function carefully before starting T006 — the restructuring must preserve the single-manual path exactly
- Commit after each phase checkpoint
