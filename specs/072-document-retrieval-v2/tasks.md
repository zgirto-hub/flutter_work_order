# Tasks: Document Retrieval v2 — Replace Knowledge Tab

**Input**: Design documents from `/specs/072-document-retrieval-v2/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Manual curl tests only (no automated test tasks).

**Organization**: Tasks grouped by user story across 8 phases. Backend (Python) + Frontend (Dart) + 1 Supabase migration.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1-US5)

## Important Context for the Implementer

**READ BEFORE STARTING**: This spec enhances the Documents tab (spec 070) to replace the Knowledge tab. You are modifying existing code, not writing from scratch.

### Architecture Overview
- **RAG orchestration**: `ask()` in `backend/services/manual_rag_service.py` (line ~766)
- **Layer 2 block** (spec 070): lines 1078-1202 — document chunk search with direct embedding
- **Layer 3 block** (specs 040-046): lines 1287-1567 — HyDE + manual-chunks pipeline
- **HyDE function**: `_generate_hypothetical_answer()` at line 489 — generates hypothetical passage, returns string or None
- **Per-manual retrieval**: `_retrieve_chunks_per_manual()` at line 520 — queries `search_manual_chunks` RPC, groups by manual, caps at 3/manual, 8 manuals
- **Sub-answer generation**: `_generate_sub_answers()` at line 577 — builds prompt per manual's chunks, calls LLM
- **Synthesis**: `_synthesize_answers()` at line 677 — combines sub-answers, detects conflicts
- **Document search service**: `backend/services/document_search_service.py` — `search_document_chunks()` + `fetch_parent_context()`
- **Document service**: `backend/services/document_service.py` — indexing pipeline, chunking
- **Documents router**: `backend/routers/documents.py` — 5 existing endpoints
- **Existing chunk CRUD**: `backend/routers/manuals.py` lines 917-1400 — 9 endpoints to replicate for document_chunks
- **Frontend Documents tab**: `frontend/lib/screens/manual_assistant/documents_tab.dart`
- **Frontend chunk editor (old)**: `frontend/lib/screens/manual_assistant/chunk_editor_screen.dart` — reference for UI patterns

### What NOT to Change
- `backend/services/ai_providers/resolver.py` — off limits
- `backend/services/validated_qa_service.py` — off limits
- `.env` files
- The validated_qa blocks in `manual_rag_service.py` (lines 811-1084) — do not modify
- The greeting bypass at the top of `ask_question()` in manuals.py

### Key Decisions (from clarifications)
1. **chunk_index** integer column on `document_chunks` — auto-reindex on split/merge/delete
2. **embedding_stale** boolean on `document_chunks` — exclude stale from search, show warning badge
3. **Sequential migration** — one manual at a time with progress reporting
4. **Move Layer 3 functions** into Layer 2 — adapt `_retrieve_chunks_per_manual()` → `_retrieve_chunks_per_document()`, reuse synthesis
5. **Relaxed search threshold** — 0.55 distance (0.45 similarity), 10 candidates, rerank to top 3

### Distance vs Similarity
- `<=>` returns cosine distance: 0.0=identical, 1.0=orthogonal
- similarity = 1.0 - distance
- Relaxed threshold: 0.55 distance = 0.45 similarity (wider pool for reranking)
- Reranker cap: MAX_CHUNK_DISTANCE=0.55, MAX_PROMPT_CHUNKS=3

---

## Phase 1: Setup (Schema Migration)

**Purpose**: Add columns and update RPC before any code changes.

- [ ] T001 Create Supabase migration `supabase/migrations/20260417000000_document_chunks_v2.sql`

  **What to do**: Single migration file with:

  ```sql
  -- Add chunk ordering
  ALTER TABLE document_chunks ADD COLUMN chunk_index int;

  -- Add stale embedding tracking
  ALTER TABLE document_chunks ADD COLUMN embedding_stale boolean NOT NULL DEFAULT false;

  -- Add file extension tracking
  ALTER TABLE knowledge_documents ADD COLUMN file_extension text;

  -- Backfill chunk_index for existing chunks (order by created_at within parent)
  WITH ranked AS (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY parent_id ORDER BY created_at) - 1 AS idx
    FROM document_chunks
    WHERE chunk_type = 'child'
  )
  UPDATE document_chunks SET chunk_index = ranked.idx
  FROM ranked WHERE document_chunks.id = ranked.id;

  -- Also index parent chunks (by created_at)
  WITH ranked_parents AS (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY document_id ORDER BY created_at) - 1 AS idx
    FROM document_chunks
    WHERE chunk_type = 'parent'
  )
  UPDATE document_chunks SET chunk_index = ranked_parents.idx
  FROM ranked_parents WHERE document_chunks.id = ranked_parents.id;

  -- Update RPC to exclude stale chunks
  CREATE OR REPLACE FUNCTION search_document_chunks(
    query_embedding vector(768),
    match_count int DEFAULT 10,
    match_threshold float DEFAULT 0.55
  )
  RETURNS TABLE (
    id uuid,
    document_id uuid,
    parent_id uuid,
    section_title text,
    content text,
    page_number int,
    distance float
  )
  LANGUAGE sql STABLE
  AS $$
    SELECT
      dc.id,
      dc.document_id,
      dc.parent_id,
      dc.section_title,
      dc.content,
      dc.page_number,
      dc.embedding <=> query_embedding AS distance
    FROM document_chunks dc
    JOIN knowledge_documents kd ON kd.id = dc.document_id
    WHERE dc.chunk_type = 'child'
      AND kd.status = 'ready'
      AND dc.embedding_stale = false
      AND dc.embedding <=> query_embedding < match_threshold
    ORDER BY dc.embedding <=> query_embedding
    LIMIT match_count;
  $$;
  ```

  **NOTE**: The RPC now defaults to `match_count=10` and `match_threshold=0.55` (was 3 and 0.30 in spec 070). This retrieves more candidates for reranking.

**Checkpoint**: Migration applied. No code changes yet.

---

## Phase 2: Enhanced Search Pipeline (US1 — Priority: P1) MVP

**Goal**: Replace the Layer 2 block in `ask()` with HyDE + per-document retrieval + reranking + cross-document synthesis. This makes document search quality match or exceed the old Knowledge tab.

**Independent Test**:
```bash
# Upload a document first via Documents tab, wait for "ready", then:
curl -X POST http://localhost:8000/api/manuals/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "what should I check during routine maintenance"}'
# Expected: answer with HyDE-enhanced matching, source_type="document", manuals_consulted, has_conflicts
```

- [ ] T002 [US1] Create `_retrieve_chunks_per_document()` in `backend/services/document_search_service.py`

  **What to do**: Add a new async function modeled on `_retrieve_chunks_per_manual()` (manual_rag_service.py line 520). This function:

  1. Calls `search_document_chunks` RPC with the embedding (already retrieves 10 candidates at 0.55 threshold from T001)
  2. Converts distance to similarity for each result
  3. Groups results by `document_id`
  4. Caps at 3 chunks per document (`MAX_CHUNKS_PER_DOCUMENT = 3`)
  5. If more than 8 documents qualify, keeps top 8 by average distance
  6. For each matched child, fetches parent content via `fetch_parent_context()`
  7. Also fetches document metadata (`display_name`) for each document

  **Signature**:
  ```python
  async def retrieve_chunks_per_document(
      embedding_str: str,
      max_chunks_per_doc: int = 3,
      max_documents: int = 8,
  ) -> dict[str, list[dict]]:
      """Returns {document_id: [enriched_chunk_dicts]} grouped by document."""
  ```

  Each chunk dict must include: `id`, `document_id`, `display_name`, `parent_id`, `section_title`, `content`, `page_number`, `similarity`, `parent_content`.

  **Import**: Add `from db import supabase` if not already imported.

- [ ] T003 [US1] Create `_generate_document_sub_answers()` in `backend/services/document_search_service.py`

  **What to do**: Add a function modeled on `_generate_sub_answers()` (manual_rag_service.py line 577). For each document's chunks, builds a prompt with parent section context and calls the LLM.

  **Context format per document**:
  ```
  [Document Source 1]
  Document: {display_name}
  Section: {section_title}
  Page: {page_number}

  {parent_content}

  [Document Source 2]
  ...
  ```

  **Signature**:
  ```python
  async def generate_document_sub_answers(
      chunks_by_document: dict[str, list[dict]],
      question: str,
      history: list[dict] | None = None,
      memory: str | None = None,
      user_email: str | None = None,
      latency_breakdown: dict | None = None,
  ) -> tuple[list[dict], str, bool, str]:
      """Returns (sub_answers, provider_used, fallback_used, provider_display_name)."""
  ```

  Each sub_answer dict: `{"answer": str, "grounded": bool, "document_id": str, "display_name": str, "sources": list[dict]}`.

  Use `DOCUMENT_QA_SYSTEM_PROMPT` from `manual_rag_service.py` (line ~98) for the prompt. Call `provider_generate()` from `services.ai_providers.resolver`.

  Check groundedness using the sentinel phrases from `manual_rag_service.py` (lines 97-120).

- [ ] T004 [US1] Create `synthesize_document_answers()` in `backend/services/document_search_service.py`

  **What to do**: Add a synthesis function modeled on `_synthesize_answers()` (manual_rag_service.py line 677). Takes sub_answers from T003, synthesizes into one answer, detects conflicts.

  **Signature**:
  ```python
  async def synthesize_document_answers(
      sub_answers: list[dict],
      question: str,
      user_email: str | None = None,
      latency_breakdown: dict | None = None,
  ) -> dict:
      """Returns {answer, synthesized, documents_consulted, has_conflicts, grounded, ...}."""
  ```

  **Key behaviors** (copy from `_synthesize_answers`):
  - If only 1 grounded sub_answer → return it directly (no LLM call)
  - If multiple → synthesize with LLM, detect "CONFLICT:" sentinel
  - If 0 grounded → return ungrounded flag

- [ ] T005 [US1] Replace Layer 2 block in `backend/services/manual_rag_service.py` with HyDE-enhanced document search

  **What to do**: Replace the entire Layer 2 block (lines 1078-1202, between `# --- Layer 2: Document chunk search (spec 070) ---` and `# --- End Layer 2 ---`) with the new enhanced pipeline.

  **New Layer 2 block**:
  1. Apply HyDE: `hyde_text = await _generate_hypothetical_answer(search_query)` (reuse existing function at line 489)
  2. Embed: `embed_input = hyde_text if hyde_text else search_query`; `doc_query_embedding = await embed_single(embed_input)`
  3. Convert to string: `embedding_str = "[" + ",".join(str(x) for x in doc_query_embedding) + "]"`
  4. Per-document retrieval: `chunks_by_doc = await retrieve_chunks_per_document(embedding_str)`
  5. If no chunks found → fall through to Layer 3 (existing manual-chunks pipeline, for now)
  6. Sub-answers: `sub_answers, provider_used, fallback_used, provider_display_name = await generate_document_sub_answers(chunks_by_doc, search_query, ...)`
  7. Synthesis: `result = await synthesize_document_answers(sub_answers, search_query, ...)`
  8. If result is grounded → build and return response dict with `source_type="document"`, `manuals_consulted` (list of `{id, title}` for each doc), `has_conflicts`, `confidence`, `score`, `sources`
  9. If result is NOT grounded → fall through to Layer 3

  **Add imports** at top of file:
  ```python
  from services.document_search_service import (
      retrieve_chunks_per_document,
      generate_document_sub_answers,
      synthesize_document_answers,
  )
  ```

  **Response dict** for document-sourced answers must include ALL these fields:
  ```python
  {
      "answer": result["answer"],
      "grounded": True,
      "sources": sources,  # [{type, document_id, display_name, section_title, page_number, score}]
      "confidence": confidence,
      "score": max_score,
      "source_type": "document",
      "model": provider_display_name,
      "provider_display_name": provider_display_name,
      "duration_seconds": round(elapsed, 1),
      "is_verified": False,
      "verified_source": None,
      "manuals_consulted": [{"id": doc_id, "title": name} for doc_id, name in ...],
      "has_conflicts": result.get("has_conflicts", False),
      "retrieval_info": retrieval_info,
      "provider_used": provider_used,
      "fallback_used": fallback_used,
      "session_summary": None,
      "latency_breakdown": breakdown,
  }
  ```

  **IMPORTANT**: Do NOT remove Layer 3 yet. If Layer 2 doesn't find grounded answers, the flow should still fall through to Layer 3. Layer 3 removal happens in Phase 7 (US5).

