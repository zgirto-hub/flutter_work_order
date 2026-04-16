# Tasks: Document Retrieval — Upload, Chunk, and Search Technical Manuals

**Input**: Design documents from `/specs/070-document-retrieval/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Manual curl tests only (no automated test tasks).

**Organization**: Tasks grouped by user story. Changes span backend (Python), frontend (Dart), and one Supabase migration.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1, US2, US3, US4, US5)

## Important Context for the Implementer

**READ BEFORE STARTING**: This feature adds a second RAG retrieval layer (uploaded PDF manuals) alongside the existing validated_qa pipeline. Here's the architecture you need to understand:

### Architecture Overview
- **RAG orchestration**: `ask()` in `backend/services/manual_rag_service.py` (line ~766)
- **Validated QA lookup**: `check_validated_match()` in `backend/services/validated_qa_service.py` (line ~265)
- **Embedding**: `embed_single()` / `embed_many()` in `backend/services/ollama_embedder.py`
- **Provider resolver**: `generate()` in `backend/services/ai_providers/resolver.py` — DO NOT modify
- **Admin auth pattern**: `_admin_check()` in `backend/routers/manuals.py` (lines ~856-869) — replicate this
- **File upload pattern**: `backend/routers/files.py` (lines 16-60) — replicate this for PDF uploads
- **Activity logging**: `log_activity()` in `backend/utils/activity.py` — fire-and-forget, never blocks
- **Frontend tabs**: `ManualAssistantScreen` in `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart`
- **Answer model**: `ManualQaAnswer` in `frontend/lib/models/manual_qa_answer.dart`
- **Source model**: `ManualSource` in `frontend/lib/models/manual_source.dart`
- **Static files mount**: `app.mount("/files", StaticFiles(directory=UPLOAD_DIR), name="files")` in `backend/main.py` line 79
- **Router registration**: `app.include_router(...)` in `backend/main.py` lines 103-125

### Current RAG Flow (what you're extending)
1. User asks question → `manual_rag_service.ask()` is called
2. **Pre-rewrite check** (~line 816): `check_validated_match(question)` → if similarity >= 0.70, LLM with validated_qa context → return
3. **Query rewrite** (~line 922): `_rewrite_query(question, history)` for context resolution
4. **Post-rewrite check** (~line 944): `check_validated_match(search_query)` → if similarity >= 0.70, LLM → return
5. **HyDE** (~line 1053): generate hypothetical answer → embed → manual-chunks pipeline

### New Flow (what you're building)
Insert **Layer 2** (document chunk search) between step 4 and step 5:
1. Pre-rewrite validated_qa check → if match >= 0.70 → return (existing, unchanged)
2. Query rewrite (existing, unchanged)
3. Post-rewrite validated_qa check → if match >= 0.70 → return (existing, unchanged)
4. **NEW: Document chunk search** → embed `search_query` → search `document_chunks` (child, status='ready') → if match >= 0.70 → fetch parent context → LLM → return with `source_type="document"`
5. HyDE → manual-chunks pipeline (existing fallback, unchanged)

### What NOT to Change
- `backend/services/ai_providers/resolver.py` — provider resolver is off limits
- `backend/services/validated_qa_service.py` — validated_qa service is unchanged
- Any existing Supabase migrations in `supabase/migrations/`
- `.env` files
- The validated_qa blocks in `manual_rag_service.py` (lines 811-1051) — do not modify these
- The HyDE / manual-chunks pipeline (lines 1053+) — do not modify
- The greeting bypass at the top of `ask_question()` in manuals.py

### Existing Admin Auth Pattern (MUST replicate)
From `backend/routers/manuals.py` lines 856-869:
```python
def _admin_check(user_email: str):
    user_resp = supabase.table("users").select("user_type").eq("email", user_email).maybe_single().execute()
    if not user_resp.data or user_resp.data.get("user_type") != "admin":
        raise HTTPException(status_code=403, detail={"error": "admin_required"})
```

### Existing File Upload Pattern (MUST replicate)
From `backend/routers/files.py` lines 16-35:
```python
UPLOAD_DIR = "uploaded_files"
file_id = str(uuid.uuid4())
extension = file.filename.split(".")[-1].lower()
filename = f"{file_id}.{extension}"
file_path = os.path.join(UPLOAD_DIR, filename)
with open(file_path, "wb") as f:
    content = await file.read()
    f.write(content)
