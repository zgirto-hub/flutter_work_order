# Tasks: Contextual Embeddings

**Input**: `/specs/075-contextual-embeddings/plan.md` + `research.md` + `data-model.md` + `contracts/api.md` + `spec.md`
**Implementer**: opencode
**Reviewer after implementation**: Claude Code (superpowers code review)
**Branch**: `075-contextual-embeddings` (`git checkout 075-contextual-embeddings` before starting)

## Implementer orientation (read before T001)

This feature adds a contextual prefix (document title + section title) to chunk text before embedding, improving retrieval quality. The prefix is transient — NEVER stored. Read these files before coding:

1. Read `plan.md` and `research.md` (R-001 through R-008) end-to-end
2. Read the current contents of these files; do not edit yet:
   - `backend/services/document_service.py` (specifically `index_document()`, lines ~60–140)
   - `backend/services/manual_rag_service.py` (specifically `upload_manual()`, lines ~280–400)
   - `backend/services/ollama_embedder.py` (the `embed_single()` and `embed_many()` signatures)
   - `backend/routers/documents.py` (specifically `re_embed_all_chunks()`, lines ~817–859)
   - `backend/routers/manuals.py` (for the endpoint pattern)
3. Note the key invariant: **chunk `content` column must NEVER contain the prefix**. The prefix is built in-memory, passed to the embedder, then discarded.

## Guardrails (opencode must follow)

- **Do NOT modify** the `content` field stored in any database table — the prefix is for embedding input ONLY
- **Do NOT modify** `ollama_embedder.py` — the embedder stays generic; prefix construction lives in the callers
- **Do NOT modify** search RPCs or retrieval logic — query-side embedding stays unchanged (FR-010)
- **Do NOT modify** any frontend code — this is backend-only
- **Do NOT add** new database columns, tables, or migration files — no schema changes
- **Do NOT commit** `backend/version.json`
- Match existing code style — look at surrounding code before writing
- If pytest collects but pre-existing tests fail for unrelated reasons, note it in the final report
- Commit each phase separately with a descriptive message
- Do NOT push to remote

---

## Phase A — Foundational: Shared Prefix Helper (T001)

**Purpose**: Create the shared prefix builder used by all subsequent tasks.

- [ ] T001 Create `backend/services/contextual_prefix.py` with a function `build_contextual_prefix(doc_title: str | None, section_title: str | None = None) -> str` that:
  1. If `doc_title` is None, empty, or whitespace-only: return `""` (no prefix, graceful degradation per FR-006)
  2. Strip `doc_title` of leading/trailing whitespace
  3. If `section_title` is provided, non-empty, and non-whitespace: return `f"{doc_title} > {section_title}: "`
  4. Otherwise: return `f"{doc_title}: "`
  5. Add a second function `apply_contextual_prefix(content: str, doc_title: str | None, section_title: str | None = None, max_chars: int = 30000) -> str` that:
     - Calls `build_contextual_prefix(doc_title, section_title)` to get the prefix
     - If `prefix` is empty: return `content` unchanged
     - If `len(prefix) + len(content) > max_chars`: truncate the prefix from the left (remove characters from the beginning of `doc_title`) until it fits, then rebuild. If even a minimal prefix ("...: ") would exceed the limit, return `content` unchanged
     - Otherwise: return `prefix + content`
     - Import `logging` and log a warning when truncation occurs (FR-009, FR-011)
  6. Add module-level `import logging` and `logger = logging.getLogger(__name__)`
  7. Keep the file minimal — no classes, no external imports beyond `logging`

**Done when**: `python -c "from backend.services.contextual_prefix import build_contextual_prefix, apply_contextual_prefix; print('OK')"` succeeds.

**Checkpoint**: Shared helper is ready. All subsequent tasks import from this module.

---

## Phase B — User Story 1: Document Chunk Pipeline (Priority: P1)

**Goal**: New document uploads embed chunks with contextual prefixes. Existing documents can be re-embedded.

**Independent Test**: Upload a document, check server logs for the contextual prefix being applied. Search for a topic using the document title — verify improved chunk ranking.

### Implementation for User Story 1

- [ ] T002 [US1] Modify `backend/services/document_service.py` to apply contextual prefix during initial document indexing. In the `index_document()` function:
  1. Add `from services.contextual_prefix import apply_contextual_prefix` at the top of the file
  2. Find where child chunk texts are collected for embedding (the list of texts passed to `embed_many()`). This is around lines 122–129.
  3. BEFORE calling `embed_many(texts)`, build a new list `prefixed_texts` where each text is transformed via `apply_contextual_prefix(content=chunk_content, doc_title=display_name, section_title=section_title)`:
     - `display_name` is the document's display name, already available in scope (fetched at the start of `index_document()`)
     - `section_title` comes from each chunk's parent section — it's stored on the chunk dict during section detection (the `section_title` field)
  4. Pass `prefixed_texts` to `embed_many()` instead of the original texts
  5. The chunk rows inserted into the database MUST still use the ORIGINAL `content` text — do NOT store the prefixed version
  6. Add a `logger.info(f"Embedding {len(prefixed_texts)} chunks with contextual prefix for document '{display_name}'")` for observability (FR-011)

