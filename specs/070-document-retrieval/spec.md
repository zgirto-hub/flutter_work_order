# Spec 070: Document Retrieval — Upload, Chunk, and Search Technical Manuals

## Feature Name
Document Retrieval — Technical Manual Knowledge Base (Knowledge Base → Documents tab)

## Context
This is a CMMS (flutter_work_order) for civil aviation maintenance with a FastAPI backend,
Supabase (PostgreSQL + pgvector), and a Flutter frontend. The AI Assistant already has:
- `validated_qa` table: approved Q&A pairs with embeddings (spec 067/068)
- RAG pipeline: embed query → search validated_qa → LLM answer (spec 069)
- Embedding model: `nomic-embed-text-v2-moe` via Ollama at `localhost:11434`
- AI provider resolver: Mistral → Gemini → Ollama (spec 063)

Spec 070 adds a second retrieval layer: uploaded PDF manuals, chunked and embedded,
searchable alongside validated_qa. The search priority is:
  1. validated_qa (human-curated, highest trust)
  2. knowledge_documents (uploaded manuals, high trust)
  3. Neither matches → fallback message

All PDFs are native (text-selectable) English-only documents. No OCR needed.

## Existing File Upload Pattern (MUST follow exactly)
The project already has a file upload system in `backend/routers/files.py`.
Spec 070 MUST follow the identical pattern — do not invent a new one.

```python
# Existing pattern in files.py → replicate this exactly
UPLOAD_DIR = "uploaded_files"

file_id = str(uuid.uuid4())
extension = file.filename.split(".")[-1].lower()
filename = f"{file_id}.{extension}"
file_path = os.path.join(UPLOAD_DIR, filename)        # save to disk here
with open(file_path, "wb") as f:
    content = await file.read()
    f.write(content)
public_url = f"/files/{filename}"                     # served via static files
```

For spec 070, PDFs go into a `manuals/` subfolder:
```python
file_path = os.path.join(UPLOAD_DIR, "manuals", filename)
# → backend/uploaded_files/manuals/{uuid}.pdf

public_url = f"/files/manuals/{filename}"
# → served via existing static file middleware
```

The `file_path` column in `knowledge_documents` stores this local path.
Do NOT use Supabase Storage for PDFs — files live on the Zorin server SSD.

---

## Problem Statement
The AI can only answer questions that were previously asked AND approved by an admin.
If a technician asks something new — even if the answer exists clearly in an uploaded manual
(AIDA-NG, CADAS ATS, equipment guides, DGCA procedures) — the AI says "I don't have that
information." Spec 070 fixes this by making every uploaded manual fully searchable.

---

## Goals
1. Admin can upload native PDF manuals via a full management UI (upload, list, delete, re-index).
2. Backend extracts text, splits into parent sections + child paragraphs (parent-child chunking).
3. Each child chunk is embedded and stored with a reference to its parent section.
4. RAG search queries both validated_qa AND knowledge_documents, returning the best matches.
5. When a document chunk matches, the LLM receives the full parent section (not just the child) for complete context.
6. API response includes document name, section title, and page number as source reference.
7. Admin can delete a document (removes all its chunks) and re-index it (re-chunks + re-embeds).

---

## Out of Scope
- Scanned PDF / OCR (all PDFs are native text-selectable)
- Arabic language documents (English only for this spec)
- Per-chunk thumbs up/down rating
- Automatic re-indexing on model change (manual re-index button covers this)
- Full-text search (vector search only)
- Access by technicians to the document management UI (admin only)

---

## User Stories

**US-1 — Upload and index a manual**
As an admin, I can upload a PDF manual. The system extracts text, chunks it into sections
and paragraphs, embeds each child chunk, and confirms how many chunks were indexed.

**US-2 — AI answers from uploaded manual**
As a technician, I ask "How do I do a backup in CADAS ATS?" The system finds no match in
validated_qa but finds a high-confidence match in the CADAS ATS manual. The AI answers
with the full section context and cites: "CADAS ATS Manual, Section 4.2 Backup Procedures, page 23."

**US-3 — Full parent context returned**
As a technician, I ask about a multi-step procedure. Even though only one child paragraph
matched my query, the AI receives the entire parent section — prerequisites, steps, and
troubleshooting — and gives a complete answer.

**US-4 — Admin manages documents**
As an admin, I can see all uploaded documents, delete one (removes all its chunks from the
vector store), and re-index one (re-chunks and re-embeds after a manual update).

**US-5 — validated_qa takes priority**
As a technician, I ask a question that matches both a validated_qa entry and a document chunk.
The system uses the validated_qa answer (human-curated, higher trust).

---

## Technical Shape

### Database — New table: `knowledge_documents`

```sql
CREATE TABLE knowledge_documents (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  filename      text NOT NULL,
  display_name  text NOT NULL,
  file_path     text NOT NULL,         -- local disk path
  status        text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'indexing', 'ready', 'failed')),
  error_message text,                  -- populated on status='failed'; NULL otherwise
  total_pages   int,
  total_chunks  int,
  indexed_at    timestamptz,
  uploaded_by   text NOT NULL,         -- admin email
  created_at    timestamptz DEFAULT now()
);
```

