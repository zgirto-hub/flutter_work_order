---

description: "Task list for spec 088 — RAG Refusal Diagnostic Logging"
---

# Tasks: RAG Refusal Diagnostic Logging

**Input**: Design documents from `/specs/088-rag-refusal-diagnostic/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/diagnostic-api.md ✓, quickstart.md ✓

**Tests**: Contract tests are included because they were designed in contracts/diagnostic-api.md. No broader TDD suite — behaviour-preserving observability is validated end-to-end by re-running `backend/tests/test_rag_quality.py` (SC-004).

**Organization**: Tasks grouped by user story (P1 → P2 → P3). Phase 2 (Foundational) blocks every user story phase.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 = P1, US2 = P2, US3 = P3 from spec.md
- File paths are absolute-from-repo-root and exact

## Path Conventions

Web application layout (per plan.md):

- Backend under `backend/` — FastAPI + Supabase Python client
- Frontend under `frontend/lib/` — Flutter
- Migrations under `supabase/migrations/`
- Tests under `backend/tests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the workspace is ready. Spec 088 has no new dependencies, so setup is minimal.

- [x] T001 Verify current branch is `088-rag-refusal-diagnostic` and `backend/tests/test_rag_quality.py` on the branch matches the 2026-04-19 baseline (rewritten questions, 87 total). If the branch or test file is wrong, stop and realign with `main` before proceeding.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the write path — without these, no user story produces data. All tasks in this phase MUST complete before any user-story phase begins.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T002 Write Supabase migration in `supabase/migrations/20260419000000_rag_diagnostic_log.sql` per the schema in data-model.md: `CREATE TABLE rag_diagnostic_log` with 11 columns (id, created_at, user_email, source, question_raw, decision, reason_code, reason_note, pipeline_stages jsonb, thresholds jsonb, latency_breakdown jsonb, provider_used); `CHECK` constraints on source/decision/reason_code and the decision↔reason_code consistency check; compound index `rag_diagnostic_log_filter_idx` on `(source, decision, reason_code, created_at DESC)`; single index `rag_diagnostic_log_created_at_idx` on `(created_at)`; `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`; admin-only `SELECT` policy; `CREATE EXTENSION IF NOT EXISTS pg_cron;` followed by `SELECT cron.schedule('rag-diagnostic-prune', '15 3 * * *', $$...$$)` with the asymmetric DELETE statement (30d refused/errored, 7d grounded). Apply the migration against the dev Supabase and confirm the table + RLS + cron job exist.
- [x] T003 [P] Extend `AskRequest` Pydantic model in `backend/routers/manuals.py` by adding optional field `source: Optional[Literal['user', 'test_suite', 'internal']] = 'user'`. Confirm existing frontend callers without the field continue to resolve to `'user'` (no schema error on missing key).
- [x] T004 Create `backend/services/rag_diagnostic_service.py` containing: (a) a pure function `classify_reason_code(diagnostic: dict, answer: str, grounded: bool) -> tuple[str, str, str]` returning `(decision, reason_code, reason_note)` and implementing first-trigger-wins over the six closed reason codes defined in research.md R-02; (b) an async `persist_entry(supabase_client, entry_payload: dict)` that INSERTs one row into `rag_diagnostic_log` with a try/except that increments a module-level `_write_failure_counter` and logs to stderr on failure (never raises to caller); (c) a module-level `get_failure_stats() -> dict` exposing `in_process_write_failures_last_hour` and `last_successful_write_at` (use a time-windowed deque for the hour count).
- [x] T005 Extend `backend/services/manual_rag_service.py`: alongside the existing spec-066 `_StageTimer` class, add helper function `_record_stage(diagnostic: dict, stage: str, data: dict)` that mutates `diagnostic[stage]` with the supplied dict. Do NOT repurpose `_StageTimer` — `_record_stage` is purely a writer. Thread calls to `_record_stage(diagnostic, 'rewrite', {...})` inside `_rewrite_query`, `_record_stage(diagnostic, 'hyde', {...})` inside `_generate_hypothetical_answer`, `_record_stage(diagnostic, 'retrieval', {'candidates': [...], 'k': ...})` after the hybrid search, and `_record_stage(diagnostic, 'rerank', {'scored': [...], 'top_score': ..., 'threshold_applied': MAX_CHUNK_DISTANCE})` after the rerank filter. Retrieval candidates MUST include `chunk_id`, `manual_title`, `document_name`, `score_vector`, `score_bm25`, `score_hybrid`, and a 120-char `preview`. **Stages MUST only write to the dict — never read back from it**, preserving FR-013.
- [x] T006 Thread the same `diagnostic: dict` parameter through `backend/services/agentic_tools.py:run_agentic_loop` (add it to the signature, default `None`, and pass it to every call into `manual_rag_service` functions modified in T005). When `diagnostic is None`, functions MUST no-op on `_record_stage` — preserves callers that don't request diagnostics (none today, but defensive).
- [x] T007 Wire the persistence hook into `ask_question` in `backend/routers/manuals.py` (handler at line 573). Allocate a fresh `diagnostic: dict = {}` at the top of the handler. Pass it into `run_agentic_loop`. After the response dict is assembled (around line 744 where the JSON is built, before return): call `classify_reason_code` from T004 to derive `(decision, reason_code, reason_note)`; handle the sentinel-phrase override at lines 708-722 by setting a `grounding.sentinel_phrase_detected=True` flag in the diagnostic dict so the classifier sees it; build the payload row (id=new uuid, created_at=now, user_email, source=request.source, question_raw=request.question, decision, reason_code, reason_note, pipeline_stages=diagnostic, thresholds={'max_chunk_distance': MAX_CHUNK_DISTANCE, 'verbatim_match_min': 0.85}, latency_breakdown=response['latency_breakdown'], provider_used=response.get('provider_used')); schedule persistence via `asyncio.create_task(persist_entry(...))`; schedule a fire-and-forget `log_activity(user_email, 'manual', 'rag_diagnostic_logged', target_id=str(diagnostic_row_id))` heartbeat. The background task MUST NOT delay the response.
- [x] T008 [P] Update `backend/tests/test_rag_quality.py` — modify the `payload` dict inside `run_test` (around line 866) to include `'source': 'test_suite'`. No other test changes. Confirm the file still parses with `python -c "import ast; ast.parse(open('backend/tests/test_rag_quality.py').read())"`.

