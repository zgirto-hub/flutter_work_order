# Implementation Plan: Spec 072 — Document Retrieval v2

**Branch**: `072-document-retrieval-v2` | **Date**: 2026-04-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/072-document-retrieval-v2/spec.md`

## Summary

Enhance the Documents tab (spec 070) to fully replace the Knowledge tab by adding HyDE + reranking + cross-document synthesis to the Layer 2 search pipeline, chunk editing/split/merge UI, multi-format upload (DOCX/TXT/MD), migration of existing manuals, and retirement of the old Layer 3 pipeline. The existing Layer 3 functions are moved (not duplicated) into Layer 2.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client, pdfplumber, httpx, ollama_embedder, ollama_generator, ai_providers.resolver (backend); Flutter Material, http package (frontend)
**Storage**: Supabase (PostgreSQL + pgvector) — existing `knowledge_documents` + `document_chunks` tables modified; `manuals` + `manual_chunks` tables retired after migration. Local filesystem for PDFs.
**Testing**: Manual curl tests (backend), manual UI testing (frontend)
**Target Platform**: Web (Flutter PWA) + Linux server (FastAPI)
**Project Type**: Web application (full-stack)
**Performance Goals**: Document-sourced response time within 5 seconds of current Layer 2; chunk edits reflected in search within 5 seconds
**Constraints**: Max 50 MB upload; Ollama at localhost:11434; sequential migration processing
**Scale/Scope**: ~10-20 existing manuals to migrate, < 5k total chunks

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend (migration, endpoints, pipeline changes), Frontend (chunk editor, multi-format upload), DB migration — all layers covered |
| II. Explicit Over Automatic | PASS | Migration triggered explicitly by admin; chunk edits are explicit; embedding_stale flag is explicit state |
| III. Role-Based Access Control | PASS | All chunk CRUD and migration endpoints are admin-only via `_admin_check()` |
| IV. Server-First File Storage | PASS | Files stay on local disk; migration copies files between paths on same disk |
| V. Client-Side Computation | N/A | Admin-only features, no client-side filtering needed |
| VI. Audit Everything | PASS | Activity logging for chunk edits, migration, cleanup via `log_activity()` |
| VII. Simplicity & YAGNI | PASS | Moves existing functions rather than duplicating; single code path after migration |

**Post-Phase 1 Re-check**: All principles still pass.

## Project Structure

### Documentation

```text
specs/072-document-retrieval-v2/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── api-endpoints.md # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code

```text
backend/
├── routers/
│   ├── documents.py              # MODIFY — add 9 chunk CRUD endpoints + 3 migration endpoints
│   └── manuals.py                # MODIFY (US5) — remove chunk CRUD endpoints + Layer 3-only code
├── services/
│   ├── document_service.py       # MODIFY — multi-format support, reindex with chunk_index
│   ├── document_search_service.py # MODIFY — per-document retrieval, sub-answers, synthesis
│   ├── manual_rag_service.py     # MODIFY — replace Layer 2+3 with unified HyDE+rerank+synthesis pipeline
│   ├── manual_parser.py          # KEEP (rename to text_extractor.py in US5) — DOCX/TXT/MD extraction
│   ├── manual_chunker.py         # RETIRE (US5) — replaced by parent-child chunking
│   ├── manual_storage_service.py # RETIRE (US5) — replaced by document_service.py
│   └── ollama_embedder.py        # EXISTING — reused, no changes
├── utils/
│   └── activity.py               # EXISTING — reused for audit logging
└── requirements.txt              # NO CHANGES (all deps already present)

supabase/migrations/
└── 20260417000000_document_chunks_v2.sql  # NEW — alter tables + update RPC

frontend/lib/
├── screens/manual_assistant/
│   ├── manual_assistant_screen.dart  # MODIFY (US5) — remove Knowledge tab
│   ├── documents_tab.dart            # MODIFY — add chunk browsing navigation
│   ├── document_chunk_editor.dart    # NEW — chunk list + edit/split/merge/delete UI
│   ├── manuals_tab.dart              # RETIRE (US5)
│   ├── chunk_edit_screen.dart        # RETIRE (US5)
│   ├── chunk_editor_screen.dart      # RETIRE (US5)
│   └── widgets/
│       ├── document_card.dart        # EXISTING — no changes
│       └── document_chunk_card.dart  # NEW — per-chunk card with actions
├── services/
│   └── document_service.dart         # MODIFY — add chunk CRUD + migration API calls
└── models/
    └── manual_qa_answer.dart         # MODIFY — add manuals_consulted, has_conflicts for doc source
```

## Implementation Phases

