# Implementation Plan: Spec 070 — Document Retrieval

**Branch**: `070-document-retrieval` | **Date**: 2026-04-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/070-document-retrieval/spec.md`

## Summary

Add a second RAG retrieval layer: uploaded PDF manuals, chunked into parent sections + child paragraphs, embedded via nomic-embed-text, and searchable alongside the existing validated_qa pipeline. Admins manage documents via a new "Documents" tab; the AI assistant searches validated_qa first (highest trust), then document chunks, falling through to the existing manual-chunks pipeline if neither matches.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)
**Primary Dependencies**: FastAPI, Supabase Python client, pdfplumber (NEW), httpx, ollama_embedder (existing); Flutter Material, http package (frontend)
**Storage**: Supabase (PostgreSQL + pgvector) — new `knowledge_documents` + `document_chunks` tables; local filesystem `backend/uploaded_files/manuals/` for PDFs
**Testing**: Manual curl tests (backend), manual UI testing (frontend)
**Target Platform**: Web (Flutter PWA) + Linux server (FastAPI)
**Project Type**: Web application (full-stack)
**Performance Goals**: Indexing < 60s for 50-page PDF; search latency comparable to existing validated_qa path
**Constraints**: Max 50 MB PDF upload; only `status='ready'` documents searchable; Ollama at localhost:11434
**Scale/Scope**: Dozens of manuals, < 5k total chunks expected

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS | Backend (router, service, migration), Frontend (tab, widget, service), all layers covered |
| II. Explicit Over Automatic | PASS | Upload is explicit admin action; indexing status tracked explicitly via `status` column |
| III. Role-Based Access Control | PASS | All `/api/documents/*` endpoints enforce admin check via `_admin_check()` pattern; frontend tab admin-only |
| IV. Server-First File Storage | PASS | PDFs stored at `backend/uploaded_files/manuals/` on local disk; served via StaticFiles mount |
| V. Client-Side Computation | N/A | Document management is admin-only CRUD; no client-side filtering optimization needed |
| VI. Audit Everything | PASS | `log_activity()` for upload, delete, reindex events |
| VII. Simplicity & YAGNI | PASS | Single new dependency (pdfplumber); reuses existing embedder, provider resolver, admin auth pattern |

**Post-Phase 1 Re-check**: All principles still pass. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/070-document-retrieval/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── api-endpoints.md
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── documents.py              # NEW — all document CRUD endpoints
├── services/
│   ├── document_service.py       # NEW — PDF extraction + chunking + embedding pipeline
│   ├── document_search_service.py # NEW — search_document_chunks + fetch_parent_context
│   ├── manual_rag_service.py     # MODIFY — add Layer 2 (document search) between validated_qa and HyDE
│   └── ollama_embedder.py        # EXISTING — reused for embed_single/embed_many
├── utils/
│   └── activity.py               # EXISTING — reused for audit logging
├── requirements.txt              # MODIFY — add pdfplumber
└── uploaded_files/
    └── manuals/                  # NEW directory — PDF storage

supabase/migrations/
└── 20260416000000_knowledge_documents.sql  # NEW — tables + RPC + index

frontend/lib/
├── screens/manual_assistant/
│   ├── manual_assistant_screen.dart  # MODIFY — add Documents tab (admin, position 7)
│   ├── documents_tab.dart            # NEW — upload, list, delete, reindex UI
│   └── widgets/
│       └── document_card.dart        # NEW — per-document card widget
└── services/
    └── document_service.dart         # NEW — HTTP calls to /api/documents/*
```

**Structure Decision**: Follows existing web application pattern with `backend/routers/`, `backend/services/`, `frontend/lib/screens/`, `frontend/lib/services/`. New files placed alongside existing counterparts.

## Complexity Tracking

No constitution violations. No complexity justifications needed.

## Implementation Phases

### Phase 1: Database Migration
- Create `knowledge_documents` table with `status` column and `error_message`
- Create `document_chunks` table with parent-child structure and `vector(768)` embedding
- Create `search_document_chunks` RPC function with `status='ready'` filter
- Create IVFFlat partial index on child chunk embeddings

### Phase 2: PDF Extraction + Chunking Pipeline
- New `backend/services/document_service.py`
- Extract text per page via pdfplumber
- Detect section headings (numbered, ALL CAPS, colon-ending patterns)
- Create parent chunks (full sections) and child chunks (paragraphs, min 50 chars)
- Embed child chunks via `embed_many()`
- Store in Supabase with document_id references
- Update `knowledge_documents.status` to `ready` or `failed` (with error_message)
- Fallback: fixed-size chunking (400 tokens per parent, 100-token overlap) when no headings detected

### Phase 3: Backend Endpoints
- New `backend/routers/documents.py` with 5 endpoints
- POST `/upload` — save PDF to disk, insert metadata, trigger background indexing
- GET `/` — list all documents sorted by created_at desc
- GET `/{id}/status` — poll indexing status
- DELETE `/{id}` — cascade delete + remove file from disk
- POST `/{id}/reindex` — delete chunks, re-run pipeline
- Admin auth via `_admin_check()` pattern
- Activity logging via `log_activity()`

### Phase 4: Document Search Service
- New `backend/services/document_search_service.py`
- `search_document_chunks(query_embedding, limit=3)` — calls RPC, converts distance to similarity
- `fetch_parent_context(child_matches)` — loads parent chunk content for each matched child
- Returns enriched results with document metadata (display_name, section_title, page_number)

### Phase 5: RAG Pipeline Integration
- Modify `backend/services/manual_rag_service.py`
- Insert Layer 2 (document search) after post-rewrite validated_qa check (line ~1052) and before HyDE (line ~1053)
- Embed `search_query` for document search (separate from HyDE embedding)
- If document match >= 0.70 similarity: build prompt with parent context, call LLM, return response with `source_type="document"`
- If below threshold: fall through to existing manual-chunks pipeline (unchanged)
- Add `source_type` field to validated_qa responses too (`"validated_qa"`)
- Reuse existing `VALIDATED_QA_SYSTEM_PROMPT` with document-specific context format

### Phase 6: Frontend — Documents Tab
- Modify `manual_assistant_screen.dart` — add 7th tab "Documents" (admin only)
- New `documents_tab.dart` — upload form, document list, status polling
- New `document_card.dart` — display name, status badge, chunk count, action buttons
- New `frontend/lib/services/document_service.dart` — HTTP client for all 5 endpoints
- Empty state message when no documents uploaded

### Phase 7: Integration Testing
- Upload a real PDF, verify chunks created
- Ask a question matching document content, verify answer + sources
- Test validated_qa priority over document match
- Test delete cascade and re-index
- Verify frontend Documents tab end-to-end

## Key Design Decisions

1. **Document search uses separate embedding** (not HyDE): The search_query is embedded directly via `embed_single()` for the document chunk search. HyDE generates a hypothetical answer which biases toward the manual-chunks content style. For validated_qa and document chunks, direct query embedding is more appropriate.

2. **Parent context sent to LLM, not child text**: When a child chunk matches, the LLM receives the full parent section. This ensures complete procedure context (prerequisites, steps, troubleshooting) rather than a single matching paragraph.

3. **Failed documents keep partial chunks**: On embedding failure, partial chunks are retained for debuggability. Only re-index (or delete) removes them. The `status='ready'` filter ensures partial documents are never searched.

4. **No duplicate embedding model**: Reuses `ollama_embedder.embed_single` / `embed_many` — same model (`nomic-embed-text-v2-moe`), same dimensions (768), same queue/timeout handling.

5. **source_type field added to all responses**: Both validated_qa and document responses include `source_type` to let the frontend distinguish source provenance. This is additive — no existing fields changed.