**Checkpoint**: Foundation ready — every `/api/manuals/ask` call now produces a row in `rag_diagnostic_log`. Verify with `SELECT COUNT(*) FROM rag_diagnostic_log` before and after a single test-suite question.

---

## Phase 3: User Story 1 — Classify a single refusal (Priority: P1) 🎯 MVP

**Goal**: Admin can open a screen, find the log entry for a specific refused question, and see exactly which pipeline stage caused the refusal.

**Independent Test** (from spec.md US1): Ask the AI a question that the test suite shows is refused. Open the admin RAG Logs tab, find the entry, confirm it identifies which stage caused the refusal with enough detail to classify into one of the three named root-cause buckets (retrieval empty / rerank threshold / generator refused).

### Backend — admin query endpoints

- [x] T009 [US1] Create `backend/routers/admin_rag_diagnostics.py` with: admin-role guard dependency (copy the pattern from the existing admin-only route — see how other admin endpoints check `users.role='admin'` in the project); `GET /api/admin/rag-diagnostics` endpoint accepting query params `source` (optional enum), `decision` (optional enum), `reason_code` (optional enum), `from` (ISO-8601, default now-24h), `to` (ISO-8601, default now), `limit` (default 50, max 200), `offset` (default 0); query Supabase with the compound filter + ORDER BY created_at DESC + pagination; response shape per contracts/diagnostic-api.md §2 — `{entries: [...], total, limit, offset}`; **omit `pipeline_stages` and `thresholds`** from list rows for bandwidth (contract §2 note).
- [x] T010 [US1] Add `GET /api/admin/rag-diagnostics/{id}` to the same router. Returns the full row per contracts/diagnostic-api.md §3 (all 11 columns including the JSONB payloads). `404` if id not found.
- [x] T011 [P] [US1] Wire `admin_rag_diagnostics` router into the FastAPI app in `backend/main.py` (or whichever file includes routers — match the existing pattern for other admin routers). Prefix `/api/admin/rag-diagnostics`.

### Contract tests

- [x] T012 [P] [US1] Create `backend/tests/test_admin_rag_diagnostics.py` with contract test `test_list_endpoint_returns_expected_schema`: seed 3 rows (2 ungrounded, 1 grounded) in a test Supabase fixture, GET `/api/admin/rag-diagnostics?decision=ungrounded` with admin JWT, assert response has keys `{entries, total, limit, offset}`, `total==2`, each entry has all documented fields, `pipeline_stages` and `thresholds` absent from list response.
- [x] T013 [P] [US1] In the same file, add `test_detail_endpoint_returns_full_payload`: GET `/api/admin/rag-diagnostics/{id}` for one of the seeded rows, assert every column from data-model.md is present including `pipeline_stages` and `thresholds` JSONB; assert 404 for unknown id; assert 403 for non-admin JWT.

