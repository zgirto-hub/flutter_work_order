# Research: Smart Document Preprocessing

**Feature**: 073-smart-doc-preprocess  
**Date**: 2026-04-16

## R-001: Preprocessing Insertion Point in Document Pipeline

**Decision**: Insert preprocessing between text extraction and section detection in `document_service.py:index_document()`. The function currently flows: extract text → detect sections → create parent chunks → split children → embed. Preprocessing transforms the raw page text before it enters section detection.

**Rationale**: Preprocessing at the page level (before chunking) ensures the enriched Markdown flows through the entire existing chunking pipeline without modifying chunking logic. The section detector and child splitter operate on the preprocessed text, producing richer child chunks that embed better.

**Alternatives considered**:
- Post-chunk preprocessing (enrich each child chunk individually): Rejected — higher API call volume, loses page-level context that the model needs to expand terse bullets meaningfully.
- Pre-extraction preprocessing (send raw PDF bytes to AI): Rejected — the AI model works on text, not binary; text extraction must happen first.

## R-002: AI Provider for Preprocessing

**Decision**: Use Gemini Flash directly via the existing `gemini.py` provider, but called as a standalone service function rather than through the Q&A resolver. Create a lightweight `document_preprocessor.py` service that imports the Gemini SDK directly.

**Rationale**: The Q&A resolver adds fallback logic, latency tracking, and provider switching that are designed for conversational use. Preprocessing is a batch operation where: (a) fallback should be "use raw text" not "try another model," (b) the provider is fixed (Gemini Flash — fast and cheap), and (c) timeout/retry semantics differ. A dedicated service function keeps concerns separated.

**Alternatives considered**:
- Reuse the resolver's `generate()`: Rejected — would route through fallback chain to local Ollama, which is slower and may produce lower-quality preprocessing.
- Add a `preprocess()` method to the AIProvider base class: Rejected — over-engineering per constitution principle VII (YAGNI). Only one provider is used for preprocessing.

## R-003: Raw Text Retention Strategy

**Decision**: Add a `raw_content` text column to `document_chunks` for child chunks. Parent chunks already store their section text in `content`; child chunks will now have `raw_content` (original) and `content` (preprocessed). For the legacy `manual_chunks` table, add the same `raw_content` column.

**Rationale**: Per-chunk retention (not per-page) is needed because the chunking pipeline may split a page differently after preprocessing vs. before. Storing raw text at the chunk level enables future re-preprocessing by iterating over chunks rather than re-extracting from PDFs.

**Alternatives considered**:
- Per-page raw text in a separate table: Rejected — adds a join and doesn't align with the chunk-level granularity needed for re-processing.
- Store raw text in the parent chunk only: Rejected — child chunks are the searchable units; re-processing needs to map raw → preprocessed at the child level.

## R-004: Preprocessing Prompt Design

**Decision**: Use a system prompt that instructs the model to:
1. Rewrite terse bullet points into complete, self-contained sentences
2. Preserve all original factual content — no hallucination
3. Add implicit context (e.g., if a slide title says "APU Troubleshooting" and a bullet says "Check oil pressure," expand to "During APU troubleshooting, check the oil pressure...")
4. Output clean Markdown with headings preserved
5. For already-rich prose, return the text with minimal cleanup (whitespace normalization, consistent heading levels)

**Rationale**: The prompt must handle two extremes — terse slides and dense manuals — without a mode switch. Instructing the model to expand terse content while leaving rich content alone achieves this naturally. Gemini Flash is capable of following these nuanced instructions.

**Alternatives considered**:
- Two-pass approach (classify page type first, then preprocess): Rejected — adds latency and complexity for minimal benefit. The model can handle both cases in a single pass.
- Template-based expansion (no AI): Rejected — cannot infer context from slide titles or surrounding content.

## R-005: Status Tracking for Preprocessing

**Decision**: Add `'preprocessing'` to the `knowledge_documents.status` CHECK constraint. The pipeline becomes: `pending` → `preprocessing` → `indexing` → `ready`/`failed`. The frontend already polls status every 3 seconds and stops on terminal states — it only needs to display the new status string.

**Rationale**: Minimal change to existing infrastructure. The frontend status display and polling logic work unchanged; only the status label rendering needs updating to show "Preprocessing..." for the new state.

**Alternatives considered**:
- Progress percentage (e.g., "preprocessing 15/30 pages"): Deferred — nice-to-have but adds complexity. The status field is a simple string; percentage tracking would require additional columns or response fields. Can be added later.

## R-006: Admin Toggle Mechanism

**Decision**: Add `'smart_preprocessing_enabled'` key to `app_settings` table (default `'true'`). Query via existing `get_setting()` at the start of `index_document()`. Expose toggle via existing admin settings UI pattern.

**Rationale**: Follows the exact same pattern as `'ai_provider'` setting from spec 063. No new infrastructure needed.

**Alternatives considered**:
- Environment variable: Rejected — requires server restart to change. Settings table allows runtime toggling.
- Per-document toggle: Rejected — YAGNI. Bulk on/off is sufficient for the current need.

## R-007: Legacy Manuals Pipeline Integration

**Decision**: Add preprocessing to `manual_rag_service.upload_manual()` following the same pattern as the knowledge documents pipeline. The manual upload flow extracts text via `manual_parser.py`, then chunks via `manual_chunker.py`. Preprocessing inserts between extraction and chunking.

**Rationale**: Both pipelines serve the same search system. Inconsistent search quality between "manuals" and "knowledge documents" would confuse users.

**Alternatives considered**:
- Knowledge documents only: Rejected — spec clarification explicitly requires both pipelines.
- Migrate manuals to knowledge documents pipeline first: Rejected — separate concern, out of scope for this spec.

## R-008: Rate Limiting and Batch Processing

**Decision**: Process pages sequentially with a configurable delay between API calls (default: no delay, rely on Gemini Flash rate limits which are generous). If a rate limit error is detected (HTTP 429), back off exponentially starting at 2 seconds, max 3 retries per page. On persistent failure, fall back to raw text for that page.

**Rationale**: Gemini Flash has generous rate limits (typically 1500 RPM for pay-as-you-go). Sequential processing of a 100-page document at 1-2 seconds per page means ~50-100 calls over 2-3 minutes — well within limits. Explicit retry logic handles transient rate limits without over-engineering.

**Alternatives considered**:
- Parallel processing (e.g., 5 pages at once): Rejected — increases rate limit risk and complexity for marginal time savings on a background task.
- Pre-flight rate limit check: Rejected — YAGNI. Handle errors when they occur.
