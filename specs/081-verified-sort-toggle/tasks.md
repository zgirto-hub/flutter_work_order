# Tasks: Verified Tab Sort Toggle

**Input**: Design documents from `/specs/081-verified-sort-toggle/`
**Prerequisites**: spec.md, plan.md

**Tests**: Requested for backend changes (service + route). Frontend has no widget-test infrastructure — manual QA only.

**Organization**: Linear — no independent user stories. Backend first (with tests), then frontend, then version bump.

## Format: `[ID] [P?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- Exact file paths included in every task

---

## Phase 1: Backend — Service-layer sort branching

- [ ] T001 Create `backend/tests/test_verified_sort.py` with six unit tests covering `get_all_verified_answers()` sort branches. Tests use `unittest.mock.MagicMock` to record the Supabase query-builder method chain (`.select().gt().ilike().order().range().execute()`). Test cases: (a) `sort="recent"` → no `.gt()` call, `.order("updated_at", desc=True)`; (b) `sort="most_used"` → `.gt("thumbs_up_count", 0)` + primary `.order("thumbs_up_count", desc=True)` + tie-breaker `.order("updated_at", desc=True)`; (c) `sort="most_problematic"` → `.gt("thumbs_down_count", 0)` + primary `.order("thumbs_down_count", desc=True)` + tie-breaker; (d) count query uses same `.gt()` filter as data query (verify `.gt("thumbs_up_count", 0)` called at least twice for `most_used`); (e) search ANDs with sort filter — both `.ilike("question_text", "%backup%")` and `.gt("thumbs_down_count", 0)` called when `search="backup"` + `sort="most_problematic"`; (f) `sort="bogus"` raises `ValueError(match="Invalid sort")`. Full test code is in `specs/081-verified-sort-toggle/plan.md` Task 1 Step 1 — copy verbatim. Run `cd backend && pytest tests/test_verified_sort.py -v` and confirm all six FAIL with `TypeError: unexpected keyword argument 'sort'`.

- [ ] T002 Modify `get_all_verified_answers()` in `backend/services/validated_qa_service.py:360-381` to accept `sort: str = "recent"` parameter. Add module-level constant `_ALLOWED_SORTS = {"recent", "most_used", "most_problematic"}` just below the existing `REFLAG_MIN_TOTAL = 3` line (around L14). Raise `ValueError(f"Invalid sort: {sort}")` for unknown values. Apply `.gt("thumbs_up_count", 0)` to BOTH `query` and `count_query` when `sort == "most_used"`; `.gt("thumbs_down_count", 0)` to both when `sort == "most_problematic"`; no filter for `"recent"`. Order: `most_used` → `.order("thumbs_up_count", desc=True).order("updated_at", desc=True)`; `most_problematic` → same with `thumbs_down_count`; `recent` → `.order("updated_at", desc=True)`. Full function body is in `specs/081-verified-sort-toggle/plan.md` Task 1 Step 3 — copy verbatim. Run `cd backend && pytest tests/test_verified_sort.py -v` and confirm all six PASS. Run `cd backend && pytest tests/test_validated_qa_lookup.py -v` to confirm no regressions.

- [ ] T003 Commit T001+T002: `git add backend/services/validated_qa_service.py backend/tests/test_verified_sort.py && git commit -m "feat(081): add sort parameter to get_all_verified_answers"`.

---

## Phase 2: Backend — Route validation

- [ ] T004 Append three route-layer tests to `backend/tests/test_verified_sort.py` under a new `class TestVerifiedAnswersRoute`: (a) `test_invalid_sort_returns_400` — GET `/manuals/verified-answers?user_email=admin@test.com&sort=bogus` returns 400 with `detail.error == "invalid_sort"`; service NOT called; (b) `test_valid_sort_reaches_service` — GET with `sort=most_used` returns 200, service called with `sort="most_used"`; (c) `test_default_sort_is_recent` — GET without `sort` param calls service with `sort="recent"`. Patch `routers.manuals._admin_check` to return None and `routers.manuals.validated_qa_service.get_all_verified_answers` to return `{"items": [], "count": 0}`. Full test code is in `specs/081-verified-sort-toggle/plan.md` Task 2 Step 1. If `from app import app` fails, run `grep -rn 'FastAPI()' backend/ --include='*.py'` to locate the app instance and adjust the import path. Run `cd backend && pytest tests/test_verified_sort.py::TestVerifiedAnswersRoute -v` and confirm all three FAIL.

- [ ] T005 Modify `get_verified_answers` route in `backend/routers/manuals.py:1037-1052` to accept `sort: str = Query("recent")`. Before calling the service, validate `sort` against `_ALLOWED_VERIFIED_SORTS = {"recent", "most_used", "most_problematic"}` (declare this constant near the top of `manuals.py` alongside other module-level constants). On invalid value, `raise HTTPException(status_code=400, detail={"error": "invalid_sort", "allowed": sorted(_ALLOWED_VERIFIED_SORTS)})`. Pass `sort=sort` into the `validated_qa_service.get_all_verified_answers(...)` call. Full route body is in `specs/081-verified-sort-toggle/plan.md` Task 2 Step 3. Run `cd backend && pytest tests/test_verified_sort.py -v` and confirm all nine tests PASS.

- [ ] T006 Commit T004+T005: `git add backend/routers/manuals.py backend/tests/test_verified_sort.py && git commit -m "feat(081): add sort query param to /manuals/verified-answers with 400 on invalid"`.

---

## Phase 3: Frontend — Service-layer parameter