### Frontend — list view + detail dialog

- [x] T014 [P] [US1] Create `frontend/lib/models/rag_diagnostic_entry.dart` — Dart class mirroring the list and detail payloads. Two constructors: `RagDiagnosticEntry.fromListJson` (list-view shape without JSONB payloads) and `RagDiagnosticEntry.fromDetailJson` (full shape). Fields: id (String), createdAt (DateTime), userEmail (String), source (String), questionRaw (String), decision (String), reasonCode (String), reasonNote (String?), providerUsed (String?), latencyBreakdown (Map<String,dynamic>), pipelineStages (Map<String,dynamic>? — null in list mode), thresholds (Map<String,dynamic>? — null in list mode).
- [x] T015 [P] [US1] Create `frontend/lib/services/rag_diagnostic_service.dart` — HTTP client with `fetchEntries({source, decision, reasonCode, from, to, limit, offset})` returning `List<RagDiagnosticEntry>` + `int total`, and `fetchDetail(String id)` returning full entry. Use the existing `http` dependency and the base URL from `config.dart` via `kIsProduction`. JWT from the existing Supabase auth session.
- [x] T016 [US1] Create `frontend/lib/screens/manual_assistant/rag_diagnostics_tab.dart` — Flutter widget with: header row of filter controls (source dropdown, decision dropdown, reason-code dropdown, time-range picker with presets `last 1h / last 24h / last 7d`); paginated `ListView.builder` of entries showing `[decision badge] [reason_code pill] question_raw[:80] (latency_breakdown.total_ms ms)`; tap opens a bottom sheet / dialog rendering the full detail via `fetchDetail`. Detail view shows the four stage sections (rewrite, hyde, retrieval with candidate table, rerank with score table) plus grounding decision + reason note. Follow the existing `bottom_sheet_widgets.dart` style for sheet structure.
- [x] T017 [US1] Register the new tab in `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart`: extend the admin-gated TabController (`length: _isAdmin ? 8 : 1` — currently 7, adding one) and append `if (_isAdmin) RagDiagnosticsTab(userEmail: _userEmail, service: RagDiagnosticService(...))` to the tab children list, with a `Tab(text: 'RAG Logs')` in the tab bar. Keep the existing Train AI tab and its ordering unchanged.

**Checkpoint**: SC-001 is now verifiable — the admin can run the quality suite (T008 ensures `source=test_suite`), open the RAG Logs tab filtered to `source=test_suite`, tap any ungrounded row, and see the per-stage breakdown identifying the root cause. User Story 1 independently functional.

---

## Phase 4: User Story 2 — Classify a batch of refusals (Priority: P2)

**Goal**: Admin can see refusal counts grouped by reason code for a selected time range, and export the counts as CSV for offline analysis.

**Independent Test** (from spec.md US2): Run the 87-question RAG quality suite. Open the RAG Logs tab. Confirm a summary panel shows refusal counts grouped by reason code, and the numbers sum to the total refusal count observed in the suite.

### Backend — summary + export endpoints

- [ ] T018 [US2] Add `GET /api/admin/rag-diagnostics/summary` to `backend/routers/admin_rag_diagnostics.py` accepting query params `source`, `from`, `to` (same semantics as the list endpoint). Returns `{from, to, total_requests, by_decision, by_reason_code}` per contracts/diagnostic-api.md §4. Implement as a single SQL query using `GROUP BY` on both reason_code and decision via two CTEs (or two queries — simpler wins at this volume). Every reason_code key present with value 0 if no entries match. MUST complete in under 3s at 9K rows (SC-003).
- [ ] T019 [US2] Add `GET /api/admin/rag-diagnostics/export` to the same router. Same query params as `/summary`. Returns `text/csv` with header row `reason_code,count` and one row per reason code in the fixed vocabulary order defined in research.md R-02. `Content-Disposition: attachment; filename="rag-diagnostics-summary-<from>-to-<to>.csv"`.

### Contract tests

- [ ] T020 [P] [US2] Add `test_summary_endpoint_groups_correctly` to `backend/tests/test_admin_rag_diagnostics.py`: seed 10 rows across 4 reason codes, GET `/summary`, assert `by_reason_code` sums to `total_requests`, assert every enum reason-code is a key (even with value 0).
- [ ] T021 [P] [US2] Add `test_export_returns_csv`: GET `/export`, assert `Content-Type: text/csv`, assert first line is `reason_code,count`, assert 7 data rows (one per enum value) in the documented order, assert the Content-Disposition header contains a filename.

### Frontend — summary panel + export button