- [ ] T003 [US1] Modify `backend/routers/documents.py` to apply contextual prefix during re-embedding. In the `_re_embed_task()` inner function (inside `re_embed_all_chunks()`, around lines 835–855):
  1. Add `from services.contextual_prefix import apply_contextual_prefix` at the top of the file
  2. At the start of `_re_embed_task()`, fetch the document's `display_name` from the `knowledge_documents` table: `doc_resp = supabase.table("knowledge_documents").select("display_name").eq("id", document_id).execute()` and extract `display_name = doc_resp.data[0]["display_name"] if doc_resp.data else ""`
  3. In the loop where each chunk is re-embedded, change `emb = await embed_single(chunk["content"])` to `prefixed = apply_contextual_prefix(content=chunk["content"], doc_title=display_name, section_title=chunk.get("section_title"))` then `emb = await embed_single(prefixed)`
  4. The database update still writes the embedding to the chunk row — the `content` field is NOT modified
  5. To get `section_title` in the query, update the select to include it: `.select("id, content, section_title")`

**Checkpoint**: Document chunk pipeline complete. New uploads and re-embeds use contextual prefixes. Stored content unchanged.

---

## Phase C — User Story 2: Manual Chunk Pipeline (Priority: P1)

**Goal**: New manual uploads embed chunks with contextual prefixes. A new re-embed endpoint allows batch re-embedding of existing manuals.

**Independent Test**: Upload two manuals with overlapping terms but different titles. Search using one manual's domain terminology — verify correct manual's chunks rank higher.

### Implementation for User Story 2

- [ ] T004 [US2] Modify `backend/services/manual_rag_service.py` to apply contextual prefix during manual upload. In the `upload_manual()` function:
  1. Add `from services.contextual_prefix import apply_contextual_prefix` at the top of the file
  2. Find where chunk texts are collected for embedding (around lines 322–327, the list passed to `embed_many()`)
  3. BEFORE calling `embed_many(texts)`, build `prefixed_texts` where each text is `apply_contextual_prefix(content=chunk.content, doc_title=title)` — note: manual chunks have NO section title, so omit that parameter
  4. `title` is the manual title parameter already available in the function signature
  5. Pass `prefixed_texts` to `embed_many()` instead of the original texts
  6. The chunk payloads sent to the `create_manual_with_chunks` RPC MUST still use the ORIGINAL `chunk.content` — do NOT store the prefixed version
  7. Add a `logger.info(f"Embedding {len(prefixed_texts)} chunks with contextual prefix for manual '{title}'")` for observability

