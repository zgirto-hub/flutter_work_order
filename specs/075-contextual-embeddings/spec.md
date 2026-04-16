# Feature Specification: Contextual Embeddings for Knowledge Chunks

**Feature Branch**: `075-contextual-embeddings`
**Created**: 2026-04-16
**Status**: Draft
**Input**: User description: "Build Spec 076: Contextual Embeddings — before embedding each chunk, prepend the document title and section title as context (e.g., 'CADAS-IMS Admin Training > Alarm Configuration: [chunk text]'). This gives the embedding model document-level context so that chunks like 'Select Administration > Alarms' embed near queries like 'how to configure CADAS alarms' instead of being a generic instruction. Apply to both document_chunks and manual_chunks pipelines. The contextual prefix is used only for embedding — the stored chunk content stays unchanged so display is not affected. Based on Anthropic's contextual retrieval technique."

> **Note on numbering**: The user referred to this work as "Spec 076" but the sequential branch-numbering scheme assigned the next available slot, `075`. The branch and spec folder are `075-contextual-embeddings`.

## Clarifications

### Session 2026-04-16

- Q: Should this spec include a batch re-embed capability for manual chunks, or only for document chunks? → A: Both pipelines — add a batch re-embed endpoint for manuals matching the existing document re-embed pattern.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Improved retrieval on short, context-dependent chunks (Priority: P1)

A technician or engineer asks the AI assistant a natural-language question that references a product or system by name ("how do I configure alarms in CADAS-IMS?", "what does the Saab fire panel do on low battery?"). Today, a chunk that reads only "Select Administration > Alarms." — a short, generic-looking instruction lifted from a product manual — may not surface because its embedding carries no signal about which product or procedure it belongs to. After this feature, the retrieval layer uses the chunk's originating document and section as additional context during embedding, so those short, procedural chunks end up near product-specific queries. The user sees answers that cite the correct manual section, even when the chunk text alone would have been too generic to find.

**Why this priority**: This is the entire value of the feature. Everything else (indexing tooling, migration path, observability) exists to support this one retrieval-quality improvement. Without it, the feature delivers nothing.

**Independent Test**: Take a known-weak query from the existing RAG quality test set — one where the expected chunk is short and generic-looking ("Select Administration > Alarms", "Click Save", "Set threshold to default") — embed the corpus with contextual prefixes, re-run the same query, and verify the target chunk now ranks in the top-K retrieved results when it previously did not.

**Acceptance Scenarios**:

1. **Given** a document titled "CADAS-IMS Admin Training" with a section "Alarm Configuration" containing the chunk "Select Administration > Alarms.", **When** a user asks "how do I configure CADAS alarms?", **Then** the chunk appears in the top retrieved results and the answer references it.
2. **Given** the same chunk retrieved via the AI assistant, **When** the answer is displayed with source references, **Then** the chunk's on-screen text shows the original content ("Select Administration > Alarms.") without the contextual prefix appearing in the visible quote.
3. **Given** a document with no identifiable section title (flat structure), **When** the chunk is embedded, **Then** the document title alone is used as the contextual prefix, and retrieval still improves over the no-context baseline.

---

### User Story 2 - Re-indexing existing corpus with contextual embeddings (Priority: P1)

A system administrator needs to apply contextual embeddings to all knowledge already in the system — uploaded documents and product manuals — without losing existing content, references, or upload history. The administrator triggers a re-embedding pass; the system regenerates embeddings for every chunk using the contextual-prefix approach while leaving chunk text, document metadata, and ingestion records untouched. Users querying the system during or after the pass get progressively better retrieval as chunks are updated.

**Why this priority**: Without a re-indexing path, the feature only benefits chunks embedded after the change ships. The bulk of the corpus is already ingested, so the user-facing improvement only lands once existing data is re-embedded.

**Independent Test**: Verify that after a re-embedding run completes, every chunk in the knowledge corpus has a new embedding while its stored text, source-document linkage, page references, and any associated ratings or verifications are preserved.

**Acceptance Scenarios**:

1. **Given** a corpus of already-ingested documents and manuals, **When** the administrator triggers a re-embedding pass, **Then** every chunk's embedding is regenerated using the contextual-prefix approach and the chunk's stored text, source-document linkage, and display references are unchanged.
2. **Given** a re-embedding pass is in progress, **When** a user submits a query, **Then** the query returns results without errors, drawing from whatever embeddings are currently available (partially migrated corpus must remain searchable).
3. **Given** a re-embedding pass fails partway through, **When** the administrator re-runs it, **Then** the pass resumes or safely re-processes remaining chunks without duplicating or corrupting data.

---

### User Story 3 - New ingestion automatically applies contextual embeddings (Priority: P1)

A user uploads a new document, or an administrator ingests a new product manual. The ingestion pipeline automatically prepends the document title and section title to each chunk's text before generating the embedding — no administrator action needed. The resulting chunks benefit from the same retrieval quality improvements as re-embedded legacy content, starting from the moment they are ingested.

**Why this priority**: Without automatic application on new ingestion, every new upload regresses to pre-feature behavior and requires a re-embedding pass to catch up. The feature only stays effective if it is the default for all new content.

**Independent Test**: Upload a new document containing a short, procedurally-worded chunk, then query for it using product- or topic-specific terminology that only appears in the document's title or section heading. Verify the chunk is retrieved.

**Acceptance Scenarios**:

1. **Given** a new document upload, **When** chunking and embedding complete, **Then** each chunk's embedding was generated from contextual text (document title + section title + chunk content), while the stored chunk text matches the source text verbatim.
2. **Given** a new manual ingested by an administrator, **When** chunks are embedded, **Then** the same contextual-prefix rule is applied and retrieval for short generic chunks works on first query — no additional re-embedding step required.

---

### Edge Cases

- **Chunk already contains the document or section title** (e.g., the first chunk of a document opens with the title). The prefix is still applied; duplication in the text used for embedding is acceptable because only embedding quality matters, not readability of the prefixed form.
- **Missing section title**. If the chunk's parent section cannot be determined, the prefix uses only the document title. If neither is available, the chunk is embedded without a prefix (fall back to current behavior) rather than failing.
- **Very long titles**. If the combined prefix + chunk text exceeds the embedding model's input limit, the chunk text is preserved and the prefix is truncated from the front of the title string until it fits.
- **Non-English or mixed-language titles** (Arabic, mixed Arabic/English manuals). The prefix is built from the title text as-stored, without translation or transliteration.
- **Re-embedding partially complete** when a query arrives. The corpus must remain searchable — queries should still return results from whatever embeddings exist, even if some are old-style and some are new-style.
- **Duplicate chunks across documents** (same procedural text appears in two manuals). Each copy is embedded with its own document/section prefix, so each ends up in a different region of the embedding space and is retrieved for the appropriate product/manual query.
- **Display or citation views**. Because the prefix is used only for embedding, source-reference panels, chunk previews, and exported quotes must always show the original stored chunk text.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST, before generating a chunk's embedding, construct an embedding input that prepends the chunk's originating document title and section title to the chunk text, using a consistent delimiter pattern (e.g., `Document Title > Section Title: chunk text`).
- **FR-002**: The contextual prefix MUST be applied identically to both the uploaded-document chunk pipeline and the product-manual chunk pipeline, so retrieval quality is consistent across the two knowledge sources.
- **FR-003**: The system MUST store the chunk's original text unchanged. The contextual prefix is constructed in-memory for embedding only and is NOT persisted as part of the chunk's stored content.
- **FR-004**: When a chunk's source section title is unavailable, the system MUST fall back to document title only. When neither is available, the system MUST embed the chunk text alone (current behavior) and log the fallback.
- **FR-005**: The system MUST apply contextual embedding automatically to every new chunk produced by document upload or manual ingestion — no administrator action or feature-flag toggle required for new content (see also Assumptions).
- **FR-006**: The system MUST provide a re-embedding path for the existing corpus — both document chunks and manual chunks — that regenerates embeddings for all existing chunks using the contextual-prefix approach while leaving chunk text, source-document linkage, page/section references, verification records, ratings, and any other chunk-associated metadata untouched. For manuals, a batch re-embed endpoint MUST be added matching the existing document re-embed pattern.
- **FR-007**: While a re-embedding pass is in progress, the system MUST keep the knowledge corpus searchable — retrieval results may be drawn from a mix of old-style and new-style embeddings during the transition without returning errors to users.
- **FR-008**: When retrieved chunks are shown to users (in source-reference panels, quote previews, or audit views), the system MUST display the chunk's original stored text, NOT the contextual-prefixed form used for embedding.
- **FR-009**: If the combined prefix + chunk text would exceed the embedding model's input length limit, the system MUST preserve the full chunk text and truncate the prefix (from the front of the longer title string) rather than truncating the chunk.
- **FR-010**: The system MUST NOT change query-side behavior — user queries continue to be embedded as-is, without a contextual prefix, because retrieval works by matching a raw query against a context-enriched corpus.
- **FR-011**: The system MUST log enough information per chunk embedding (at minimum: document title used, section title used or "none", whether prefix was truncated) to support post-hoc retrieval-quality debugging without requiring a re-embedding run to reproduce.

