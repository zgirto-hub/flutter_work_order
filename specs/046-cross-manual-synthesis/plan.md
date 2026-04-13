# Implementation Plan: Cross-Manual Synthesis (Layer 4)

**Branch**: `046-cross-manual-synthesis` | **Date**: 2026-04-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/046-cross-manual-synthesis/spec.md`

## Summary

Transform the manual assistant's "All Manuals" mode from flat-pool chunk retrieval into a per-manual retrieval → sub-answer generation → synthesis pipeline. Each manual's top chunks are retrieved independently, a sub-answer is generated per manual via Ollama (gemma4:e2b), then all sub-answers are combined by a synthesis prompt that produces one coherent answer with source attribution and conflict detection. Single-manual queries bypass synthesis entirely.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, httpx, Supabase Python client (backend); http, Flutter Material (frontend)  
**Storage**: Supabase (PostgreSQL) with pgvector — no schema changes  
**Testing**: Manual integration testing (existing pattern)  
**Target Platform**: Web (PWA) frontend, Linux server backend  
**Project Type**: Web service + PWA  
**Performance Goals**: Cross-manual queries complete within 3x single-manual latency (~45s max given 15s baseline)  
**Constraints**: 15GB server RAM; Ollama processes requests sequentially (gemma4:e2b); single Ollama instance  
**Scale/Scope**: Corpus typically 5-15 manuals; sub-answer generation is the bottleneck

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | **PASS** | Backend pipeline changes + Flutter AnswerCard updates + response model updates |
| II. Explicit Over Automatic | **PASS** | Synthesis is triggered explicitly by "All Manuals" selection (manual_id=null); no implicit behavior changes |
| III. Role-Based Access Control | **PASS** | No new endpoints or access patterns; uses existing `/manuals/ask` |
| IV. Server-First File Storage | **N/A** | No file storage changes |
| V. Client-Side Computation | **N/A** | Synthesis is server-side by nature (LLM calls) |
| VI. Audit Everything | **PASS** | Existing `log_activity` call in `ask_question` already logs manual queries; no new auditable actions |
| VII. Simplicity & YAGNI | **PASS** | No abstractions; synthesis is a sequential addition to the existing `ask()` function |

No violations. No Complexity Tracking entries needed.

## Project Structure

### Documentation (this feature)

```text
specs/046-cross-manual-synthesis/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── manuals.py                    # No changes needed (routing already correct)
└── services/
    └── manual_rag_service.py         # Main changes: per-manual retrieval, sub-answer gen, synthesis