- [ ] T005 [US2] Add a new re-embed endpoint in `backend/routers/manuals.py`. Add a `POST /manuals/{manual_id}/re-embed` endpoint:
  1. Add these imports at the top (if not already present): `from services.ollama_embedder import embed_single` and `from services.contextual_prefix import apply_contextual_prefix`
  2. Create the endpoint:
     ```python
     @router.post("/manuals/{manual_id}/re-embed")
     async def re_embed_manual_chunks(
         manual_id: str,
         user_email: str = Query(...),
         background_tasks: BackgroundTasks = None,
     ):
     ```
  3. Validate admin access: fetch user from `users` table by `user_email`, check `user_type == "admin"`. Return 403 if not admin.
  4. Fetch the manual: `supabase.table("manuals").select("id, title").eq("id", manual_id).execute()`. Return 404 if not found.
  5. Fetch chunk count: `supabase.table("manual_chunks").select("id", count="exact").eq("manual_id", manual_id).execute()`
  6. Define an inner async function `_re_embed_task()` that:
     - Fetches all chunks: `supabase.table("manual_chunks").select("id, content").eq("manual_id", manual_id).execute()`
     - Iterates each chunk: builds `prefixed = apply_contextual_prefix(content=chunk["content"], doc_title=title)`, calls `emb = await embed_single(prefixed)`, converts to string `emb_str = "[" + ",".join(str(x) for x in emb) + "]"`, updates the row: `supabase.table("manual_chunks").update({"embedding": emb_str}).eq("id", chunk["id"]).execute()`
     - Wraps each chunk in try/except — log errors and continue (don't abort on single-chunk failure)
     - After completion, log activity: `log_activity(user_email, category="admin", action="manual_re_embedded", target_label=title, target_id=manual_id)`
  7. Add `_re_embed_task` as a background task: `background_tasks.add_task(_re_embed_task)`
  8. Return immediately: `{"status": "re-embedding started", "manual_id": manual_id, "chunk_count": chunk_count}`
  9. Import `log_activity` from `utils.activity` — it is synchronous, do NOT await it

**Checkpoint**: Manual chunk pipeline complete. New uploads and re-embeds use contextual prefixes. New re-embed endpoint works.

---

## Phase D — Tests (T006)

- [ ] T006 [P] Create `backend/tests/test_contextual_prefix.py` with these tests:

  1. `test_build_prefix_with_title_and_section()` — Assert `build_contextual_prefix("CADAS-IMS", "Alarm Config")` returns `"CADAS-IMS > Alarm Config: "`

  2. `test_build_prefix_with_title_only()` — Assert `build_contextual_prefix("CADAS-IMS")` returns `"CADAS-IMS: "`

  3. `test_build_prefix_with_empty_title()` — Assert `build_contextual_prefix("")` returns `""`

  4. `test_build_prefix_with_none_title()` — Assert `build_contextual_prefix(None)` returns `""`

  5. `test_build_prefix_with_whitespace_title()` — Assert `build_contextual_prefix("  ")` returns `""`

  6. `test_build_prefix_with_none_section()` — Assert `build_contextual_prefix("Doc", None)` returns `"Doc: "`

  7. `test_build_prefix_with_empty_section()` — Assert `build_contextual_prefix("Doc", "")` returns `"Doc: "`

  8. `test_apply_prefix_normal()` — Assert `apply_contextual_prefix("chunk text", "Doc", "Section")` returns `"Doc > Section: chunk text"`

  9. `test_apply_prefix_no_title()` — Assert `apply_contextual_prefix("chunk text", None)` returns `"chunk text"` (unchanged)

  10. `test_apply_prefix_truncation()` — Create a content string of 29990 chars and a title of 100 chars. Assert the result is the content unchanged (prefix truncated because combined would exceed 30000).

  Use standard imports: `from services.contextual_prefix import build_contextual_prefix, apply_contextual_prefix`. Follow existing test patterns (pytest-asyncio auto mode, no decorators needed for sync tests).

**Checkpoint**: All tests pass. Prefix builder and edge cases verified.

---

## Phase E — Polish & Cross-Cutting Concerns

- [ ] T007 Run all existing tests with `cd backend && python -m pytest tests/ -v` to verify no regressions
- [ ] T008 Verify end-to-end: start the backend, upload a test document, check server logs for contextual prefix messages, then search using title-specific terminology and confirm chunk ranking reflects the prefix

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase A (Foundational)**: No dependencies — start immediately
- **Phase B (US1)**: Depends on T001 (shared helper). T002 → T003 sequential.
- **Phase C (US2)**: Depends on T001 (shared helper). T004 → T005 sequential. Can run in parallel with Phase B.
- **Phase D (Tests)**: Depends on T001 (tests import the helper directly)
- **Phase E (Polish)**: Depends on all previous phases

### User Story Dependencies

- **US1 (P1)**: Depends on T001 only. Independent of US2.
- **US2 (P1)**: Depends on T001 only. Independent of US1.
- US1 and US2 can run in parallel after T001.

### Parallel Opportunities

- T002 and T004 can run in parallel (different files, both depend only on T001)
- T003 and T005 can run in parallel (different files)
- T006 can start as soon as T001 is done (tests only import the helper)

---

## Parallel Example: After T001

```bash
# Launch both pipeline modifications together:
Task: "Modify document_service.py for contextual prefix" (T002)
Task: "Modify manual_rag_service.py for contextual prefix" (T004)
```

## Parallel Example: Re-embed endpoints

```bash
# After T002 and T004, launch both re-embed tasks:
Task: "Update document re-embed in documents.py" (T003)
Task: "Add manual re-embed endpoint in manuals.py" (T005)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001 (shared helper)
2. Complete T002, T003 (document pipeline)
3. **STOP and VALIDATE**: Upload a document, verify prefixed embeddings in logs, test search improvement
4. Deploy if ready — document retrieval immediately improves

### Full Delivery

1. T001 → Foundational complete
2. T002 + T004 in parallel → Both pipelines use prefix on new uploads
3. T003 + T005 in parallel → Both pipelines support batch re-embed
4. T006 → Tests pass
5. T007 + T008 → Full validation

---

## Notes

- The KEY INVARIANT: prefix is for embedding ONLY — never stored in `content` column
- Total new files: 2 (contextual_prefix.py helper + test file)
- Total modified files: 3 (document_service.py, manual_rag_service.py, documents.py) + 1 (manuals.py for new endpoint)
- No schema changes, no migrations, no frontend changes
- After implementation, Claude Code will perform a superpowers code review
