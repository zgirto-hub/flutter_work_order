# Implementation Plan: Contextual Embeddings

**Branch**: `075-contextual-embeddings` | **Date**: 2026-04-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/075-contextual-embeddings/spec.md`

## Summary

Before embedding each chunk, prepend the document title and section title as context (e.g., "CADAS-IMS Admin Training > Alarm Configuration: [chunk text]"). This gives the embedding model document-level context so generic procedural chunks embed near domain-specific queries. Apply to both `document_chunks` (via `document_service.py`) and `manual_chunks` (via `manual_rag_service.py`) pipelines. The contextual prefix is transient — used only for embedding input, never stored. A shared `build_contextual_prefix()` helper ensures consistent format. The existing document re-embed endpoint is updated to use the prefix; a new manual re-embed endpoint is added. No schema changes, no frontend changes, no new dependencies.

## Technical Context

**Language/Version**: Python 3.10 (backend only — no Flutter/Dart changes)  
**Primary Dependencies**: FastAPI, Supabase Python client, httpx, existing `services.ollama_embedder`, existing `services.document_service`, existing `services.manual_rag_service`  
**Storage**: Supabase (PostgreSQL) with pgvector — existing `document_chunks`, `manual_chunks`, `knowledge_documents`, `manuals` tables. No schema changes.  
**Testing**: pytest + pytest-asyncio (auto mode)  
**Target Platform**: Linux server (Zorin OS), single-server deployment  
**Project Type**: web-service (backend only)  
**Performance Goals**: Upload processing time increase ≤5% (SC-003). Prefix construction is string concatenation — negligible overhead.  
**Constraints**: nomic-embed-text 8192 token limit (~30k chars). Prefix truncation if combined text exceeds 30k chars (R-006). Chunk content must never be modified.  
**Scale/Scope**: ~5 files modified/created. Shared prefix helper, two pipeline modifications (document + manual), one existing endpoint update, one new endpoint, one test file.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Notes |
|-----------|-----------|-------|
| I. Full-Stack Ownership | **Exempt with justification** | Backend-only — no frontend display changes needed because chunk content is unchanged (FR-003/FR-008). Frontend already renders stored content, not embedding input. |
| II. Explicit Over Automatic | **Pass** | Contextual embedding applies automatically to all new uploads (FR-005). Re-embedding is admin-initiated (FR-006). No hidden behavior. |
| III. RBAC | **Pass** | New manual re-embed endpoint is admin-only, matching existing document re-embed pattern. |
| IV. Server-First File Storage | **N/A** | No file storage changes. |
| V. Client-Side Computation | **N/A** | No client-side changes. |
| VI. Audit Everything | **Pass** | FR-011 requires per-chunk embedding logging (title used, section used, truncation). Re-embed endpoints log activity. |
| VII. Simplicity & YAGNI | **Pass** | Minimal: one shared helper, two pipeline touch points, one new endpoint. No abstraction layers, no feature flags, no config tables. |

**Post-Phase 1 Re-check**: All gates still pass.

## Project Structure

### Documentation (this feature)

```text
specs/075-contextual-embeddings/
├── plan.md              # This file
├── spec.md              # Feature specification (clarified 2026-04-16)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── api.md           # New manual re-embed endpoint + behavioral changes
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (files to modify)

```text
backend/
├── services/
│   ├── document_service.py              # CHANGE: add prefix before embed_many() in index_document()
│   ├── manual_rag_service.py            # CHANGE: add prefix before embed_many() in upload_manual()
│   └── contextual_prefix.py             # NEW: shared build_contextual_prefix() helper
├── routers/
│   ├── documents.py                     # CHANGE: update re_embed_all_chunks() to use prefix
│   └── manuals.py                       # CHANGE: add POST /manuals/{manual_id}/re-embed endpoint
└── tests/
    └── test_contextual_prefix.py        # NEW: prefix builder + pipeline integration tests
```

**Structure Decision**: Backend-only. 3 existing files modified + 2 new files (helper module + tests). No new directories.

## Complexity Tracking

> No violations. Constitution gate passes.