public_url = f"/files/{filename}"
```
For spec 070: `file_path = os.path.join(UPLOAD_DIR, "manuals", filename)` and `public_url = f"/files/manuals/{filename}"`.

### Distance vs Similarity
The pgvector `<=>` operator returns cosine distance:
- distance 0.0 = identical, distance 1.0 = orthogonal
- **similarity = 1.0 - distance**
- Threshold 0.70 similarity = distance 0.30
- The `search_document_chunks` RPC uses `match_threshold` in distance space (0.30)

---

## Phase 1: Setup (Database + Dependencies)

**Purpose**: Create tables, RPC function, and install pdfplumber

- [ ] T001 Create Supabase migration `supabase/migrations/20260416000000_knowledge_documents.sql`

  **What to do**: Create a single migration file with ALL of the following DDL:

  ```sql
  -- knowledge_documents table
  CREATE TABLE knowledge_documents (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    filename      text NOT NULL,
    display_name  text NOT NULL,
    file_path     text NOT NULL,
    status        text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'indexing', 'ready', 'failed')),
    error_message text,
    total_pages   int,
    total_chunks  int,
    indexed_at    timestamptz,
    uploaded_by   text NOT NULL,
    created_at    timestamptz DEFAULT now()
  );

  -- document_chunks table
  CREATE TABLE document_chunks (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id     uuid REFERENCES knowledge_documents(id) ON DELETE CASCADE,
    chunk_type      text NOT NULL CHECK (chunk_type IN ('parent', 'child')),
    parent_id       uuid REFERENCES document_chunks(id) ON DELETE CASCADE,
    section_title   text,
    content         text NOT NULL,
    page_number     int,
    embedding       vector(768),
    created_at      timestamptz DEFAULT now()
  );

  -- Partial index: only child chunks with embeddings are searched
  CREATE INDEX idx_document_chunks_embedding
    ON document_chunks USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100)
    WHERE chunk_type = 'child';

  -- RPC function for vector search
  CREATE OR REPLACE FUNCTION search_document_chunks(
    query_embedding vector(768),
    match_count int DEFAULT 3,
    match_threshold float DEFAULT 0.30
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
      AND dc.embedding <=> query_embedding < match_threshold
    ORDER BY dc.embedding <=> query_embedding
    LIMIT match_count;
  $$;
  ```

  **IMPORTANT**: The IVFFlat index requires at least ~100 rows with embeddings to work. Until then, pgvector falls back to sequential scan — this is fine for initial data.

- [ ] T002 [P] Add `pdfplumber` to `backend/requirements.txt`

  **What to do**: Add `pdfplumber` on a new line after `pymupdf==1.24.10` (line 70). Do not pin a version — just `pdfplumber`.

- [ ] T003 [P] Create `backend/uploaded_files/manuals/` directory

  **What to do**: Ensure the directory exists. Add a `.gitkeep` file inside so git tracks it. Do NOT commit actual PDFs.

**Checkpoint**: Tables created, dependency added, upload directory exists.

---

## Phase 2: Foundational — PDF Chunking Pipeline

**Purpose**: The document service that extracts text, detects sections, creates parent/child chunks, and embeds children. ALL subsequent phases depend on this.

**CRITICAL**: No endpoint or search work can begin until this is complete and correct.

- [ ] T004 Create `backend/services/document_service.py` — full chunking + indexing pipeline

  **What to do**: Create a new service file with these functions:

  **1. `async def index_document(document_id: str, file_path: str) -> None`**
  - This is the main pipeline function, called as a background task after upload.
  - Steps:
    1. Update `knowledge_documents` status to `'indexing'` via Supabase
    2. Extract text per page using pdfplumber: `import pdfplumber; pdf = pdfplumber.open(file_path)`
    3. For each page, get `page.extract_text()` — store as list of `(page_number, text)` tuples
    4. Update `total_pages` in `knowledge_documents`
    5. Detect section boundaries across all pages (call `_detect_sections()`)
    6. Create parent chunks (one per section) — insert into `document_chunks` with `chunk_type='parent'`
    7. Create child chunks from each parent (split on `\n\n`) — insert into `document_chunks` with `chunk_type='child'`, `parent_id` set
    8. Embed all child chunks using `embed_many()` from `services.ollama_embedder`
    9. Update each child chunk's `embedding` column in Supabase
    10. Update `knowledge_documents`: `status='ready'`, `total_chunks=N`, `indexed_at=now()`
  - On ANY exception: set `status='failed'`, `error_message=str(e)`, keep partial chunks (do NOT delete them)
  - Use `from db import supabase` for all DB operations
  - Use `from services.ollama_embedder import embed_many` for embeddings
  - Add `import logging; logger = logging.getLogger(__name__)` for logging

  **2. `def _detect_sections(pages: list[tuple[int, str]]) -> list[dict]`**
  - Input: list of (page_number, page_text) tuples
  - Output: list of section dicts: `{"title": str, "content": str, "page_number": int}`
  - Scan each line for heading patterns:
    - Numbered headings: regex `r'^(\d+\.)+\d*\s+\S'` (matches `1.`, `2.3`, `3.2.1 Title`)
    - `Chapter N` or `Section N`: regex `r'^(Chapter|Section)\s+\d+'`
    - ALL CAPS lines shorter than 80 chars: `line == line.upper() and len(line.strip()) < 80 and len(line.strip()) > 3`
    - Lines ending with colon, shorter than 60 chars: `line.strip().endswith(':') and len(line.strip()) < 60`
  - When a heading is detected, start a new section. Accumulate text until the next heading.
  - Track which page each section starts on.
  - **Fallback**: If NO headings detected across the entire document, call `_fixed_size_chunking(pages)` instead.

  **3. `def _fixed_size_chunking(pages: list[tuple[int, str]]) -> list[dict]`**
  - Fallback when no headings detected.
  - Concatenate all page text. Split into chunks of ~400 tokens (~2000 chars) with 100-token overlap (~500 chars).
  - Each chunk becomes a "section" with `title=f"Section {i+1}"`, `page_number` estimated from char offset.
  - Return same shape as `_detect_sections`.

  **4. `def _split_into_children(section: dict) -> list[dict]`**
  - Split section content on `\n\n` (double newline).
  - Filter out chunks shorter than 50 chars.
  - Each child: `{"content": paragraph, "section_title": section["title"], "page_number": section["page_number"]}`

  **5. `async def reindex_document(document_id: str) -> None`**
  - Delete all chunks for this document: `supabase.table("document_chunks").delete().eq("document_id", document_id).execute()`
  - Get the document's `file_path` from `knowledge_documents`
  - Call `index_document(document_id, file_path)`

  **6. `async def delete_document(document_id: str) -> bool`**
  - Get the document row to find `file_path`
  - Delete the row from `knowledge_documents` (CASCADE handles chunks)
  - Delete the PDF file from disk: `os.remove(file_path)` — catch FileNotFoundError silently
  - Return True

  **Important implementation details**:
  - The embedding step is the slowest part. Use `embed_many()` which processes sequentially (not true batch). For a 50-page manual with ~200 child chunks, this will take 30-60 seconds.
  - When inserting chunks into Supabase, first insert all parent chunks (get their IDs back), then insert children with `parent_id` references, then update children with embeddings.
  - The vector must be stored as a string: `"[0.1, 0.2, ...]"` for Supabase PostgREST to cast to pgvector.
  - Use `supabase.table("document_chunks").insert({...}).execute()` for each chunk, or batch with `.insert([...])`.

**Checkpoint**: `document_service.py` exists with all 6 functions. Not yet callable from any endpoint.

---

## Phase 3: User Story 1 — Upload and Index a Manual (Priority: P1) MVP

**Goal**: Admin uploads a PDF via API. Backend saves file, creates metadata row, triggers background indexing pipeline (from Phase 2), returns immediately with `status: "indexing"`.

**Independent Test**:
```bash
curl -X POST http://localhost:8000/api/documents/upload \
  -F "file=@/path/to/any-manual.pdf" \
  -F "display_name=Test Manual" \
  -F "uploaded_by=admin@example.com"
# Expected: {"document_id": "uuid", "status": "indexing", "message": "..."}
# Then poll: curl http://localhost:8000/api/documents/{id}/status
# Wait for: {"status": "ready", "total_chunks": N}
```

- [ ] T005 [US1] Create `backend/routers/documents.py` with upload and status endpoints

  **What to do**: Create a new FastAPI router file with prefix `/documents`:

  ```python
  from fastapi import APIRouter, UploadFile, File, Form, HTTPException, BackgroundTasks
  import os, uuid
  from db import supabase
  from utils.activity import log_activity
  from services.document_service import index_document

  router = APIRouter(prefix="/documents", tags=["documents"])

  UPLOAD_DIR = "uploaded_files"
  MAX_FILE_SIZE = 50 * 1024 * 1024  # 50 MB
  ```

  **Endpoint 1: `POST /upload`**
  - Parameters: `file: UploadFile`, `display_name: str = Form(...)`, `uploaded_by: str = Form(...)`, `background_tasks: BackgroundTasks`
  - Admin check: call `_admin_check(uploaded_by)` (copy the function from manuals.py)
  - Validate file extension is `.pdf` — else HTTP 400 `"Only PDF files are accepted"`
  - Read file content, check size <= 50MB — else HTTP 413 `"File too large. Maximum size is 50 MB"`
  - Follow the file upload pattern:
    ```python
    file_id = str(uuid.uuid4())
    filename = f"{file_id}.pdf"
    manuals_dir = os.path.join(UPLOAD_DIR, "manuals")
    os.makedirs(manuals_dir, exist_ok=True)
    file_path = os.path.join(manuals_dir, filename)
    with open(file_path, "wb") as f:
        f.write(content)
    ```
  - Insert metadata row into `knowledge_documents`:
    ```python
    doc_row = {
        "filename": file.filename,
        "display_name": display_name,
        "file_path": file_path,
        "status": "pending",
        "uploaded_by": uploaded_by,
    }
    resp = supabase.table("knowledge_documents").insert(doc_row).execute()
    document_id = resp.data[0]["id"]
    ```
  - Add background task: `background_tasks.add_task(index_document, document_id, file_path)`
  - Log activity: `log_activity(uploaded_by, "document", "uploaded", display_name, str(document_id))`
  - Return: `{"document_id": document_id, "status": "indexing", "message": f"Indexing started for '{display_name}'"}`

  **Endpoint 2: `GET /{document_id}/status`**
  - Admin check on a query param `user_email: str`
  - Query `knowledge_documents` by id
  - If not found: HTTP 404 `"Document not found"`
  - Return: `{"document_id": id, "status": row["status"], "total_chunks": row["total_chunks"], "error_message": row["error_message"]}`

  **`_admin_check()` function**: Copy exactly from `backend/routers/manuals.py` lines 856-869:
  ```python
  def _admin_check(user_email: str):
      user_resp = supabase.table("users").select("user_type").eq("email", user_email).maybe_single().execute()
      if not user_resp.data or user_resp.data.get("user_type") != "admin":
          raise HTTPException(status_code=403, detail={"error": "admin_required"})
  ```

- [ ] T006 [US1] Register the documents router in `backend/main.py`

  **What to do**:
  1. Add import at the top (near line 30, with other router imports): `from routers import documents`
  2. Add router registration (after line 125, near the other `app.include_router` calls):
     ```python
     app.include_router(documents.router, prefix="/api", tags=["documents"])
     ```

  **IMPORTANT**: The static files mount at line 79 (`app.mount("/files", StaticFiles(directory=UPLOAD_DIR), name="files")`) already serves everything under `uploaded_files/` including the `manuals/` subdirectory. No additional mount needed.

**Checkpoint**: Upload a PDF via curl, get `document_id` back, poll status endpoint until `ready`. Verify chunks exist in `document_chunks` table.

---

## Phase 4: User Story 4 — Admin Manages Documents (Priority: P2)

**Goal**: Admin can list all documents, delete one (removes chunks + PDF file), and re-index one (re-chunks + re-embeds).

**Independent Test**:
```bash
# List all
curl http://localhost:8000/api/documents/?user_email=admin@example.com
# Delete
curl -X DELETE http://localhost:8000/api/documents/{id}?user_email=admin@example.com
# Re-index
curl -X POST http://localhost:8000/api/documents/{id}/reindex?user_email=admin@example.com
```

- [ ] T007 [US4] Add list, delete, and reindex endpoints to `backend/routers/documents.py`

  **What to do**: Add 3 more endpoints to the existing `documents.py` router:

  **Endpoint 3: `GET /`**
  - Admin check on query param `user_email: str`
  - Query all rows from `knowledge_documents`, order by `created_at` descending
  - Return list of dicts with: id, display_name, filename, status, error_message, total_pages, total_chunks, indexed_at, uploaded_by, created_at

  **Endpoint 4: `DELETE /{document_id}`**
  - Admin check on query param `user_email: str`
  - Get document row — if not found, HTTP 404
  - Call `delete_document(document_id)` from document_service
  - Log activity: `log_activity(user_email, "document", "deleted", display_name, str(document_id))`
  - Return: `{"deleted": true}`

  **Endpoint 5: `POST /{document_id}/reindex`**
  - Admin check on query param `user_email: str`
  - Parameters: `background_tasks: BackgroundTasks`
  - Get document row — if not found, HTTP 404
  - Update status to `'indexing'`, clear `error_message`
  - Add background task: `background_tasks.add_task(reindex_document, document_id)`
  - Log activity: `log_activity(user_email, "document", "reindexed", display_name, str(document_id))`
  - Return: `{"document_id": document_id, "status": "indexing", "message": "Re-indexing started"}`

  Import `delete_document, reindex_document` from `services.document_service`.

**Checkpoint**: Full CRUD working. Upload → list → reindex → delete all functional via curl.

---

## Phase 5: User Story 2+3+5 — AI Answers from Documents with Parent Context (Priority: P1)

**Goal**: The RAG pipeline searches document chunks after validated_qa misses. When a document chunk matches (similarity >= 0.70), the LLM receives the full parent section as context and the response includes document name, section title, and page number. Validated_qa always takes priority (US-5).

**Independent Test**:
```bash
# Upload a manual first, wait for "ready" status, then:
curl -X POST http://localhost:8000/api/manuals/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "how do I retrieve incoming messages"}'
# Expected: answer with source_type="document", sources[0] has display_name, section_title, page_number
```

- [ ] T008 [US2] Create `backend/services/document_search_service.py` — search + parent fetch

  **What to do**: Create a new service file with two async functions:

  **1. `async def search_document_chunks(query_embedding: list[float], limit: int = 3) -> list[dict]`**
  - Call the `search_document_chunks` RPC via Supabase:
    ```python
    from db import supabase
    embedding_str = "[" + ",".join(str(x) for x in query_embedding) + "]"
    resp = supabase.rpc("search_document_chunks", {
        "query_embedding": embedding_str,
        "match_count": limit,
        "match_threshold": 0.30,  # 0.30 distance = 0.70 similarity
    }).execute()
    ```
  - Convert results to list of dicts, adding similarity: `similarity = round(1.0 - row["distance"], 2)`
  - Also fetch the document metadata for each result:
    ```python
    doc_ids = list(set(r["document_id"] for r in resp.data))
    docs_resp = supabase.table("knowledge_documents").select("id, display_name").in_("id", doc_ids).execute()
    doc_map = {d["id"]: d["display_name"] for d in docs_resp.data}
    ```
  - Return list of:
    ```python
    {
        "id": str(row["id"]),
        "document_id": str(row["document_id"]),
        "display_name": doc_map.get(row["document_id"], "Unknown"),
        "parent_id": str(row["parent_id"]),
        "section_title": row["section_title"],
        "content": row["content"],
        "page_number": row["page_number"],
        "similarity": round(1.0 - row["distance"], 2),
    }
    ```
  - If `resp.data` is empty, return `[]`.

  **2. `async def fetch_parent_context(child_matches: list[dict]) -> list[dict]`**
  - For each child match, fetch the parent chunk's full content:
    ```python
    parent_ids = list(set(m["parent_id"] for m in child_matches if m.get("parent_id")))
    if not parent_ids:
        return child_matches  # no parents — return as-is

    parents_resp = supabase.table("document_chunks").select("id, content, section_title").in_("id", parent_ids).execute()
    parent_map = {str(p["id"]): p for p in parents_resp.data}
    ```
  - Enrich each child match with parent content:
    ```python
    for m in child_matches:
        parent = parent_map.get(m["parent_id"])
        if parent:
            m["parent_content"] = parent["content"]
            # Use parent's section_title if child doesn't have one
            m["section_title"] = m["section_title"] or parent.get("section_title", "")
    ```
  - Return enriched list.

  Add `import logging; logger = logging.getLogger(__name__)` and log search results.

- [ ] T009 [US2] [US3] [US5] Integrate document search into `backend/services/manual_rag_service.py`

  **What to do**: Add Layer 2 (document chunk search) between the post-rewrite validated_qa check and the HyDE step.

  **Step 1 — Add imports** (near top of file, after existing imports ~line 14):
  ```python
  from services.document_search_service import search_document_chunks, fetch_parent_context
  from services.ollama_embedder import embed_single  # add embed_single to existing import
  ```
  Note: `embed_single` is already imported at line 1060 inside the function. Move it to the top-level import instead, alongside the existing `embed_many` import on line 11.

  **Step 2 — Add document system prompt constant** (near the existing `VALIDATED_QA_SYSTEM_PROMPT` at line ~82):
  ```python
  # --- System prompt for document-sourced RAG (spec 070) ---
  DOCUMENT_QA_SYSTEM_PROMPT = (
      "You are a technical assistant for a civil aviation maintenance management system (CMMS).\n\n"
      "Your job is to answer maintenance and operations questions using ONLY the context provided below.\n"
      "The context comes from uploaded technical manuals.\n\n"
      "Rules:\n"
      "- Answer ONLY from the provided context. Do not use outside knowledge.\n"
      "- If the answer is not clearly stated in the context, respond with exactly: "
      '"I don\'t have that information in the knowledge base."\n'
      "- Never guess, infer, or make up technical specifications, procedures, or values.\n"
      "- Be concise and direct. Use bullet points for procedures.\n"
      "- Always cite the document source (e.g. \"According to CADAS ATS Manual, Section 4.2...\").\n"
      "- If multiple sources are relevant, synthesize them into one clear answer."
  )
  ```

  **Step 3 — Insert document search block** in the `ask()` function.

  Find the exact location: after the post-rewrite validated_qa `except` block (line ~1051: `logger.warning("Validated QA check failed...")`), and BEFORE the HyDE step (line ~1053: `# HyDE: generate hypothetical answer`).

  Insert this block between them:

  ```python
    # --- Layer 2: Document chunk search (spec 070) ---
    # Search uploaded document chunks BEFORE falling through to the manual-chunks pipeline.
    # Embed the search_query directly (no HyDE — that's for manual-chunks).
    try:
        _doc_embed_start = _time.monotonic()
        doc_query_embedding = await embed_single(search_query)
        _doc_embed_elapsed = _time.monotonic() - _doc_embed_start

        doc_matches = await search_document_chunks(doc_query_embedding, limit=3)

        if doc_matches:
            doc_max_score = max(m["similarity"] for m in doc_matches)
            logger.info(
                "[document-search] max_similarity=%.2f threshold=%.2f",
                doc_max_score,
                RAG_CONFIDENCE_THRESHOLD,
            )

            if doc_max_score >= RAG_CONFIDENCE_THRESHOLD:
                # Fetch full parent section content for each matched child
                enriched_matches = await fetch_parent_context(doc_matches)

                # Build document context for LLM
                context_parts = []
                for i, m in enumerate(enriched_matches):
                    part = f"[Document Source {i + 1}]\n"
                    part += f"Document: {m['display_name']}\n"
                    if m.get("section_title"):
                        part += f"Section: {m['section_title']}\n"
                    if m.get("page_number"):
                        part += f"Page: {m['page_number']}\n"
                    part += f"\n{m.get('parent_content', m['content'])}"
                    context_parts.append(part)
                combined_context = "\n\n".join(context_parts)

                # Build prompt with document system prompt
                prompt = (
                    f"{DOCUMENT_QA_SYSTEM_PROMPT}\n\n"
                    f"CONTEXT:\n{combined_context}\n\n"
                    f"QUESTION: {search_query}\n\nANSWER:"
                )

                # Call LLM
                from services.ai_providers.resolver import generate as provider_generate

                gen_start = _time.monotonic()
                (
                    answer,
                    doc_provider_used,
                    doc_provider_display_name,
                    doc_fallback_used,
                    doc_fallback_info,
                ) = await provider_generate(
                    prompt, [], user_email, latency_breakdown=breakdown
                )
                gen_elapsed = _time.monotonic() - gen_start

                doc_provider_display_name = doc_provider_display_name or "Local (Ollama)"

                # Build confidence band
                if doc_max_score >= RAG_HIGH_CONFIDENCE:
                    confidence = "high"
                elif doc_max_score >= RAG_CONFIDENCE_THRESHOLD:
                    confidence = "medium"
                else:
                    confidence = "low"

                # Build document sources array
                sources = [
                    {
                        "type": "document",
                        "document_id": m["document_id"],
                        "display_name": m["display_name"],
                        "section_title": m.get("section_title", ""),
                        "page_number": m.get("page_number"),
                        "score": m["similarity"],
                    }
                    for m in enriched_matches
                ]

                logger.info(
                    "document_chunk hit",
                    extra={
                        "document_id": enriched_matches[0]["document_id"],
                        "section": enriched_matches[0].get("section_title"),
                        "max_similarity": doc_max_score,
                    },
                )

                return {
                    "answer": answer,
                    "grounded": True,
                    "sources": sources,
                    "confidence": confidence,
                    "score": doc_max_score,
                    "source_type": "document",
                    "model": doc_provider_display_name,
                    "provider_display_name": doc_provider_display_name,
                    "duration_seconds": round(gen_elapsed, 1),
                    "is_verified": False,
                    "verified_source": None,
                    "retrieval_info": retrieval_info,
                    "provider_used": doc_provider_used,
                    "fallback_used": doc_fallback_used,
                    "session_summary": None,
                    "latency_breakdown": breakdown,
                }
            else:
                logger.info(
                    "[document-search] below threshold (%.2f < %.2f), falling through to manual-chunks",
                    doc_max_score,
                    RAG_CONFIDENCE_THRESHOLD,
                )
        else:
            logger.info("[document-search] no matches found")
    except Exception as e:
        logger.warning(
            "Document chunk search failed, falling through to manual-chunks: %s", e
        )

    # --- End Layer 2 ---
  ```

  **Step 4 — Add `source_type` to existing validated_qa returns**.

  In the pre-rewrite validated_qa return block (~line 879), add `"source_type": "validated_qa",` to the return dict.

  In the post-rewrite validated_qa return block (~line 1015), add `"source_type": "validated_qa",` to the return dict.

  This is additive — no existing fields are modified.

**Checkpoint**: Upload a PDF manual, wait for indexing, then ask a question that matches document content. Verify the response has `source_type: "document"` and `sources` with document name/section/page.

---

## Phase 6: User Story 4 (Frontend) — Documents Tab UI

**Goal**: Admin sees a "Documents" tab in the Ask the AI screen with upload, list, status, delete, and re-index functionality.

**Independent Test**: Navigate to "Ask the AI" as admin. The 7th tab "Documents" shows the management UI. Upload a PDF, watch status change, delete/re-index.

- [ ] T010 [P] [US4] Create `frontend/lib/services/document_service.dart` — HTTP client for document endpoints

  **What to do**: Create a new Dart service file for all document API calls. Follow the same patterns used in `frontend/lib/services/manual_assistant_service.dart`.

  ```dart
  import 'dart:convert';
  import 'package:http/http.dart' as http;
  import 'package:http_parser/http_parser.dart';
  import '../config.dart';

  class DocumentService {
    final String _baseUrl = AppConfig.baseUrl;

    /// Upload a PDF document
    Future<Map<String, dynamic>> uploadDocument({
      required String filePath,
      required String fileName,
      required List<int> fileBytes,
      required String displayName,
      required String uploadedBy,
    }) async {
      final uri = Uri.parse('$_baseUrl/api/documents/upload');
      final request = http.MultipartRequest('POST', uri)
        ..fields['display_name'] = displayName
        ..fields['uploaded_by'] = uploadedBy
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
          contentType: MediaType('application', 'pdf'),
        ));
      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw Exception('Upload failed: ${streamed.statusCode} $body');
      }
      return jsonDecode(body);
    }

    /// List all documents
    Future<List<Map<String, dynamic>>> listDocuments(String userEmail) async {
      final resp = await http.get(
        Uri.parse('$_baseUrl/api/documents/?user_email=$userEmail'),
      );
      if (resp.statusCode != 200) throw Exception('List failed: ${resp.statusCode}');
      return List<Map<String, dynamic>>.from(jsonDecode(resp.body));
    }

    /// Get document indexing status
    Future<Map<String, dynamic>> getStatus(String documentId, String userEmail) async {
      final resp = await http.get(
        Uri.parse('$_baseUrl/api/documents/$documentId/status?user_email=$userEmail'),
      );
      if (resp.statusCode != 200) throw Exception('Status failed: ${resp.statusCode}');
      return jsonDecode(resp.body);
    }

    /// Delete a document
    Future<void> deleteDocument(String documentId, String userEmail) async {
      final resp = await http.delete(
        Uri.parse('$_baseUrl/api/documents/$documentId?user_email=$userEmail'),
      );
      if (resp.statusCode != 200) throw Exception('Delete failed: ${resp.statusCode}');
    }

    /// Re-index a document
    Future<Map<String, dynamic>> reindexDocument(String documentId, String userEmail) async {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/documents/$documentId/reindex?user_email=$userEmail'),
      );
      if (resp.statusCode != 200) throw Exception('Reindex failed: ${resp.statusCode}');
      return jsonDecode(resp.body);
    }
  }
  ```

  **IMPORTANT**: For the upload function, use `http.MultipartRequest` — this is the standard Flutter HTTP pattern. The file bytes come from `file_picker` in the UI.

- [ ] T011 [P] [US4] Create `frontend/lib/screens/manual_assistant/widgets/document_card.dart` — per-document card widget

  **What to do**: Create a card widget that displays a single document's info with action buttons.

  ```dart
  import 'package:flutter/material.dart';

  class DocumentCard extends StatelessWidget {
    final Map<String, dynamic> document;
    final VoidCallback onReindex;
    final VoidCallback onDelete;

    const DocumentCard({
      super.key,
      required this.document,
      required this.onReindex,
      required this.onDelete,
    });

    @override
    Widget build(BuildContext context) {
      final status = document['status'] ?? 'pending';
      final displayName = document['display_name'] ?? 'Untitled';
      final filename = document['filename'] ?? '';
      final totalChunks = document['total_chunks'];
      final uploadedBy = document['uploaded_by'] ?? '';
      final createdAt = document['created_at'] ?? '';
      final errorMessage = document['error_message'];

      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row with status badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  _statusBadge(status),
                ],
              ),
              const SizedBox(height: 4),
              // Filename
              Text(filename, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              // Info row: chunks, uploader, date
              Wrap(
                spacing: 16,
                children: [
                  if (totalChunks != null)
                    Text('$totalChunks chunks',
                        style: Theme.of(context).textTheme.bodySmall),
                  Text('by $uploadedBy',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(_formatDate(createdAt),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              // Error message if failed
              if (status == 'failed' && errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorMessage,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.red.shade700,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Re-index',
                    onPressed: status == 'indexing' ? null : onReindex,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'Delete',
                    color: Colors.red.shade400,
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    Widget _statusBadge(String status) {
      Color color;
      String label;
      switch (status) {
        case 'ready':
          color = Colors.green;
          label = 'Ready';
          break;
        case 'indexing':
          color = Colors.amber;
          label = 'Indexing';
          break;
        case 'failed':
          color = Colors.red;
          label = 'Failed';
          break;
        default:
          color = Colors.grey;
          label = 'Pending';
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color.shade700,
          ),
        ),
      );
    }

    String _formatDate(String iso) {
      try {
        final dt = DateTime.parse(iso);
        return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      } catch (_) {
        return iso;
      }
    }
  }
  ```

- [ ] T012 [US4] Create `frontend/lib/screens/manual_assistant/documents_tab.dart` — full management UI

  **What to do**: Create a StatefulWidget tab that provides:
  1. **Upload section** at top: "Upload Manual" button → file picker (PDF only) + display name text field → upload → show progress
  2. **Document list** below: scrollable list of DocumentCard widgets
  3. **Status polling**: after upload, poll `/status` every 3 seconds until `ready` or `failed`
  4. **Delete confirmation**: show AlertDialog before deleting
  5. **Empty state**: "No documents uploaded yet. Upload a PDF manual to expand the knowledge base."

  Key implementation details:
  - Use `file_picker` package for file selection (already a dependency — check `pubspec.yaml`). Filter for PDF only: `FileType.custom, allowedExtensions: ['pdf']`
  - Constructor: `DocumentsTab({required this.userEmail})`
  - Load documents in `initState` via `documentService.listDocuments(userEmail)`
  - After upload, start a Timer that polls status every 3 seconds. Cancel on dispose or when status is `ready`/`failed`.
  - On delete: show `AlertDialog` with "Are you sure?" → on confirm, call `deleteDocument()` → reload list
  - On re-index: call `reindexDocument()` → start polling → update card status
  - Use `ScaffoldMessenger` for success/error toasts

  Follow the same widget patterns used in `verified_answers_tab.dart` and `rules_tab.dart` (same directory) for consistent styling.

- [ ] T013 [US4] Add "Documents" tab to `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart`

  **What to do**: Modify the existing screen to add a 7th admin-only tab.

  **Step 1** — Add import at top:
  ```dart
  import 'documents_tab.dart';
  ```

  **Step 2** — Change TabController length from 6 to 7 for admin (line 33):
  ```dart
  _tabController = TabController(length: _isAdmin ? 7 : 2, vsync: this);
  ```

  **Step 3** — Add the tab label in the `tabs` list (after the Verified tab, before the closing `]` at line 138):
  ```dart
  if (_isAdmin)
    Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.description_outlined, size: 18),
          SizedBox(width: 4),
          Text('Documents'),
        ],
      ),
    ),
  ```

  **Step 4** — Add the tab body in the `children` list (after `VerifiedAnswersTab`, before closing `]` at line 156):
  ```dart
  if (_isAdmin) DocumentsTab(userEmail: _userEmail),
  ```

**Checkpoint**: Navigate to "Ask the AI" as admin. 7th tab "Documents" visible. Upload a PDF, see it appear in the list with status badge, delete and re-index work.

---

## Phase 7: Polish — Frontend Source Display + Backward Compatibility

**Purpose**: Ensure the frontend correctly displays document sources in the answer card, and existing validated_qa answers still render correctly.

- [ ] T014 [US2] Update `frontend/lib/models/manual_qa_answer.dart` to handle the new `source_type` field

  **What to do**: Add `sourceType` field to the `ManualQaAnswer` model.

  1. Add field to the class:
     ```dart
     final String? sourceType;  // "validated_qa" or "document"
     ```
  2. Add to constructor:
     ```dart
     this.sourceType,
     ```
  3. Add to `fromJson`:
     ```dart
     sourceType: json['source_type'] as String?,
     ```

  This is purely additive. Existing answers without `source_type` will get `null`, which the UI can treat as validated_qa (backward compatible).

- [ ] T015 [US2] Update `frontend/lib/models/manual_source.dart` to support document sources

  **What to do**: The sources array now has two shapes. For document sources, fields are `type`, `document_id`, `display_name`, `section_title`, `page_number`, `score`. For validated_qa sources, fields are `id`, `question_text`, `score`.

  Add document-related optional fields to `ManualSource`:
  ```dart
  final String? type;          // "document" or null (validated_qa)
  final String? documentId;
  final String? displayName;
  final String? sectionTitle;
  final int? pageNumber;
  final double? score;
  ```

  Update the constructor and `fromJson`:
  ```dart
  factory ManualSource.fromJson(Map<String, dynamic> json) {
    return ManualSource(
      manualId: json['manual_id'] ?? json['id'] ?? '',
      manualTitle: json['manual_title'] ?? json['display_name'] ?? '',
      chunkIndex: json['chunk_index'] ?? 0,
      sourcePage: json['source_page'] ?? json['page_number'],
      contentPreview: json['content_preview'] ?? '',
      highlightStart: json['highlight_start'],
      highlightEnd: json['highlight_end'],
      type: json['type'] as String?,
      documentId: json['document_id'] as String?,
      displayName: json['display_name'] as String?,
      sectionTitle: json['section_title'] as String?,
      pageNumber: json['page_number'] as int?,
      score: (json['score'] as num?)?.toDouble(),
    );
  }
  ```

  This handles both source shapes in a single model. The `fromJson` uses fallbacks (`json['manual_id'] ?? json['id']`) so both validated_qa and document sources parse correctly.

- [ ] T016 [US2] Update `frontend/lib/screens/manual_assistant/widgets/source_card.dart` to render document sources

  **What to do**: Read the existing `source_card.dart` to understand how it renders sources. Then add conditional rendering for document sources:

  - If `source.type == 'document'`: show document name, section title, page number
  - Otherwise: show existing validated_qa / manual-chunks rendering

  The exact changes depend on the current `source_card.dart` implementation — read it first, then add a conditional branch for document sources. The display should show:
  - Document icon + display_name
  - Section title (if present)
  - Page number (if present)
  - Similarity score

**Checkpoint**: Ask a question that matches a document → verify the answer card shows document source info (document name, section, page). Ask a question that matches validated_qa → verify existing rendering unchanged.

---

## Phase 8: Verification

**Purpose**: End-to-end validation of all acceptance criteria.

- [ ] T017 Verify AC-1: Upload a ~50 page PDF, confirm chunks created and status becomes `ready` within 60 seconds

  ```bash
  curl -X POST http://localhost:8000/api/documents/upload \
    -F "file=@/path/to/50page-manual.pdf" \
    -F "display_name=Test Manual" \
    -F "uploaded_by=admin@example.com"
  # Poll status until ready:
  curl http://localhost:8000/api/documents/{id}/status?user_email=admin@example.com
  ```

- [ ] T018 Verify AC-3+AC-4: Ask a question matching a document chunk, confirm answer uses parent context and response includes document name, section, page

  ```bash
  curl -X POST http://localhost:8000/api/manuals/ask \
    -H "Content-Type: application/json" \
    -d '{"question": "how do I retrieve incoming messages in CADAS"}'
  # Check: source_type="document", sources[0] has display_name, section_title, page_number
  ```

- [ ] T019 Verify AC-5: validated_qa match takes priority over document match

  If there's an existing validated_qa entry that matches the same topic as a document chunk, the response should have `source_type: "validated_qa"` and `is_verified: true`.

- [ ] T020 Verify AC-7+AC-8: Delete a document → confirm chunks gone. Re-index → confirm new chunks created.

  ```bash
  # Delete
  curl -X DELETE http://localhost:8000/api/documents/{id}?user_email=admin@example.com
  # Re-upload, then reindex
  curl -X POST http://localhost:8000/api/documents/{id}/reindex?user_email=admin@example.com
  ```

- [ ] T021 Verify AC-10: Existing response shape unchanged for validated_qa answers

  ```bash
  curl -X POST http://localhost:8000/api/manuals/ask \
    -H "Content-Type: application/json" \
    -d '{"question": "a question that has a validated_qa match"}'
  # Check: is_verified=true, verified_source present, all existing fields in same positions
  ```

- [ ] T022 Show diff of all changed files

  ```bash
  git diff
  ```

  **Must appear in diff**:
  - `backend/services/document_service.py` (NEW)
  - `backend/services/document_search_service.py` (NEW)
  - `backend/routers/documents.py` (NEW)
  - `backend/services/manual_rag_service.py` (MODIFIED — Layer 2 insertion + source_type additions)
  - `backend/main.py` (MODIFIED — router registration)
  - `backend/requirements.txt` (MODIFIED — pdfplumber added)
  - `supabase/migrations/20260416000000_knowledge_documents.sql` (NEW)
  - `frontend/lib/services/document_service.dart` (NEW)
  - `frontend/lib/screens/manual_assistant/documents_tab.dart` (NEW)
  - `frontend/lib/screens/manual_assistant/widgets/document_card.dart` (NEW)
  - `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart` (MODIFIED — 7th tab)
  - `frontend/lib/models/manual_qa_answer.dart` (MODIFIED — sourceType field)
  - `frontend/lib/models/manual_source.dart` (MODIFIED — document fields)
  - `frontend/lib/screens/manual_assistant/widgets/source_card.dart` (MODIFIED — document rendering)

  **Must NOT appear in diff**:
  - `backend/services/ai_providers/resolver.py`
  - `backend/services/validated_qa_service.py`
  - Any existing migration files
  - `.env` files

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 (migration must exist). BLOCKS all user stories.
- **Phase 3 (US1 — Upload)**: Depends on Phase 2 (needs document_service.py)
- **Phase 4 (US4 — Management)**: Depends on Phase 3 (needs router + document_service)
- **Phase 5 (US2+3+5 — Search)**: Depends on Phase 2 (needs document_service for test data) + Phase 3 (needs uploaded documents to search)
- **Phase 6 (Frontend)**: Depends on Phase 4 (needs all backend endpoints working)
- **Phase 7 (Polish)**: Depends on Phase 5 (needs source_type field in responses)
- **Phase 8 (Verification)**: Depends on all previous phases

### Task Execution Order

```
T001 + T002 + T003 (parallel) → T004 → T005 → T006 → T007 → T008 → T009 → T010 + T011 (parallel) → T012 → T013 → T014 → T015 → T016 → T017-T022
```

### Parallel Opportunities

- **T001, T002, T003** can run in parallel (migration, requirements.txt, directory — different files)
- **T010, T011** can run in parallel (Dart service file vs widget file — different files, no dependencies)
- **T017-T022** can run in parallel (independent verification tests)

---

## Implementation Strategy

### MVP First (Phases 1-3)

1. T001-T003: Setup (migration, pdfplumber, directory)
2. T004: Chunking pipeline
3. T005-T006: Upload + status endpoints
4. **STOP and VALIDATE**: Upload a real PDF, verify chunks in DB

### Core Search (Phases 4-5)

5. T007: Management endpoints (list/delete/reindex)
6. T008-T009: Document search service + RAG integration
7. **STOP and VALIDATE**: Ask a question, get document-sourced answer

### Frontend (Phases 6-7)

8. T010-T013: Documents tab UI
9. T014-T016: Source display in answer cards
10. **STOP and VALIDATE**: End-to-end flow in browser

### Final (Phase 8)

11. T017-T022: Full verification against all acceptance criteria

---

## Notes

- All backend services use `from db import supabase` for database access
- Embeddings are 768-dim vectors from `nomic-embed-text-v2-moe` via Ollama
- Distance → similarity conversion: `similarity = 1.0 - distance` (applied in service layer, not SQL)
- The `search_document_chunks` RPC threshold is in distance space: 0.30 = 0.70 similarity
- The IVFFlat index needs ~100+ rows to function properly; before that, sequential scan is used (slower but correct)
- Background tasks run in the FastAPI worker process — no external task queue needed
- The `uploaded_files/manuals/` directory must exist before upload — `os.makedirs(manuals_dir, exist_ok=True)` in the upload endpoint handles this
- Commit after each phase for clean history
