# Feature Specification: Delete Legacy `manuals` Table & Dead Code

**Feature Branch**: `090-delete-legacy-manuals`
**Created**: 2026-04-20
**Status**: Draft — audit complete, pending review before code changes
**Input**: User description: "Delete the legacy `manuals` table and all code that references it. The live corpus is `knowledge_documents` — `manuals` is empty in production and was superseded during earlier RAG work."

---

## Summary

The `manuals` family of tables (`manuals`, `manual_chunks`, `manual_corpus_stats`) is a dead path. The live document corpus was migrated to `knowledge_documents` / `document_chunks` during spec 072 (Document Retrieval V2), and training/verified-answer flows (spec 080) were repointed in follow-up migrations. In production the `manuals` table is empty and nothing reads it for RAG anymore, but the CRUD code path — upload, chunk editing, legacy-manuals migration UI — is still wired end-to-end on both frontend and backend. This spec removes those dead branches in a safe, ordered way so that (a) no user-facing regressions leak in, (b) foreign-key constraints are cleaned before table drops, and (c) the remaining `/manuals/*` URL surface (which is the live AI-assistant API — unrelated to the SQL table) is preserved.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Admin no longer sees the dead "Manuals" tab or "Migrate old manuals" button (Priority: P1)

Today an admin opening **Ask the AI → Documents** sees a "Migrate old manuals" section that polls an empty source and always returns 0. The admin-only "Manuals" tab (the legacy CRUD UI) still exists behind the Documents/Train AI tabs. Both surfaces create confusion and invite the admin to run pointless maintenance actions.

**Why this priority**: User-facing dead code is the highest-leverage removal. Admins can act on it, it makes the app look unmaintained, and eliminating it is a pure frontend/wiring change with no DB impact. Ships first so the UX is clean regardless of how slowly later backend/DB cleanup proceeds.

**Independent Test**: Deploy only the frontend portion of this spec. Log in as admin, open the Ask the AI screen. Verify (a) no "Manuals" tab is reachable, (b) the "Old manuals detected" / migration UI is gone from the Documents tab, (c) all other Ask-the-AI functions (ask, rate, verified answers, settings, document upload) still work normally.

**Acceptance Scenarios**:

1. **Given** an admin on the Ask the AI screen, **When** they inspect the tab bar, **Then** no tab lists legacy manuals (only the currently-used tabs such as Documents, Train AI, etc. appear).
2. **Given** an admin on the Documents tab, **When** the page loads, **Then** no "Old manuals" block, "Migrate all" button, or migration-progress UI appears anywhere in the tab.
3. **Given** a non-admin user on the Ask the AI screen, **When** they use the assistant, **Then** asking a question, rating an answer, and viewing verified answers all work identically to before this change.

---

### User Story 2 — Backend exposes no dead manuals-CRUD routes (Priority: P2)

The backend currently exposes roughly a dozen routes that read/write the empty `manuals` and `manual_chunks` tables (upload, list, delete, chunk editing, re-embed, bulk delete) plus three migration routes in `documents.py` (`POST /migrate-all`, `GET /migration-status`, `DELETE /migrate-cleanup`). None of these are reachable from the production app once Story 1 ships; they are only reachable by a direct API call. Keeping them means the attack/error surface still points at an empty, soon-to-be-dropped table.

**Why this priority**: Backend route removal blocks the DB migration (Story 3) — once the tables are gone, those routes would 500 on any caller. Ships after Story 1 so no user-visible button points at a removed route. Still isolated from DB changes, so if an issue surfaces we only roll back the backend deploy.

**Independent Test**: Deploy backend with Story 2 changes. Hit each removed route via curl; confirm 404. Hit every retained `/manuals/*` route (ask, rate-answer, verified-answers, settings, models, active-provider, paraphrase-variants, etc.); confirm all still respond as before. Run the full backend test suite; all non-removed tests pass.

**Acceptance Scenarios**:

1. **Given** the backend deployed, **When** any client calls the removed CRUD routes for manuals or chunks, **Then** the server responds 404 (route no longer registered).
2. **Given** the backend deployed, **When** the frontend performs a normal Ask-the-AI flow (ask → rate → review → verified answer CRUD), **Then** every request succeeds with the same response shape as before this spec.
3. **Given** the backend deployed, **When** an admin triggers "index a new knowledge document" via the current knowledge-documents flow, **Then** the indexing pipeline completes without touching any manuals-family table or RPC.

---

### User Story 3 — Database contains no legacy `manuals` tables, RPCs, or FK constraints (Priority: P3)