**Checkpoint**: Ask a question matching a document → get HyDE-enhanced answer with cross-document synthesis. Layer 3 still works as fallback.

---

## Phase 3: Chunk CRUD Backend (US2 Backend — Priority: P2)

**Goal**: Add 9 chunk management endpoints to the documents router.

- [ ] T006 [US2] Add chunk list endpoint `GET /{document_id}/chunks` to `backend/routers/documents.py`

  **What to do**: Paginated chunk list, ordered by parent chunk_index then child chunk_index within parent. Include: id, chunk_type, parent_id, chunk_index, section_title, content, page_number, char_count (computed as `len(content)`), embedding_stale, children_count (for parents).

  Parameters: `document_id: str`, `user_email: str`, `page: int = 1`, `page_size: int = 20`.

  Query: `supabase.table("document_chunks").select("*").eq("document_id", document_id).order("chunk_index")`. Then paginate in Python (group parents with their children).

- [ ] T007 [P] [US2] Add chunk CRUD endpoints to `backend/routers/documents.py`

  **Add these 4 endpoints**:

  1. `POST /{document_id}/chunks` — add child chunk under parent_id, embed, set chunk_index (insert_after param), reindex siblings
  2. `GET /{document_id}/chunks/{chunk_id}` — single chunk detail
  3. `PUT /{document_id}/chunks/{chunk_id}` — update content. If child: re-embed (set `embedding_stale=false` on success, `true` on embed failure). If parent: just update content.
  4. `DELETE /{document_id}/chunks/{chunk_id}` — delete chunk, reindex siblings

  Use `embed_single()` from `services.ollama_embedder` for re-embedding. Store embedding as string: `"[" + ",".join(str(x) for x in emb) + "]"`.

  Use `_admin_check(user_email)` on all endpoints. Use `log_activity()` for audit logging.