### Key Entities *(include if feature involves data)*

- **Knowledge Chunk**: A retrievable unit of text produced by splitting a document or manual. Has stored content (unchanged by this feature), a source document reference, an optional section title, and one embedding vector (regenerated by this feature).
- **Contextual Prefix**: A transient, per-chunk string constructed at embed time from the parent document's title and the chunk's section title. Not persisted. Used exclusively as input to the embedding model.
- **Knowledge Document / Product Manual**: The parent entity whose title seeds the contextual prefix. Already exists in the system; no new attributes required by this feature beyond what is already stored (title, section hierarchy).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a held-out evaluation set of questions where the expected-correct chunk is short, procedural, or generic-looking (length under ~25 words, or heavy in UI/menu terminology), top-5 retrieval accuracy improves by at least 20 percentage points compared to the pre-feature baseline measured on the same queries and corpus.
- **SC-002**: Overall top-5 retrieval accuracy on the full RAG quality test set does not regress (≥ baseline) — the feature improves hard cases without harming queries that already worked.
- **SC-003**: At least 95% of user-visible source-reference panels and chunk-preview displays, sampled after the feature ships, show chunk text identical to the source document — no contextual prefix ever leaks into user-facing views.
- **SC-004**: After a full re-embedding pass completes, 100% of chunks in both the uploaded-document corpus and the product-manual corpus have embeddings generated via the contextual-prefix approach, with zero loss of stored chunk text, source linkage, or chunk-associated metadata (ratings, verifications, page references).
- **SC-005**: During a re-embedding pass, user-facing query success rate (queries that return any result, without error) remains at or above the pre-pass rate — users do not experience a search outage.
- **SC-006**: Fallback behavior (missing section title, prefix truncation) occurs on fewer than 10% of chunks in a typical ingested manual, confirming the document/section metadata is reliable enough for the feature to deliver its intended benefit on the vast majority of content.

## Assumptions

- The existing chunking pipelines for uploaded documents and product manuals already track the chunk's parent document title and, where the source structure permits, an associated section or heading title. The feature uses whatever is currently tracked — it does not require a new pass over document structure beyond what the ingestion pipeline already produces.
- The embedding model currently in use accepts enriched input text and produces embeddings in the same vector space as today. Changing the embedding model itself is out of scope for this feature.
- Re-embedding the existing corpus is an operator-initiated task, run once when this feature ships and again only if the prefix format or embedding model changes. An in-product, real-time "drip" migration is not required.
- The feature applies automatically to all new ingestion with no user-facing toggle. An administrator-level override to disable contextual embeddings is out of scope for v1; if needed, it will be addressed in a follow-up spec.
- Query-side behavior remains unchanged. This feature deliberately does NOT add a query-side transformation (e.g., HyDE already exists as a separate stage and is independent).
- The feature is compatible with, but does not modify, downstream RAG pipeline stages (query rewrite, HyDE, vector search, re-ranking, session compression, cross-manual synthesis, generation). Improvements compound with, but do not depend on, those stages.
- Source-reference rendering is already driven by the chunk's stored text, not by any transient pre-embedding form. No change is needed to display logic — only a guarantee that no implementation shortcut accidentally persists the prefixed form.
- A batch re-embed endpoint for manual chunks is in scope for this spec (matching the existing per-document re-embed endpoint pattern). This ensures the full corpus — both documents and manuals — can be re-embedded without requiring manual deletion and re-upload.
