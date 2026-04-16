# Data Model: Spec 072 — Document Retrieval v2

## Schema Changes (Migration)

### knowledge_documents — ADD column

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| file_extension | text | NULLABLE | File extension: pdf, docx, txt, md |

### document_chunks — ADD columns

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| chunk_index | int | NULLABLE | Ordering within parent. Auto-reindexed on split/merge/delete. |
| embedding_stale | boolean | NOT NULL DEFAULT false | True when content changed but re-embedding failed. Stale chunks excluded from search. |

### search_document_chunks RPC — UPDATE

Add `AND dc.embedding_stale = false` filter to exclude stale chunks from search results. No other changes to the function signature.

## Existing Entities (from spec 070, unchanged)

### knowledge_documents

| Column | Type | Description |
|--------|------|-------------|
| id | uuid PK | Document ID |
| filename | text | Original filename |
| display_name | text | Admin-provided name |
| file_path | text | Local disk path |
| status | text | pending/indexing/ready/failed |
| error_message | text | Error on failure |
| total_pages | int | Pages extracted |
| total_chunks | int | Child chunk count |
| indexed_at | timestamptz | When indexing completed |
| uploaded_by | text | Admin email |
| created_at | timestamptz | Upload time |
| **file_extension** | **text** | **NEW — pdf/docx/txt/md** |

### document_chunks

| Column | Type | Description |
|--------|------|-------------|
| id | uuid PK | Chunk ID |
| document_id | uuid FK | → knowledge_documents(id) CASCADE |
| chunk_type | text | 'parent' or 'child' |
| parent_id | uuid FK | → document_chunks(id) CASCADE (NULL for parents) |
| section_title | text | Section heading |
| content | text | Full section (parent) or paragraph (child) |
| page_number | int | Starting page |
| embedding | vector(768) | Child only |
| created_at | timestamptz | Creation time |
| **chunk_index** | **int** | **NEW — ordering within parent** |
| **embedding_stale** | **boolean** | **NEW — true if content changed but embed failed** |

## Tables to Retire (after migration)

### manuals (DROP after migration)

| Column | Type |
|--------|------|
| id | uuid PK |
| title | text |
| file_name | text |
| file_extension | text |
| file_size_bytes | int |
| uploaded_by | uuid FK → users |
| chunk_count | int |
| created_at | timestamptz |

### manual_chunks (DROP after migration)

| Column | Type |
|--------|------|
| id | uuid PK |
| manual_id | uuid FK → manuals CASCADE |
| chunk_index | int |
| source_page | int |
| content | text |
| embedding | vector(768) |
| created_at | timestamptz |

### manual_corpus_stats (DROP after migration)

| Column | Type |
|--------|------|
| id | int PK |
| total_bytes | bigint |
| manual_count | int |

## Relationships

```
knowledge_documents 1──* document_chunks (via document_id, CASCADE)
document_chunks (parent) 1──* document_chunks (child) (via parent_id, CASCADE)

manuals 1──* manual_chunks (via manual_id, CASCADE) — TO BE RETIRED
```

## State Transitions

### knowledge_documents.status
```
pending → indexing → ready
                  → failed
```
Migration creates documents directly in `indexing` state.

### document_chunks.embedding_stale
```
false → true   (content edited but embed fails)
true  → false  (re-embed succeeds)
```