### Database — New table: `document_chunks`

```sql
CREATE TABLE document_chunks (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id     uuid REFERENCES knowledge_documents(id) ON DELETE CASCADE,

  -- parent-child fields
  chunk_type      text NOT NULL CHECK (chunk_type IN ('parent', 'child')),
  parent_id       uuid REFERENCES document_chunks(id) ON DELETE CASCADE,

  -- content
  section_title   text,                -- e.g. "3.2 Retrieving Incoming Messages"
  content         text NOT NULL,       -- full section text (parent) or paragraph (child)
  page_number     int,

  -- vector (child only — parents are not embedded)
  embedding       vector(768),

  created_at      timestamptz DEFAULT now()
);

CREATE INDEX ON document_chunks USING ivfflat (embedding vector_cosine_ops)
  WHERE chunk_type = 'child';          -- only index child chunks
```

### Chunking Strategy — Parent-Child

**Step 1 — Extract text per page** using `pdfplumber` (native PDF, no OCR needed).

**Step 2 — Detect section boundaries** by scanning for heading patterns:
- Numbered headings: `1.`, `2.3`, `3.2.1`, `Chapter 4`, `Section 5`
- ALL CAPS lines shorter than 80 chars
- Lines ending with a colon that are shorter than 60 chars

**Step 3 — Create parent chunks** — one per detected section. Store full section text.
Parent chunks are stored in `document_chunks` with `chunk_type='parent'`, NOT embedded.

**Step 4 — Create child chunks** — split each parent section into paragraphs
(split on double newline `\n\n`). Minimum child size: 50 chars (drop shorter ones).
Each child stores: `parent_id`, `section_title`, `page_number`, `content`.

**Step 5 — Embed child chunks** — call `nomic-embed-text-v2-moe` for each child.
Store 768-dim vector in `embedding` column.

**Fallback:** If no section headings detected in the entire document, fall back to
fixed-size chunking: 400 tokens per parent, 100-token overlap, paragraphs as children.

### Backend Endpoints

#### `POST /api/documents/upload`
- Admin only
- Multipart form: `file` (PDF only — reject other extensions with HTTP 400; max 50 MB — reject larger with HTTP 413), `display_name` (string), `uploaded_by` (string — admin email)
- Saves PDF to local disk at `uploaded_files/manuals/{uuid}.pdf` (follow exact pattern from `files.py`)
- Stores `file_path` as `uploaded_files/manuals/{uuid}.pdf` and `public_url` as `/files/manuals/{uuid}.pdf` in `knowledge_documents`
- Inserts row in `knowledge_documents` with `status='indexing'`
- Triggers async indexing pipeline via FastAPI `BackgroundTasks` (extract → chunk → embed → store)
- Returns: `{ "document_id": uuid, "status": "indexing", "message": "Indexing started" }`
- Do NOT use Supabase Storage — local disk only

#### `GET /api/documents/`
- Admin only
- Returns list of all documents with: id, display_name, filename, total_pages,
  total_chunks, indexed_at, uploaded_by, created_at
- Sorted by created_at descending

#### `GET /api/documents/{document_id}/status`
- Admin only
- Returns indexing status: `{ "document_id": uuid, "status": "indexing|ready|failed", "total_chunks": N }`
- Used by frontend to poll after upload

#### `DELETE /api/documents/{document_id}`
- Admin only
- Deletes document row from `knowledge_documents` (CASCADE removes all chunks via FK)
- Deletes PDF file from local disk at the stored `file_path`
- Returns: `{ "deleted": true }`

#### `POST /api/documents/{document_id}/reindex`
- Admin only
- Deletes all existing chunks for this document
- Re-runs the full chunking + embedding pipeline on the stored PDF
- Returns: `{ "document_id": uuid, "status": "indexing" }`

### RAG Search Extension

Extend the existing RAG query function (from spec 069) to search document chunks
after validated_qa:

```python
async def search_knowledge(query: str) -> SearchResult:
    query_embedding = await embed_single(query)

    # Layer 1: validated_qa (existing)
    qa_results = await search_validated_qa(query_embedding, limit=3)
    if qa_results and qa_results[0].score >= RAG_CONFIDENCE_THRESHOLD:
        return SearchResult(source="validated_qa", results=qa_results)

    # Layer 2: document_chunks (new)
    doc_results = await search_document_chunks(query_embedding, limit=3)
    if doc_results and doc_results[0].score >= RAG_CONFIDENCE_THRESHOLD:
        # fetch parent section for each matched child
        enriched = await fetch_parent_context(doc_results)
        return SearchResult(source="documents", results=enriched)

    # Layer 3: fallback
    return SearchResult(source="none", results=[])
```

`search_document_chunks` queries only `chunk_type='child'` rows using pgvector
cosine similarity. **Only chunks belonging to documents with `status='ready'` are searched**
(join on `knowledge_documents.status = 'ready'`). For each matched child,
`fetch_parent_context` loads the parent row's full `content` — this is what gets sent to the LLM.

