# API Contracts: Spec 070 — Document Retrieval

## New Router: `/api/documents`

All endpoints require admin role (enforced via `_admin_check(user_email)` pattern).

---

### POST /api/documents/upload

Upload a PDF manual and trigger async indexing.

**Request**: `multipart/form-data`
| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| file | File | Yes | PDF only (`.pdf` extension); max 50 MB |
| display_name | string | Yes | Human-readable name for the document |
| uploaded_by | string | Yes | Admin email address |

**Response 200**:
```json
{
  "document_id": "uuid",
  "status": "indexing",
  "message": "Indexing started for '{display_name}'"
}
```

**Error 400**: Non-PDF file extension
```json
{ "detail": "Only PDF files are accepted" }
```

**Error 413**: File exceeds 50 MB
```json
{ "detail": "File too large. Maximum size is 50 MB" }
```

**Error 403**: Non-admin user
```json
{ "detail": { "error": "admin_required" } }
```

---

### GET /api/documents/

List all uploaded documents.

**Response 200**:
```json
[
  {
    "id": "uuid",
    "display_name": "CADAS ATS User Manual",
    "filename": "cadas_ats_manual.pdf",
    "status": "ready",
    "error_message": null,
    "total_pages": 156,
    "total_chunks": 423,
    "indexed_at": "2026-04-16T10:30:00Z",
    "uploaded_by": "admin@example.com",
    "created_at": "2026-04-16T10:28:00Z"
  }
]
```

Sorted by `created_at` descending.

---

### GET /api/documents/{document_id}/status

Poll indexing status after upload.

**Response 200**:
```json
{
  "document_id": "uuid",
  "status": "ready",
  "total_chunks": 423,
  "error_message": null
}
```

**Error 404**: Document not found
```json
{ "detail": "Document not found" }
```

---

### DELETE /api/documents/{document_id}

Delete document, all chunks, and the PDF file from disk.

**Response 200**:
```json
{ "deleted": true }
```

**Error 404**: Document not found
```json
{ "detail": "Document not found" }
```

---

### POST /api/documents/{document_id}/reindex

Delete all chunks and re-run the indexing pipeline.

**Response 200**:
```json
{
  "document_id": "uuid",
  "status": "indexing",
  "message": "Re-indexing started"
}
```

**Error 404**: Document not found
```json
{ "detail": "Document not found" }
```

---

## Modified Endpoint: POST /api/manuals/ask

**Existing endpoint** — response shape extended with new `source_type` field.

### Response when source is validated_qa (unchanged + additive)

```json
{
  "answer": "...",
  "grounded": true,
  "sources": [
    { "id": "uuid", "question_text": "...", "score": 0.92 }
  ],
  "confidence": "high",
  "score": 0.92,
  "source_type": "validated_qa",
  "model": "...",
  "provider_display_name": "...",
  "duration_seconds": 1.2,
  "is_verified": true,
  "verified_source": { "validated_qa_id": "...", "validated_by": "...", "validated_at": "...", "similarity": 0.92 },
  "retrieval_info": { ... },
  "provider_used": "...",
  "fallback_used": false,
  "session_summary": null,
  "latency_breakdown": { ... }
}
```

### Response when source is document (new)

```json
{
  "answer": "To perform a backup in CADAS ATS, navigate to...",
  "grounded": true,
  "sources": [
    {
      "type": "document",
      "document_id": "uuid",
      "display_name": "CADAS ATS User Manual",
      "section_title": "4.2 Backup Procedures",
      "page_number": 23,
      "score": 0.88
    }
  ],
  "confidence": "high",
  "score": 0.88,
  "source_type": "document",
  "model": "...",
  "provider_display_name": "...",
  "duration_seconds": 2.1,
  "is_verified": false,
  "verified_source": null,
  "retrieval_info": { ... },
  "provider_used": "...",
  "fallback_used": false,
  "session_summary": null,
  "latency_breakdown": { ... }
}
```

**Key differences**:
- `source_type`: `"document"` instead of `"validated_qa"`
- `is_verified`: `false` (document answers are not human-curated)
- `verified_source`: `null`
- `sources[].type`: `"document"` with document-specific fields
