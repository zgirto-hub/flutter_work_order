# Data Model: 075 — Contextual Embeddings

**Date**: 2026-04-16

## Entities Modified

### document_chunks (existing table, no schema change)

No new columns. The `embedding` column (vector(768)) is updated in-place with contextually-prefixed embeddings. The `content` column remains unchanged.

| Column | Change | Notes |
|--------|--------|-------|
| `content` | None | Stored text stays original — prefix is NOT persisted |
| `embedding` | Updated | Regenerated from prefix + content during re-embed |
| `section_title` | Read-only | Used to build contextual prefix |
| `embedding_stale` | Read-only | Used by re-embed to track failures |

### manual_chunks (existing table, no schema change)

No new columns. Same pattern as document_chunks — embedding updated in-place, content unchanged.

| Column | Change | Notes |
|--------|--------|-------|
| `content` | None | Stored text stays original |
| `embedding` | Updated | Regenerated from prefix + content during re-embed |

### knowledge_documents (existing table, no schema change)

| Column | Change | Notes |
|--------|--------|-------|
| `display_name` | Read-only | Used as document title in contextual prefix |

### manuals (existing table, no schema change)

| Column | Change | Notes |
|--------|--------|-------|
| `title` | Read-only | Used as manual title in contextual prefix |

## No New Tables or Columns

The contextual prefix is a transient in-memory construct used only during embedding. No persistent storage of the prefix is needed.

## No Migration Files

No database schema changes required.
