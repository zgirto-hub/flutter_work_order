# Feature Specification: Document Retrieval v2 — Replace Knowledge Tab

**Feature Branch**: `072-document-retrieval-v2`
**Created**: 2026-04-16
**Status**: Draft
**Input**: Replace the Knowledge tab with an enhanced Documents tab that includes all existing Knowledge tab features (chunk editing, reranking, cross-document synthesis, HyDE) plus spec 070's parent-child chunking, then migrate existing manuals and retire the old system.

## Context

The project currently has two overlapping document systems:

1. **Knowledge tab** (old, specs 040-046): uploads to `manuals` table, flat chunking (250-word sliding window), feeds Layer 3 RAG (HyDE + rerank + cross-manual synthesis). Full chunk management UI (edit, split, merge, re-embed, bulk delete).

2. **Documents tab** (new, spec 070): uploads to `knowledge_documents` table, parent-child chunking, feeds Layer 2 RAG (direct embed + cosine search). Basic management UI (upload, list, delete, re-index). No chunk editing, no reranking, no HyDE, no cross-document synthesis.

Spec 072 unifies them: enhance the Documents tab to include all Knowledge tab capabilities, migrate existing manuals, then remove the Knowledge tab and Layer 3 pipeline.

**Prerequisite**: Spec 070 must be fully deployed and working.

---

## User Scenarios & Testing

### User Story 1 — Enhanced Document Search with Reranking + HyDE (Priority: P1)

As a technician, when I ask the AI a question that matches uploaded document content, the system uses HyDE to generate a better embedding, searches document chunks, reranks results by relevance, and returns a high-quality answer with full parent section context.

**Why this priority**: Without improved search quality, the Documents tab produces worse answers than the Knowledge tab it's replacing. This is the core quality parity requirement.

**Independent Test**: Upload a manual via Documents tab. Ask a vague question that requires HyDE to match well (e.g., "what should I check during routine maintenance" when the manual section is titled "Preventive Maintenance Checklist"). Verify the answer is accurate and cites the correct section.

**Acceptance Scenarios**:

1. **Given** a document is indexed and ready, **When** a technician asks a vague question, **Then** HyDE generates a hypothetical passage, the embedding matches relevant child chunks, reranking filters low-relevance results, and the LLM receives parent section context for the top matches.
2. **Given** multiple documents contain related content, **When** a question spans topics across documents, **Then** cross-document synthesis produces a unified answer citing multiple document sources with section and page references.
3. **Given** a question matches both validated_qa and document chunks, **Then** validated_qa takes priority (existing Layer 1 behavior preserved).

---

### User Story 2 — Chunk Browsing and Editing (Priority: P2)

As an admin, I can view all extracted chunks for a document, edit chunk content (with automatic re-embedding), add new chunks, split a chunk into two, merge adjacent chunks, and bulk-delete chunks. This lets me fix extraction errors without re-uploading the entire document.

**Why this priority**: The Knowledge tab's most-used admin feature is chunk editing — fixing bad PDF extractions, splitting merged paragraphs, merging orphaned fragments. Without this, admins must re-upload documents to fix minor issues.

**Independent Test**: Upload a document, navigate to its chunk list. Edit a chunk's text, verify it re-embeds. Split a chunk, verify two new chunks appear. Merge two adjacent chunks. Delete a chunk. Ask a question to verify the edited content is searchable.

**Acceptance Scenarios**:

1. **Given** a document with chunks, **When** admin taps a document in the list, **Then** a paginated chunk list appears showing chunk type (parent/child), section title, page number, content preview, and character count.
2. **Given** a child chunk, **When** admin edits its content and saves, **Then** the chunk content is updated and its embedding is regenerated automatically.
3. **Given** a child chunk, **When** admin splits it at a position, **Then** two new child chunks are created with correct parent_id references and fresh embeddings.
4. **Given** two adjacent child chunks with the same parent, **When** admin merges them, **Then** one combined chunk replaces both with a fresh embedding.
5. **Given** a parent chunk, **When** admin edits its content, **Then** the parent section text is updated (no embedding needed — parents are not embedded).
6. **Given** multiple chunks selected, **When** admin triggers bulk delete, **Then** all selected chunks are removed.

---

### User Story 3 — Multi-Format Upload Support (Priority: P2)