- [ ] T008 [P] [US2] Add split, merge, re-embed, and bulk-delete endpoints to `backend/routers/documents.py`

  **Add these 4 endpoints**:

  1. `POST /{document_id}/chunks/{chunk_id}/split` — split child at `split_position`. Create 2 new children with same `parent_id`, embed both, reindex siblings. Return both new chunks.
  2. `POST /{document_id}/chunks/{chunk_id}/merge` — merge child with next sibling (same parent_id). Validate same parent. Combined content, embed, reindex. Return merged chunk.
  3. `POST /{document_id}/chunks/re-embed` — background task: re-embed all child chunks for this document. Set `embedding_stale=false` for each successful embed.
  4. `DELETE /{document_id}/chunks/bulk-delete` — accept `chunk_ids` list, delete all, reindex.

  **Reindex helper function** — create `_reindex_siblings(document_id, parent_id)`:
  ```python
  def _reindex_siblings(document_id: str, parent_id: str):
      siblings = supabase.table("document_chunks").select("id").eq("document_id", document_id).eq("parent_id", parent_id).order("chunk_index").execute()
      for i, s in enumerate(siblings.data):
          supabase.table("document_chunks").update({"chunk_index": i}).eq("id", s["id"]).execute()
  ```

**Checkpoint**: All 9 chunk CRUD endpoints working via curl.

