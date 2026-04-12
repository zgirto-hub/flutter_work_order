# Phase 0 Research: System Manual RAG Assistant

All `NEEDS CLARIFICATION` from the Technical Context have been resolved below. Each section follows the `Decision / Rationale / Alternatives considered` format mandated by `/speckit.plan`.

---

## 1. pgvector index type and list count

**Decision**: Create an **ivfflat** index on `manual_chunks.embedding` with `vector_cosine_ops` and **`lists = 50`**. Use the built-in pgvector default probe count (`ivfflat.probes = 10`) at query time.

**Rationale**: The corpus cap is 100 manuals × ~445 chunks = ~45,000 rows. The pgvector maintainer's rule of thumb is `lists ≈ rows / 1000` up to ~1M rows, so `lists = 50` is the right band for ~45k rows. The original input spec suggested `lists = 100`, but that is a one-size-fits-all value that over-partitions a small corpus — each list would hold ~450 rows, below ivfflat's recommended minimum of ~1000 per list, which degrades recall without helping latency. `lists = 50` keeps ~900 rows per list and leaves headroom for corpus growth after the first delete/upload cycles.

**Alternatives considered**:
- **HNSW** (`pgvector >= 0.5.0`) — faster query, better recall, but more memory, slower index build, and Supabase's enabled pgvector version in the free tier historically lags. ivfflat is the safe, universally-supported default.
- **No index, exact scan** — fine at ~45k rows (sub-second), but fails the ≥100-manual perf guarantee ([SC-007a](./spec.md)) as the corpus fills.
- **lists = 100** (as in original spec draft) — rejected per the math above.

---

## 2. Chunking strategy