As an admin, I can upload PDF, DOCX, TXT, and Markdown files to the Documents tab (matching the Knowledge tab's format support). The system extracts text appropriately for each format before applying parent-child chunking.

**Why this priority**: The Knowledge tab supports PDF, DOCX, TXT, MD. The Documents tab (spec 070) only supports PDF. Format parity is needed before retirement.

**Independent Test**: Upload a DOCX file. Verify it is chunked and indexed. Ask a question matching its content.

**Acceptance Scenarios**:

1. **Given** a DOCX file, **When** admin uploads it, **Then** text is extracted, parent-child chunking is applied, and child chunks are embedded.
2. **Given** a TXT or MD file, **When** admin uploads it, **Then** text is extracted, section boundaries are detected (headings for MD, delimiters for TXT), and parent-child chunking is applied.
3. **Given** an unsupported file type (e.g., .xlsx), **When** admin uploads it, **Then** the system rejects it with a clear error message listing supported formats.

---

### User Story 4 — Migration of Existing Manuals (Priority: P3)

As an admin, I can migrate all existing manuals from the Knowledge tab to the Documents tab with one action. The system re-chunks each manual using parent-child chunking, re-embeds all child chunks, and preserves the original file and metadata. After migration, the old Knowledge tab data can be deleted.

**Why this priority**: Migration is the bridge to retirement. Without it, admins must manually re-upload every manual.

**Independent Test**: With existing manuals in the Knowledge tab, trigger migration. Verify each manual appears in the Documents tab with status "ready", correct chunk counts, and that questions previously answered by Layer 3 now get answered by Layer 2.

**Acceptance Scenarios**:

1. **Given** N manuals exist in the `manuals` table, **When** admin triggers "Migrate All", **Then** manuals are processed sequentially (one at a time), each re-chunked with parent-child strategy, a `knowledge_documents` row is created, and embeddings are generated. Progress is reported after each manual (e.g., "3 of 12 complete").
2. **Given** a manual has a file format not supported by the PDF extractor (DOCX, TXT), **Then** the migration uses the appropriate parser for that format and applies parent-child chunking to the extracted text.
3. **Given** migration completes for all manuals, **When** admin verifies, **Then** a "Delete Old Knowledge Data" option becomes available.
4. **Given** a migration fails for one manual, **Then** it is marked as failed with error details, and other manuals continue migrating independently.

---

### User Story 5 — Retire Knowledge Tab and Layer 3 Pipeline (Priority: P3)

As a developer, after all manuals are migrated, the old Knowledge tab, its backend endpoints, the Layer 3 manual-chunks pipeline (HyDE embed + chunk search + rerank + cross-manual synthesis), and the old tables are removed. The Documents tab becomes the single document management interface.

**Why this priority**: Cleanup happens last, after everything else is working and migrated.

**Independent Test**: After migration, remove the Knowledge tab. Verify the Documents tab handles all document management. Verify the AI assistant still answers from documents correctly (via the enhanced Layer 2 pipeline).

**Acceptance Scenarios**:

1. **Given** all manuals migrated and verified, **When** the Knowledge tab is removed, **Then** no runtime errors occur and the tab count updates correctly.
2. **Given** the Layer 3 manual-chunks pipeline is removed, **Then** the RAG flow becomes: Layer 1 (validated_qa) → Layer 2 (document chunks with HyDE + rerank + synthesis) → fallback message.
3. **Given** old tables are dropped, **Then** no active code references them.

---

### Edge Cases

- Document has 0 extractable text: set status to "failed" with error "No extractable text found".
- Ollama unavailable during chunk editing: content update is saved, `embedding_stale` is set to true. Stale chunks are excluded from search results. UI shows a warning badge on stale chunks + "Re-embed" button to retry when Ollama is back.
- Migration source file missing from disk: mark that manual as "failed" with "Source file not found", continue with remaining manuals.
- Admin edits a parent chunk: child chunks are NOT automatically re-chunked. Only the parent's stored content is updated.
- Merging chunks from different parents: system prevents it — only adjacent child chunks with the same parent_id can be merged.
- Adding a new child chunk: admin specifies which parent it belongs to. Fresh embedding generated on save.
- Re-embed All when Ollama is overloaded: background task retries failed embeddings up to 3 times with exponential backoff, then marks remaining as stale.

---

## Requirements

### Functional Requirements

**Search Quality (Layer 2 Enhancement)**:
- **FR-001**: The document search pipeline MUST apply HyDE before embedding the search query for document chunk retrieval.
- **FR-002**: The document search pipeline MUST retrieve up to 10 candidate chunks using a relaxed distance threshold (0.55 cosine distance / 0.45 similarity), then rerank and filter to the top 3 most relevant results.
- **FR-003**: When matched document chunks come from multiple documents, the system MUST synthesize answers across documents and cite each source with document name, section title, and page number.
- **FR-004**: The system MUST detect conflicting information across documents and flag it in the response.
- **FR-005**: The response MUST include a `manuals_consulted` equivalent listing all documents that contributed to the answer.

**Chunk Management**:
- **FR-006**: Admin MUST be able to view a paginated list of chunks for any document, showing chunk type (parent/child), section title, page number, content, and character count.
- **FR-007**: Admin MUST be able to edit a child chunk's content, triggering automatic re-embedding.
- **FR-008**: Admin MUST be able to edit a parent chunk's content (no re-embedding needed).
- **FR-009**: Admin MUST be able to add a new child chunk under a specific parent, with automatic embedding.
- **FR-010**: Admin MUST be able to split a child chunk at a text position into two new child chunks, each re-embedded automatically.
- **FR-011**: Admin MUST be able to merge two adjacent child chunks (same parent) into one, re-embedded automatically.
- **FR-012**: Admin MUST be able to delete individual chunks or bulk-delete multiple chunks.
- **FR-013**: Admin MUST be able to trigger "Re-embed All" for a document as a background task.

**Multi-Format Upload**:
- **FR-014**: The upload endpoint MUST accept PDF, DOCX, TXT, and MD files (max 50 MB).
- **FR-015**: Each format MUST use an appropriate text extraction method before parent-child chunking.

**Migration**:
- **FR-016**: Admin MUST be able to migrate all existing `manuals` table entries to `knowledge_documents` with one action.
- **FR-017**: Migration MUST preserve the original filename, title, uploader, and upload date.
- **FR-018**: After successful migration, admin MUST be able to delete old Knowledge tab data.

**Retirement**:
- **FR-019**: The Knowledge tab, its backend endpoints, and the Layer 3 pipeline MUST be removable after migration without breaking any other feature.
- **FR-020**: Document count and total file size tracking MUST be maintained in the Documents system.

### Key Entities

- **knowledge_documents**: Extended with `file_extension` field. Existing fields unchanged from spec 070.
- **document_chunks**: Extended from spec 070 with `chunk_index` (integer, ordering within parent, auto-reindexed on split/merge/delete) and `embedding_stale` (boolean, default false — set true when content changes but re-embedding fails). Chunk editing operations modify content and trigger re-embedding for child chunks.
- **manuals** (existing, to be retired): Source for migration. Read-only during migration, deleted after.
- **manual_chunks** (existing, to be retired): Not directly migrated — documents are re-chunked with parent-child strategy.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: Questions previously answered by the Knowledge tab's Layer 3 pipeline are answered with equal or better quality by the enhanced Layer 2 pipeline (validated by comparing answers on 10 representative test questions).
- **SC-002**: Admin can edit, split, merge, and delete chunks with changes reflected in search results within 5 seconds of the operation completing.
- **SC-003**: Migration of all existing manuals completes without manual intervention (failed manuals are reported but don't block others).
- **SC-004**: After retirement, the codebase has zero references to old Knowledge tab tables or services in active code paths.
- **SC-005**: The AI assistant's document-sourced response time stays within 5 seconds of the current Layer 2 response time (HyDE + rerank adds latency).
- **SC-006**: Upload supports all 4 file formats (PDF, DOCX, TXT, MD) with clear error messages for unsupported types.

---

## Assumptions

- Spec 070 (Document Retrieval v1) is fully deployed and working before this spec begins.
- The existing HyDE, reranking, and cross-manual synthesis functions will be moved into the Layer 2 code path (adapted to work with `document_chunks` instead of `manual_chunks`). No duplication — the old Layer 3 call sites are removed once Layer 2 has these capabilities.
- All existing manuals in the `manuals` table have their source files still present on disk.
- The existing `manual_parser.py` handles DOCX/TXT/MD extraction and will be reused for those formats during upload and migration.
- After migration, no user workflow depends on the `manuals` or `manual_chunks` tables directly.
- The chunk editing UI follows the same interaction patterns as the existing `chunk_editor_screen.dart`.

---

## Out of Scope

- OCR for scanned PDFs (English native text only)
- Arabic language documents
- Automatic re-chunking when parent content changes
- Version history for chunk edits
- Diff view between old and new chunk content
- Automatic migration scheduling (admin triggers manually)
- Per-chunk thumbs up/down rating

---

## Clarifications

### Session 2026-04-16
- Q: How should chunk ordering within a parent be maintained after split/merge/delete? → A: Add a `chunk_index` integer column to `document_chunks`. Auto-reindex siblings (same parent_id) on split/merge/delete — matching the existing Knowledge tab pattern.
- Q: Should embedding staleness be tracked formally, and how should stale chunks behave in search? → A: Add `embedding_stale` boolean flag. Stale chunks excluded from search. UI shows warning badge + "Re-embed" button.
- Q: Should migration process manuals in parallel or sequentially? → A: Sequential with progress reporting — one manual at a time, status updates after each (e.g., "3 of 12 complete"). Failures don't block remaining manuals.
- Q: Should Layer 3 functions (HyDE/rerank/synthesis) be moved, duplicated, or shared for Layer 2? → A: Move — adapt existing functions to work with `document_chunks`. Delete old Layer 3 call sites. Single code path, no duplication.
- Q: Should the document chunk search threshold be relaxed for reranking? → A: Yes — relax to 0.55 distance (0.45 similarity), retrieve up to 10 candidates, let reranking filter to top 3. Matches Layer 3's proven approach.