---

## Phase 4: Multi-Format Upload (US3 — Priority: P2)

**Goal**: Extend upload to accept DOCX, TXT, MD files alongside PDF.

- [ ] T009 [US3] Extend `backend/services/document_service.py` to support DOCX, TXT, MD extraction

  **What to do**:

  1. Add format detection at the start of `index_document()`:
     ```python
     ext = os.path.splitext(file_path)[1].lower()
     ```
  2. For `.pdf`: keep existing pdfplumber extraction (unchanged)
  3. For `.docx`, `.txt`, `.md`: import and use existing parser:
     ```python
     from services.manual_parser import parse
     pages = parse(file_path)  # returns list of (page_number, text) tuples
     ```
  4. After extraction, the rest of the pipeline is the same: `_detect_sections(pages)` → parent/child chunking → embedding

  **Also**: When inserting the `knowledge_documents` row (in the upload endpoint in `documents.py`), store `file_extension`:
  ```python
  doc_row["file_extension"] = extension  # pdf, docx, txt, md
  ```

- [ ] T010 [US3] Update upload endpoint in `backend/routers/documents.py` to accept multi-format

  **What to do**: Change the file extension validation (currently PDF-only) to:
  ```python
  ALLOWED_EXTENSIONS = {"pdf", "docx", "txt", "md"}
  extension = file.filename.split(".")[-1].lower()
  if extension not in ALLOWED_EXTENSIONS:
      raise HTTPException(status_code=400, detail="Unsupported file type. Accepted: PDF, DOCX, TXT, MD")
  ```

  Update the filename generation:
  ```python
  filename = f"{file_id}.{extension}"  # was hardcoded .pdf
  ```