- [ ] T022 [US2] Add a summary panel to the top of `frontend/lib/screens/manual_assistant/rag_diagnostics_tab.dart` (above the filter row). It calls `/summary` with the current filter and renders a small table of reason-code → count, plus a single `Export CSV` button that hits `/export` and triggers a browser download via the existing `download_helper_web.dart` (do NOT use `url_launcher`, per Constitution). Refresh the summary when filters change.

**Checkpoint**: SC-002 is now verifiable — admin runs suite, opens summary, sees refusal counts sum correctly. User Stories 1 AND 2 independently functional.

---

## Phase 5: User Story 3 — Inspect a successful answer to contrast with a refusal (Priority: P3)

**Goal**: Admin can compare two entries (e.g., one successful, one refused on the same topic) without losing filter context in the list view.

**Independent Test** (from spec.md US3): Submit two questions on the same topic — one with full technical terms (likely answered), one with abbreviations (likely refused). Open both detail views in the RAG Logs tab and view them at the same time.

- [ ] T023 [US3] In `frontend/lib/screens/manual_assistant/rag_diagnostics_tab.dart`: (a) ensure the back navigation from the detail bottom sheet returns the user to the list with all filter state preserved (scroll position, active filters, pagination offset); (b) add "Previous entry / Next entry" navigation buttons inside the detail view that traverse the currently-filtered entry list in created_at order without closing the sheet; (c) add a secondary "Open in new tab" action that launches the detail view at a deeplink URL like `/manual-assistant/rag-logs/{id}` so two entries can literally be compared side-by-side in two browser tabs. This requires registering the deeplink route in the app router — follow the existing pattern from other admin deeplinks in the project.

**Checkpoint**: All user stories independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Non-MVP hardening — health visibility, acceptance validation, documentation, and operational checks.

