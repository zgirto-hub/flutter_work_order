# Research: Spec 072 — Document Retrieval v2

**Date**: 2026-04-16

## R1: Adapting HyDE for Document Chunks

**Decision**: Reuse `_generate_hypothetical_answer()` as-is. No changes needed.
**Rationale**: The function generates a hypothetical manual passage from a query — the output is generic text, not tied to any table structure. It calls `ollama_generator.generate()` which is table-agnostic. The HyDE text is then embedded with `embed_single()` and used as the search query — this works identically for `document_chunks` as for `manual_chunks`.
**Alternatives considered**: Writing a document-specific HyDE prompt. Rejected — the current prompt ("write a short passage that would appear in a civil aviation technical manual") is equally applicable to document chunks.

## R2: Adapting Per-Manual Retrieval for Per-Document Retrieval

**Decision**: Create `_retrieve_chunks_per_document()` modeled on `_retrieve_chunks_per_manual()` (lines 520-574), but querying `search_document_chunks` RPC instead of `search_manual_chunks`.
**Rationale**: The existing function groups results by manual_id, caps at 3 chunks per manual and 8 manuals total. The document version groups by document_id with the same caps. Key difference: document chunks have parent_id, so after retrieval we fetch parent content.
**Changes needed**:
- Call `search_document_chunks` RPC with relaxed threshold (0.55 distance, 10 candidates per clarification Q5)
- Group by `document_id` instead of `manual["id"]`
- Apply same per-document cap (3) and cross-document limit (8)
- After grouping, call `fetch_parent_context()` to enrich with parent section text

## R3: Adapting Sub-Answer Generation

**Decision**: Adapt `_generate_sub_answers()` to work with document chunks. The function builds a prompt per manual's chunks and calls the LLM. For documents, the prompt includes parent section context instead of raw chunk content.
**Rationale**: The prompt structure is the same — retrieved text + question + history. Only the "retrieved text" format changes: instead of `[Chunk {index}] {content}`, use `[Document Source {i}]\nDocument: {name}\nSection: {title}\nPage: {page}\n{parent_content}`.
**Key difference**: Document chunks send parent section content to the LLM (richer context), while manual chunks send the raw chunk text.

## R4: Adapting Synthesis

**Decision**: Reuse `_synthesize_answers()` as-is. No changes needed.
**Rationale**: The function takes a list of `sub_answers` dicts (each with `answer`, `grounded`, `manual_title` fields) and synthesizes them. For documents, use `document_name` where `manual_title` was. The synthesis prompt and conflict detection logic are content-agnostic.

## R5: Search Threshold Relaxation

**Decision**: Update `search_document_chunks` RPC to accept `match_threshold=0.55` and `match_count=10` (per clarification Q5).
**Rationale**: Reranking works best with a wider candidate pool. Current RPC defaults are `match_threshold=0.30, match_count=3` (from spec 070). The reranker (distance < MAX_CHUNK_DISTANCE=0.55, cap at 3) does the final filtering.
**Implementation**: Either pass new defaults in the Python call, or update the RPC default params. Simpler to pass from Python.

## R6: Chunk CRUD for document_chunks

**Decision**: Add chunk CRUD endpoints to `backend/routers/documents.py` — replicate the 9 endpoints from `manuals.py` (lines 917-1400) adapted for `document_chunks` table with parent-child awareness.
**Endpoints to add**:
1. `GET /{doc_id}/chunks` — paginated, ordered by parent then chunk_index
2. `POST /{doc_id}/chunks` — add child chunk under specified parent, embed, reindex
3. `GET /{doc_id}/chunks/{chunk_id}` — single chunk
4. `PUT /{doc_id}/chunks/{chunk_id}` — update content; if child, re-embed + set embedding_stale=false; if parent, no embed
5. `DELETE /{doc_id}/chunks/{chunk_id}` — delete + reindex siblings
6. `POST /{doc_id}/chunks/{chunk_id}/split` — split child at position, create 2 new children with same parent_id, embed both, reindex
7. `POST /{doc_id}/chunks/{chunk_id}/merge` — merge child with next sibling (same parent_id), embed result, reindex
8. `POST /{doc_id}/chunks/re-embed` — background task: re-embed all child chunks
9. `DELETE /{doc_id}/chunks/bulk-delete` — delete multiple chunks, reindex

## R7: Multi-Format Upload

**Decision**: Reuse existing `manual_parser.py` for DOCX/TXT/MD extraction. Only add format detection to `document_service.py`.
**Rationale**: `manual_parser.py` already handles PDF (via PyMuPDF), DOCX (python-docx), TXT, and MD. For spec 070, `document_service.py` only handles PDF via pdfplumber. Extend it to detect file extension and route to the appropriate parser.
**Note**: For PDFs, keep pdfplumber (spec 070's choice) rather than switching to PyMuPDF. For DOCX/TXT/MD, delegate to `manual_parser.parse()` which returns page-aware text.

## R8: Migration Strategy

**Decision**: Add a `POST /api/documents/migrate-all` endpoint. Reads all `manuals` rows, processes sequentially, creates `knowledge_documents` entries and chunks.
**Steps per manual**:
1. Read manual metadata (title, filename, file_extension, uploaded_by, created_at)
2. Locate source file at `uploaded_files/manuals/{manual_id}.{ext}`
3. Copy to `uploaded_files/manuals/{new_uuid}.{ext}` (new UUID for knowledge_documents)
4. Run the full indexing pipeline (extract → chunk → embed)
5. Set `knowledge_documents.created_at` to original manual's `created_at`
6. Report progress after each manual

## R9: Schema Changes

**Decision**: One migration adds `chunk_index` and `embedding_stale` to `document_chunks`. Also add `file_extension` to `knowledge_documents`.
**Details**:
- `ALTER TABLE document_chunks ADD COLUMN chunk_index int` — nullable initially, populated by reindex
- `ALTER TABLE document_chunks ADD COLUMN embedding_stale boolean NOT NULL DEFAULT false`
- `ALTER TABLE knowledge_documents ADD COLUMN file_extension text` — nullable, populated on upload
- Update `search_document_chunks` RPC to exclude `embedding_stale = true` rows
- No new tables needed

## R10: Retirement Plan

**Decision**: After migration is verified, remove in this order:
1. Remove Knowledge tab from `manual_assistant_screen.dart` (ManualsTab import + tab + body)
2. Remove `manuals_tab.dart`, `chunk_edit_screen.dart`, `chunk_editor_screen.dart`, `upload_dialog.dart`
3. Remove chunk CRUD endpoints from `manuals.py` (lines 917-1400)
4. Remove `manual_parser.py`, `manual_chunker.py`, `manual_storage_service.py` — BUT keep `manual_parser.py` if multi-format upload reuses it
5. Remove Layer 3 block from `manual_rag_service.ask()` (lines 1286-1567)
6. Remove `_retrieve_chunks_per_manual()`, `_generate_sub_answers()` if fully replaced
7. Drop `manuals`, `manual_chunks`, `manual_corpus_stats` tables via migration
**Note**: `manual_parser.py` should be kept and renamed to `text_extractor.py` since multi-format upload needs it.