**Checkpoint**: Upload a .docx file, verify chunks created and searchable.

---

## Phase 5: Chunk Editor UI (US2 Frontend — Priority: P2)

**Goal**: Admin can browse, edit, split, merge, delete chunks for any document.

- [ ] T011 [P] [US2] Add chunk CRUD methods to `frontend/lib/services/document_service.dart`

  **What to do**: Add these methods to the existing `DocumentService` class:

  ```dart
  Future<Map<String, dynamic>> listChunks(String documentId, String userEmail, {int page = 1, int pageSize = 20})
  Future<Map<String, dynamic>> getChunk(String documentId, String chunkId, String userEmail)
  Future<Map<String, dynamic>> updateChunk(String documentId, String chunkId, String content, String userEmail)
  Future<Map<String, dynamic>> addChunk(String documentId, String parentId, String content, String userEmail, {int? insertAfter})
  Future<void> deleteChunk(String documentId, String chunkId, String userEmail)
  Future<List<Map<String, dynamic>>> splitChunk(String documentId, String chunkId, int splitPosition, String userEmail)
  Future<Map<String, dynamic>> mergeChunk(String documentId, String chunkId, String userEmail)
  Future<void> reEmbedAll(String documentId, String userEmail)
  Future<void> bulkDeleteChunks(String documentId, List<String> chunkIds, String userEmail)
  ```

  **URL pattern**: `$_baseUrl/documents/$documentId/chunks/...` (NO `/api/` prefix — baseUrl already includes it).

- [ ] T012 [P] [US2] Create `frontend/lib/screens/manual_assistant/widgets/document_chunk_card.dart`

  **What to do**: A card widget for displaying a single chunk. Follow the same patterns as the existing `chunk_card.dart` in the same widgets directory.

  Show: chunk_type badge (Parent/Child), section_title, page_number, content preview (first 200 chars), char_count, embedding_stale warning badge (amber "Stale" if true).

  Action buttons (for child chunks): Edit, Split, Merge, Delete.
  Action buttons (for parent chunks): Edit, Delete.

