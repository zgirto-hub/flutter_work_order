# Quickstart: Spec 070 — Document Retrieval

## Prerequisites

- Backend running (`uvicorn` or `document_server.service`)
- Supabase accessible with migrations applied
- Ollama running at `localhost:11434` with `nomic-embed-text-v2-moe` loaded
- `pdfplumber` installed (`pip install pdfplumber`)
- `backend/uploaded_files/manuals/` directory exists

## Setup

### 1. Apply migration

```bash
# From project root — apply via Supabase CLI or directly in SQL editor
supabase db push
```

### 2. Install new dependency

```bash
cd backend
pip install pdfplumber
```

### 3. Create manuals upload directory

```bash
mkdir -p backend/uploaded_files/manuals
```

### 4. Restart backend

```bash
sudo systemctl restart document_server.service
```

## Test the feature

### Upload a document

```bash
curl -X POST http://localhost:8000/api/documents/upload \
  -F "file=@/path/to/manual.pdf" \
  -F "display_name=CADAS ATS User Manual" \
  -F "uploaded_by=admin@example.com"
```

Expected: `{ "document_id": "uuid", "status": "indexing", "message": "..." }`

### Poll status

```bash
curl http://localhost:8000/api/documents/{document_id}/status
```

Wait for `"status": "ready"`.

### Ask a question

```bash
curl -X POST http://localhost:8000/api/manuals/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "how do I do a backup in CADAS ATS"}'
```

Expected: answer with `source_type: "document"`, `sources` array with document name/section/page.

### List all documents

```bash
curl http://localhost:8000/api/documents/
```

### Delete a document

```bash
curl -X DELETE http://localhost:8000/api/documents/{document_id}
```

### Re-index a document

```bash
curl -X POST http://localhost:8000/api/documents/{document_id}/reindex
```

## Frontend

Navigate to "Ask the AI" screen as admin. The "Documents" tab (7th tab) shows the management UI. Upload a PDF, watch status badge change from Indexing → Ready, then test a question in the Chat tab.