After Stories 1–2 ship, the `manuals`, `manual_chunks`, and `manual_corpus_stats` tables and their RPCs (`search_manual_chunks`, `create_manual_with_chunks`, `delete_manual_with_stats`) are unreferenced. Two FK constraints still point at `manuals.id`: `manual_chunks.manual_id` (resolved by cascade when manual_chunks is dropped) and `answer_ratings.manual_id`. Dropping is a single migration executed in the right order.

**Why this priority**: Lowest urgency because the tables don't cost anything to keep (they're empty) — but highest irreversibility, so it ships last, after code changes have soaked without regressions. Ships separately so a DB issue can be diagnosed without touching the app.

**Independent Test**: Apply the migration on a staging branch. Confirm (a) `manuals`, `manual_chunks`, `manual_corpus_stats` do not appear in `information_schema.tables`, (b) the three RPC functions are absent from `pg_proc`, (c) `answer_ratings` no longer has a FK constraint to `manuals`, (d) every existing application test suite still passes, (e) `/manuals/ask`, rating, and verified-answer flows all return expected results with the live knowledge-documents corpus.

**Acceptance Scenarios**:

1. **Given** the migration applied, **When** the database is inspected, **Then** the tables `manuals`, `manual_chunks`, `manual_corpus_stats` do not exist.
2. **Given** the migration applied, **When** the database is inspected, **Then** the RPC functions `search_manual_chunks`, `create_manual_with_chunks`, `delete_manual_with_stats` do not exist.
3. **Given** the migration applied, **When** an admin uses the Ask-the-AI assistant end-to-end (ask → rate → create verified answer → retrieve), **Then** every step succeeds against the `knowledge_documents` / `document_chunks` corpus.
4. **Given** the migration applied, **When** the `validated_qa` table is queried, **Then** the `source_manual_id` column still exists and holds existing values (FK was already dropped in the spec-080 migration; this spec does not re-touch it).

---

### Edge Cases

- **Non-empty `manuals` or `manual_chunks` at migration time**: the scope assumes both tables hold zero rows in production. A pre-migration safety check MUST confirm row counts are zero before any DROP executes. If either table is non-empty, migration aborts with a clear message rather than silently discarding data.
- **`answer_ratings` rows with a populated `manual_id`**: the FK constraint is dropped; the column itself is dropped in this spec (no reader code remains once Story 2 ships). Any information in those UUIDs is not preserved — this is acceptable because the column pointed at `manuals.id` values that themselves were never repopulated after corpus migration, so the UUIDs are dangling references by construction.
- **Partial rollout** (e.g., backend deployed before frontend): the frontend still has to call the removed routes. Mitigation: Story 1 ships and is verified before Story 2; the deploy order is part of the plan, not the spec.
- **Other code still importing the deleted model/service classes**: a compile-time build (Flutter analyze + Python import-time) must pass after each story — this is how we detect stragglers.
- **External automation / cron jobs**: no known scheduled jobs touch `manuals` (verified during audit). If one is discovered, it must be cleaned up or redirected to `knowledge_documents` before Story 3.
- **`manual_assistant_settings` table**: despite the name, this holds live Layer 2 AI system-instructions config and is NOT in scope for deletion. The name is misleading but the behavior is active.

## Requirements *(mandatory)*

### Functional Requirements

#### Frontend removal (Story 1)

- **FR-001**: System MUST remove the legacy "Manuals" CRUD tab from the Ask-the-AI screen so it no longer appears in the admin tab bar.
- **FR-002**: System MUST remove the "Old manuals detected / Migrate all" block and all related migration-progress dialogs from the Documents tab.
- **FR-003**: System MUST remove all Flutter source files whose sole purpose is the legacy manuals UI (manuals tab widget, upload dialog used only by that tab, chunk editor screen if exclusively reached from manuals tab, the `Manual` model class, and any icon/helper assets with no other consumer).
- **FR-004**: System MUST remove methods from `manual_assistant_service.dart` that call only the removed backend routes (list/upload/delete a manual, list/get/add/update/delete/split/merge a chunk, bulk-delete chunks, re-embed all chunks).
- **FR-005**: System MUST retain every Flutter service method that calls the AI-assistant surface (ask, ask/stream, rate-answer, rating feedback/delete, flagged-answers, review-answer, paraphrase-variants, verified-answers CRUD and variants, generate-qa-candidates, ratings bulk-delete, real-usage-suggestions, stale-cache-entries, mark-cache-reviewed, models, active-provider, settings GET/POST, `/manuals/count`).
- **FR-006**: System MUST retain the `/manuals/*` URL prefix for the AI-assistant routes (a URL rename is explicitly out of scope for this spec; see Assumptions).
- **FR-007**: System MUST pass `flutter analyze` with no warnings introduced by dangling imports or unused files after Story 1 ships.

#### Backend route & code removal (Story 2)