- [ ] T013 [US2] Create `frontend/lib/screens/manual_assistant/document_chunk_editor.dart`

  **What to do**: A StatefulWidget screen for managing a document's chunks. Reference the existing `chunk_editor_screen.dart` for UI patterns.

  Features:
  - **Constructor**: `DocumentChunkEditor({required this.documentId, required this.displayName, required this.userEmail})`
  - **Paginated list**: Load chunks with page/pageSize, show parent groups with children nested
  - **Edit dialog**: Tap edit → modal with TextField → save → re-embed (show loading)
  - **Split dialog**: Tap split → show text with cursor → confirm position → creates 2 chunks
  - **Merge**: Tap merge on a child → merges with next sibling (confirm dialog)
  - **Delete**: Single delete with confirm, or bulk select + delete
  - **Re-embed All**: Button in AppBar → triggers background task → show toast
  - **Stale warning**: Amber badge on stale chunks, "Re-embed" button per chunk

- [ ] T014 [US2] Wire chunk editor navigation from `frontend/lib/screens/manual_assistant/documents_tab.dart`

  **What to do**: When admin taps a document card, navigate to the chunk editor:
  ```dart
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => DocumentChunkEditor(
      documentId: doc['id'],
      displayName: doc['display_name'],
      userEmail: _userEmail,
    ),
  ));
  ```

  Add the import for `document_chunk_editor.dart`.

**Checkpoint**: Navigate to Documents tab → tap a document → see chunk list → edit/split/merge/delete work.

---

## Phase 6: Migration (US4 — Priority: P3)

**Goal**: Admin can migrate all existing Knowledge tab manuals to Documents tab.

- [ ] T015 [US4] Add migration endpoints to `backend/routers/documents.py`

  **Add 3 endpoints**:

  1. `POST /migrate-all` — admin check, read all rows from `manuals` table, process sequentially:
     - For each manual: get file_path (`uploaded_files/manuals/{manual_id}.{ext}`), create `knowledge_documents` row with original metadata (title → display_name, file_name → filename, uploaded_by, created_at), trigger `index_document()` synchronously (not background — we need sequential progress)
     - Track progress in a module-level dict: `_migration_status = {"status": "idle", "completed": 0, "total": 0, "failed": [], "current": ""}`
     - Run as background task but update status dict after each manual
     - Return: `{"status": "migrating", "total_manuals": N}`

  2. `GET /migration-status` — admin check, return `_migration_status` dict

  3. `DELETE /migrate-cleanup` — admin check, verify migration completed, then:
     - `supabase.table("manual_chunks").delete().neq("id", "").execute()` (delete all)
     - `supabase.table("manuals").delete().neq("id", "").execute()` (delete all)
     - Reset `manual_corpus_stats` to zero
     - Return: `{"deleted_manuals": N, "deleted_chunks": M}`

- [ ] T016 [US4] Add migration UI to `frontend/lib/screens/manual_assistant/documents_tab.dart`

  **What to do**: Add a "Migrate from Knowledge" section at the top of the Documents tab (only visible if there are manuals in the old system).

  - "Migrate All Manuals" button → calls `POST /migrate-all` → starts polling `GET /migration-status` every 3s
  - Progress bar: "Migrating: 3 of 12 — CADAS ATS Manual"
  - On completion: show summary (N migrated, M failed) + "Delete Old Data" button
  - "Delete Old Data" button → confirm dialog → calls `DELETE /migrate-cleanup`

  Add methods to `document_service.dart`:
  ```dart
  Future<Map<String, dynamic>> migrateAll(String userEmail)
  Future<Map<String, dynamic>> getMigrationStatus(String userEmail)
  Future<Map<String, dynamic>> migrateCleanup(String userEmail)
  ```

**Checkpoint**: Trigger migration → watch progress → verify documents appear in Documents tab → delete old data.

---

## Phase 7: Retirement (US5 — Priority: P3)

**Goal**: Remove Knowledge tab, Layer 3 pipeline, and old code.

**IMPORTANT**: Only execute this phase AFTER migration is verified and old data deleted.