### Phase 1: Schema Migration
- Add `chunk_index`, `embedding_stale` columns to `document_chunks`
- Add `file_extension` column to `knowledge_documents`
- Update `search_document_chunks` RPC to exclude `embedding_stale = true`
- Backfill `chunk_index` for existing chunks (order by created_at within each parent)

### Phase 2: Enhanced Search Pipeline (US1)
- Create `_retrieve_chunks_per_document()` — modeled on `_retrieve_chunks_per_manual()`, queries document_chunks with relaxed threshold (0.55 distance, 10 candidates), groups by document_id, caps at 3 per doc / 8 docs
- Create `_generate_document_sub_answers()` — builds prompts with parent section context per document
- Adapt synthesis: reuse `_synthesize_answers()` with document names instead of manual titles
- Replace the Layer 2 block in `ask()` with: HyDE → embed → per-document retrieval → sub-answers → synthesis → return
- Add `manuals_consulted` and `has_conflicts` to document-sourced responses

### Phase 3: Chunk CRUD Backend (US2)
- Add 9 chunk endpoints to `documents.py` router
- Implement auto-reindexing of `chunk_index` on insert/delete/split/merge
- Handle `embedding_stale` flag: set true on embed failure, false on success
- Activity logging for all chunk operations

### Phase 4: Multi-Format Upload (US3)
- Extend `document_service.py` to detect file extension and route to appropriate extractor
- For DOCX/TXT/MD: use `manual_parser.parse()` to get page-aware text, then apply `_detect_sections()` + parent-child chunking
- Update upload endpoint to accept .docx, .txt, .md extensions
- Store `file_extension` in `knowledge_documents` row

### Phase 5: Chunk Editor UI (US2 Frontend)
- New `document_chunk_editor.dart` screen — paginated chunk list with parent/child grouping
- Chunk cards showing: type badge, section title, page number, content preview, char count, stale warning
- Edit dialog: modify content, save triggers re-embed
- Split dialog: tap position in text, confirm split
- Merge button: merge with next sibling (same parent only)
- Bulk selection mode + delete
- Re-embed All button (background task)
- Add chunk CRUD methods to `document_service.dart`
- Navigate from document card → chunk editor

### Phase 6: Migration (US4)
- Add `POST /api/documents/migrate-all` endpoint — sequential processing with progress
- Add `GET /api/documents/migration-status` endpoint — poll progress
- Add `DELETE /api/documents/migrate-cleanup` endpoint — delete old tables' data
- Migration UI: button in Documents tab, progress indicator, completion summary
- Handle multi-format: route each manual to correct parser by `file_extension`

### Phase 7: Retirement (US5)
- Remove Knowledge tab from `manual_assistant_screen.dart`
- Remove Layer 3 block from `manual_rag_service.ask()` (lines 1286-1567)
- Remove `_retrieve_chunks_per_manual()`, old `_generate_sub_answers()` (only if fully replaced by document versions)
- Remove chunk CRUD endpoints from `manuals.py`
- Rename `manual_parser.py` → `text_extractor.py`, update imports
- Remove `manual_chunker.py`, `manual_storage_service.py`
- Remove old frontend files: `manuals_tab.dart`, `chunk_edit_screen.dart`, `chunk_editor_screen.dart`, `upload_dialog.dart`
- Drop migration: `DROP TABLE manual_chunks; DROP TABLE manuals; DROP TABLE manual_corpus_stats;`
- Update tab count: 6 for admin (was 7)

### Phase 8: Verification
- Test all 5 user stories end-to-end
- Compare answer quality on 10 test questions (before/after)
- Verify stale chunk exclusion
- Verify chunk edit → search update < 5s
- Verify migration of all existing manuals
- Verify no references to retired tables/services in active code

## Key Design Decisions

1. **Move, don't duplicate**: Layer 3 functions (HyDE, reranking, synthesis) are adapted for document_chunks and the old Layer 3 call sites removed. Single code path eliminates maintenance burden.

2. **Relaxed search threshold with reranking**: Search retrieves 10 candidates at 0.55 distance, reranker filters to top 3. Wider pool + strict filter produces better results than tight threshold alone.

3. **Parent context preserved through synthesis**: When multiple documents match, each sub-answer is generated from parent section context. Synthesis combines these into one answer with conflict detection.

4. **Sequential migration**: One manual at a time with progress reporting. Avoids Ollama overload and gives admins clear visibility. Failed manuals don't block the rest.

5. **Keep manual_parser.py**: Renamed to `text_extractor.py`, it provides DOCX/TXT/MD extraction that pdfplumber doesn't handle. Reused by both upload and migration.

6. **embedding_stale flag**: Explicit tracking of chunks where content changed but embedding failed. Excluded from search to prevent stale results. Admin sees warning badge + retry button.