frontend/
├── lib/
│   ├── models/
│   │   └── manual_qa_answer.dart     # Add manualsConsulted, hasConflicts fields
│   └── screens/
│       └── manual_assistant/
│           └── widgets/
│               └── answer_card.dart  # Display synthesis notice + conflict warnings
```

**Structure Decision**: All backend changes are in `manual_rag_service.py` (the existing pipeline). No new files needed on backend. Frontend changes are additive fields on the model and a UI section in AnswerCard.

---

## Phase 1 — Foundation: Per-Manual Chunk Retrieval

**Goal**: Replace the single flat-pool `search_manual_chunks` call with per-manual retrieval that returns the top qualifying chunks grouped by manual.

### Design

The existing `ask()` function calls `search_manual_chunks` RPC once with `manual_id_filter=None` and `match_count=5`, returning a flat list of the 5 nearest chunks across all manuals. For cross-manual synthesis, we need chunks grouped by manual.

**Approach**: Call the existing `search_manual_chunks` RPC once per manual. First, query the `manuals` table to get all manual IDs, then call the RPC for each manual with that manual's ID as filter and `match_count=3` (top 3 per manual). Apply the existing chunk reranking (distance threshold ≤ 0.45) to each manual's results independently.

**New helper function**: `_retrieve_chunks_per_manual(embedding_str: str) -> dict[str, list[dict]]`

- Queries `manuals` table for all manual IDs
- Calls `search_manual_chunks` for each manual_id with `match_count=3`
- Filters each result set by `MAX_CHUNK_DISTANCE` threshold
- Returns `{manual_id: [qualified_chunks]}` (only manuals with ≥1 qualifying chunk)
- Calls are made sequentially (Ollama is the bottleneck, not pgvector)

### Files Changed

| File | Change |
|------|--------|
| `backend/services/manual_rag_service.py` | Add `_retrieve_chunks_per_manual()` function |

### Acceptance Criteria

- Given 3 manuals in the corpus, calling `_retrieve_chunks_per_manual` returns up to 3 chunks per manual, grouped by manual ID
- Chunks exceeding the distance threshold (0.45) are excluded per-manual
- Manuals with zero qualifying chunks are omitted from the result dict

---

## Phase 2 — Sub-Answer Generation

**Goal**: For each manual that returned qualifying chunks, generate a scoped sub-answer using a single Ollama call.

### Design

**New helper function**: `_generate_sub_answers(chunks_by_manual: dict, question: str, history: list, memory: str, model: str) -> list[dict]`

- For each manual in `chunks_by_manual`:
  - Build a prompt using existing `_build_prompt()` (reuse as-is) with that manual's chunks only
  - Call `generate()` to get a sub-answer
  - Check for the "not found" sentinel — if present, mark this manual as non-contributing
- Returns list of `{"manual_id": str, "manual_title": str, "answer": str, "chunks": list, "grounded": bool}`

**Parallelization note**: Ollama gemma4:e2b processes one request at a time (sequential inference on GPU). True parallelism won't help. Sub-answers are generated sequentially. The user-facing description says "parallelized" but on a single Ollama instance this means "as fast as possible, one at a time." If Ollama is ever scaled to multiple instances, `asyncio.gather` can be swapped in.

**Concurrency cap**: Process a maximum of 8 manuals. If more than 8 manuals have qualifying chunks, take the 8 manuals with the lowest average chunk distance (most relevant manuals first).

### Files Changed

| File | Change |
|------|--------|
| `backend/services/manual_rag_service.py` | Add `_generate_sub_answers()` function |

### Acceptance Criteria

- Given 3 manuals with qualifying chunks, 3 sub-answers are generated (one per manual)
- Sub-answers that contain the "not found" sentinel are marked as `grounded=False`
- If all sub-answers are ungrounded, the function returns an empty list of grounded answers

---

## Phase 3 — Synthesis

**Goal**: Combine all grounded sub-answers into one coherent final answer that names consulted manuals and flags conflicts.

### Design

**New helper function**: `_synthesize_answers(sub_answers: list[dict], question: str, model: str) -> dict`

- If only 1 grounded sub-answer: skip synthesis, return that answer directly with `synthesized=False`
- If 2+ grounded sub-answers: build a synthesis prompt and call `generate()`

**Synthesis prompt template**:
```
You are a technical synthesis expert for civil aviation maintenance.
You have received answers from multiple technical manuals to the same question.

Produce ONE coherent answer that:
1. Combines information from all manuals into a unified response
2. Names each manual when attributing information (e.g., "According to [Manual Title], ...")
3. If manuals AGREE on a point, state it once and cite all agreeing manuals
4. If manuals CONTRADICT each other, explicitly flag the conflict:
   "⚠ CONFLICT: [Manual A] states X, while [Manual B] states Y"
5. Reply in the same language as the question (Arabic or English)

QUESTION: {question}

MANUAL ANSWERS:
[Manual: {title_1}]
{sub_answer_1}

[Manual: {title_2}]
{sub_answer_2}
...

SYNTHESIZED ANSWER:
```

- Returns `{"answer": str, "synthesized": bool, "manuals_consulted": [{"id": str, "title": str}], "has_conflicts": bool}`
- `has_conflicts` is determined by checking for the "⚠ CONFLICT:" marker in the synthesized answer

### Files Changed

| File | Change |
|------|--------|
| `backend/services/manual_rag_service.py` | Add `_synthesize_answers()` function |

### Acceptance Criteria

- Given 2 sub-answers, the synthesis prompt includes both manual titles and answers
- The synthesized answer names each consulted manual
- Conflicts between manuals are flagged with the "⚠ CONFLICT:" marker
- Single sub-answer case skips synthesis (no extra LLM call)

---

## Phase 4 — Routing: Single vs Multi-Manual Decision Logic

**Goal**: Modify the existing `ask()` function to route between the existing single-manual pipeline and the new cross-manual synthesis pipeline.

### Design

The routing decision is simple and already implicit in the existing code:
- `manual_id_filter is not None` → **single-manual path** (existing code, unchanged)
- `manual_id_filter is None` → **cross-manual synthesis path** (new code)

**Changes to `ask()` function**:

After the embedding step (which is shared), add a branch:

```python
if manual_id_filter:
    # === EXISTING SINGLE-MANUAL PATH (unchanged) ===
    # search_manual_chunks with manual_id_filter → rerank → build_prompt → generate → return
    ...
else:
    # === NEW CROSS-MANUAL SYNTHESIS PATH ===
    # 1. _retrieve_chunks_per_manual(embedding_str)
    # 2. _generate_sub_answers(chunks_by_manual, ...)
    # 3. _synthesize_answers(grounded_sub_answers, ...)
    # 4. Build response with manuals_consulted and has_conflicts
    ...
