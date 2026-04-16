# Data Model: Spec 070 — Document Retrieval

## New Entities

### knowledge_documents

Stores metadata for each uploaded PDF manual.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | uuid | PK, DEFAULT gen_random_uuid() | Document ID |
| filename | text | NOT NULL | Original filename as uploaded |
| display_name | text | NOT NULL | Admin-provided display name |
| file_path | text | NOT NULL | Local disk path: `uploaded_files/manuals/{uuid}.pdf` |
| status | text | NOT NULL, DEFAULT 'pending', CHECK IN ('pending','indexing','ready','failed') | Indexing lifecycle state |
| error_message | text | NULLABLE | Error details when status='failed' |
| total_pages | int | NULLABLE | Populated after PDF extraction |
| total_chunks | int | NULLABLE | Count of child chunks after indexing |
| indexed_at | timestamptz | NULLABLE | Timestamp of successful indexing completion |
| uploaded_by | text | NOT NULL | Admin email who uploaded |
| created_at | timestamptz | DEFAULT now() | Upload timestamp |

**Lifecycle**: `pending` → `indexing` → `ready` | `failed`
- Upload creates row with `status='pending'`
- Background task sets `status='indexing'` at pipeline start
- On success: `status='ready'`, `indexed_at=now()`, `total_pages` + `total_chunks` populated
- On failure: `status='failed'`, `error_message` populated, partial chunks kept
- Re-index: deletes all chunks, resets to `indexing`, re-runs pipeline

### document_chunks

Stores parent (section) and child (paragraph) chunks for each document.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | uuid | PK, DEFAULT gen_random_uuid() | Chunk ID |
| document_id | uuid | FK → knowledge_documents(id) ON DELETE CASCADE | Parent document |
| chunk_type | text | NOT NULL, CHECK IN ('parent','child') | Section or paragraph |
| parent_id | uuid | FK → document_chunks(id) ON DELETE CASCADE, NULLABLE | Child → parent reference (NULL for parents) |
| section_title | text | NULLABLE | Detected section heading |
| content | text | NOT NULL | Full section (parent) or paragraph (child) |
| page_number | int | NULLABLE | Starting page number |
| embedding | vector(768) | NULLABLE | Child chunks only — nomic-embed-text 768-dim |
| created_at | timestamptz | DEFAULT now() | Chunk creation time |

**Index**: `ivfflat (embedding vector_cosine_ops) WHERE chunk_type = 'child'` — only child chunks are searched.

**Parent-child relationship**:
- Parent chunks: `chunk_type='parent'`, `parent_id=NULL`, `embedding=NULL`, contain full section text
- Child chunks: `chunk_type='child'`, `parent_id` references their parent, `embedding` populated, contain paragraph-level text

## Relationships

```
knowledge_documents 1──* document_chunks (via document_id, CASCADE delete)
document_chunks (parent) 1──* document_chunks (child) (via parent_id, CASCADE delete)
```

## Existing Tables Referenced (no changes)

- `validated_qa` — searched in Layer 1 of RAG pipeline (unchanged)
- `users` — queried for admin check (`user_type='admin'`)
- `user_activity_log` — fire-and-forget audit entries for upload/delete/reindex

## New RPC Function

### search_document_chunks

```sql
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

**Note**: `match_threshold` is in distance space (0.30 distance = 0.70 similarity). The JOIN on `knowledge_documents.status = 'ready'` ensures only fully-indexed documents are searched.
