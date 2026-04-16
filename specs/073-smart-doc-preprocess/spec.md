# Feature Specification: Smart Document Preprocessing

**Feature Branch**: `073-smart-doc-preprocess`  
**Created**: 2026-04-16  
**Status**: Draft  
**Input**: User description: "Build Spec 073: Smart Document Preprocessing — when a PDF is uploaded, send each page's raw text through Gemini Flash to produce clean structured Markdown before chunking and embedding. This fixes the search quality issue where terse slide bullet points don't embed well."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Slide-Deck PDF Produces Searchable Chunks (Priority: P1)

A maintenance engineer uploads a vendor slide deck (e.g., "Boeing 737 APU Troubleshooting") to the knowledge base. Today, terse bullet points like "Check oil pressure — replace filter if low" yield poor search results because the short, context-free text does not embed meaningfully. With smart preprocessing, each page's raw text is expanded into clean, structured Markdown that preserves the original meaning while adding enough context for the embedding model to produce high-quality vectors. The engineer later searches "how to diagnose APU oil pressure problems" and finds the relevant slide.

**Why this priority**: This is the core value proposition — fixing the search quality gap for the most common document type (vendor slide decks) that currently produces poor results.

**Independent Test**: Upload a real slide-deck PDF, then search for a concept described only via terse bullets on one slide. Verify the relevant chunk ranks in the top 3 results.

**Acceptance Scenarios**:

1. **Given** a slide-deck PDF with terse bullet points is uploaded, **When** the system processes the document, **Then** each page's raw text is sent through an AI model to produce structured Markdown before chunking and embedding.
2. **Given** a preprocessed slide-deck PDF, **When** a user searches for a concept described only in terse bullets, **Then** the relevant chunk appears in the top 5 search results (compared to not appearing at all without preprocessing).
3. **Given** a page with fewer than 50 characters of extractable text (e.g., title-only slide), **When** preprocessing runs, **Then** the page is skipped (not sent to the AI model) consistent with current behavior.

---

### User Story 2 - Dense Technical Manuals Remain Unharmed (Priority: P1)

A maintenance engineer uploads a well-structured technical manual (200+ pages of full prose paragraphs with headings). The preprocessing step recognizes that the text is already rich and well-structured and either passes it through with minimal transformation or applies light cleanup only. The existing search quality for dense manuals is not degraded.

**Why this priority**: Equal priority to Story 1 because degrading search quality for manuals that already work well would be a regression.

**Independent Test**: Upload a dense prose manual, run the same set of test queries used before the feature, and verify search result rankings are equal or better.

**Acceptance Scenarios**:

1. **Given** a page of dense prose (multiple full paragraphs, > 500 characters), **When** preprocessing runs, **Then** the output preserves the original content and structure without introducing hallucinated information.
2. **Given** a manual with clear headings and well-formed paragraphs, **When** preprocessing runs, **Then** the resulting Markdown retains the heading hierarchy and paragraph boundaries.

---

### User Story 3 - Preprocessing Status Visible During Upload (Priority: P2)

When a user uploads a document, the upload progress indicator shows that preprocessing is happening. The user understands the system is doing extra work to improve search quality and is not stuck.

**Why this priority**: Important for user experience — preprocessing adds processing time and users need feedback — but not critical to the core search-quality improvement.

**Independent Test**: Upload a 30-page slide deck and observe the UI shows a preprocessing status message before the document transitions to "ready."

**Acceptance Scenarios**:

1. **Given** a document is uploaded, **When** preprocessing begins, **Then** the document status reflects that preprocessing is in progress (distinct from "pending" and "indexing").
2. **Given** preprocessing completes for all pages, **When** the system transitions to chunking and embedding, **Then** the status updates accordingly.
3. **Given** the AI preprocessing service is unavailable, **When** a document is uploaded, **Then** the system falls back to the current behavior (raw text chunking) and the document still becomes searchable.

---

### User Story 4 - Administrator Toggles Preprocessing On/Off (Priority: P3)

An administrator can enable or disable smart preprocessing from the settings. When disabled, the upload pipeline uses the current raw-text chunking behavior. This allows the admin to control costs or disable the feature if the external AI service is unavailable.

**Why this priority**: Nice-to-have control mechanism; the system already has graceful fallback when the AI service is down, so a manual toggle is a convenience rather than a necessity.

**Independent Test**: Toggle preprocessing off in settings, upload a document, verify no AI preprocessing calls are made. Toggle back on, upload another document, verify preprocessing occurs.

**Acceptance Scenarios**:

1. **Given** preprocessing is disabled in settings, **When** a document is uploaded, **Then** the system uses the existing raw-text chunking pipeline with no AI calls.
2. **Given** preprocessing is enabled (default), **When** a document is uploaded, **Then** the system sends each page through AI preprocessing before chunking.

---

### Edge Cases

