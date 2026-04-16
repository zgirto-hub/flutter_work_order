# Data Model: Smart Document Preprocessing

**Feature**: 073-smart-doc-preprocess  
**Date**: 2026-04-16

## Schema Changes

### Modified Table: `knowledge_documents`

**Change**: Add `'preprocessing'` to the `status` CHECK constraint.

| Column | Type | Change | Description |
|--------|------|--------|-------------|
| status | text | MODIFIED | CHECK now includes `('pending', 'preprocessing', 'indexing', 'ready', 'failed')` |

### Modified Table: `document_chunks`

**Change**: Add `raw_content` column to retain original text before preprocessing.

| Column | Type | Change | Description |
|--------|------|--------|-------------|
| raw_content | text | NEW (nullable) | Original raw extracted text before AI preprocessing. NULL for chunks created before this feature or when preprocessing is disabled. |

### Modified Table: `manual_chunks`

**Change**: Add `raw_content` column (same as document_chunks).

| Column | Type | Change | Description |
|--------|------|--------|-------------|
| raw_content | text | NEW (nullable) | Original raw extracted text before AI preprocessing. NULL for chunks created before this feature or when preprocessing is disabled. |

### Modified Table: `app_settings`

**Change**: New row (no schema change).

| Key | Default Value | Description |
|-----|---------------|-------------|
| `smart_preprocessing_enabled` | `'true'` | Enables/disables AI preprocessing for newly uploaded documents. |

## Entity Relationships

```
knowledge_documents (1) ──── (N) document_chunks
  status: pending → preprocessing → indexing → ready/failed
  
document_chunks
  content: preprocessed Markdown (used for embedding & search)
  raw_content: original extracted text (retained for re-processing)
  chunk_type: parent | child
  parent_id: self-referential FK (child → parent)

manual_chunks
  content: preprocessed Markdown (used for embedding & search)
  raw_content: original extracted text (retained for re-processing)

app_settings
  key: 'smart_preprocessing_enabled'
  value: 'true' | 'false'
```

## State Transitions

### Document Lifecycle (Updated)

```
pending ──→ preprocessing ──→ indexing ──→ ready
   │              │               │
   │              │               └──→ failed (embedding error)
   │              └──→ indexing (AI unavailable, fallback to raw text)
   │              └──→ failed (extraction error)
   └──→ failed (validation error)
```

**New state**: `preprocessing` — entered after text extraction completes, before chunking begins. If AI service is unavailable at this point, transitions directly to `indexing` (graceful fallback).

## Migration Strategy

- Single migration file adding `raw_content` column to both `document_chunks` and `manual_chunks`
- ALTER the `knowledge_documents.status` CHECK constraint to include `'preprocessing'`
- INSERT `smart_preprocessing_enabled` into `app_settings` with default `'true'`
- All changes are backward-compatible: `raw_content` is nullable, new status value is additive, setting is opt-in by default
- Existing documents and chunks are unaffected (FR-014)