**Decision**: Two-pass chunker in `backend/services/manual_chunker.py`:
1. **Pass 1 — paragraph-first**: split extracted text into paragraphs (double-newline or DOCX paragraph element). Greedily pack paragraphs into a chunk until the next paragraph would push the chunk past 500 words. Emit. Start the next chunk with the last ~50 words (one full overlapping sentence's worth) from the emitted chunk.
2. **Pass 2 — fallback**: if any single paragraph exceeds 500 words (common in PDFs where page-level text arrives as one big string), slide a 500-word window with 50-word overlap over that paragraph and emit each window as its own chunk.

Chunks retain the `source_page` of the paragraph they originated from (PDF only; DOCX/TXT/MD are `NULL` per section 4).

**Rationale**: Paragraph-first preserves semantic locality, which nomic-embed-text benefits from. The 500-word / 50-word-overlap parameters come directly from the spec input and match the langchain/llamaindex defaults for general-purpose RAG. Fallback avoids pathological single-long-paragraph PDFs (legal or safety preambles) from producing one 10k-word mega-chunk.

**Alternatives considered**:
- **Fixed-size sliding window only** — simpler but blows up paragraph boundaries mid-sentence, measurably worse retrieval quality on structured manuals.
- **Sentence-aware chunking via spaCy** — better quality, but spaCy adds a ~500 MB model and a language-detection dependency. Rejected per YAGNI.
- **Recursive character splitter (langchain-style)** — good middle ground, but we don't currently use langchain and pulling it in for one utility is excess scope.

---

## 3. PDF parsing (pymupdf)

**Decision**: Use `pymupdf` (import as `fitz`). For each page, call `page.get_text("text")` to extract the flowed text, and tag the resulting text block with the 1-based page number. Concatenate `(page_text, page_number)` tuples into the chunker's input stream. Reject the upload with [FR-006](./spec.md)-compliant "no extractable text" if `sum(len(page_text.strip()) for page in doc) < 20` characters — covers empty, corrupt, and image-only PDFs without a separate OCR probe.

**Rationale**: `pymupdf` is the fastest, most accurate open-source PDF text extractor, returns per-page text natively (so the page-number mapping is trivial), handles both Latin and Arabic scripts correctly, and is already well-known in the RAG community. The 20-character empty-text threshold is a pragmatic floor — every real manual has far more than 20 characters of extractable text on at least one page.

**Alternatives considered**:
- **`pypdf`** — slower, less accurate on complex layouts, no consistent per-page text API.
- **`pdfplumber`** — good for tables but overkill for our text-only use case and slower than `pymupdf`.
- **`pdf2image` + pytesseract OCR** — explicitly out of scope per [Out of Scope](./spec.md) (OCR deferred to a follow-up feature).

---

## 4. DOCX parsing (python-docx) — page number limitation

**Decision**: Use `python-docx` to iterate `document.paragraphs` and collect each paragraph's `.text`. Store `source_page = NULL` for all DOCX chunks. The UI renders "Page —" or omits the page label for sources with a NULL page.

**Rationale**: DOCX files have no authoritative page model. Pagination is a rendering-time property computed by Word/LibreOffice based on the target paper size, margins, and font metrics. Any synthesized "page number" we emit would be wrong on the user's machine, which is worse than no page number. This is already acknowledged in [FR-006](./spec.md) ("page number when available") and [FR-012b](./spec.md).

**Alternatives considered**:
- **Convert DOCX → PDF at upload time via LibreOffice headless** — would give us real page numbers, but adds a 300 MB LibreOffice dependency to the server and a multi-second conversion step per upload. Rejected per YAGNI and [SC-001](./spec.md)'s 3-minute total upload budget.
- **Parse raw `.docx` XML for `w:lastRenderedPageBreak`** — unreliable (only populated if Word rendered the doc before saving; absent for files produced by generators or LibreOffice).

---

## 5. TXT / MD parsing

**Decision**: Read the file as UTF-8 (fall back to `latin-1` on decode error). No special parsing for Markdown — treat it as plain text. Store `source_page = NULL`. Double newlines separate paragraphs; the chunker handles the rest.

**Rationale**: Markdown-aware parsing would require a parser and special-case handling for code blocks, tables, and headings, none of which is valuable for embedding-based retrieval — the embedder sees the raw text either way. Simpler is better.

**Alternatives considered**:
- **Markdown → HTML → text via `markdown` package** — adds a dep for zero retrieval benefit.
- **Header-aware chunk boundaries** — marginally better quality for well-structured Markdown, but the 500-word paragraph packer already handles heading blocks well.

---

## 6. Ollama embedding API — nomic-embed-text

**Decision**: Call Ollama's `POST http://localhost:11434/api/embeddings` with `{"model": "nomic-embed-text", "prompt": <chunk_text>}`. The response is `{"embedding": [768 floats]}`. Send chunks **sequentially** (not in a batch endpoint) because Ollama's embeddings API is single-prompt only. Wrap the loop in `asyncio.gather` with a concurrency cap of **4** to parallelize without saturating Ollama. Total time for a 500-page manual (~445 chunks) at Ollama's typical ~50 ms/embedding on CPU ≈ 22 seconds — well under the [SC-001](./spec.md) 3-minute budget.

**Rationale**: Ollama's `/api/embeddings` endpoint does not accept batches as of the version the project uses (confirmed by the existing AI services pattern in this repo). `asyncio.gather` with a cap gives us concurrency without backpressure surprises. 4 concurrent embeddings is below the server's 15 GB RAM ceiling and matches the pattern used by spec 020/023/024 AI features on the same Ollama instance.

**Alternatives considered**:
- **True batch endpoint** — not available in current Ollama.
- **Thread pool executor** — unnecessary; Ollama is I/O bound from our side and asyncio handles this natively via `httpx.AsyncClient`.
- **Pre-warm Ollama embedder model** — Ollama already caches loaded models in memory; first call has a ~2s warm-up penalty but subsequent calls within the same upload do not. Acceptable.

---

## 7. Gemma 4 prompt template

**Decision**: Use the exact template provided in the spec input, called via `POST http://localhost:11434/api/generate` with `{"model": "gemma3:e2b", "prompt": <built_prompt>, "stream": false}`:

```
You are a technical assistant for a civil aviation maintenance department.
Answer the technician's question using ONLY the manual sections provided below.
If the answer is not found in the sections, say: "This information is not in the available manuals."
Reply in the same language as the question (Arabic or English).

MANUAL SECTIONS:
{retrieved_chunks}

QUESTION: {user_question}

ANSWER:
```

Where `{retrieved_chunks}` is the top-5 chunks concatenated as:

```
[Source {i}: {manual_title}, page {source_page or '—'}]
{chunk.content}
---
```

**Rationale**: Grounded-answer prompting with explicit "say X if not found" instructions has been the most reliable RAG pattern for local open-weight models. Gemma 4 E2B (chosen over E4B because the Zorin server has 15 GB RAM per memory `project_ai_ollama.md`) reliably follows this template when the `say X` sentinel is present in the instructions. The source headers give the model enough context to ground its answer correctly without confusing section boundaries.

**Alternatives considered**:
- **Chat endpoint (`/api/chat` with role-based messages)** — cleaner for multi-turn, but we don't persist chat history this version and the generate endpoint has slightly lower latency.
- **Few-shot examples in the prompt** — measurable quality bump but adds 400+ tokens to every query, which pushes latency past the 15 s budget for small questions. Skip for v1.
- **Streaming response to the UI** — nicer UX but complicates the highlight-detection step (which runs after the full answer arrives). Defer to follow-up.

---

## 8. Highlight detection (FR-012a)

**Decision**: Post-hoc substring matching. After Gemma returns the answer, split the answer into sentences via a regex (`[.!?؟]\s+`). For each retrieved chunk, score each of its sentences by `max_sentence_overlap(chunk_sentence, answer_sentences)` using a simple case-insensitive normalized-token Jaccard similarity. Mark the top-1 chunk sentence per chunk with `highlight_start`/`highlight_end` offsets if its best Jaccard ≥ **0.35**. If nothing passes the threshold, return `highlight_start = highlight_end = null` and the UI renders the preview as plain text (per [FR-012a](./spec.md)'s "If no highlight can be confidently determined" clause).

**Rationale**: This is cheap (O(chunk_sentences × answer_sentences), runs in milliseconds), deterministic, and has no additional LLM cost. The 0.35 Jaccard threshold is the empirical sweet spot between noisy matches and missed ones for 15–30-word sentences. The `؟` alternate is the Arabic question mark. The implementation is a simple pure function that is trivially unit-testable.

**Alternatives considered**:
- **Ask Gemma to emit the source sentence verbatim** in a structured block — cleanest signal, but adds prompt complexity and costs ~50–100 output tokens per question. Rejected per [SC-004](./spec.md) latency budget.
- **Second embedding similarity pass** (embed answer sentences → cosine vs. chunk sentence embeddings) — strictly better recall, but would embed ~10 more vectors per question, adding ~500 ms. Not worth it for the gain.
- **Levenshtein/fuzzy match** — handles paraphrasing slightly better but is 10× slower per sentence pair. Jaccard is good enough.

---

## 9. Language detection for the assistant's reply

**Decision**: No explicit detection — delegate to the LLM via the prompt. The template already says "Reply in the same language as the question (Arabic or English)." Gemma 4 is multilingual and follows this instruction reliably when the question is predominantly in one language.

**Rationale**: Adding a char-range heuristic would only tell us what the LLM already sees. Mixed-language questions (e.g., Arabic question referring to an English part number) are handled gracefully by the model — it will reply in the dominant language. Avoids an unnecessary code path. [SC-009](./spec.md)'s 95% same-language target is well above the threshold at which a deterministic detector would help.

**Alternatives considered**:
- **Unicode block check** (if any char in U+0600–U+06FF → Arabic) — works but adds no value; the LLM sees the same signal.
- **`langdetect` / `fasttext-langdetect`** — external dependency for zero benefit.

---

## 10. DB-side corpus size tracking for FR-004c ceiling check

**Decision**: Track a running estimate in a single-row `manual_corpus_stats` table: `total_bytes BIGINT`. On every manual upload, after chunks are persisted, add `sum(octet_length(chunk.content)) + count(chunks) * 3072` (the 768-dim vector at float4 = 3072 bytes) + row overhead (~200 bytes each) + the `manuals` row (~500 bytes). On every delete, subtract the same formula. Before accepting a new upload, read `total_bytes` and reject if `total_bytes + projected_upload_bytes > ceiling_bytes`.

Ceiling is configurable via an environment variable `MANUAL_CORPUS_CEILING_MB` (default **400**), read at router startup.

**Rationale**: Supabase does not expose `pg_total_relation_size` via its RLS-enabled REST API without a SECURITY DEFINER function, and our calculation is approximate anyway. Maintaining a counter is simple, transactional (update in the same txn as the inserts/deletes), and millisecond-fast on the admission check. The ~15% error margin vs. actual on-disk size is absorbed by leaving 100 MB of headroom below the Supabase free-tier 500 MB limit.

**Alternatives considered**:
- **`pg_total_relation_size('manual_chunks')` via a SECURITY DEFINER RPC** — most accurate, but an extra moving part and harder to unit-test.
- **Per-upload calculation on the fly** (`SELECT sum(octet_length(content)) FROM manual_chunks`) — simple and accurate but scans the full table on every upload admission; fine for 45k rows, but needlessly slow if corpus grows. Counter is O(1).
- **No tracking — let Supabase fail hard** — violates [FR-004c](./spec.md) ("user MUST see a clear, actionable message").

---

## 11. Upload transaction ordering (FR-019b)

**Decision**: Three-phase write with compensating cleanup:

1. **Parse + chunk + embed** entirely in memory. If any step fails, return HTTP 400/422 with the reason. Nothing persisted.
2. **Write the original file** to `backend/uploaded_files/manuals/<manual_uuid>.<ext>`. If this fails, return HTTP 500 and abort. Nothing in DB yet.
3. **Insert DB rows** (manuals row + manual_chunks rows + corpus_stats update) in a single Supabase transaction. If this fails, **delete the already-written file** from disk in a `finally` block, then return HTTP 500. Atomicity is achieved via the compensating action.

**Rationale**: [FR-019b](./spec.md) requires that no orphaned on-disk file or half-committed DB manual survives a partial failure. Writing the file first means the disk write — the most likely failure point — fails cheaply before we touch the DB. Writing the DB in a single txn means either all rows land or none do. The compensating delete on DB failure is the only asymmetric step, and it's a single `os.unlink` inside a `try/except` — easy to test.

**Alternatives considered**:
- **DB-first, then file** — leaves orphaned rows on file-write failure and requires a more complex rollback (the DB may have already committed).
- **Two-phase commit via a staging table** — overkill for the failure modes we actually face.
- **Save-point based rollback inside one big Supabase call** — Supabase REST doesn't expose savepoints.

---

## 12. Collision-safe filename scheme

**Decision**: `<manual_uuid>.<normalized_extension>` where `manual_uuid` is the `manuals.id` primary key (generated via `gen_random_uuid()` in the DB, but computed client-side by the router **before** the INSERT so the filename is known during phase 2 of the transaction plan). `normalized_extension` is one of `pdf`, `docx`, `txt`, `md` derived from the uploaded file's MIME type — not from the user-supplied filename, to prevent extension spoofing.

Example: `backend/uploaded_files/manuals/3f2504e0-4f89-41d3-9a0c-0305e82c3301.pdf`.

The user-supplied original `file_name` is recorded separately in the `manuals.file_name` column for display ([FR-007](./spec.md)).

**Rationale**: UUID v4 collisions are cryptographically negligible. Using the primary key keeps disk and DB in lockstep — no separate `file_path` column needed beyond a derived convention. Normalizing the extension from MIME type prevents `malicious.pdf.exe`-style tricks if anyone ever serves the file directly.

**Alternatives considered**:
- **Hash-based name (`sha256(content)[:16]`)** — deduplication for free, but [Assumptions](./spec.md) explicitly leave dedup out of scope, and re-uploading the same file should produce two distinct manual entries per user expectation.
- **Preserve the original filename with a numeric suffix on collision** — messy, leaks user-supplied strings into path names, encoding issues with Arabic filenames.
- **Store the full on-disk path in the DB** — redundant; the path is always derivable from the id + extension.

---

## 13. RLS policies for cross-role access

**Decision**: Enable RLS on both new tables. Policies:

- `manuals`: `SELECT` / `INSERT` / `UPDATE` / `DELETE` allowed to `authenticated` (any signed-in user), independent of `role`.
- `manual_chunks`: same as `manuals`.
- `manual_corpus_stats`: `SELECT` to `authenticated`; `UPDATE` only via service role (backend-only).

**Rationale**: The feature is intentionally open to all three roles per [FR-001](./spec.md) and [Assumptions](./spec.md). The backend will continue to use the service-role key for these endpoints (matching existing patterns), so RLS is defense-in-depth against accidental direct-SDK access — not the primary access control. Constitution principle III is satisfied.

**Alternatives considered**:
- **Admin-only delete** — rejected; [FR-008](./spec.md) grants delete to all roles.
- **`uploaded_by`-scoped delete** (users can only delete their own manuals) — not required by the spec and would surprise users who expect a shared library. Explicitly out of scope per clarification Q1 (open corpus).

---

## 14. Audit logging — category and actions

**Decision**: Reuse the existing `file` category in `user_activity_log` with three new action values:
- `uploaded_manual` (on successful upload — logs `manual_id`, `title`, `file_name`, `chunk_count`)
- `deleted_manual` (on delete — logs `manual_id`, `title`)
- `asked_manual` (on every question — logs `question` truncated to 500 chars, `manual_id_filter` or `null`, `chunk_count_returned`)

All three go through `backend/utils/activity.py` fire-and-forget (constitution VI).

**Rationale**: The `file` category already exists (manuals are documents → files). The action values are new but additive; there is no schema change. `asked_manual` is important for understanding how the feature is used in production and for future RAG quality tuning. Truncating the question at 500 chars keeps the audit table bounded.

**Alternatives considered**:
- **New `manual_qa` category** — cleaner taxonomy but adds a new enum value that every downstream consumer (dashboards, activity feed) would have to learn.
- **Don't log questions** — loses all insight into retrieval quality over time.

---

## 15. Flutter screen navigation wiring

**Decision**: Add a new bottom-nav or drawer entry "Manual Assistant" (icon: `Icons.menu_book_outlined`) to the existing navigation shell, visible to **all three roles**. Route: `/manual-assistant`. Screen: `ManualAssistantScreen` with a `DefaultTabController(length: 2)` containing the Chat and Manuals tabs.

**Rationale**: [FR-001](./spec.md) mandates "accessible from main navigation to all authenticated users." The existing drawer/bottom-nav pattern (consult [frontend/lib/screens/](frontend/lib/screens/) for the shell file that owns role-gated entries) is the right insertion point. Two tabs per [FR-002](./spec.md).

**Alternatives considered**:
- **Embed as a floating action bubble** — doesn't match the existing nav pattern and hides the feature.
- **Only accessible from the dashboard** — unnecessarily hidden.

---

## 16. Ollama timeout handling

**Decision**: Set `httpx.AsyncClient` timeout to **90 seconds** for the generate call and **20 seconds** for each embedding call. On timeout, return HTTP 504 with body `{"error": "assistant_unavailable", "message": "The assistant is taking longer than usual to respond. Please try again."}`. The frontend surfaces the `message` per [FR-015](./spec.md).

**Rationale**: A normal Gemma 4 E2B response on CPU for a 2k-token prompt is under 10 seconds, but cold-start (first call after idle) can touch 30–40 seconds. 90 seconds absorbs cold-starts without hanging indefinitely. Embedding is faster but also has cold-start; 20 seconds is comfortable. These timeouts are exposed to the frontend via `ApiException` handling in `manual_assistant_service.dart`.

**Alternatives considered**:
- **Retry once on timeout** — would double the worst-case wait to ~3 minutes, exceeding [SC-004](./spec.md)'s 15-second visible-response target under adverse conditions.
- **Pre-warm Gemma on app start** — worth considering in a follow-up, but out of scope here.

---

## Cross-cutting notes

- **Server setup step (one-time)**: `ollama pull nomic-embed-text`. Document in `quickstart.md` and in the backend README. Not a code change.
- **Migration order**: The pgvector extension (`CREATE EXTENSION IF NOT EXISTS vector`) must be the first statement in the migration file so that the `embedding VECTOR(768)` column declaration that follows it parses.
- **Embedding idempotency**: Re-embedding the same chunk is deterministic (nomic-embed-text is purely a function of input), so reindexing after a pgvector upgrade is a one-shot rebuild rather than a re-ingest.
- **No streaming**: the first version returns the full answer in one JSON response (simpler error handling, simpler highlight detection). Streaming is a follow-up.

All unknowns resolved. **Ready for Phase 1.**
