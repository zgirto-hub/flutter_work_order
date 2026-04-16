# Research: 075 — Contextual Embeddings

**Date**: 2026-04-16

## R-001: Where to inject the contextual prefix for document chunks?

**Decision**: In `backend/services/document_service.py`, in the embedding phase (lines 122–129), construct prefixed text before calling `embed_many()`. The prefix is built from `display_name` (from the `knowledge_documents` row) and `section_title` (from the parent chunk). Both are available in the `index_document()` function scope — `display_name` is fetched at the start, and `section_title` is set during section detection.

**Rationale**: The embedding call is isolated — modifying the text sent to `embed_many()` without changing the stored `content` field is straightforward. The metadata is already in scope; no additional DB queries needed.

**Alternatives considered**: Modifying `ollama_embedder.embed_many()` to accept metadata — rejected because that would couple the embedder to document semantics and break its reusability.

## R-002: Where to inject the contextual prefix for manual chunks?

**Decision**: In `backend/services/manual_rag_service.py`, in the `upload_manual()` function (lines 322–327), construct prefixed text before calling `embed_many()`. The prefix uses the `title` parameter which is already passed to the function.

**Rationale**: Same pattern as document chunks. The manual title is available as a function parameter. Manual chunks lack section titles, so the prefix is just "Manual Title: ".

**Alternatives considered**: Adding section detection to manual chunking — rejected as out of scope (manual chunker uses word-count windows, not heading-based sections).

## R-003: Helper function for prefix construction

**Decision**: Create a small helper function `build_contextual_prefix(doc_title: str, section_title: str | None = None) -> str` that returns the prefix string. Place it in a new utility module or directly in `document_service.py` and import it into `manual_rag_service.py`.

**Rationale**: Both pipelines need the same prefix logic. A shared function prevents drift between the two prefix formats. The function handles edge cases: empty/None titles → empty prefix, missing section → title-only prefix.

**Format**: 
- With section: `"Doc Title > Section Title: "`
- Without section: `"Doc Title: "`
- Empty title: `""` (no prefix)

## R-004: Re-embedding for document chunks (existing endpoint)

**Decision**: Modify the existing `POST /{document_id}/chunks/re-embed` endpoint in `backend/routers/documents.py` (lines 817–859). The current code re-embeds with `embed_single(chunk["content"])`. Change to: look up the document's `display_name`, look up the chunk's `section_title`, build the contextual prefix, and embed `prefix + chunk["content"]`.

**Rationale**: The re-embed endpoint already iterates all child chunks. Adding prefix construction is a small change. The document title can be fetched once at the start; `section_title` is already on each chunk row.

## R-005: Re-embedding for manual chunks (NEW endpoint)

**Decision**: Add a new endpoint `POST /manuals/{manual_id}/re-embed` in `backend/routers/manuals.py`. Pattern mirrors the existing document re-embed: fetch the manual's title, iterate all chunks, build prefix, call `embed_single()`, update embedding in-place. Run as a background task.

**Rationale**: Clarification session confirmed both pipelines need batch re-embed. The manual_chunks table already has an embedding column. The endpoint follows the same async background pattern as the document re-embed.

**Implementation notes**:
- Fetch manual title once
- Iterate `manual_chunks` for that manual_id
- For each chunk: `embed_single(prefix + chunk["content"])`, update row
- No `embedding_stale` column on manual_chunks (unlike document_chunks), so errors simply log and skip

## R-006: Token limit safety for nomic-embed-text

**Decision**: nomic-embed-text supports 8192 tokens (~32k characters). Typical titles are under 100 characters. Combined prefix + chunk text will almost never exceed the limit. Add a safety check: if `len(prefix + content) > 30000` characters (conservative buffer), truncate the prefix. Log a warning when truncation occurs.

**Rationale**: FR-009 requires preserving full chunk text and truncating prefix if needed. The 30k character threshold provides ample safety margin. In practice, truncation should never trigger (SC-006 expects <10% fallback).

**Alternatives considered**: Dynamic tokenization check — rejected as over-engineering; character-based estimate is sufficient for this model.

## R-007: Query-side behavior

**Decision**: No change to query embedding. User queries continue to be embedded as-is (FR-010). The contextual prefix on corpus chunks biases the embedding space to be document-aware; raw queries naturally match because the embedding model learns to associate domain terms with their context.

**Rationale**: This is the standard Anthropic contextual retrieval pattern — enrich the corpus side, leave the query side alone.

## R-008: Test strategy

**Decision**: Add `backend/tests/test_contextual_prefix.py` with:
1. Unit tests for the prefix builder: empty title, title-only, title+section, long title truncation.
2. Integration-style test: verify that the embedding call in `index_document` receives prefixed text (mock `embed_many` and assert the input).
3. Verify stored content is NOT prefixed (mock DB insert and assert the content field).

**Rationale**: The key invariant is "prefix at embed time, original text in storage." Tests should verify both the prefix construction and the separation of concerns.
