# Research: Spec 070 — Document Retrieval

**Date**: 2026-04-16

## R1: PDF Text Extraction Library

**Decision**: `pdfplumber` (Python)
**Rationale**: Native PDF text extraction with page-level access, table detection, and position-aware text. Lightweight, no external binaries required. Already well-suited for text-selectable English PDFs.
**Alternatives considered**:
- `PyMuPDF` (already in requirements.txt as `pymupdf==1.24.10`) — fast but GPL licensed; could use it instead of adding a new dependency. However, `pdfplumber` has better section-boundary detection via line-level metadata.
- `PyPDF2` (already in requirements.txt) — basic text extraction, no positional info for heading detection.

**Note**: The project already has `pymupdf==1.24.10` in requirements.txt. If we want to avoid a new dependency, `pymupdf` (via `fitz`) can do page-level text extraction. Decision: use `pdfplumber` per spec for better heading detection support.

## R2: Embedding Model and Dimensions

**Decision**: `nomic-embed-text-v2-moe` via Ollama at localhost:11434, 768-dim vectors
**Rationale**: Already deployed and used by validated_qa pipeline. `embed_single()` and `embed_many()` in `backend/services/ollama_embedder.py` handle the Ollama API calls with timeout and queue support.
**Integration**: Import `embed_single` / `embed_many` from `services.ollama_embedder`. Vectors are 768-dim (matches `vector(768)` in DDL).

## R3: Vector Search Pattern (pgvector)

**Decision**: Supabase RPC function using `<=>` cosine distance operator, filtered to `chunk_type='child'` and `status='ready'` documents.
**Rationale**: Matches the existing `search_validated_qa` RPC pattern. The `<=>` operator returns cosine distance (0 = identical, 1 = orthogonal). Convert to similarity: `1.0 - distance`.
**Implementation**: New Supabase RPC `search_document_chunks(query_embedding, match_count, match_threshold)` with JOIN on `knowledge_documents` to filter by `status='ready'`.

## R4: File Upload Pattern

**Decision**: Follow existing pattern from `backend/routers/files.py` exactly.
**Details**:
- `UPLOAD_DIR = "uploaded_files"` → manuals go to `uploaded_files/manuals/{uuid}.pdf`
- Files saved to disk with `os.path.join(UPLOAD_DIR, "manuals", filename)`
- Public URL: `/files/manuals/{filename}` — served by existing StaticFiles mount
- Metadata stored in `knowledge_documents` table via Supabase client

## R5: Admin Auth Pattern

**Decision**: Replicate `_admin_check()` helper from `backend/routers/manuals.py`.
**Details**: Query `users` table for `user_type` by email. Raise HTTP 403 if not `admin`. Pattern used consistently across manuals.py, users.py.

## R6: Background Task for Indexing

**Decision**: FastAPI `BackgroundTasks` parameter injection.
**Rationale**: Simple, built-in, no external task queue needed. The indexing pipeline (extract → chunk → embed → store) runs after the upload response is returned. Status is tracked via `knowledge_documents.status` column.
**Error handling**: On failure, set `status='failed'` and `error_message` with the exception. Partial chunks are kept for inspection; re-index cleans up.

## R7: RAG Integration Point

**Decision**: Insert document chunk search between post-rewrite validated_qa check (line ~1052) and the HyDE step (line ~1053) in `manual_rag_service.py`.
**Flow**:
1. Pre-rewrite validated_qa check → if match >= 0.70 → return
2. Query rewrite → post-rewrite validated_qa check → if match >= 0.70 → return
3. **NEW**: Document chunk search → if match >= 0.70 → fetch parent context → LLM → return
4. Existing: HyDE → embed → manual-chunks pipeline (unchanged fallback)

**Key detail**: The document search reuses the already-computed `question_embedding` (line ~1061) — BUT this embedding happens AFTER the HyDE step. To search document chunks before HyDE, we need to embed the `search_query` (or `embed_input`) separately for the document search, or move the embedding before the document search. Best approach: embed `search_query` directly for document chunk search (skip HyDE for this layer — HyDE is for the manual-chunks pipeline which has different content patterns).

## R8: Activity Logging

**Decision**: Use existing fire-and-forget `log_activity()` from `backend/utils/activity.py`.
**Events to log**:
- `category="document"`, `action="uploaded"` — on upload
- `category="document"`, `action="deleted"` — on delete
- `category="document"`, `action="reindexed"` — on re-index

## R9: IVFFlat Index Requirements

**Decision**: The `ivfflat` index in the DDL requires at least `lists` parameter for optimal performance. However, for small-to-medium collections (< 10k chunks), the default works fine. The filtered partial index (`WHERE chunk_type = 'child'`) is correct.
**Note**: IVFFlat needs training data. If the table is empty at index creation, queries still work (sequential scan fallback) but performance degrades with scale. For the expected volume (a few dozen manuals × ~50-200 chunks each = < 5k chunks), this is fine.

## R10: Frontend Structure

**Decision**: Add "Documents" tab to `ManualAssistantScreen` in `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart`.
**Current tabs** (admin): Chat, Knowledge, Review, Rules, Alerts, Verified (6 tabs, TabController length 6 for admin, 2 for non-admin).
**New**: Add "Documents" tab at position 6 (after Verified) for admin only → 7 tabs for admin.
**Files**: New `documents_tab.dart` in same directory, new `document_card.dart` widget, new `document_service.dart` in `frontend/lib/services/`.
