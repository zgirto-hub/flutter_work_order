---

description: "Task list — Spec 090, Delete Legacy `manuals` Table & Dead Code"
---

# Tasks: Delete Legacy `manuals` Table & Dead Code

**Input**: Design documents from `specs/090-delete-legacy-manuals/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/removed-api.md, contracts/retained-api.md, quickstart.md

**Tests**: This spec does NOT introduce new behavior; it removes code. No TDD-style "red test first" tasks are generated. The existing test suite is the regression net — tasks include surgical edits to tests that exclusively covered removed routes. `flutter analyze` and `pytest --collect-only` are the pass/fail gates at each story boundary.

**Organization**: Tasks are grouped by user story so each story is independently shippable (and reversible).

## Format

- Checkbox + TaskID + optional `[P]` + optional `[USn]` + description with exact path.
- `[P]` = parallelizable (different file, no dep on a task earlier in the same phase).
- `[US1]`/`[US2]`/`[US3]` = the story the task belongs to.

## Path Conventions

- **Frontend**: `frontend/lib/...`
- **Backend**: `backend/routers/`, `backend/services/`, `backend/scripts/`, `backend/tests/`
- **DB migrations**: `supabase/migrations/`
- **Docs**: repo root (`CLAUDE.md`, `AGENT.md`)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm we're on the right branch and capture a clean baseline so regressions are attributable.

- [ ] T001 Verify current branch is `090-delete-legacy-manuals` via `git branch --show-current`; if not, check it out before proceeding
- [ ] T002 [P] Capture baseline frontend analyze output: run `cd frontend && flutter analyze` and save the summary (should be zero pre-existing warnings or a known count) — treat any new warning introduced by later tasks as a regression
- [ ] T003 [P] Capture baseline backend test collection: run `cd backend && pytest --collect-only -q` and confirm it completes without errors; save the count of collected tests for later comparison

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Verify production data state matches spec assumptions. This is the only gate that blocks Story 3; Stories 1 and 2 are pure code changes with no data dependency, but the confirmation is cheap and is run before any story starts so the plan doesn't advance past the first story if data has drifted.

**⚠️ CRITICAL**: If T004 reveals non-zero rows in either table, stop and consult the user before proceeding with any story.

- [ ] T004 Confirm `manuals` and `manual_chunks` row counts are both zero in production via `mcp__claude_ai_Supabase__execute_sql` with the query `SELECT (SELECT COUNT(*) FROM manuals) AS manuals_n, (SELECT COUNT(*) FROM manual_chunks) AS chunks_n;` — both MUST equal 0. Record the result as evidence before starting Story 3.

**Checkpoint**: Branch confirmed, baseline captured, production data state re-verified. Stories 1–3 may now proceed.

---

## Phase 3: User Story 1 — Remove dead admin UI (Priority: P1) 🎯 MVP

**Goal**: Eliminate the legacy Manuals tab, the "Migrate old manuals" block in the Documents tab, and every frontend service method that calls removed backend routes. Production admins see a clean Ask-the-AI screen with only the surfaces they actually use.

**Independent Test**: Deploy only the frontend. Log in as `salah@admin.com`, open Ask the AI, inspect the tab bar (no Manuals tab — already absent on main, this story deletes the orphaned file), open the Documents tab (no Old Manuals block, no Migrate-all button), then exercise Chat / Review Queue / Rules / Alerts / Verified Answers / Documents / Train AI / RAG Logs tabs — every one works identically. Full quickstart Story 1 checklist in [quickstart.md](quickstart.md#story-1--frontend-removal) passes.

### Implementation for User Story 1

- [ ] T005 [P] [US1] Delete the orphaned legacy Manuals tab file [frontend/lib/screens/manual_assistant/manuals_tab.dart](frontend/lib/screens/manual_assistant/manuals_tab.dart) — verified not rendered in `manual_assistant_screen.dart` tab bar on main; 186 lines
- [ ] T006 [P] [US1] Delete the legacy chunk editor screen [frontend/lib/screens/manual_assistant/chunk_editor_screen.dart](frontend/lib/screens/manual_assistant/chunk_editor_screen.dart) — only caller is `manuals_tab.dart` which is also being deleted; 502 lines
- [ ] T007 [P] [US1] Delete the legacy upload dialog [frontend/lib/screens/manual_assistant/widgets/upload_dialog.dart](frontend/lib/screens/manual_assistant/widgets/upload_dialog.dart) — only caller is `manuals_tab.dart`
- [ ] T008 [US1] Trim legacy-manuals migration block from [frontend/lib/screens/manual_assistant/documents_tab.dart](frontend/lib/screens/manual_assistant/documents_tab.dart) — remove the `_checkOldManuals()` helper (lines ~434–445), the `_migrationStatus` state, `_startMigration()`, `_pollMigrationStatus()`, `_showMigrationStatus()`, `_showMigrationSummary()` helpers and every widget they render (the "Old manuals detected" banner, "Migrate all" button, progress dialog) while leaving the live knowledge-documents UI untouched. Remove now-unused imports (e.g. `package:http/http.dart` only if no other method uses it). Target end state: the Documents tab shows only live knowledge_documents. ~80 lines removed.
- [ ] T009 [US1] Trim removed-route callers from [frontend/lib/services/manual_assistant_service.dart](frontend/lib/services/manual_assistant_service.dart) — delete these methods verbatim and their helper imports: `listManuals` (around line 125), `uploadManual` (around line 155), `deleteManual` (around line 429), `listChunks` (~732), `getChunk` (~747), `addChunk` (~793), `updateChunk` (the `put` variant near 779), `deleteChunk` (~762), `splitChunk` (~815), `mergeChunk` (~833), `reEmbedAll` (~850), `bulkDeleteChunks` (~866). Retain every other method listed in [contracts/retained-api.md](contracts/retained-api.md). Remove the `Manual` type import if it becomes unused (T010 will delete that file next).
- [ ] T010 [US1] Delete the now-unused Manual model [frontend/lib/models/manual.dart](frontend/lib/models/manual.dart) — last consumers are removed by T005–T009. If grep finds any remaining reference, resolve it before deleting (do not leave broken imports).
- [ ] T011 [US1] Run `cd frontend && flutter analyze` and confirm zero new warnings vs. the T002 baseline. Any new warning about an undefined symbol, dangling import, or unused method means a T005–T010 step missed a reference — fix before proceeding.
- [ ] T012 [US1] Manually exercise the Ask-the-AI screen per the [quickstart Story 1 browser checklist](quickstart.md#what-to-check-in-the-browser) in a local `flutter run` or `flutter build web` preview. Confirm: no "Manuals" tab, no "Old manuals" block, Chat answers, rating works, settings dialog saves. If any step fails, fix before deploying.
- [ ] T013 [US1] Deploy the frontend to production via `bash scripts/deploy_frontend.sh`. Repeat the [quickstart Story 1 browser checklist](quickstart.md#what-to-check-in-the-browser) against the deployed PWA before marking this task done. On success, commit the diff and open a PR (squash-merge into `main`).

**Checkpoint**: Frontend is clean and in production. Story 2 may begin after at least one admin session exercises the new UI without regression.

---

## Phase 4: User Story 2 — Remove dead backend routes and services (Priority: P2)

**Goal**: Backend exposes zero routes that read or write the `manuals` / `manual_chunks` / `manual_corpus_stats` tables. The retained `/manuals/*` AI-assistant surface (ask, rate, verified-answers, settings, models, …) is untouched and keeps working against `knowledge_documents` / `document_chunks`.

**Independent Test**: Deploy backend only. Run the curl matrix from [quickstart Story 2](quickstart.md#story-2--backend-removal) — every removed path returns 404, every retained path returns its normal payload. Repeat the full admin UI flow; no new dev-tools network errors. `cd backend && pytest` passes.

### Implementation for User Story 2

- [ ] T014 [US2] Trim CRUD routes from [backend/routers/manuals.py](backend/routers/manuals.py) — remove these handlers and nothing else: `list_manuals` (~209), `upload_manual` (~258), `delete_manual` (~349), `re_embed_all` (~2147), `bulk_delete_chunks` (~2219), `list_chunks` (~2244), `add_chunk` (~2300), `get_chunk` (~2391), `update_chunk` (~2416), `delete_chunk` (~2467), `split_chunk` (~2491), `merge_chunk` (~2620). Leave every handler listed in [contracts/retained-api.md](contracts/retained-api.md). Remove now-unused Pydantic request models if they are only used by the removed handlers. Remove now-unused imports. The router's final line count should drop from 2696 to ~1500–1700.
- [ ] T015 [P] [US2] Trim migration helpers from [backend/routers/documents.py](backend/routers/documents.py) — remove `migrate_all_documents` (POST /migrate-all, ~181), `get_migration_status` (GET /migration-status, ~268), `migrate_cleanup` (DELETE /migrate-cleanup, ~274), plus the `_run_migration` async helper (~209) and the module-level `_migration_status` dict. Remove now-unused imports (`BackgroundTasks` if only used here). Leave all other document-registry routes untouched.
- [ ] T016 [US2] Trim upload/delete logic from [backend/services/manual_rag_service.py](backend/services/manual_rag_service.py) — remove the `upload_manual` function (the one calling `create_manual_with_chunks` RPC around line 984) and the `delete_manual` function (calling `delete_manual_with_stats` RPC around line 2225). Remove the `manual_corpus_stats` ceiling check (around line 945–956) and stats-update call sites (~1248, ~1623). Remove the top-level import `from services.manual_storage_service import save, delete as delete_file` at line 14 and the nested re-import at line 2222. **RETAIN** everything else — the entire `/manuals/ask` RAG pipeline (HyDE, rewrite, retrieval against `document_chunks`, rerank, synthesis, generation, helpers), the paraphrase/variants logic, and the verified-QA helpers. After the trim the file should still import, pytest should still collect, and `/manuals/ask` behavior is unchanged.
- [ ] T017 [P] [US2] Delete [backend/services/manual_storage_service.py](backend/services/manual_storage_service.py) — only callers are the `manual_rag_service.py` imports removed in T016. Confirm with `git grep manual_storage_service backend/` before deleting; expected result after T016: no matches.
- [ ] T018 [P] [US2] Delete the one-shot backfill script [backend/scripts/backfill_validated_qa_manual_ids.py](backend/scripts/backfill_validated_qa_manual_ids.py) — already run in production; preserved in git history for replay.
- [ ] T019 [P] [US2] Delete [backend/tests/routers/test_manuals_bulk_delete.py](backend/tests/routers/test_manuals_bulk_delete.py) — every test in this file exercises the removed `DELETE /manuals/{manual_id}/chunks/bulk-delete` route.
- [ ] T020 [US2] Trim or delete [backend/tests/test_derive_manual_ids.py](backend/tests/test_derive_manual_ids.py) — audit each test; keep assertions that exercise `derive_manual_ids` against `knowledge_documents`, delete assertions that require a row in the `manuals` table. If every assertion requires `manuals`, delete the whole file. Update fixtures accordingly.
- [ ] T021 [P] [US2] Audit [backend/tests/test_manual_rag_latency.py](backend/tests/test_manual_rag_latency.py) — keep ask-path latency assertions; delete any test that calls removed upload-path helpers or seeds the `manuals` table. If only retained helpers are covered, no edit is needed.
- [ ] T022 [P] [US2] Audit [backend/tests/test_sentinel_phrases.py](backend/tests/test_sentinel_phrases.py) — grep-confirmed to reference `manual_storage_service` / `manual_parser`. Remove references to `manual_storage_service` (dead after T017). Keep `manual_parser` references (still live — see note below the task list). Run the file's tests locally to confirm green.
- [ ] T023 [P] [US2] Audit [backend/tests/conftest.py](backend/tests/conftest.py) — the file only mentions `manual_parser` in a docstring comment (no active mock). No edit required unless new mocks are added for `manual_storage_service`; in that case remove the mock entry.
- [ ] T024 [US2] Run `cd backend && pytest -x` and confirm every collected test passes. Test count should drop by ~the number of removed test cases — compare to T003 baseline.
- [ ] T025 [US2] Smoke-test backend locally by starting the FastAPI server and executing the curl matrix from [quickstart Story 2](quickstart.md#what-to-check-via-curl) against `localhost`: every removed path returns 404, every retained path returns its normal payload.
- [ ] T026 [US2] Deploy backend to production: push the branch, on the server run `cd backend && pip install -r requirements.txt` (no new deps expected — this is the cautious habit from memory), then `sudo systemctl restart document_server.service` and `sudo systemctl status document_server.service`. Tail `journalctl -u document_server.service --since "1 min ago"` for errors.
- [ ] T027 [US2] Re-run the [quickstart Story 2 curl matrix](quickstart.md#what-to-check-via-curl) against the production URL `https://zorin.taila92fe8.ts.net`. On success, commit the diff and open a PR (squash-merge into `main`). **Note on manual_parser.py**: despite the name, this file is RETAINED — `backend/services/document_service.py:31` imports `parse` from it for the live knowledge-documents pipeline. Do NOT delete it at any point in this story.

**Checkpoint**: Backend routes/services are trimmed and in production. Story 3 may begin after at least one working day of soak with no regression reports.

---

## Phase 5: User Story 3 — Drop legacy database objects (Priority: P3)

**Goal**: Database contains no `manuals`, `manual_chunks`, `manual_corpus_stats` tables; no `search_manual_chunks` / `create_manual_with_chunks` / `delete_manual_with_stats` RPCs; no `answer_ratings.manual_id` column or FK. `manual_assistant_settings` and `validated_qa.source_manual_id` / `manual_ids` are preserved.

**Independent Test**: Apply the migration on a branch/staging DB first, then on production. Run the post-migration verification queries from [quickstart Story 3](quickstart.md#post-migration-verification) — all expected counts match. Exercise the full Ask-the-AI flow (ask → rate → create verified answer → retrieve); every step works. Tail `journalctl -u document_server.service` during the test — no mentions of `manuals`, `manual_chunks`, etc.

### Implementation for User Story 3

- [ ] T028 [US3] Create the migration file [supabase/migrations/20260420_drop_legacy_manuals.sql](supabase/migrations/20260420_drop_legacy_manuals.sql) using the shape in [data-model.md §Migration shape](data-model.md#migration-shape-non-normative-outline--real-sql-in-tasks-phase). The file MUST contain, in this exact order: (1) a `DO $$ … RAISE EXCEPTION` safety gate that aborts if `manuals` or `manual_chunks` has any rows; (2) `ALTER TABLE answer_ratings DROP CONSTRAINT IF EXISTS answer_ratings_manual_id_fkey;` and `ALTER TABLE answer_ratings DROP COLUMN IF EXISTS manual_id;`; (3) `DROP FUNCTION IF EXISTS` for `search_manual_chunks`, `create_manual_with_chunks`, `delete_manual_with_stats` (match existing signatures from [supabase/migrations/20260411000000_create_manuals.sql](supabase/migrations/20260411000000_create_manuals.sql)); (4) `DROP TABLE IF EXISTS manual_chunks; DROP TABLE IF EXISTS manuals; DROP TABLE IF EXISTS manual_corpus_stats;` Wrap the whole thing in `BEGIN; … COMMIT;`. Do NOT drop `manual_assistant_settings`, `validated_qa.source_manual_id`, or anything else.
- [ ] T029 [US3] Create a Supabase dev branch via `mcp__claude_ai_Supabase__create_branch` and apply the migration on the branch via `mcp__claude_ai_Supabase__apply_migration`. Confirm the branch DB reports: three target tables gone, three target RPCs gone, `answer_ratings.manual_id` column + FK gone, `manual_assistant_settings` present, `validated_qa.source_manual_id` present. Use the SQL verification block in [quickstart Story 3](quickstart.md#post-migration-verification).
- [ ] T030 [US3] With the dev-branch DB attached, run the full backend test suite (`cd backend && pytest`) and exercise `/manuals/ask` end-to-end — confirm zero errors referencing dropped objects. If any test fails, fix (typically a residual import or a leftover field in a response model) and re-test before moving on.
- [ ] T031 [US3] Apply the migration to production. Prefer `mcp__claude_ai_Supabase__apply_migration` against the production project; fallback to psql against `$SUPABASE_URL`. The safety gate should silently pass (zero rows confirmed in T004); if the migration raises the exception, STOP — do not drop `IF EXISTS` to bypass; investigate the non-zero row count first.
- [ ] T032 [US3] Run all post-migration verification queries from [quickstart Story 3](quickstart.md#post-migration-verification) against production and confirm every expected count matches (0/0/0 for dropped objects, 1/1 for retained objects).
- [ ] T033 [US3] Re-run the full admin browser checklist from [quickstart Story 1](quickstart.md#what-to-check-in-the-browser) against the production PWA. Simultaneously tail `sudo journalctl -u document_server.service -f` on the server — confirm no log entry mentions `manuals`, `manual_chunks`, `manual_corpus_stats`, `search_manual_chunks`, `create_manual_with_chunks`, or `delete_manual_with_stats`. On success, commit the migration file, merge into `main`.
- [ ] T034 [US3] Optionally delete the Supabase dev branch via `mcp__claude_ai_Supabase__delete_branch` once Story 3 is green in production.

**Checkpoint**: All three legacy DB objects and their FKs are gone from production. 7-day soak period (SC-006) begins.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Update project-wide documentation and user-memory so future specs don't reintroduce references to the removed surfaces.

- [ ] T035 [P] Update [CLAUDE.md](CLAUDE.md) — remove any line in the "Active Technologies" or "Recent Changes" sections that specifically references the `manuals` or `manual_chunks` tables, the removed RPCs, or the Manuals tab. Preserve entries that reference the retained `knowledge_documents` / `document_chunks` pipeline. Do not remove entries for unrelated specs.
- [ ] T036 [P] Update [AGENT.md](AGENT.md) if it contains a features checklist or architecture section that lists the `manuals` table or Manuals tab — trim only the removed surfaces; leave Ask-the-AI feature descriptions intact.
- [ ] T037 [P] Update the user memory index at `C:\Users\Aftn2\.claude\projects\c--Development-flutter-work-order\memory\MEMORY.md` — add a one-line pointer under "## Project" to a new memory file noting that spec 090 completed. Do NOT rewrite existing memory entries; only append the pointer and create the detail file per the auto-memory pattern.
- [ ] T038 Run the full [quickstart.md](quickstart.md) one more time end-to-end against production (Stories 1 + 2 + 3 verifications). This is the final regression gate before closing the spec.
- [ ] T039 Write a one-paragraph completion note in the PR description summarizing what was removed and linking to [spec.md](spec.md) for future readers. The PR becomes the canonical historical record once merged.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: depends on Setup. Blocks all stories; T004 especially gates Story 3.
- **User Story 1 (Phase 3)**: depends on Foundational. Ships and is verified in production BEFORE Story 2 starts.
- **User Story 2 (Phase 4)**: depends on User Story 1 being live in production. A backend route removal while the old frontend is still deployed would cause a visible 404 regression (Stories 1→2 hard ordering per [research.md Decision 7](research.md#decision-7--deploy-order-hard-constraint-stories-1--2--3)).
- **User Story 3 (Phase 5)**: depends on User Story 2 being live in production for at least one full working day. A DB drop while the old backend still has route handlers would 500 on every call.
- **Polish (Phase 6)**: depends on User Story 3.

### Within-story ordering

**Story 1**: T005–T007 and T010 are pure file deletes and can run in parallel. T008 and T009 are single-file trims and can also run in parallel with the deletes. T011 (analyze), T012 (local test), T013 (deploy) are strictly sequential and depend on every earlier Story-1 task.

**Story 2**: T014 (routers/manuals.py trim) is sequential — one file, long edit. T015 (routers/documents.py) is a separate file and can run in parallel with T014. T016 (manual_rag_service.py trim) must happen BEFORE T017 (delete manual_storage_service.py) because T017's safety check depends on T016 having removed the import. T018–T023 are parallelizable test/file deletes that don't overlap T014–T017. T024 (pytest), T025 (local smoke), T026 (deploy), T027 (production smoke) are sequential and gate each other.

**Story 3**: T028 (write migration), T029 (apply on branch), T030 (test against branch), T031 (apply to prod), T032 (verify), T033 (soak-in-browser), T034 (optional branch cleanup) are strictly sequential; no parallelism possible.

### Parallel Opportunities

- Within Phase 1: T002 and T003 in parallel.
- Within Phase 3 (Story 1): T005, T006, T007, T008, T009, T010 all in parallel (each is a different file); then T011→T012→T013 sequentially.
- Within Phase 4 (Story 2): T014 and T015 in parallel; then T016 must precede T017; T018, T019, T020, T021, T022, T023 all in parallel with T016 and with each other; then T024→T025→T026→T027 sequentially.
- Within Phase 5 (Story 3): none — ordered.
- Within Phase 6: T035, T036, T037 in parallel; T038 sequential; T039 sequential.

---

## Parallel Example — Story 1 deletion burst

```text
# Six independent file edits, same story, no cross-file dependencies:
Task T005: delete frontend/lib/screens/manual_assistant/manuals_tab.dart
Task T006: delete frontend/lib/screens/manual_assistant/chunk_editor_screen.dart
Task T007: delete frontend/lib/screens/manual_assistant/widgets/upload_dialog.dart
Task T008: trim documents_tab.dart to remove migration block
Task T009: trim manual_assistant_service.dart to remove CRUD methods
Task T010: delete frontend/lib/models/manual.dart
# Then sequentially:
Task T011: flutter analyze
Task T012: local browser test
Task T013: deploy + production browser test
```

## Parallel Example — Story 2 test/support cleanup

```text
# After T014 and T016 are done, these can run in any order / in parallel:
Task T017: delete backend/services/manual_storage_service.py
Task T018: delete backend/scripts/backfill_validated_qa_manual_ids.py
Task T019: delete backend/tests/routers/test_manuals_bulk_delete.py
Task T020: audit/trim backend/tests/test_derive_manual_ids.py
Task T021: audit backend/tests/test_manual_rag_latency.py
Task T022: trim backend/tests/test_sentinel_phrases.py
Task T023: audit backend/tests/conftest.py
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Run Phase 1 (Setup) and Phase 2 (Foundational) — fast, read-only except for branch check.
2. Run Phase 3 (User Story 1). Deploy frontend.
3. STOP and VALIDATE — observe production for at least one admin session.
4. If the MVP is the only thing this iteration, the feature is already a win (UI noise gone). Ship.

### Incremental delivery (recommended default)

1. MVP as above.
2. After one admin session of Story-1 soak, start Story 2 (backend). Deploy + smoke.
3. After one working day of Story-2 soak, start Story 3 (migration). Apply + verify.
4. Phase 6 (polish) after Story 3 is green.

### Parallel team strategy

Not applicable at team scale — the spec is small and the three stories are intentionally sequenced by production deploy order, not by developer capacity. A single engineer can complete the whole spec in 1–2 working days.

---

## Notes

- Every task is immediately executable — the implementer does not need to guess file paths or line numbers.
- Task T027's footer is a CRITICAL correction: `manual_parser.py` is RETAINED (imported by `document_service.py:31`). Earlier drafts of the plan flagged it for deletion; this was incorrect and has been fixed in the artifacts.
- If a task description says "around line X", treat the number as navigational only — do a grep for the function name to find the real location before editing.
- Commit after each checkpoint (end of Phase 3, Phase 4, Phase 5) at minimum; committing after each individual task is even better for bisectability.
- No task modifies `backend/version.json` — that file is managed on the server (per `feedback_backend_version_json.md` in user memory) and MUST NOT be committed from the dev machine.
- When installing backend dependencies on the server in T026, do it even though no new packages are expected (per `feedback_install_deps_before_deploy.md`) — habit beats surprise.
- Restart the backend service after any route change (T026) per `feedback_restart_backend_after_routes.md` in user memory; do not skip.