- [ ] T007 Add `String sort = 'recent'` named parameter to `getVerifiedAnswers()` in `frontend/lib/services/manual_assistant_service.dart`. Locate the method with `grep -n 'getVerifiedAnswers' frontend/lib/services/manual_assistant_service.dart`. In the URL construction, append `&sort=${Uri.encodeComponent(sort)}` to the existing query string. Full before/after is in `specs/081-verified-sort-toggle/plan.md` Task 3 Step 2. Run `cd frontend && flutter analyze lib/services/manual_assistant_service.dart` and confirm no errors.

- [ ] T008 Commit T007: `git add frontend/lib/services/manual_assistant_service.dart && git commit -m "feat(081): add sort parameter to ManualAssistantService.getVerifiedAnswers"`.

---

## Phase 4: Frontend — Sort dropdown UI

- [ ] T009 In `frontend/lib/screens/manual_assistant/verified_answers_tab.dart` add state field `String _sort = 'recent';` to `_VerifiedAnswersTabState` (after the `final int _limit = 50;` line near L27). Update the `_loadEntries()` service call (around L66-L71) to pass `sort: _sort` to `_service.getVerifiedAnswers(...)`.

- [ ] T010 In the same file, add a sort dropdown row to `build()` between the search-field `Padding` and the total-count `Container` (around L388). Use the exact widget code in `specs/081-verified-sort-toggle/plan.md` Task 4 Step 3 — a `Padding` containing a `Row` with a "Sort:" label and a `DropdownButton<String>` with three items: `'recent'` → "Most recent", `'most_used'` → "Most used", `'most_problematic'` → "Most problematic". `onChanged` must guard against null and no-op changes, then `setState` to update `_sort`, reset `_offset = 0`, clear `_entries`, clear `_totalCount`, set `_loading = true`, and call `_loadEntries()`.

- [ ] T011 In the same file, update the empty-state `Text` inside the `if (_entries.isEmpty)` block (around L413-L432) to branch on `_sort` when no search term is active: `most_used` → "No verified answers have thumbs-up votes yet."; `most_problematic` → "No verified answers have thumbs-down votes yet."; `recent` → "No verified answers yet." (existing text). When a search term IS active, keep the existing "No matching answers found." message regardless of sort. Exact expression is in `specs/081-verified-sort-toggle/plan.md` Task 4 Step 4.

- [ ] T012 Run `cd frontend && flutter analyze lib/screens/manual_assistant/verified_answers_tab.dart` and confirm no errors. Then manual smoke test against a backend with at least one `validated_qa` row where `thumbs_up_count > 0` and one where `thumbs_down_count > 0`: (a) default "Most recent" view unchanged; (b) "Most used" orders by thumbs-up desc, zero-vote rows hidden, count badge reflects filtered total; (c) "Most problematic" orders by thumbs-down desc, zero-vote rows hidden; (d) search + sort combined returns intersection; (e) switching sort back to "Most recent" restores the full list.

- [ ] T013 Commit T009-T012: `git add frontend/lib/screens/manual_assistant/verified_answers_tab.dart && git commit -m "feat(081): add sort dropdown to Verified tab (recent/most_used/most_problematic)"`.

---

## Phase 5: Version bump

- [ ] T014 Bump `version:` in `frontend/pubspec.yaml` — read the current value with `grep '^version:' frontend/pubspec.yaml`, then increment both the patch and the build number (e.g. `1.17.9+194` → `1.17.10+195`). Commit: `git add frontend/pubspec.yaml && git commit -m "bump version to v<new>"`.

---

## Phase 6: Post-deploy verification (manual — not opencode work)

**Reference only. Runs after merge + deploy.**

- [ ] T015 After deploy to Zorin server, from admin session run: `curl -s 'https://zorin.taila92fe8.ts.net/manuals/verified-answers?user_email=<admin_email>&sort=most_used' | jq .count` and verify it matches the count shown in the UI's Verified tab when sorted the same way. Then `curl -s -o /dev/null -w '%{http_code}\n' 'https://zorin.taila92fe8.ts.net/manuals/verified-answers?user_email=<admin_email>&sort=bogus'` and verify it returns `400`. Open the deployed PWA Verified tab and switch between the three sorts, confirming each shows the expected subset.

---

## Dependencies

- T001 → T002 → T003 (tests before impl, commit last)
- T004 → T005 → T006 (same pattern)
- T003 and T006 can merge to main independently; T007+ depends on T005 being deployed OR local backend running new code.
- T007 → T008
- T009/T010/T011 touch the same file; do them in order. T012 is the verification step. T013 commits the three edits as one unit.
- T014 last.
- T015 is post-deploy; not part of the opencode run.

## Execution notes for opencode

- **Do NOT skip the red-green cycle**: for T001+T002 and T004+T005, write the failing tests first, confirm they fail for the expected reason, then implement.
- **Do NOT auto-commit** if any test fails or `flutter analyze` reports errors.
- **Do NOT commit `backend/version.json`** — the server manages its own copy. Only bump `frontend/pubspec.yaml`.
- **Do NOT change the card rendering** — FR-010 is explicit that the thumbs-up/thumbs-down counters already on the card are the signal; no new column or badge is needed.
- **Do NOT add a new endpoint** — extend the existing `/manuals/verified-answers`. NFR-002 is explicit.
- If a test imports `from app import app` and fails, locate the FastAPI app with `grep -rn 'FastAPI()' backend/ --include='*.py'` and adjust.