- [ ] T017 [US5] Remove Layer 3 manual-chunks pipeline from `backend/services/manual_rag_service.py`

  **What to do**:
  1. Delete the entire Layer 3 block (lines ~1204 to end of function, starting at `# HyDE: generate hypothetical answer` through the end of the `ask()` function's cross-manual synthesis return). This includes the HyDE call, embedding, chunk retrieval, sub-answer generation, synthesis, and return statements for Layer 3.
  2. After the Layer 2 enhanced block (which now returns on grounded document matches), add a simple fallback return for when neither validated_qa nor documents matched:
     ```python
     # No grounded answer from validated_qa or documents — return fallback
     breakdown["total_ms"] = round((time.perf_counter() - _total_start) * 1000)
     return {
         "answer": "This information is not in the available manuals.",
         "grounded": False,
         "sources": [],
         "session_summary": None,
         "retrieval_info": retrieval_info,
         "latency_breakdown": breakdown,
     }
     ```
  3. Remove `_retrieve_chunks_per_manual()` (line 520-574)
  4. Remove `_generate_sub_answers()` (line 577-674) — now replaced by `generate_document_sub_answers` in document_search_service.py
  5. Remove `_synthesize_answers()` (line 677-782) — now replaced by `synthesize_document_answers` in document_search_service.py
  6. Remove unused imports: `from services.manual_parser import parse, NoExtractableTextError`, `from services.manual_chunker import chunk_paragraphs, Chunk`, `from services.manual_storage_service import save, delete as delete_file`

  **Keep**: `_generate_hypothetical_answer()` (line 489) — still used by Layer 2's HyDE step. Keep `_build_prompt()` ONLY if it's still referenced; otherwise remove.

- [ ] T018 [US5] Remove chunk CRUD endpoints from `backend/routers/manuals.py`

  **What to do**: Remove these endpoints (lines ~917-1400):
  - `POST /{manual_id}/chunks/re-embed`
  - `DELETE /{manual_id}/chunks/bulk-delete`
  - `GET /{manual_id}/chunks`
  - `POST /{manual_id}/chunks`
  - `GET /{manual_id}/chunks/{chunk_id}`
  - `PUT /{manual_id}/chunks/{chunk_id}`
  - `DELETE /{manual_id}/chunks/{chunk_id}`
  - `POST /{manual_id}/chunks/{chunk_id}/split`
  - `POST /{manual_id}/chunks/{chunk_id}/merge`

  Also remove the manual upload and delete endpoints if they only serve the Knowledge tab.

- [ ] T019 [US5] Remove Knowledge tab from `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart`

  **What to do**:
  1. Remove `import 'manuals_tab.dart';`
  2. Change TabController length: `_isAdmin ? 6 : 1` (was 7 : 2 — Knowledge tab was at index 1 for all users)
  3. Remove the Knowledge tab label and body (`ManualsTab(isAdmin: _isAdmin)`)
  4. Reorder remaining tabs: Chat, Review, Rules, Alerts, Verified, Documents (admin) or just Chat (non-admin)

  Wait — the Knowledge tab is visible to ALL users (not just admin). The Documents tab is admin-only. After retirement, non-admin users lose the ability to browse manuals. This is acceptable per the spec (out of scope for this phase — a future spec could add read-only document browsing for non-admins).

- [ ] T020 [US5] Delete retired frontend files

  Delete these files:
  - `frontend/lib/screens/manual_assistant/manuals_tab.dart`
  - `frontend/lib/screens/manual_assistant/chunk_edit_screen.dart`
  - `frontend/lib/screens/manual_assistant/chunk_editor_screen.dart`
  - `frontend/lib/screens/manual_assistant/widgets/upload_dialog.dart`

- [ ] T021 [US5] Rename `backend/services/manual_parser.py` → `backend/services/text_extractor.py` and update imports

  **What to do**:
  1. Rename the file
  2. Update all imports: `from services.manual_parser import parse` → `from services.text_extractor import parse`
  3. Check these files for imports: `document_service.py`, `manual_rag_service.py` (if still used), `routers/manuals.py`

- [ ] T022 [US5] Delete retired backend files

  Delete:
  - `backend/services/manual_chunker.py`
  - `backend/services/manual_storage_service.py`

  Verify no remaining imports reference these files.

- [ ] T023 [US5] Create retirement migration `supabase/migrations/20260418000000_drop_manuals_tables.sql`

  ```sql
  DROP TABLE IF EXISTS manual_chunks;
  DROP TABLE IF EXISTS manuals;
  DROP TABLE IF EXISTS manual_corpus_stats;
  DROP FUNCTION IF EXISTS search_manual_chunks;
  ```

  **Only apply this after confirming migration + cleanup are complete.**

**Checkpoint**: Build succeeds. No references to manuals/manual_chunks in active code. Ask a question → answered by Layer 2 only.

---

## Phase 8: Verification

- [ ] T024 Verify US1: Ask 5 questions matching documents → verify HyDE-enhanced answers with cross-document synthesis
- [ ] T025 Verify US2: Edit a chunk, split, merge, delete → verify changes reflected in search
- [ ] T026 Verify US3: Upload a DOCX file → verify chunked and searchable
- [ ] T027 Verify US4: Migration of all existing manuals → verify all appear in Documents tab
- [ ] T028 Verify US5: No references to `manuals` table, `manual_chunks`, `ManualsTab` in active code
- [ ] T029 Show `git diff` — verify only expected files changed

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (US1)**: Depends on Phase 1. MVP — enhanced search quality.
- **Phase 3 (US2 Backend)**: Depends on Phase 1 only. Can run parallel with Phase 2.
- **Phase 4 (US3)**: Depends on Phase 1 only. Can run parallel with Phase 2 and 3.
- **Phase 5 (US2 Frontend)**: Depends on Phase 3 (needs backend endpoints).
- **Phase 6 (US4)**: Depends on Phases 2, 3, 4 (needs enhanced pipeline + multi-format).
- **Phase 7 (US5)**: Depends on Phase 6 completion + migration verified.
- **Phase 8 (Verification)**: Depends on all phases.

### Task Execution Order

```
T001 → T002 → T003 → T004 → T005 → T006 + T007 + T008 (parallel) → T009 → T010 → T011 + T012 (parallel) → T013 → T014 → T015 → T016 → T017 → T018 → T019 → T020 → T021 → T022 → T023 → T024-T029
```

### Parallel Opportunities

- **T006 + T007 + T008** can run in parallel (different endpoint groups, no dependencies)
- **T011 + T012** can run in parallel (Dart service vs widget, different files)
- **T024-T029** can run in parallel (independent verification tests)

---

## Implementation Strategy

### MVP First (Phases 1-2)

1. T001: Schema migration
2. T002-T005: Enhanced search pipeline
3. **STOP and VALIDATE**: Document search now uses HyDE + reranking + synthesis

### Chunk Management (Phases 3-5)

4. T006-T008: Backend chunk CRUD
5. T009-T010: Multi-format upload
6. T011-T014: Frontend chunk editor
7. **STOP and VALIDATE**: Full chunk management working

### Migration + Retirement (Phases 6-7)

8. T015-T016: Migration
9. T017-T023: Retirement
10. **STOP and VALIDATE**: Knowledge tab gone, everything works

---

## Notes

- Do NOT commit changes — leave all modifications as uncommitted working tree changes for review
- The existing `_generate_hypothetical_answer()` at line 489 is KEPT — it's used by the new Layer 2 HyDE step
- Layer 3 removal (Phase 7) must NOT happen until migration is verified
- All new endpoints use `_admin_check(user_email)` for auth
- All mutations use `log_activity()` for audit
- Embedding stored as string: `"[0.1,0.2,...]"` for Supabase PostgREST
- Distance → similarity: `similarity = round(1.0 - distance, 2)`
- Use `from datetime import datetime, timezone` for timestamps, NOT `"now()"`
