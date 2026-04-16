# API Contracts: Spec 072 — Document Retrieval v2

## New Endpoints (added to existing `/api/documents` router)

### Chunk CRUD — 9 endpoints

All require admin auth (`_admin_check(user_email)`).

---

#### GET /api/documents/{document_id}/chunks

List chunks for a document, paginated.

**Query params**: `user_email` (required), `page` (default 1), `page_size` (default 20)

**Response 200**:
```json
{
  "chunks": [
    {
      "id": "uuid",
      "chunk_type": "parent",
      "parent_id": null,
      "chunk_index": 0,
      "section_title": "1.1 Introduction",
      "content": "Full section text...",
      "page_number": 3,
      "char_count": 1250,
      "embedding_stale": false,
      "children_count": 5
    },
    {
      "id": "uuid",
      "chunk_type": "child",
      "parent_id": "uuid",
      "chunk_index": 0,
      "section_title": "1.1 Introduction",
      "content": "First paragraph...",
      "page_number": 3,
      "char_count": 280,
      "embedding_stale": false
    }
  ],
  "total": 45,
  "page": 1,
  "page_size": 20
}
```

Ordered by: parent chunk_index, then child chunk_index within each parent.

---

#### POST /api/documents/{document_id}/chunks

Add a new child chunk under a specified parent.

**Request body**:
```json
{
  "parent_id": "uuid",
  "content": "New chunk text...",
  "insert_after": 2,
  "user_email": "admin@example.com"
}
```

`insert_after`: chunk_index position to insert after (-1 or omit for end). Siblings reindexed.

**Response 200**: The created chunk with `id`, `embedding_stale: false`.

---

#### GET /api/documents/{document_id}/chunks/{chunk_id}

**Query params**: `user_email`

**Response 200**: Single chunk dict (same shape as list item).

---

#### PUT /api/documents/{document_id}/chunks/{chunk_id}

Update chunk content. If child → re-embed automatically. If parent → no embed.

**Request body**:
```json
{
  "content": "Updated text...",
  "user_email": "admin@example.com"
}
```

**Response 200**: Updated chunk. `embedding_stale: false` if embed succeeded, `true` if embed failed.

---

#### DELETE /api/documents/{document_id}/chunks/{chunk_id}

**Query params**: `user_email`

**Response 200**: `{ "deleted": true }`

Siblings reindexed after deletion.

---

#### POST /api/documents/{document_id}/chunks/{chunk_id}/split

Split a child chunk at a text position.

**Request body**:
```json
{
  "split_position": 150,
  "user_email": "admin@example.com"
}
```

**Response 200**: Two new chunk objects (both embedded, same parent_id).

---

#### POST /api/documents/{document_id}/chunks/{chunk_id}/merge

Merge a child chunk with its next sibling (same parent_id).

**Request body**:
```json
{
  "user_email": "admin@example.com"
}
```

**Response 200**: The merged chunk (re-embedded).

**Error 400**: If next sibling doesn't exist or has different parent_id.

---

#### POST /api/documents/{document_id}/chunks/re-embed

Re-embed all child chunks for a document (background task).

**Request body**:
```json
{
  "user_email": "admin@example.com"
}
```

**Response 200**: `{ "status": "re-embedding", "total_children": N }`

---

#### DELETE /api/documents/{document_id}/chunks/bulk-delete

Bulk delete multiple chunks.

**Request body**:
```json
{
  "chunk_ids": ["uuid1", "uuid2", "uuid3"],
  "user_email": "admin@example.com"
}
```

**Response 200**: `{ "deleted": 3 }`

Siblings reindexed after deletion.

---

## New Endpoint: Migration

#### POST /api/documents/migrate-all

Migrate all manuals from `manuals` table to `knowledge_documents`.

**Request body**:
```json
{
  "user_email": "admin@example.com"
}
```

**Response 200**: `{ "status": "migrating", "total_manuals": N }`

Background task processes sequentially with progress tracking.

---

#### GET /api/documents/migration-status

Check migration progress.

**Query params**: `user_email`

**Response 200**:
```json
{
  "status": "in_progress",
  "completed": 5,
  "total": 12,
  "failed": ["manual-uuid-1"],
  "current": "CADAS ATS User Manual"
}
```

Status values: `idle`, `in_progress`, `completed`, `completed_with_errors`.

---

#### DELETE /api/documents/migrate-cleanup

Delete old Knowledge tab data after migration.

**Request body**:
```json
{
  "user_email": "admin@example.com"
}
```

**Response 200**: `{ "deleted_manuals": N, "deleted_chunks": M }`

**Error 400**: If migration not completed.

---

## Modified Endpoint: POST /api/manuals/ask

Response shape extended when source is `"document"` with cross-document fields:

```json
{
  "answer": "...",
  "source_type": "document",
  "sources": [...],
  "manuals_consulted": [
    { "id": "doc-uuid", "title": "CNMS User Manual" },
    { "id": "doc-uuid", "title": "CADAS ATS Manual" }
  ],
  "has_conflicts": false,
  "confidence": "high",
  "score": 0.88,
  ...
}
```

New fields `manuals_consulted` and `has_conflicts` added to document-sourced responses (matching the existing Layer 3 response shape for backward compatibility with frontend).

---

## Modified Upload: POST /api/documents/upload

**Extended**: Now accepts PDF, DOCX, TXT, MD files (was PDF-only in spec 070).

File extension validation:
```
Allowed: .pdf, .docx, .txt, .md
Rejected: everything else → HTTP 400 "Unsupported file type. Accepted: PDF, DOCX, TXT, MD"
```

`file_extension` is stored in `knowledge_documents` row.