```

The existing code before the branch (corpus empty check, query rewrite, HyDE, embedding) remains shared. The existing code after the branch (history compression) also feeds into both paths.

**History compression** runs before the branch since it depends on conversation state, not retrieval strategy. The compressed `memory` and `effective_history` are passed into both paths.

### Files Changed

| File | Change |
|------|--------|
| `backend/services/manual_rag_service.py` | Restructure `ask()` with if/else branch after embedding |

### Acceptance Criteria

- Single-manual queries (`manual_id` provided) follow the existing code path with zero changes to behavior or response format
- "All Manuals" queries (`manual_id` is null) use the new per-manual → sub-answer → synthesis pipeline
- Both paths share the query rewrite, HyDE, and embedding steps

---

## Phase 5 — Response: Include Consulted Manuals and Conflict Flags

**Goal**: Add `manuals_consulted` and `has_conflicts` to the response JSON for cross-manual queries.

### Design

The response dict from `ask()` gains two new optional fields (additive, backward-compatible):

```python
# Cross-manual synthesis response (when manual_id_filter is None and synthesis ran)
{
    "answer": "...",           # synthesized answer
    "grounded": True,
    "sources": [...],          # combined sources from all contributing manuals
    "model": "gemma4:e2b",
    "duration_seconds": 42.3,  # total time including all sub-answers + synthesis
    "session_summary": "...",
    "manuals_consulted": [     # NEW — only present for cross-manual queries
        {"id": "uuid-1", "title": "AMM Chapter 12"},
        {"id": "uuid-2", "title": "CMM Engine 737"}
    ],
    "has_conflicts": true      # NEW — only present for cross-manual queries
}
```

**Sources aggregation**: The `sources` list is built by collecting chunks from all contributing manuals (from the per-manual retrieval step). Each source already contains `manual_id` and `manual_title`, so no change to the source format is needed. Highlight computation runs on the final synthesized answer against each chunk.

**Duration tracking**: `duration_seconds` measures total wall time from embedding to final synthesis (inclusive of all sub-answer generations).

### Files Changed

| File | Change |
|------|--------|
| `backend/services/manual_rag_service.py` | Add `manuals_consulted` and `has_conflicts` to response dict in synthesis path |

### Acceptance Criteria

- Single-manual responses do NOT include `manuals_consulted` or `has_conflicts` fields (backward-compatible)
- Cross-manual responses include `manuals_consulted` array with id and title per manual
- `has_conflicts` is `true` only when the synthesized answer contains conflict markers

---

## Phase 6 — Flutter: Display Synthesis Notice and Conflict Warnings

**Goal**: Update the Flutter AnswerCard to show which manuals were consulted and highlight any conflicts detected.

### Design

**Model changes** (`manual_qa_answer.dart`):
- Add `List<ManualConsulted> manualsConsulted` field (default empty list)
- Add `bool hasConflicts` field (default false)
- Parse from JSON: `manuals_consulted` → `manualsConsulted`, `has_conflicts` → `hasConflicts`
- New simple model `ManualConsulted` with `id` and `title` fields (can be inline or separate class)

**AnswerCard changes** (`answer_card.dart`):

Add two new UI sections between the answer text and the model attribution:

1. **Synthesis notice** (shown when `manualsConsulted.isNotEmpty`):
   - Small chip/banner: "Synthesized from N manuals: [Title 1], [Title 2], ..."
   - Styled with a subtle info color (blue-grey) and an icon (e.g., `Icons.auto_awesome`)
   - Compact: single line with manual titles comma-separated

2. **Conflict warning** (shown when `hasConflicts` is true):
   - Small chip/banner: "⚠ This answer contains conflicting information between manuals"
   - Styled with amber/warning color
   - Appears below the synthesis notice, above model attribution

Both sections are conditionally rendered and take minimal vertical space.

### Files Changed

| File | Change |
|------|--------|
| `frontend/lib/models/manual_qa_answer.dart` | Add `manualsConsulted`, `hasConflicts` fields + parsing |
| `frontend/lib/screens/manual_assistant/widgets/answer_card.dart` | Add synthesis notice and conflict warning UI |

### Acceptance Criteria

- Single-manual answers display identically to current behavior (no new UI elements)
- Cross-manual synthesized answers show a "Synthesized from N manuals" notice with manual titles
- When conflicts exist, an amber warning banner appears
- New UI elements do not break existing layout or scrolling behavior
