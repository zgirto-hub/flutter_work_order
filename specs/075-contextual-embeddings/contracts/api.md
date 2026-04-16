# API Contracts: 075 — Contextual Embeddings

**Date**: 2026-04-16

## New Endpoint

### POST /manuals/{manual_id}/re-embed

Re-embeds all chunks for a specific manual using contextual prefixes. Runs as a background task.

**Request**:
- Path: `manual_id` (UUID)
- Query: `user_email` (string, required — for audit logging)

**Response** (immediate):
```json
{
  "status": "re-embedding started",
  "manual_id": "<uuid>",
  "chunk_count": <int>
}
```

**Behavior**:
- Fetches the manual's title
- Iterates all chunks, builds contextual prefix ("Manual Title: "), re-embeds each
- Updates embedding in-place
- Runs in background — endpoint returns immediately
- Errors on individual chunks are logged and skipped (no partial failure abort)

**Auth**: Admin-only (same pattern as document re-embed endpoint)

## Behavioral Changes (non-breaking)

### POST /documents/upload
- **Before**: Chunks embedded with raw content text
- **After**: Chunks embedded with "Doc Title > Section Title: content" prefix
- **Response shape**: Unchanged
- **Stored content**: Unchanged — prefix is NOT persisted

### POST /manuals/upload
- **Before**: Chunks embedded with raw content text
- **After**: Chunks embedded with "Manual Title: content" prefix
- **Response shape**: Unchanged
- **Stored content**: Unchanged

### POST /documents/{document_id}/chunks/re-embed
- **Before**: Re-embeds with raw content text
- **After**: Re-embeds with contextual prefix
- **Response shape**: Unchanged

### Search RPCs (search_document_chunks, search_manual_chunks)
- **No change**: Queries are embedded as-is (no prefix on query side)
- Vector space has shifted (contextually-enriched embeddings), so cosine distances may change
- No threshold changes needed — improved relevance is the goal
