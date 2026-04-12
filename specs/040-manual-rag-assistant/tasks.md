---
description: "Task list for feature 040 — System Manual RAG Assistant"
---

# Tasks: System Manual RAG Assistant

**Feature**: `040-manual-rag-assistant`
**Branch**: `040-manual-rag-assistant`
**Input**: Design documents from [`specs/040-manual-rag-assistant/`](.)
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/manuals-api.md](./contracts/manuals-api.md), [quickstart.md](./quickstart.md)

**Tests**: Minimal test tasks are included in Phase 7 (Polish) so the reviewer can verify implementation against the contract. Not a TDD structure — implementation comes first.

**Organization**: Tasks are grouped by user story. Both P1 stories are listed below; US2 (Upload) is sequenced before US1 (Ask) because US1 cannot be demonstrated until at least one manual exists in the corpus. Both remain independently testable per the spec (US1's independent test assumes a pre-seeded manual; US2's does not touch the ask path).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel with other [P] tasks in the same phase (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task serves (US1, US2, US3, US4). Setup/Foundational/Polish phases have no story label.
- Every task description includes exact file paths.

---

## ⚠️ Critical guidance for the implementing LLM

Before touching any task:

1. **Read the full set of design docs in this directory**: [spec.md](./spec.md) (requirements + clarifications), [plan.md](./plan.md) (tech context + constitution check), [research.md](./research.md) (decisions + rationale for every non-obvious choice), [data-model.md](./data-model.md) (exact schema and file layout), [contracts/manuals-api.md](./contracts/manuals-api.md) (exact request/response shapes), [quickstart.md](./quickstart.md) (manual acceptance flows).
2. **Never invent behavior not in the spec**. If a task description conflicts with the spec, the spec wins. If you're unsure, stop and write a note in the task — do not guess.
3. **Use existing project conventions**. Before creating a new pattern, read neighboring files (`backend/routers/*.py`, `backend/services/*.py`, `frontend/lib/services/*.dart`, `frontend/lib/screens/*`) and match them: imports, error handling, logging, dependency injection, Flutter model conventions, etc.
4. **Backend uses the Supabase service-role key** via the existing client helper (search `backend/` for the existing import pattern — likely `from supabase import ...` via a shared module). Do NOT instantiate a new Supabase client inline.
5. **Audit logging is mandatory** per constitution VI. Every successful upload, delete, and ask MUST call `backend/utils/activity.py` fire-and-forget. Tasks below call this out explicitly.
6. **Never commit `backend/version.json`** and never modify it. Per the user's feedback memory, this file is server-managed.
7. **No new Flutter packages**. All required packages (`http`, `file_picker`, `supabase_flutter`, Flutter Material) are already in `pubspec.yaml`.
8. **Follow FR numbers in the spec**. When in doubt about error messages or edge cases, look up the FR the task cites.
9. **Commit after each task or logical group** of ≤3 tasks. Use conventional-commit style messages (e.g. `feat(manuals): add manual_chunker service`).
10. **When you finish each phase's checkpoint**, stop and self-verify against the checkpoint description — do not barrel into the next phase until the checkpoint is demonstrably met.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project dependencies, environment, and one-time server setup.

- [X] T001 Append two lines to [backend/requirements.txt](../../backend/requirements.txt): `pymupdf==1.24.10` and `python-docx==1.1.2`. Do not reformat or reorder other lines.
- [X] T002 Run `pip install -r backend/requirements.txt` from the repo root to install the new dependencies. Verify `python -c "import fitz; import docx"` succeeds.
- [X] T003 [P] Append four new environment variable entries to [backend/.env.example](../../backend/.env.example) (create the file if it does not exist): `OLLAMA_URL=http://localhost:11434`, `OLLAMA_GEN_MODEL=gemma3:e2b`, `OLLAMA_EMBED_MODEL=nomic-embed-text`, `MANUAL_CORPUS_CEILING_MB=400`. Mirror the same four variables into the dev machine's actual `backend/.env` if it exists.
- [X] T004 [P] Add a short "Manual RAG Assistant" section to [backend/README.md](../../backend/README.md) (create the section if missing) documenting the one-time server setup step `ollama pull nomic-embed-text` and noting that Gemma 4 E2B must already be installed.
- [X] T005 [P] Create the runtime directory [backend/uploaded_files/manuals/](../../backend/uploaded_files/manuals/) (use `os.makedirs(..., exist_ok=True)` at service startup per T014; **do not** commit the directory itself — add a `.gitignore` entry in `backend/uploaded_files/.gitignore` that keeps the tree uncommitted if one does not already exist).

**Checkpoint**: Dependencies installed, env vars defined, server setup documented. No code changes yet.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Migration, backend services, Flutter models, and screen skeleton that every user story depends on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Database migration

- [X] T006 Create the migration file [supabase/migrations/20260411000000_create_manuals.sql](../../supabase/migrations/20260411000000_create_manuals.sql) implementing the full schema from [data-model.md](./data-model.md) sections 1–4: `CREATE EXTENSION IF NOT EXISTS vector;` as the first statement, then the `manuals`, `manual_chunks`, and `manual_corpus_stats` tables with all columns, types, nullability, defaults, PKs, FKs, and CHECKS as specified. Use exact column types (`VECTOR(768)`, `BIGINT`, `TIMESTAMPTZ`, etc.).
- [X] T007 In the same migration file, add all indexes from [data-model.md](./data-model.md) sections 2–3: `manuals_uploaded_by_idx`, `manuals_created_at_desc_idx`, `manual_chunks_manual_id_idx`, `manual_chunks_embedding_ivfflat_idx` with `USING ivfflat (embedding vector_cosine_ops) WITH (lists = 50)`, and `manual_chunks_manual_id_chunk_index_uq`.
- [X] T008 In the same migration file, add the RLS policies from [data-model.md](./data-model.md) section 5 verbatim: enable RLS on all three tables, `manuals_authenticated_all`, `manual_chunks_authenticated_all`, `manual_corpus_stats_authenticated_read`.
- [X] T009 In the same migration file, seed the singleton stats row: `INSERT INTO manual_corpus_stats (id, total_bytes, manual_count) VALUES (1, 0, 0);`.
- [X] T010 Apply the migration against the dev Supabase project (e.g. via the project's usual `supabase db push` or Supabase dashboard SQL editor). Verify via `SELECT table_name FROM information_schema.tables WHERE table_name IN ('manuals','manual_chunks','manual_corpus_stats');` — expect 3 rows.

### Backend services (parallelizable)

- [X] T011 [P] Create [backend/services/manual_parser.py](../../backend/services/manual_parser.py) exposing `parse(file_bytes: bytes, file_extension: str) -> list[tuple[int | None, str]]` that dispatches on extension to `parse_pdf`, `parse_docx`, `parse_txt`, `parse_md`. Implement per [research.md](./research.md) §3–5: pymupdf per-page text with 1-based page numbers for PDFs; python-docx paragraph iteration with `source_page = None` for DOCX; UTF-8 decode (fallback `latin-1` on UnicodeDecodeError) for TXT/MD. Raise `NoExtractableTextError` (define in the same module) if the PDF produces fewer than 20 total characters of extractable text. Return value is a list of `(page_number_or_none, paragraph_text)` tuples.
- [X] T012 [P] Create [backend/services/manual_chunker.py](../../backend/services/manual_chunker.py) exposing `chunk_paragraphs(paragraphs: list[tuple[int | None, str]], max_words: int = 500, overlap_words: int = 50) -> list[Chunk]` where `Chunk` is a dataclass `(chunk_index: int, source_page: int | None, content: str)`. Implement the two-pass algorithm from [research.md](./research.md) §2: greedy paragraph packing, falling back to a 500-word sliding window with 50-word overlap for oversized single paragraphs. `source_page` on each chunk is the page of its first paragraph. Chunks are `chunk_index`-numbered starting from 0.
- [X] T013 [P] Create [backend/services/ollama_embedder.py](../../backend/services/ollama_embedder.py) exposing async functions `embed_single(text: str) -> list[float]` and `embed_many(texts: list[str], concurrency: int = 4) -> list[list[float]]`. Use `httpx.AsyncClient` POST to `{OLLAMA_URL}/api/embeddings` with body `{"model": OLLAMA_EMBED_MODEL, "prompt": text}`, timeout 20 seconds. `embed_many` uses `asyncio.Semaphore(concurrency)` to cap parallelism. On timeout raise `EmbedderTimeoutError`. Read `OLLAMA_URL` and `OLLAMA_EMBED_MODEL` from environment.
- [X] T014 [P] Create [backend/services/manual_storage_service.py](../../backend/services/manual_storage_service.py) exposing `save(manual_id: UUID, file_bytes: bytes, file_extension: str) -> Path`, `delete(manual_id: UUID, file_extension: str) -> None`, and `path_for(manual_id: UUID, file_extension: str) -> Path`. All paths resolve under `BASE_DIR / "backend" / "uploaded_files" / "manuals" / f"{manual_id}.{file_extension}"`. `save` calls `os.makedirs(parent, exist_ok=True)` before writing. `delete` logs a warning and returns normally if the file does not exist (per [FR-022](./spec.md)). Raises `StorageError` on any OS-level failure during write.
- [X] T015 [P] Create [backend/services/ollama_generator.py](../../backend/services/ollama_generator.py) exposing async `generate(prompt: str, timeout: float = 90.0) -> str`. Use `httpx.AsyncClient` POST to `{OLLAMA_URL}/api/generate` with body `{"model": OLLAMA_GEN_MODEL, "prompt": prompt, "stream": False}`. On timeout raise `GeneratorTimeoutError`. Return the `response` field from the Ollama JSON.
- [X] T016 [P] Create [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py) as an orchestration module with three async function stubs: `upload_manual(title, file_bytes, file_extension, file_size_bytes, uploaded_by)`, `ask(question, manual_id_filter)`, and `delete_manual(manual_id)`. Leave bodies as `raise NotImplementedError` — each will be implemented in the story that owns it. Also export `PROMPT_TEMPLATE: str` constant containing the exact Gemma prompt from [research.md](./research.md) §7.

### Backend router skeleton + shared list endpoint

- [X] T017 Create [backend/routers/manuals.py](../../backend/routers/manuals.py) with `router = APIRouter(prefix="/api/manuals", tags=["manuals"])` and stub handlers for `POST /upload`, `GET /`, `DELETE /{manual_id}`, `POST /ask`. Stubs raise `HTTPException(status_code=501)` except for `GET /` which is implemented in T018. Import `manual_rag_service` and `activity` (for audit). Register the router in [backend/main.py](../../backend/main.py) following the same `app.include_router(...)` pattern as existing routers.
- [X] T018 Implement `GET /api/manuals/` in [backend/routers/manuals.py](../../backend/routers/manuals.py) per [contracts/manuals-api.md](./contracts/manuals-api.md) §2. Query `manuals` joined with `users` (LEFT JOIN) for `uploaded_by_name`, order by `created_at DESC`. Read `manual_corpus_stats` single row for the `corpus_stats` block. `ceiling_bytes` = `int(os.getenv("MANUAL_CORPUS_CEILING_MB", "400")) * 1024 * 1024`. Return the exact JSON shape from the contract. This endpoint is shared across all stories.

### Flutter models and service skeleton

- [X] T019 [P] Create [frontend/lib/models/manual.dart](../../frontend/lib/models/manual.dart) with the `Manual` class from [data-model.md](./data-model.md) §8, including `fromJson` factory and `toJson`. Match existing model conventions in the project (search `frontend/lib/models/` for a simple model to mirror the style).
- [X] T020 [P] Create [frontend/lib/models/manual_source.dart](../../frontend/lib/models/manual_source.dart) with the `ManualSource` class from [data-model.md](./data-model.md) §8, including `fromJson`.
- [X] T021 [P] Create [frontend/lib/models/manual_qa_answer.dart](../../frontend/lib/models/manual_qa_answer.dart) with the `ManualQaAnswer` class from [data-model.md](./data-model.md) §8, including `fromJson`.
- [X] T022 Create [frontend/lib/services/manual_assistant_service.dart](../../frontend/lib/services/manual_assistant_service.dart) with a singleton service exposing four methods: `uploadManual(...)` (stubbed), `listManuals()` (implemented — calls `GET /api/manuals/`, returns `List<Manual>` + corpus stats), `deleteManual(...)` (stubbed), `askQuestion(...)` (stubbed). Use the project's existing HTTP client pattern — search `frontend/lib/services/` for a sibling service and match its auth header handling (Supabase JWT from the current session).

### Flutter screen skeleton + navigation wiring

- [X] T023 Create [frontend/lib/screens/manual_assistant/manual_assistant_screen.dart](../../frontend/lib/screens/manual_assistant/manual_assistant_screen.dart) as a `StatefulWidget` wrapping a `DefaultTabController(length: 2)`. AppBar title: "Manual Assistant" (localized-ready but English-first OK). Two tabs: "Chat" and "Manuals". Body: `TabBarView` with two `const SizedBox.shrink()` placeholders (will be replaced in T028 and T030).
- [X] T024 [P] Create [frontend/lib/screens/manual_assistant/chat_tab.dart](../../frontend/lib/screens/manual_assistant/chat_tab.dart) as an empty `StatelessWidget` returning `const Center(child: Text("Chat"))` — a placeholder that US1 will replace.
- [X] T025 [P] Create [frontend/lib/screens/manual_assistant/manuals_tab.dart](../../frontend/lib/screens/manual_assistant/manuals_tab.dart) as an empty `StatelessWidget` returning `const Center(child: Text("Manuals"))` — a placeholder that US2 will replace.
- [X] T026 Wire navigation: add a new entry to the app's main navigation shell (search `frontend/lib/screens/` for the file that owns the drawer/bottom-nav — look for existing role-gated entries like dashboard, work orders, calendar). Add an entry with `Icons.menu_book_outlined`, label "Manual Assistant", visible to **all three roles** (`reporter`, `technician`, `admin`). The entry pushes `ManualAssistantScreen()`. Match the existing entry style (icon size, localization, padding). Also register a named route `/manual-assistant` in the app's `MaterialApp.routes` if routes are registered centrally.

**Checkpoint**: The migration is applied, all four backend endpoints exist (three as 501 stubs), `GET /api/manuals/` returns an empty list, a user can navigate to the Manual Assistant screen and see two empty tabs. No real functionality yet.

---

## Phase 3: User Story 2 — Upload a manual so it becomes queryable (Priority: P1)

**Story goal**: A user opens the Manuals tab, uploads a PDF/DOCX/TXT/MD, enters a title, and — once processing completes — the manual appears in the list.

**Independent test**: Upload `backend/tests/fixtures/manual_sample.pdf` (a ~5-page English PDF) via the Manuals tab UI. Verify (1) a loading indicator shows during processing, (2) the manual row appears with title, file name, uploader name, date, and chunk count, (3) a row exists in `manuals` + N rows in `manual_chunks` + `manual_corpus_stats.total_bytes` increased, (4) the file exists at `backend/uploaded_files/manuals/<uuid>.pdf`.

**Note**: US2 is listed before US1 because US1 requires pre-existing content. US1's independent test is still valid with a SQL-seeded manual if US2 is not yet done.

### Backend

- [X] T027 [US2] Implement `upload_manual(...)` in [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py) per [contracts/manuals-api.md](./contracts/manuals-api.md) §1 processing pipeline and [research.md](./research.md) §11 transaction ordering. Order: (1) parse with `manual_parser.parse`, (2) chunk with `manual_chunker.chunk_paragraphs`, (3) if zero chunks raise `NoContentAfterChunkingError`, (4) embed via `ollama_embedder.embed_many(texts, concurrency=4)`, (5) allocate `manual_id = uuid4()`, (6) compute `projected_bytes` using the formula from [research.md](./research.md) §10 (sum of `len(chunk.content.encode("utf-8")) + `len(chunks) * 3072` + `200 * len(chunks)` + 500), (7) pre-check `corpus_stats.total_bytes + projected_bytes <= ceiling_bytes` and raise `CorpusFullError` if not, (8) call `manual_storage_service.save`, (9) open a Supabase transaction (use the project's existing transaction pattern or sequential writes with try/except), (10) insert `manuals` row, insert `manual_chunks` rows in batch, update `manual_corpus_stats`, (11) on any exception inside step 10, call `manual_storage_service.delete` and re-raise. Return the created `Manual` dict matching the contract response shape.
- [X] T028 [US2] Implement `POST /api/manuals/upload` in [backend/routers/manuals.py](../../backend/routers/manuals.py) per [contracts/manuals-api.md](./contracts/manuals-api.md) §1 admission checks + error mapping. Accept `file: UploadFile = File(...)` and `title: str = Form(...)`. Perform MIME check (415), size check (413 `file_too_large`), title check (400 `title_required`), read file bytes, call `manual_rag_service.upload_manual`, map exceptions to the exact HTTP codes and JSON error shapes from the contract. On success return the shape from the contract. Derive `file_extension` from MIME type (not from filename — per [research.md](./research.md) §12).
- [X] T029 [US2] Add audit logging at the end of the successful upload path in [backend/routers/manuals.py](../../backend/routers/manuals.py): `activity.log(user_id=current_user.id, category="file", action="uploaded_manual", details={"manual_id": ..., "title": ..., "file_name": ..., "chunk_count": ..., "file_size_bytes": ...})`. Use the existing `backend/utils/activity.py` fire-and-forget helper.

### Frontend

- [X] T030 [US2] Implement `uploadManual(String title, Uint8List fileBytes, String fileName, String mimeType) async -> Manual` in [frontend/lib/services/manual_assistant_service.dart](../../frontend/lib/services/manual_assistant_service.dart). POST `multipart/form-data` to `/api/manuals/upload`. Map non-200 responses to a typed exception (`ManualUploadException` with `code` and `message` fields) so the UI can show the right error text for each code (`file_too_large`, `corpus_full`, `no_extractable_text`, `unsupported_media_type`, `embedder_unavailable`).
- [X] T031 [US2] Create [frontend/lib/screens/manual_assistant/widgets/upload_dialog.dart](../../frontend/lib/screens/manual_assistant/widgets/upload_dialog.dart) — an `AlertDialog` with a `file_picker.FilePicker.platform.pickFiles()` action (allowed extensions: `['pdf','docx','txt','md']`), a `TextField` for title, and Submit/Cancel buttons. On submit, calls `manual_assistant_service.uploadManual(...)`, shows an in-dialog progress indicator while pending, closes on success and returns the new `Manual`, shows an in-dialog error text on failure mapping the exception's `code` to a user-friendly string.
- [X] T032 [US2] Replace the placeholder in [frontend/lib/screens/manual_assistant/manuals_tab.dart](../../frontend/lib/screens/manual_assistant/manuals_tab.dart) with a `StatefulWidget` that: (a) loads the list via `manual_assistant_service.listManuals()` in `initState` (with a `RefreshIndicator` wrapper), (b) displays each manual as a `ListTile` showing title as primary text and "`<file_name>` · `<uploader_name>` · `<date>` · `<chunk_count> chunks`" as subtitle, (c) shows a `FloatingActionButton(child: Icon(Icons.upload_file))` that opens `UploadDialog` and refreshes the list on successful upload, (d) shows a loading spinner while the initial list is loading, (e) shows an empty-state Column (`Icons.menu_book_outlined` + "Your library is empty. Tap the upload button to add your first manual.") per [FR-017](./spec.md) when the list is empty.
- [X] T033 [US2] Verify the Chat tab's empty state is triggered when corpus is empty. Update [frontend/lib/screens/manual_assistant/chat_tab.dart](../../frontend/lib/screens/manual_assistant/chat_tab.dart) placeholder text to "No manuals uploaded yet. Visit the Manuals tab to upload one." per [FR-016](./spec.md). Actual chat behavior is filled in by US1 in a later phase; this task only updates the placeholder wording.

**Checkpoint**: A user can upload a PDF/DOCX/TXT/MD, see the loading state, and see the manual appear in the Manuals tab list. Uploading an unsupported type, an oversized file, or a no-text PDF shows the correct error message. `backend/uploaded_files/manuals/<uuid>.<ext>` exists on disk. Validates [US2 Acceptance Scenarios 1–5](./spec.md).

---

## Phase 4: User Story 1 — Ask a question against uploaded manuals (Priority: P1)

**Story goal**: A user opens the Chat tab, types a question in Arabic or English, and receives an answer grounded in the uploaded manuals with at least one source citation.

**Independent test**: Pre-seed at least one manual (via US2 upload OR via a direct SQL seed for early testing). In the Chat tab, ask a question whose answer is in the manual; verify (1) a loading indicator shows, (2) the answer reflects the manual's content, (3) at least one source is shown. Ask a question whose answer is not in the manual; verify the sentinel "not in the available manuals" response.

### Backend

- [X] T034 [US1] Implement `ask(question: str, manual_id_filter: UUID | None) -> dict` in [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py) per [contracts/manuals-api.md](./contracts/manuals-api.md) §4 and [research.md](./research.md) §7. Steps: (1) short-circuit if corpus is empty — return grounded=false with sentinel answer, (2) call `ollama_embedder.embed_single(question)`, (3) execute the cosine-distance retrieval SQL from the contract (top 5, with optional `manual_id` filter, joined on `manuals.title`), (4) build the prompt using the `PROMPT_TEMPLATE` constant and the retrieved chunks formatted as `[Source {i}: {manual_title}, page {source_page or '—'}]\n{content}\n---`, (5) call `ollama_generator.generate(prompt)`, (6) detect groundedness by substring-searching the answer for `"This information is not in the available manuals"` OR the Arabic equivalent (research this phrase if uncertain, or include the English phrase verbatim and let Gemma match it), (7) if not grounded, return `{"answer": "<stripped>", "grounded": false, "sources": []}`, (8) otherwise, for each retrieved chunk, call the sentence-matching helper from T048 (stubbed in this phase returning `(None, None)`; real implementation happens in US4) to compute highlights, and build the sources list with `content_preview` truncated to 500 chars.
- [X] T035 [US1] Implement `POST /api/manuals/ask` in [backend/routers/manuals.py](../../backend/routers/manuals.py) per [contracts/manuals-api.md](./contracts/manuals-api.md) §4. Accept JSON body with `question` and optional `manual_id`. Admission checks in order: `question_required` (400), `question_too_long` (400, >2000 chars), `manual_not_found` (404) if `manual_id` is provided and doesn't resolve. Call `manual_rag_service.ask`, catch `EmbedderTimeoutError` and `GeneratorTimeoutError` → 504 `assistant_unavailable`, catch unexpected exceptions → 500 `ask_failed`. Return 200 with the contract's response shape on success.
- [X] T036 [US1] Add audit logging at the end of `POST /api/manuals/ask`: `activity.log(user_id=current_user.id, category="file", action="asked_manual", details={"question": question[:500], "manual_id_filter": manual_id_filter, "grounded": grounded, "chunk_count_returned": len(sources)})`. Fire-and-forget.

### Frontend

- [X] T037 [US1] Implement `askQuestion(String question, String? manualIdFilter) async -> ManualQaAnswer` in [frontend/lib/services/manual_assistant_service.dart](../../frontend/lib/services/manual_assistant_service.dart). POST JSON to `/api/manuals/ask`. Map non-200 responses to a typed `ManualAskException`.
- [X] T038 [US1] Create [frontend/lib/screens/manual_assistant/widgets/answer_card.dart](../../frontend/lib/screens/manual_assistant/widgets/answer_card.dart) — a `StatelessWidget` taking a `ManualQaAnswer`. Renders (a) the answer text inside a `Card`, (b) below it, if `sources.isNotEmpty`, an `ExpansionTile(title: Text("Sources"))` that lists each source as a placeholder `ListTile` showing `manual_title` + `page: ${source_page ?? "—"}` + a preview of `content_preview` as plain text. Rich highlighting is added in US4.
- [X] T039 [US1] Replace the placeholder in [frontend/lib/screens/manual_assistant/chat_tab.dart](../../frontend/lib/screens/manual_assistant/chat_tab.dart) with a `StatefulWidget` that: (a) maintains a message thread (`List<ChatMessage>` — a private data class with question + optional answer + loading + error state), (b) shows the empty state from T033 when no messages AND no manuals are loaded, (c) shows a `DropdownButton<String?>` populated from `manual_assistant_service.listManuals()` to optionally scope the question to a single manual ([FR-013](./spec.md)), (d) shows a `TextField` + send `IconButton`, (e) on send: disable the send button ([FR-021](./spec.md)), append a pending message, call `manual_assistant_service.askQuestion`, replace the pending with the result (answer card or error text), re-enable the button, (f) renders each answer via `AnswerCard`.
- [X] T040 [US1] Handle the 504 `assistant_unavailable` and 500 `ask_failed` cases in [chat_tab.dart](../../frontend/lib/screens/manual_assistant/chat_tab.dart) by showing the user-friendly message in-thread as a red-tinted ChatMessage with a retry action. Never leave the UI stuck on a loading indicator ([FR-015](./spec.md)).
- [X] T041 [US1] Verify the empty-corpus edge case works end-to-end: with zero manuals in the DB, the Chat tab shows the empty state from T033 and the send button is disabled. This is already covered by backend short-circuit T034 step 1 — this task is a verification task, not new code.

**Checkpoint**: A user can ask a question in the Chat tab and get a grounded answer back with plain-text source rows. A question whose answer is not in the manuals produces the "not in the available manuals" sentinel with no fabrication. Questions in Arabic get Arabic replies. Validates [US1 Acceptance Scenarios 1–6](./spec.md) (source highlights are added in US4).

---

## Phase 5: User Story 3 — Manage (list and delete) existing manuals (Priority: P2)

**Story goal**: A user can delete an individual manual after confirming in a dialog. The manual and its stored file are removed, and it is no longer cited in future answers.

**Independent test**: With at least one manual present, long-press a row in the Manuals tab, confirm the delete dialog, verify the row disappears and `manual_chunks`/`manuals`/`manual_corpus_stats` all reflect the removal, and verify `backend/uploaded_files/manuals/<uuid>.<ext>` is gone.

### Backend

- [X] T042 [US3] Implement `delete_manual(manual_id: UUID) -> None` in [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py). Steps: (1) `SELECT file_extension, chunk_count, (sum of octet_length calculation for projected_bytes)` from `manuals` join `manual_chunks`, (2) if not found raise `ManualNotFoundError`, (3) open a DB transaction: `DELETE FROM manuals WHERE id = $1` (CASCADE removes chunks), `UPDATE manual_corpus_stats SET total_bytes = GREATEST(0, total_bytes - $2), manual_count = GREATEST(0, manual_count - 1), updated_at = now() WHERE id = 1`, (4) call `manual_storage_service.delete(manual_id, file_extension)` (already tolerates missing file).
- [X] T043 [US3] Implement `DELETE /api/manuals/{manual_id}` in [backend/routers/manuals.py](../../backend/routers/manuals.py) per [contracts/manuals-api.md](./contracts/manuals-api.md) §3. Parse `manual_id` as UUID. Call `manual_rag_service.delete_manual`. Map `ManualNotFoundError` to 404. Return 204 on success.
- [X] T044 [US3] Add audit logging at the end of the successful delete path: `activity.log(user_id=current_user.id, category="file", action="deleted_manual", details={"manual_id": ..., "title": ...})`.

### Frontend

- [X] T045 [US3] Implement `deleteManual(String manualId) async -> void` in [frontend/lib/services/manual_assistant_service.dart](../../frontend/lib/services/manual_assistant_service.dart). DELETE to `/api/manuals/{id}`. Map 404 to a typed `ManualNotFoundException`.
- [X] T046 [US3] Extend [frontend/lib/screens/manual_assistant/manuals_tab.dart](../../frontend/lib/screens/manual_assistant/manuals_tab.dart) (modifying the widget from T032): wrap each `ListTile` in a `Dismissible(direction: DismissDirection.endToStart)` or add a trailing `IconButton(icon: Icon(Icons.delete_outline))`. On gesture, show an `AlertDialog` with title "Delete manual?", content "This manual and its indexed chunks will be removed. This cannot be undone.", and Cancel/Delete actions. On Delete, call `deleteManual`, remove the row from local state, show a `SnackBar` on success. Handle `ManualNotFoundException` (rare — already gone) by refreshing the list.

**Checkpoint**: A user can long-press/swipe-to-delete a manual, confirm, and see it removed. Re-querying the chat no longer returns results from that manual. The on-disk file is gone. Validates [US3 Acceptance Scenarios 1–3](./spec.md) and [FR-022](./spec.md).

---

## Phase 6: User Story 4 — See which part of a manual an answer came from (Priority: P2)

**Story goal**: Each source card in an answer's expanded Sources section visually highlights the sentence(s) from the manual chunk that most closely support the generated answer.

**NOTE**: Highlight computation is stubbed in T034/T048 returning (None, None). This will be implemented in a follow-up.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Contract tests, integration test, audit verification, docs, and full quickstart validation.

**NOTE**: Contract tests T052-T059, docs T063, and final checks T065-T066 are deferred for later execution.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)**: no dependencies — can start immediately.
- **Phase 2 (Foundational)**: depends on Phase 1. Blocks all user story phases.
- **Phase 3 (US2 Upload, P1)**: depends on Phase 2 completion. Delivers the content that US1 queries.
- **Phase 4 (US1 Ask, P1)**: depends on Phase 2 completion. Can run in parallel with Phase 3 if a SQL seed script is used for test data. In this plan it is sequenced after Phase 3 so natural end-to-end testing is available.
- **Phase 5 (US3 Manage, P2)**: depends on Phase 2 and Phase 3 (ManualsTab widget from T032 is extended, not replaced). Does not depend on Phase 4.
- **Phase 6 (US4 Citations, P2)**: depends on Phase 4 (extends `manual_rag_service.ask` and `answer_card`). Does not depend on Phase 5.
- **Phase 7 (Polish)**: depends on all desired user stories being complete. Contract tests in T052 can be written earlier but should be run green after each phase completes.

### Within each phase

- Backend service tasks marked [P] in Phase 2 (T011, T012, T013, T014, T015, T016) are in different files with no mutual imports — safe to parallelize.
- Flutter model tasks marked [P] in Phase 2 (T019, T020, T021) are in different files — safe to parallelize.
- T018 (GET endpoint implementation) depends on T017 (router skeleton creation).
- T022 (`manual_assistant_service.dart`) depends on T019–T021 (model imports).
- T023 (screen root) depends on T024 and T025 (child tab widgets) existing as stubs.

### Cross-story file-level notes

- [manuals_tab.dart](../../frontend/lib/screens/manual_assistant/manuals_tab.dart) is created in T025 (stub), replaced in T032 (US2), and extended in T046 (US3). US2 and US3 cannot be coded truly in parallel on this file — US3 must rebase on top of T032.
- [manual_rag_service.py](../../backend/services/manual_rag_service.py) accumulates code across Phase 2 (stub), Phase 3 (upload), Phase 4 (ask), Phase 5 (delete), Phase 6 (highlight helpers + ask update). The same file-ordering caveat applies.
- [manual_assistant_service.dart](../../frontend/lib/services/manual_assistant_service.dart) accumulates method implementations across Phase 2 (listManuals), Phase 3 (uploadManual), Phase 4 (askQuestion), Phase 5 (deleteManual). Same caveat.
- [manuals.py](../../backend/routers/manuals.py) accumulates endpoint implementations across Phase 2 (GET), Phase 3 (POST /upload), Phase 4 (POST /ask), Phase 5 (DELETE). Same caveat.

### Parallel opportunities

- Phase 1: T003, T004, T005 can be done in parallel.
- Phase 2 backend services: T011, T012, T013, T014, T015, T016 all in parallel (different files).
- Phase 2 Flutter models: T019, T020, T021 in parallel.
- Phase 7 contract tests and fixtures: T052, T053 in parallel with each other and with docs tasks T063, T064.

---

## Parallel example: Phase 2 (Foundational) backend services

```
T011 Create manual_parser.py        (different file)
T012 Create manual_chunker.py       (different file)
T013 Create ollama_embedder.py      (different file)
T014 Create manual_storage_service.py (different file)
T015 Create ollama_generator.py     (different file)
T016 Create manual_rag_service.py   (different file, imports T011–T015 as stubs)
```

All six can be created concurrently. Only T016 needs the others to exist as importable module stubs, but Python's late-binding makes that trivial.

---

## Implementation strategy

### MVP scope (recommended first pass)

1. **Phases 1 + 2** (Setup + Foundational) — unblocks everything. Validate the migration applies and the screen is navigable before moving on.
2. **Phase 3** (US2 Upload) — first user-visible value. Stop and run Flow A through T032 (upload-only, no chat yet).
3. **Phase 4** (US1 Ask) — now the core RAG loop works. Stop and run Flows A + B + C + D end-to-end.
4. **STOP and demo**. This is the MVP cut. Both P1 stories are done.

### Incremental delivery

5. **Phase 5** (US3 Manage) — adds lifecycle management. Stop and run Flow E.
6. **Phase 6** (US4 Citations) — adds citation highlighting. Stop and re-run Flow A to verify highlights now appear.
7. **Phase 7** (Polish) — contract tests, perf spot checks, docs, final smoke.

### If both developers are available

After Phase 2 completes, developer A takes US2 (Phase 3) while developer B prepares a SQL seed for US1 testing and drafts T034 (the rag_service.ask function) in a branch. Once Phase 3 lands, developer B's work merges cleanly and Phase 4 is halfway done. US3 and US4 can be split between the two after Phase 4 lands.

---

## Review handoff (for the reviewing LLM / human)

After the implementing LLM marks all tasks complete, the reviewer should:

1. Read this `tasks.md` and the spec + plan + contracts + data-model to establish the oracle.
2. For each task in Phase 2–6, open the indicated file(s) and verify the stated behavior is implemented and nothing extra was added. Flag any deviation.
3. Run the contract test suite from T052 and confirm it is fully green.
4. Walk through [quickstart.md](./quickstart.md) Flows A–F on a fresh dev environment. Flag any flow that does not pass exactly as described.
5. Spot-check constitution compliance: all four endpoints audit-log via `activity.log`; originals live under `backend/uploaded_files/manuals/`; RLS policies exist; no cloud storage references; `backend/version.json` untouched.
6. Check that the Manuals tab filtering works client-side (no extra API calls on filter change).
7. Check that [FR-021](./spec.md) is honored — concurrent sends cannot corrupt the chat thread.
8. Confirm the [Out of Scope](./spec.md) items are actually absent from the implementation (no viewer, no OCR, no per-manual ACL, no versioning, no line numbers in citations).

---

## Notes

- [P] tasks = different files with no inter-task ordering in the same phase.
- [Story] label maps tasks to user stories for traceability.
- Each story is independently demonstrable at its checkpoint.
- Commit after each task or small group. Match the existing repo's conventional-commit style.
- If an FR conflicts with a task description, the spec wins and the task should be updated in place with a note.
- The implementing LLM should treat `research.md` as authoritative for every non-obvious "why" — it records the decisions behind every choice that is not directly in the spec.
- **Do not modify `backend/version.json`.** Do not modify `CLAUDE.md` by hand beyond what the agent-context script already produced.