- **FR-008**: System MUST remove CRUD routes from `backend/routers/manuals.py` that operate on the `manuals` table or `manual_chunks` table: list-manuals, upload-manual, delete-manual, list-chunks, get-chunk, add-chunk, update-chunk, delete-chunk, split-chunk, merge-chunk, re-embed-all, chunks bulk-delete.
- **FR-009**: System MUST remove the three migration routes from `backend/routers/documents.py`: `POST /migrate-all`, `GET /migration-status`, `DELETE /migrate-cleanup`, along with their `_run_migration` helper and the `_migration_status` module-level state.
- **FR-010**: System MUST remove `backend/services/manual_storage_service.py` and the upload/delete paths in `backend/services/manual_rag_service.py` that call the legacy RPCs. **Note**: `backend/services/manual_parser.py` is RETAINED — despite the name, it is imported by `backend/services/document_service.py` for the live knowledge-documents pipeline.
- **FR-011**: System MUST retain every backend route, service, and helper used by the live AI-assistant flow (ask, ask/stream, rate-answer, all verified-answer endpoints, paraphrase-variants, AI provider/settings/model endpoints).
- **FR-012**: System MUST remove the one-time backfill script `backend/scripts/backfill_validated_qa_manual_ids.py` once it is confirmed it has already been run in production.
- **FR-013**: System MUST remove backend tests that exclusively cover the deleted routes and services; remaining tests MUST continue to pass against the retained routes.
- **FR-014**: System MUST preserve `validated_qa.manual_ids` read/write behavior — the column now semantically holds knowledge-documents IDs. No renaming is performed in this spec.

#### Database cleanup (Story 3)

- **FR-015**: System MUST drop the tables `manuals`, `manual_chunks`, and `manual_corpus_stats`, in an order that respects foreign-key constraints (drop `manual_chunks` before `manuals`).
- **FR-016**: System MUST drop the RPC functions `search_manual_chunks`, `create_manual_with_chunks`, and `delete_manual_with_stats`.
- **FR-017**: System MUST drop the foreign-key constraint `answer_ratings.manual_id → manuals.id` and drop the `manual_id` column from `answer_ratings` (no application code reads or writes it after Story 2).
- **FR-018**: System MUST retain the `manual_assistant_settings` table and any other object whose name starts with "manual" but holds live data (the Layer 2 system-instructions singleton).
- **FR-019**: System MUST retain the `validated_qa.source_manual_id` column as-is (its FK was already dropped by the spec-080 migration; this spec does not re-alter it).
- **FR-020**: System MUST perform a pre-migration safety check that fails the migration if `manuals` or `manual_chunks` has any rows — preventing accidental data loss if production state has diverged from the audit.

#### Cross-cutting

- **FR-021**: System MUST present the complete deletion plan (this document) for review before any code or database change is committed.
- **FR-022**: System MUST ship Stories 1 → 2 → 3 in that order, each with its own deploy and verification step, so a regression can be isolated to a single story's changes.

### Key Entities

- **`manuals` (to be dropped)**: one-row-per-uploaded-file metadata table. Columns include title, file_name, file_extension, uploaded_by, chunk_count, timestamps. Production row count: 0. Referenced by `manual_chunks.manual_id` (FK) and `answer_ratings.manual_id` (FK).
- **`manual_chunks` (to be dropped)**: one-row-per-chunk table with 768-dim pgvector embedding. Production row count: effectively 0 (all live chunk data lives in `document_chunks`). Referenced only by `manuals.id` via FK, and indirectly via the `search_manual_chunks` RPC.
- **`manual_corpus_stats` (to be dropped)**: singleton row tracking total uploaded bytes and manual count for an enforced corpus ceiling. Obsolete because the knowledge-documents pipeline has its own accounting.
- **`manual_assistant_settings` (retained)**: singleton row holding the Layer 2 system prompt. Misleadingly named but actively read on every assistant query; unrelated to the `manuals` file corpus.
- **`answer_ratings.manual_id` (column to be dropped)**: nullable UUID FK to `manuals.id`. Not read by any surviving code after Story 2. Dropping the column removes dangling references.
- **`validated_qa.source_manual_id` (retained as-is)**: already decoupled from `manuals` in the spec-080 migration (FK was dropped there). Column continues to hold a loose UUID semantically meaning "source knowledge_document id". Out of scope to rename.
- **`validated_qa.manual_ids` array (retained as-is)**: an UUID[] column whose values now reference `knowledge_documents.id` rows. Name is historically misleading but the semantic is "IDs of source documents". Out of scope to rename.
- **`/manuals/*` URL prefix (retained)**: backend route namespace. Many routes under this prefix (ask, rate, verified-answers, settings, models) belong to the live AI assistant feature and are unrelated to the `manuals` SQL table. Renaming the URL namespace is out of scope.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After Story 1 deploys, zero admin actions lead to a "migrate legacy manuals" or "upload/edit a manual" workflow — both paths are absent from the UI, as verified by clicking every tab and every primary admin button in the Ask-the-AI screen.
- **SC-002**: After Story 2 deploys, every HTTP request the production frontend sends during a typical admin session succeeds (no 404s from stale paths), and any direct call to a removed CRUD route returns 404. Verified by a scripted request against each removed path plus one full admin end-to-end smoke test.
- **SC-003**: After Story 3 deploys, the three legacy tables and three legacy RPCs are absent from the database schema, and the full Ask-the-AI flow (ask → rate → review → verified answer CRUD → ask-again) succeeds end-to-end against the `knowledge_documents` corpus with no error log entries mentioning `manuals`, `manual_chunks`, or `manual_corpus_stats`.
- **SC-004**: The backend Python import graph and Flutter build both complete with no errors introduced by this spec at each story boundary. (Verified by `pytest --collect-only` for backend and `flutter analyze` for frontend.)
- **SC-005**: Lines-of-code reduction: the spec removes at least roughly 900 lines of backend router code and at least roughly 400 lines of Flutter code (concrete numbers to be captured in the plan/tasks phase for accountability; the intent is that this is a meaningful, not cosmetic, cleanup).
- **SC-006**: No user-reported regressions in the first 7 days after Story 3 ships that trace back to a removed route, RPC, or table.

