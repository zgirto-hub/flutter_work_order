# Tasks: Smart Document Preprocessing

**Input**: Design documents from `/specs/073-smart-doc-preprocess/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Database migration and shared preprocessing service

- [x] T001 Create migration file `supabase/migrations/20260416100000_smart_preprocessing.sql` that: (a) drops and recreates the `knowledge_documents.status` CHECK constraint to include `'preprocessing'` alongside existing values `('pending', 'preprocessing', 'indexing', 'ready', 'failed')`; (b) adds nullable `raw_content TEXT` column to `document_chunks` table; (c) adds nullable `raw_content TEXT` column to `manual_chunks` table; (d) inserts `smart_preprocessing_enabled` key with value `'true'` into `app_settings` table (use ON CONFLICT DO NOTHING to be idempotent). Reference `specs/073-smart-doc-preprocess/data-model.md` for full schema details.

- [x] T002 Create `backend/services/document_preprocessor.py` — the core preprocessing service. This file should contain:
  - A `PreprocessResult` dataclass with fields: `preprocessed_text` (str), `success` (bool), `fallback_used` (bool)
  - An async function `preprocess_page(raw_text: str, page_number: int, document_title: str = "") -> PreprocessResult` that:
    - Returns raw text immediately (success=True, fallback_used=False) if `len(raw_text.strip()) < 50`
    - Uses `google.generativeai` SDK directly (import the same way as `backend/services/ai_providers/gemini.py`) with model `gemini-2.5-flash`
    - Reads `GEMINI_API_KEY` from environment (same as `backend/services/ai_providers/gemini.py`)
    - Sends a system prompt instructing the model to: (1) rewrite terse bullet points into complete self-contained sentences that preserve all original factual content; (2) add implicit context from headings/titles into expanded sentences; (3) preserve heading hierarchy and paragraph structure; (4) output clean Markdown; (5) for already-rich prose with full paragraphs, apply only minimal cleanup (whitespace normalization, consistent heading levels); (6) NEVER hallucinate, invent, or add information not present or directly implied by the original text
    - The user prompt should be: the document title (if provided) as context, followed by the raw page text
    - Has a 30-second timeout per call (use `asyncio.wait_for`)
    - Retries up to 3 times with exponential backoff (2s, 4s, 8s) on HTTP 429 rate limit errors
    - On any failure (timeout, empty response, API error, missing API key), returns `PreprocessResult(preprocessed_text=raw_text, success=False, fallback_used=True)`
    - Logs preprocessing outcomes (success/fallback) at INFO level
  - An async function `preprocess_pages(pages: list[tuple[int, str]], document_title: str = "") -> list[tuple[int, str]]` that:
    - Takes a list of (page_number, raw_text) tuples
    - Checks `app_settings` for `smart_preprocessing_enabled` — if `'false'`, returns pages unchanged
    - Checks if `GEMINI_API_KEY` is set — if not, logs a warning and returns pages unchanged
    - Processes each page sequentially through `preprocess_page()`
    - Returns a list of (page_number, preprocessed_text) tuples in the same order
    - Also returns the original raw texts somehow (e.g., as a parallel list or dict mapping page_number → raw_text) for storage in `raw_content`
  Reference: `specs/073-smart-doc-preprocess/contracts/api-contracts.md` (Internal Service Contract section) and `specs/073-smart-doc-preprocess/research.md` (R-002, R-004, R-008) for design decisions.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational blocking tasks — Phase 1 creates all shared infrastructure. User stories can begin after Phase 1.

**Checkpoint**: Migration applied, `document_preprocessor.py` created — user story implementation can now begin.

---

## Phase 3: User Story 1 — Slide-Deck PDF Produces Searchable Chunks (Priority: P1) MVP

**Goal**: When a document is uploaded via the knowledge documents pipeline, each page's raw text is preprocessed through Gemini Flash to produce structured Markdown before chunking and embedding. The original raw text is retained in `raw_content`.

**Independent Test**: Upload a terse slide-deck PDF, then search for a concept described only via terse bullets. Verify the relevant chunk appears in top 5 results and that `raw_content` contains the original text.

### Implementation for User Story 1

- [x] T003 [US1] Modify `backend/services/document_service.py` — the `index_document()` function. Currently the flow is: (1) set status to "indexing", (2) extract text, (3) detect sections, (4) create parent/child chunks, (5) embed, (6) set status to "ready". Change this to:
  - After text extraction (after the `pages = ...` line that produces `List[Tuple[page_number, text]]`) and BEFORE `_detect_sections()`:
    - Import `preprocess_pages` from `backend/services/document_preprocessor`
    - Import `get_setting` from `backend/utils/app_settings`
    - Update document status to `'preprocessing'` in `knowledge_documents` table
    - Call `preprocess_pages(pages, document_title=display_name)` — this returns the preprocessed pages and raw text mapping
    - Replace the `pages` variable with the preprocessed result so the rest of the pipeline (section detection, chunking, embedding) uses the enriched text
    - Store a mapping of page_number → original_raw_text for use when creating chunks
  - When creating child chunks (in the loop that inserts into `document_chunks`), populate the `raw_content` field with the original raw text for that page. If preprocessing was disabled or skipped, set `raw_content` to NULL.
  - Keep the existing error handling — if `index_document()` fails at any point, status goes to "failed" as before.
  Reference: `specs/073-smart-doc-preprocess/research.md` (R-001) for insertion point rationale.

- [x] T004 [US1] Modify `backend/services/manual_rag_service.py` — the `upload_manual()` function (starts at line 282). Currently the flow is: (1) parse, (2) chunk, (3) embed, (4) save. Change this to:
  - After `paragraphs = parse(file_bytes, file_extension)` (line 291) and BEFORE `chunks = chunk_paragraphs(paragraphs)` (line 296):
    - Import `preprocess_pages` from `backend/services/document_preprocessor`
    - The `parse()` function returns `List[Tuple[Optional[int], str]]` paragraphs. Convert these to the format expected by `preprocess_pages()` and call it with the manual title
    - Replace the paragraphs variable with preprocessed text so `chunk_paragraphs()` receives enriched content
    - Store the original raw text mapping for use when creating chunks
  - When building `chunk_payload` (around line 345), add `"raw_content": original_raw_text_for_this_chunk` to each chunk dict. The `create_manual_with_chunks` RPC must accept this new field — check if the RPC needs updating or if it passes through arbitrary fields. If the RPC is defined in a migration, update it to include `raw_content`.
  Reference: `specs/073-smart-doc-preprocess/research.md` (R-007) for legacy pipeline integration.

**Checkpoint**: At this point, uploading documents via either pipeline preprocesses text through Gemini Flash. Raw text is retained. Search quality for terse slides should improve.

---

## Phase 4: User Story 2 — Dense Technical Manuals Remain Unharmed (Priority: P1)

**Goal**: Ensure preprocessing does not degrade search quality for dense prose documents. The preprocessing prompt (already written in T002) is designed to apply minimal transformation to rich text. This story is primarily a verification story — the implementation is covered by the prompt design in T002.

**Independent Test**: Upload a dense prose manual, run test queries, verify results are equal or better than before.

### Implementation for User Story 2

- [x] T005 [US2] Review and tune the preprocessing prompt in `backend/services/document_preprocessor.py`. The prompt from T002 should already handle dense prose correctly (instruction 5: "for already-rich prose with full paragraphs, apply only minimal cleanup"). Verify by:
  - Reading the prompt and confirming it explicitly instructs the model to preserve rich content as-is
  - If needed, add a preamble to the prompt that says: "If the text is already well-structured with complete sentences and clear paragraphs, return it with only whitespace normalization — do NOT rewrite or expand it"
  - Ensure the prompt does not add any wrapper Markdown (e.g., no added `# Page N` headers unless they were in the original)