- [ ] T024 [P] Add `GET /api/admin/rag-diagnostics/health` to `backend/routers/admin_rag_diagnostics.py` returning `{in_process_write_failures_last_hour, last_successful_write_at, retention_job_last_run_at, retention_job_rows_deleted_last_run}` per contracts §6. Source the first two from `rag_diagnostic_service.get_failure_stats()`; source the cron values by querying `cron.job_run_details` in Supabase (read-only; admin JWT required).
- [ ] T025 [P] Add a health status indicator banner at the top of `rag_diagnostics_tab.dart`. On mount and every 60 s, call `/health`. Show a warning banner ONLY if `in_process_write_failures_last_hour > 0` OR `last_successful_write_at` is older than 1 hour. Otherwise the banner is absent (don't clutter the UI with a green "all good" sign).
- [ ] T026 Validate SC-004 (behaviour preservation): before deploying this branch to the server, run `python backend/tests/test_rag_quality.py` against a build of main (pre-spec-088); save output as `backend/tests/rag_quality_pre_088.json`. Deploy spec 088. Run the suite again; save as `rag_quality_post_088.json`. Compare: total pass count, per-category pass count, hallucination count, and per-question pass/fail MUST be identical. Any divergence blocks the merge — it indicates the instrumentation leaked into pipeline behaviour.
- [ ] T027 Validate SC-003 (summary performance): after the system has accumulated at least 500 diagnostic rows, time `GET /api/admin/rag-diagnostics/summary?from=<now-24h>&to=<now>` ten times. The p95 MUST be under 3 seconds.
- [ ] T028 Validate SC-006 (no user-facing slowdown): sample `latency_breakdown.total_ms` distributions from before spec 088 (main branch) and after (post-merge), for the same set of 20 representative questions. Median and p95 MUST NOT regress by more than 50 ms. Spec 088's background-task writes should add negligible latency.
- [ ] T029 [P] Update documentation per Constitution I (Full-Stack Ownership): add a "RAG Diagnostics" section to `ARCHITECTURE.md` explaining the `rag_diagnostic_log` table and the admin endpoint surface; add a short entry to `AGENT.md` in the relevant checklist section; the Active Technologies block in `CLAUDE.md` is already updated by the agent-context script — verify the entry is present and tidy.
- [ ] T030 [P] After the system has run for 24 hours with spec 088 live, verify the pg_cron job has executed: connect to Supabase and run `SELECT * FROM cron.job_run_details WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname='rag-diagnostic-prune') ORDER BY start_time DESC LIMIT 3;`. Confirm at least one entry with status `succeeded` exists. If not, debug the cron statement from T002.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 only — trivial branch check. Can start immediately.
- **Foundational (Phase 2)**: depends on Setup. Blocks all user stories.
  - Internal order: T002 (migration) → T004 (service) → T005, T006 (instrumentation) → T007 (wire). T003 and T008 are independent `[P]`.
- **User Story 1 (Phase 3)**: depends on Phase 2 complete.
- **User Story 2 (Phase 4)**: depends on Phase 2 complete. Can run in parallel with US1 if staffed, but the UI in T022 lives in the same file as T016, so if a single developer implements both, do US1 first, then US2.
- **User Story 3 (Phase 5)**: depends on User Story 1 complete (detail view exists) — it builds navigation on top of the T016 UI.
- **Polish (Phase 6)**: depends on US1, US2, US3 all complete.

### Within Each User Story

- **Backend endpoints before frontend widgets** — the Flutter UI can't be tested end-to-end without the API surface.
- **Models before services** — `rag_diagnostic_entry.dart` (T014) before `rag_diagnostic_service.dart` (T015).
- **Services before screens** — T015 before T016.
- **Contract tests [P] with backend endpoints** — they can be written in parallel by someone else, but they validate the same file; sequential by the same developer.

### Parallel Opportunities

- **Phase 2**: T003 (AskRequest field) and T008 (test suite update) are `[P]` — both small, different files, no dependency on the migration.
- **Phase 3**: T011 (router wiring) / T012 (contract test — list) / T013 (contract test — detail) / T014 (Dart model) / T015 (Dart service) all `[P]` once T009+T010 merge. T016 + T017 are sequential (T017 depends on T016).
- **Phase 4**: T020 + T021 (contract tests) `[P]` once T018+T019 merge.
- **Phase 6**: T024, T025, T029, T030 all `[P]` — different surfaces, no shared files.

---

## Parallel Example: User Story 1

```bash
# After T009 (list endpoint) and T010 (detail endpoint) land, these can run in parallel:
Task: "T011 Wire admin_rag_diagnostics router into backend/main.py"
Task: "T012 Contract test for list endpoint in backend/tests/test_admin_rag_diagnostics.py"
Task: "T013 Contract test for detail endpoint in backend/tests/test_admin_rag_diagnostics.py"
Task: "T014 Create frontend/lib/models/rag_diagnostic_entry.dart"
Task: "T015 Create frontend/lib/services/rag_diagnostic_service.dart"
```

Then T016 depends on T014+T015 completing, and T017 depends on T016 completing — so those two are sequential.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (T001) — trivial.
2. Complete Phase 2 (T002–T008) — write path + test-suite tagging. After this, every request produces a row. This IS the feature's value, just without a UI.
3. Complete Phase 3 (T009–T017) — admin can view + classify one refusal.
4. **STOP and VALIDATE**: run quality suite, open RAG Logs tab, classify one failing question → ≤ 30 minutes. That's SC-001 proven.
5. Deploy to production.

At this MVP milestone the team can already do the "Monday morning diagnostic" described in quickstart.md — Phases 4, 5, 6 are nice-to-haves built on top.

### Incremental Delivery

- **Milestone A (after Phase 3)**: Admin can classify individual refusals. Ship.
- **Milestone B (after Phase 4)**: Admin sees grouped counts + exports CSV for offline analysis. Ship.
- **Milestone C (after Phase 5)**: Admin can contrast entries side-by-side. Ship.
- **Milestone D (after Phase 6)**: Health surface + validated SCs + docs. Ship.

Each milestone adds value without breaking earlier ones.

### Opencode ↔ Claude Review Workflow

Per the team's existing workflow (opencode implements, Claude Code reviews):

- Opencode picks up tasks T001–T008 first (Phase 1 + 2). Claude reviews via `superpowers:code-reviewer` against the plan before moving to Phase 3.
- Opencode picks up T009–T017 (US1). Claude reviews. Deploy MVP.
- Opencode picks up US2 (T018–T022). Claude reviews.
- Opencode picks up US3 (T023). Claude reviews.
- Opencode picks up Polish (T024–T030). Final review + merge.

---

## Notes

- `[P]` tasks = different files, no dependencies — safe to parallelise.
- `[Story]` label = US1/US2/US3 — traces tasks back to the user stories in spec.md.
- Every user story (Phase 3, 4, 5) MUST be independently completable and testable.
- **Constitution III (RBAC)** — every admin endpoint added in this spec MUST be protected by the admin-role guard. Three layers of defence: backend route guard + Supabase RLS on `SELECT` + Flutter tab `_isAdmin` check.
- **Constitution XIII (behaviour-preserving)** — this is spec-specific: the pipeline's grounded/ungrounded decision for any given question MUST be identical before and after spec 088 ships. T026 validates this.
- Commit after each task or logical group. Individual commits per task are preferred for the reviewer.
- **Avoid**: vague tasks, same-file conflicts within a `[P]` batch, cross-story dependencies that break independence.