## Assumptions

- **Production data state**: `manuals.count = 0` and `manual_chunks.count = 0` are true at migration time. This was confirmed in a prior session. A pre-migration SELECT COUNT(*) check gates the DROP TABLE statements so the assumption is re-verified at execution time.
- **Corpus ownership**: the live RAG pipeline reads from `document_chunks` (indexed from `knowledge_documents`). Spec 072 performed that migration. No code path in the retained route set reads `manual_chunks` for RAG purposes; the only reads in `manual_rag_service.py` that still touch `manual_corpus_stats` and the legacy RPCs belong to the upload/delete paths being removed in Story 2.
- **`/manuals/*` URL prefix is not renamed**: the user's scope statement targets the SQL table and dead code, not the URL namespace. Frontend and backend both keep `/manuals/*` as the live AI-assistant API surface; a future spec can rename it if desired.
- **`answer_ratings.manual_id` column is dropped, not just FK-unlinked**: spec 080 chose to keep `validated_qa.source_manual_id` as a loose UUID (drop only the FK). For `answer_ratings.manual_id` the cleaner choice is full column drop, because (a) the column's only reader was the FK-driven cascade behavior on `manuals` delete, and (b) no surviving code reads the column. If the user prefers the spec-080 pattern (drop only the constraint), that is a one-line change in the migration.
- **`validated_qa.manual_ids` array column stays named as-is**: despite holding `knowledge_documents.id` values now, the name is preserved to avoid a scope-creeping rename of a backfilled column. A future spec can rename it.
- **One-shot scripts**: `backfill_validated_qa_manual_ids.py` has already been run in production. It is deleted here; if needed for replay, it stays in git history and can be recovered.
- **Deploy order is Stories 1 → 2 → 3**: each story is independently deployable, but they must ship in order so the frontend never calls a removed backend route and the backend never reads a dropped table. Each story has its own verification step before the next one proceeds.
- **No external consumers**: the `/manuals/*` API is not exposed to third parties. Only the project's Flutter app calls it. Removing routes therefore does not require a deprecation/notice period.
- **Dev admin account**: `salah@admin.com` is the account used to exercise admin endpoints during verification.

## Out of Scope

- Renaming the `/manuals/*` URL prefix. A future refactor spec can alias or rename.
- Renaming `validated_qa.manual_ids` or `validated_qa.source_manual_id` columns.
- Renaming the `manual_assistant_settings` table.
- Removing or changing anything under the Ask-the-AI feature surface (ask, rate, verified answers, settings, models, paraphrase, etc.).
- Modifying `knowledge_documents` / `document_chunks` schema or pipeline.
- Changing the embedding model, chunking strategy, or reranker.
- Any UI changes beyond removing the dead Manuals tab and the dead migration block from the Documents tab.

## Dependencies

- The prior migration `20260416000000_knowledge_documents.sql` and related specs 070–072 established `knowledge_documents` / `document_chunks` as the live corpus.
- The prior migration `20260418100000_train_ai_use_knowledge_documents.sql` already removed the FK from `validated_qa.source_manual_id` to `manuals.id`, so no additional work is needed on `validated_qa` in this spec.
- Commit `f0cf05c` (redirecting `get_manual_ids_for_system` in `system_registry.py` to `knowledge_documents`) is already on `main`.
- Production backend must be restartable via `sudo systemctl restart document_server.service` after the Story 2 backend deploy.