- [x] T006 [US3] Modify `frontend/lib/screens/manual_assistant/documents_tab.dart` — in the widget that renders document status (look for where `status` string is displayed, likely in a `_buildStatusBadge` or similar method). Add a case for `'preprocessing'` that displays a user-friendly label like "Enhancing content..." with an appropriate icon (e.g., `Icons.auto_fix_high` or `Icons.psychology`). The existing status polling (every 3 seconds via `_startStatusPolling`) does NOT need changes — it already reads the `status` field from the API response and stops only on `'ready'` or `'failed'`. The new `'preprocessing'` status will be polled and displayed automatically. Reference: `specs/073-smart-doc-preprocess/contracts/api-contracts.md` for the updated status enum.

- [x] T007 [US4] Add preprocessing toggle endpoints to `backend/routers/documents.py` (or to `backend/routers/ai_providers.py` if settings are consolidated there — check which file has the existing `GET /ai/providers` and `POST /ai/provider` routes). Add two routes:
  - `GET /settings/smart-preprocessing` — returns `{"enabled": true/false}` by reading `get_setting("smart_preprocessing_enabled")` from `backend/utils/app_settings.py`. Admin-only (check existing auth patterns in the file).
  - `PUT /settings/smart-preprocessing` — accepts `{"enabled": bool, "user_email": str}`, calls `set_setting("smart_preprocessing_enabled", "true"/"false", updated_by=user_uuid)`, returns `{"enabled": bool, "updated_at": str}`. Admin-only.
  Reference: `specs/073-smart-doc-preprocess/contracts/api-contracts.md` (New Endpoints section).

