# Quickstart: 075 — Contextual Embeddings

**Date**: 2026-04-16

## What This Feature Does

Before embedding each chunk, the system prepends the document title and section title as context. This gives the embedding model document-level awareness so that generic procedural chunks (like "Select Administration > Alarms") embed near domain-specific queries (like "how to configure CADAS alarms").

## Files to Change

1. **`backend/services/document_service.py`** — Add prefix construction before `embed_many()` call in `index_document()`
2. **`backend/services/manual_rag_service.py`** — Add prefix construction before `embed_many()` call in `upload_manual()`
3. **`backend/routers/documents.py`** — Update `re_embed_all_chunks()` to use contextual prefix
4. **`backend/routers/manuals.py`** — Add new `POST /manuals/{manual_id}/re-embed` endpoint
5. **`backend/tests/test_contextual_prefix.py`** — New test file

## Shared Helper

A `build_contextual_prefix(doc_title, section_title)` function shared between both pipelines. Returns:
- `"Doc Title > Section Title: "` (both available)
- `"Doc Title: "` (no section)
- `""` (no title)

## Prerequisites

- nomic-embed-text embedding model running on Ollama (already deployed)
- No new dependencies

## Verification

```bash
# After deployment:
# 1. Upload a test document and verify embedding uses prefix (check server logs for FR-011)
# 2. Search for a topic using document-title terminology — verify improved ranking
# 3. Trigger re-embed on existing documents and manuals
# 4. Verify displayed chunk text has no prefix artifacts
```

## Rollback

Re-embed all chunks without the prefix (revert code, trigger re-embed). No data loss — chunk content is never modified.
