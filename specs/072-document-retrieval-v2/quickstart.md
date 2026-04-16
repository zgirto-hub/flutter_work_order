# Quickstart: Spec 072 — Document Retrieval v2

## Prerequisites

- Spec 070 fully deployed (knowledge_documents + document_chunks tables, document endpoints working)
- Backend running with pdfplumber installed
- Ollama running at localhost:11434

## Setup

### 1. Apply migration
```sql
-- Run in Supabase SQL Editor
ALTER TABLE document_chunks ADD COLUMN chunk_index int;
ALTER TABLE document_chunks ADD COLUMN embedding_stale boolean NOT NULL DEFAULT false;
ALTER TABLE knowledge_documents ADD COLUMN file_extension text;

-- Update search RPC to exclude stale chunks
CREATE OR REPLACE FUNCTION search_document_chunks(...)
-- (full function in migration file)
```

### 2. Restart backend
```bash
sudo systemctl restart document_server.service
```

### 3. Redeploy frontend
```bash
cd scripts && ./deploy_frontend.sh
```

## Test the features

### US1 — Enhanced search (HyDE + rerank)
```bash
# Upload a document first, then:
curl -X POST http://localhost:8000/api/manuals/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "what should I check during routine maintenance"}'
# Verify: answer uses HyDE, has confidence/score, sources with document info
```

### US2 — Chunk editing
```bash
# List chunks
curl "http://localhost:8000/api/documents/{doc_id}/chunks?user_email=admin@example.com"

# Edit a chunk
curl -X PUT http://localhost:8000/api/documents/{doc_id}/chunks/{chunk_id} \
  -H "Content-Type: application/json" \
  -d '{"content": "Updated text", "user_email": "admin@example.com"}'

# Split a chunk
curl -X POST http://localhost:8000/api/documents/{doc_id}/chunks/{chunk_id}/split \
  -H "Content-Type: application/json" \
  -d '{"split_position": 150, "user_email": "admin@example.com"}'
```

### US3 — Multi-format upload
```bash
curl -X POST http://localhost:8000/api/documents/upload \
  -F "file=@manual.docx" \
  -F "display_name=DOCX Manual" \
  -F "uploaded_by=admin@example.com"
```

### US4 — Migration
```bash
curl -X POST http://localhost:8000/api/documents/migrate-all \
  -H "Content-Type: application/json" \
  -d '{"user_email": "admin@example.com"}'

# Poll progress
curl "http://localhost:8000/api/documents/migration-status?user_email=admin@example.com"
```

### US5 — Retirement
After migration verified, remove Knowledge tab code and redeploy.