- What happens when a page contains only images and no extractable text? The page is skipped (no text to preprocess).
- What happens when the AI model returns an empty or malformed response for a page? The system falls back to using the raw extracted text for that page.
- What happens when the AI service times out mid-document (e.g., after processing 15 of 30 pages)? Pages that were successfully preprocessed use the enhanced text; remaining pages fall back to raw text. The document still completes indexing.
- What happens when the uploaded document is not a PDF (e.g., TXT, DOCX, MD)? Preprocessing is applied to all document types, not just PDFs, since the same quality issue can affect any document with sparse text.
- What happens when preprocessing produces text significantly longer than the original? The chunking system handles it normally — longer text simply produces more child chunks.
- What happens with very large documents (100+ pages)? Pages are processed sequentially or in controlled batches to avoid overwhelming the AI service or hitting rate limits.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST send each page's raw extracted text through an AI model to produce clean, structured Markdown before the text enters the chunking pipeline.
- **FR-002**: The AI preprocessing prompt MUST instruct the model to expand terse bullet points into self-contained, context-rich sentences while preserving all original factual content.
- **FR-003**: The AI preprocessing prompt MUST instruct the model NOT to hallucinate, invent, or add information that is not present or directly implied by the original text.
- **FR-004**: System MUST skip preprocessing for pages with fewer than 50 characters of extractable text (consistent with current page-skip behavior).
- **FR-005**: System MUST fall back to raw extracted text for any page where AI preprocessing fails (timeout, error, empty response, malformed output).
- **FR-006**: System MUST fall back to the entire raw-text pipeline (no preprocessing) when the AI service is completely unavailable at upload time.
- **FR-007**: The document status MUST reflect a "preprocessing" state while AI enrichment is in progress, distinct from "pending" and "indexing."
- **FR-008**: System MUST allow an administrator to enable or disable smart preprocessing via a system setting.
- **FR-009**: When preprocessing is disabled, the upload pipeline MUST behave identically to the current implementation (no AI calls, no additional latency).
- **FR-010**: System MUST apply preprocessing to all supported document types (PDF, DOCX, TXT, MD), not only PDFs.
- **FR-011**: System MUST process pages sequentially or in controlled batches to respect AI service rate limits and avoid overloading the service.
- **FR-012**: The preprocessed Markdown MUST be stored as the chunk content used for embedding and search, so that all downstream operations (search, display, retrieval) benefit from the enriched text.
- **FR-013**: The system MUST retain the original raw extracted text alongside the preprocessed Markdown for each page, enabling future re-preprocessing, quality comparison, and debugging without re-extracting from the source file.
- **FR-014**: Smart preprocessing MUST apply to newly uploaded documents only. Already-indexed documents retain their existing chunks unchanged.
- **FR-015**: The preprocessing pipeline MUST be designed as a separable stage so that retroactive re-processing of existing documents can be added in a future iteration without architectural changes.
- **FR-016**: Preprocessing MUST use a dedicated fast/cheap AI provider, independent of the active Q&A provider setting. This avoids routing batch workloads through slow or expensive conversational models.

### Key Entities

- **Preprocessed Page**: A page of a document whose raw extracted text has been transformed into structured Markdown by the AI model. Attributes: original raw text (retained for re-preprocessing and quality auditing), preprocessed Markdown output (used for chunking and embedding), page number, preprocessing status (success/fallback).
- **Preprocessing Setting**: A system-level toggle controlling whether smart preprocessing is active. Part of the existing system settings mechanism.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Search queries against slide-deck documents return relevant results in the top 5 at least 80% of the time, compared to the current baseline where terse bullet content frequently fails to surface.
- **SC-002**: Search quality for dense prose manuals does not degrade — result rankings for a standard set of test queries remain equal or improve after preprocessing is applied.
- **SC-003**: Document upload and indexing completes within 3x the current processing time (e.g., if a 30-page document currently takes 20 seconds, it should complete in under 60 seconds with preprocessing enabled).
- **SC-004**: When the AI preprocessing service is unavailable, 100% of document uploads still complete successfully using the fallback raw-text pipeline.
- **SC-005**: Users can see the preprocessing status during upload, reducing confusion about processing time by providing clear progress feedback.

## Clarifications

### Session 2026-04-16

- Q: Should the system retain the original raw text alongside the preprocessed Markdown, or discard it after preprocessing? → A: Retain original raw text alongside preprocessed Markdown per chunk/page (enables re-preprocessing, quality auditing, and debugging).
- Q: Should already-indexed documents be re-processable with preprocessing, or new uploads only? → A: New uploads only, but design the pipeline so retroactive re-processing is easy to add later.
- Q: Should preprocessing use the active AI provider from the resolver or a dedicated fast/cheap provider? → A: Always use a specific fast/cheap provider for preprocessing, independent of the Q&A provider setting.

## Assumptions

- The existing AI provider infrastructure (spec 063) will be leveraged for API key configuration, but preprocessing uses a dedicated fast/cheap provider rather than the active Q&A provider.
- The `GEMINI_API_KEY` environment variable is already configured on the server (required by spec 063).
- Preprocessing latency per page is acceptable (estimated 1-3 seconds per page) given the batch/background nature of document indexing.
- The existing `app_settings` table (from spec 063) will be used to store the preprocessing toggle, following the same key-value pattern.
- The embedding model benefits from richer input text — structured Markdown with expanded context produces higher-quality embeddings than terse bullet points.
- Rate limits on the AI service are sufficient for the expected document upload volume (a few documents per day, not bulk ingestion).
- Both document pipelines (knowledge documents and legacy manuals) should receive preprocessing to ensure consistent search quality across the unified knowledge base.