- [x] T008 [US4] Add a preprocessing toggle to the frontend admin settings UI. Find the existing admin settings screen (likely in `frontend/lib/screens/settings/` or wherever the AI provider selection UI lives from spec 063). Add a switch/toggle for "Smart Document Preprocessing" that:
  - Calls `GET /settings/smart-preprocessing` on load to get current state
  - Calls `PUT /settings/smart-preprocessing` on toggle with the admin's email
  - Shows a brief description: "When enabled, uploaded documents are enhanced with AI to improve search quality"
  - Follow the same UI pattern as the existing AI provider setting

**Checkpoint**: Admin can toggle preprocessing. Disabled → uploads use raw text pipeline. Enabled → uploads go through Gemini Flash.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Activity logging, edge case hardening, documentation

- [ ] T009 Add activity logging for preprocessing in `backend/services/document_preprocessor.py`. After processing all pages in `preprocess_pages()`, log a summary to `user_activity_log` via the existing `backend/utils/activity.py` fire-and-forget pattern. Log: action=`"document_preprocessed"`, category=`"document"`, metadata with `total_pages`, `preprocessed_count`, `fallback_count`, `document_id`. This satisfies constitution principle VI (Audit Everything).

- [ ] T010 Update the `create_manual_with_chunks` RPC (find it in `supabase/migrations/` — likely `20260411000000_create_manuals.sql`) if it does not accept `raw_content` in the chunk payload. If the RPC uses a fixed column list for inserts, add `raw_content` to it. If it passes through JSON dynamically, no change needed. Test that manual uploads with preprocessing correctly store `raw_content`.

- [ ] T011 Run the full verification checklist from `specs/073-smart-doc-preprocess/quickstart.md`: (1) migration applied, (2) setting seeded, (3) slide-deck upload with status progression, (4) chunk content vs raw_content verification, (5) search quality check, (6) dense manual upload, (7) fallback when Gemini unavailable, (8) toggle disable/enable, (9) restart backend.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **US1 (Phase 3)**: Depends on Phase 1 (migration + preprocessor service)
- **US2 (Phase 4)**: Depends on Phase 1 (prompt review only — no code dependencies on US1)
- **US3 (Phase 5)**: Depends on Phase 1 (needs `'preprocessing'` status in DB) — can run in parallel with US1
- **US4 (Phase 6)**: Depends on Phase 1 (needs `app_settings` row) — can run in parallel with US1/US3
- **Polish (Phase 7)**: Depends on US1 completion (logging references preprocessor service)

### User Story Dependencies

- **User Story 1 (P1)**: Depends on T001 (migration) and T002 (preprocessor service). Core MVP.
- **User Story 2 (P1)**: Depends on T002 (preprocessor prompt). Can run in parallel with US1.
- **User Story 3 (P2)**: Depends on T001 (migration adds `'preprocessing'` status). Frontend-only, independent of US1 backend changes.
- **User Story 4 (P3)**: Depends on T001 (migration seeds setting). Backend + frontend, independent of US1.

### Within Each User Story

- Models/migrations before services
- Services before endpoints
- Core implementation before integration

### Parallel Opportunities

- T001 and T002 can run in parallel (migration and service are independent files)
- T003 and T004 (US1) must be sequential — T003 first (knowledge docs), then T004 (manuals, may need RPC update)
- T005 (US2), T006 (US3), T007+T008 (US4) can all run in parallel with each other
- T007 and T008 (US4) are sequential — backend endpoint before frontend toggle

---

## Parallel Example: Phase 1

```text
# Launch both setup tasks in parallel (different files):
Task T001: "Create migration supabase/migrations/20260416100000_smart_preprocessing.sql"
Task T002: "Create backend/services/document_preprocessor.py"
```

## Parallel Example: User Stories 2, 3, 4

```text
# After Phase 1 completes, these can run in parallel:
Task T005 [US2]: "Review preprocessing prompt in backend/services/document_preprocessor.py"
Task T006 [US3]: "Update frontend status display in frontend/lib/screens/manual_assistant/documents_tab.dart"
Task T007 [US4]: "Add settings endpoints in backend/routers/documents.py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001 + T002)
2. Complete Phase 3: User Story 1 (T003 + T004)
3. **STOP and VALIDATE**: Upload a slide-deck PDF, verify preprocessing occurs, check search quality
4. Deploy if ready — users immediately benefit from better search

### Incremental Delivery

1. Setup → Foundation ready
2. Add User Story 1 → Core preprocessing works → Deploy (MVP!)
3. Add User Story 2 → Dense manual quality verified
4. Add User Story 3 → Status visible in UI → Deploy
5. Add User Story 4 → Admin toggle available → Deploy
6. Polish → Logging, RPC fix, full verification → Final deploy

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- The preprocessing prompt in T002 is the most critical design element — spend time getting it right
- Remember to `pip install -r requirements.txt` on server and `sudo systemctl restart document_server.service` after deployment