### LLM Context Format (document source)

```
[Document Source 1]
Document: CADAS ATS User Manual
Section: 4.2 Backup Procedures
Page: 23

{full parent section text}

[Document Source 2]
...
```

### API Response Shape (document answer)

```json
{
  "answer": "To perform a backup in CADAS ATS, navigate to...",
  "confidence": "high",
  "score": 0.88,
  "source_type": "document",
  "sources": [
    {
      "type": "document",
      "document_id": "uuid",
      "display_name": "CADAS ATS User Manual",
      "section_title": "4.2 Backup Procedures",
      "page_number": 23,
      "score": 0.88
    }
  ]
}
```

For validated_qa answers, `source_type` = `"validated_qa"` and sources keep their
existing shape — additive only, no breaking changes.

### Frontend — Documents Tab (new tab in Knowledge Base screen)

Add a "Documents" tab alongside existing Review / Verified tabs.

**Tab contents:**

**Upload section (top)**
- "Upload Manual" button → file picker (PDF only) + display name text field → upload
- Progress indicator while indexing
- Success/error toast

**Document list (scrollable)**
Each document card shows:
- Display name + filename
- Status badge: `Indexing` (amber) / `Ready` (green) / `Failed` (red)
- Two icon buttons: **Re-index** (refresh icon) / **Delete** (trash icon, with confirm dialog)
- Total chunks count
- Uploaded by + date

**Empty state:**
"No documents uploaded yet. Upload a PDF manual to expand the knowledge base."

---

## Acceptance Criteria

| # | Criterion |
|---|-----------|
| AC-1 | Admin uploads a native PDF → chunks are created and indexed within 60s for a typical 50-page manual |
| AC-2 | Each section becomes one parent chunk; each paragraph within becomes one child chunk with embedding |
| AC-3 | Technician asks a question matching a document chunk → answer uses full parent section as context |
| AC-4 | Answer response includes document name, section title, page number |
| AC-5 | validated_qa match takes priority over document match for the same question |
| AC-6 | Score below 0.70 in both layers → fallback message, no LLM call |
| AC-7 | Admin deletes a document → all its chunks removed, no longer searchable |
| AC-8 | Admin re-indexes a document → old chunks deleted, new chunks created |
| AC-9 | Documents tab shows all uploaded documents with status, chunk count, uploader |
| AC-10 | Existing validated_qa answer shape unchanged — `answer` field stays in same position |
| AC-11 | Empty validated_qa + empty documents → fallback message returned |
| AC-12 | Document with no detectable headings → falls back to fixed-size chunking without error |

---

## Dependencies
- `pdfplumber` Python library (add to requirements.txt) — native PDF text extraction
- `nomic-embed-text-v2-moe` already running via Ollama ✓
- pgvector already enabled in Supabase ✓
- `backend/uploaded_files/manuals/` directory — create if not exists (same as existing `uploaded_files/`)
- Existing static file middleware already serves `/files/` — manuals subfolder works automatically ✓
- Spec 069 RAG pipeline already in place ✓

---

## Effort Estimate
| Area | Estimate |
|------|----------|
| DB migration (2 tables + index) | 0.5 day |
| PDF extraction + parent-child chunking pipeline | 1 day |
| Backend endpoints (upload, list, delete, reindex, status) | 1 day |
| RAG search extension (2-layer search + parent fetch) | 0.5 day |
| Flutter Documents tab (full management UI) | 1 day |
| Testing | 0.5 day |
| **Total** | **~4.5 days** |

---

## File Locations (expected)
```
backend/
  routers/documents.py                  — new, all document endpoints
  services/document_service.py          — new, chunking + indexing pipeline
  services/document_search_service.py   — new, search_document_chunks + fetch_parent_context
  services/manual_rag_service.py        — extend: add 2-layer search logic
  requirements.txt                      — add pdfplumber

supabase/migrations/
  YYYYMMDD_knowledge_documents.sql      — new tables + index

frontend/lib/
  features/knowledge_base/
    screens/knowledge_base_screen.dart  — add Documents tab
    screens/documents_tab.dart          — new, full management UI
    widgets/document_card.dart          — new, per-document card widget
  services/document_service.dart        — new, upload/list/delete/reindex API calls
```

---

## Clarifications

### Session 2026-04-16
- Q: The `knowledge_documents` DDL has no `status` column, but endpoints reference `status`. Where should indexing status live? → A: Add a `status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'indexing', 'ready', 'failed'))` column to `knowledge_documents`.
- Q: If embedding fails partway through a document, what should happen? → A: Keep partial chunks, set status to `failed` with error message; re-index cleans up and retries.
- Q: Should there be a maximum PDF file size limit on upload? → A: 50 MB maximum.
- Q: Should chunks from partially-indexed (failed) documents be included in RAG search? → A: No — only search chunks from documents with `status='ready'`.
- Q: How should admin access be enforced on `/api/documents/*` routes? → A: Follow existing admin auth pattern from other routers — replicate the same mechanism used by current admin-only endpoints.
