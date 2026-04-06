# Tasks: Natural Language Search for Work Orders

**Input**: Design documents from `/specs/023-nl-search-work-orders/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api-contracts.md, quickstart.md

**Tests**: Not requested. Manual testing via quickstart.md checklist after implementation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Context for implementor**: This task file is designed for step-by-step implementation by an LLM agent. Each task includes the exact file path, what to create or modify, and which existing files to reference as patterns. Complete each task fully before moving to the next. After completing all tasks, the work will be reviewed.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `backend/` at repository root (Python/FastAPI)
- **Frontend**: `frontend/lib/` at repository root (Dart/Flutter)

---

## Phase 1: Setup

**Purpose**: Register the new backend router and create foundational models/services that all user stories depend on.

- [X] T001 Create the NL search Pydantic request model and router skeleton in `backend/routers/ai_search.py`. Define `NLSearchRequest` with fields: `query` (str, required), `email` (str, required), `user_role` (str, required), `limit` (Optional[int] = 30), `offset` (int = 0). Create a FastAPI `APIRouter` with `tags=["search"]`. Add a single `POST /search/nl` endpoint stub that returns `{"work_orders": [], "total": 0, "filters": None, "fallback": True}`. Reference `backend/routers/ai_assist.py` for the router pattern and import style.

- [X] T002 Register the new router in `backend/main.py`. Add `from routers.ai_search import router as ai_search_router` and `app.include_router(ai_search_router, prefix="/api")`. Reference how `ai_assist` and `ai_insights` routers are registered in the same file.

- [X] T003 [P] Create the frontend NL search result model in `frontend/lib/models/nl_search_result.dart`. Define two classes: (1) `ExtractedFilters` with nullable fields: `status` (String?), `type` (String?), `department` (String?), `location` (String?), `dateFrom` (String?), `dateTo` (String?), `minResolutionDays` (double?), plus a `fromJson(Map<String, dynamic>)` factory and a `toJson()` method. (2) `NLSearchResult` with fields: `workOrders` (List<WorkOrder>), `total` (int), `filters` (ExtractedFilters?), `fallback` (bool), plus a `fromJson` factory that parses work_orders using `WorkOrder.fromJson`. Import `WorkOrder` from `frontend/lib/models/work_order.dart` — read that file first to understand the existing model shape.

- [X] T004 [P] Create the frontend NL search API service in `frontend/lib/services/ai_search_service.dart`. Follow the pattern in `frontend/lib/services/ai_assist_service.dart`. Define class `AiSearchService` with constructor taking `baseUrl` (String) and `email` (String). Add method `Future<NLSearchResult> searchWorkOrders(String query, String userRole, {int limit = 30, int offset = 0})` that: (1) POSTs to `$baseUrl/search/nl` with JSON body `{query, email, user_role, limit, offset}`, (2) handles HTTP 200 by parsing `NLSearchResult.fromJson`, (3) handles HTTP 422 by throwing with the detail message, (4) has a 15-second client timeout. Import `NLSearchResult` from the model created in T003. Reference `frontend/lib/config.dart` for `AppConfig.baseUrl`.

**Checkpoint**: Backend has a stub endpoint registered. Frontend has model and service ready. Verify backend starts without errors and the stub endpoint responds.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Implement the core AI parsing logic and keyword fallback in the backend — these are needed by ALL user stories.

**CRITICAL**: No user story work can begin until this phase is complete.

- [X] T005 Implement the Ollama prompt builder function `_build_nl_prompt(query: str, departments: list[str], today: str) -> str` in `backend/routers/ai_search.py`. The prompt must: (1) instruct the model to act as a work order search filter parser, (2) list valid statuses: "Pending", "In Progress", "Resolved", "Closed", (3) list valid types: "Technical", "Inspection", "Other", (4) list department names (passed as parameter — fetched from DB at call time), (5) provide today's date for resolving relative dates ("last month", "this week"), (6) instruct the model to output ONLY a JSON object with nullable fields: `status`, `type`, `department`, `location`, `date_from` (ISO date), `date_to` (ISO date), `min_resolution_days` (number), (7) instruct: "Only include fields the user explicitly mentioned. Use null for unmentioned fields. Do not add any text before or after the JSON." Reference the prompt patterns in `backend/routers/ai_assist.py` (lines 51-58) and `backend/routers/ai_insights.py` for style.

- [X] T006 Implement the Ollama call and JSON parsing in `backend/routers/ai_search.py`. Add function `async _parse_query_with_ai(query: str, departments: list[str]) -> dict | None` that: (1) builds the prompt using `_build_nl_prompt` with today's date from `datetime.date.today().isoformat()`, (2) calls `http://localhost:11434/api/generate` via httpx with `{"model": "gemma4:e2b", "prompt": prompt, "stream": False}` and a **5-second timeout** (not 60s like other AI features), (3) strips preamble from response text using the same pattern as `_strip_preamble()` in `backend/routers/ai_assist.py` (lines 19-48) — copy and adapt that function, (4) attempts `json.loads()` on the stripped text, (5) returns the parsed dict on success, (6) returns `None` on any exception (ConnectError, ConnectTimeout, ReadTimeout, JSONDecodeError, KeyError). This function must NEVER raise — all failures return None for fallback handling.

- [X] T007 Implement filter validation function `_validate_filters(raw_filters: dict, departments_from_db: list[dict]) -> dict` in `backend/routers/ai_search.py`. This function takes the raw AI output dict and the departments list (each with `id` and `name`). It must: (1) validate `status` against known statuses or set to None, (2) validate `type` against known types or set to None, (3) for `department`: case-insensitive partial match against department names (e.g., "plumbing" matches "Plumbing Department") — if matched, store the department `id`; if no match, set to None, (4) keep `location` as-is (string or None), (5) validate `date_from` and `date_to` are valid ISO dates; ensure date_from <= date_to if both present; set to None if invalid, (6) validate `min_resolution_days` is a positive number or set to None. Return a clean dict with only valid filters.

- [X] T008 Implement the keyword fallback search function `_keyword_search(query: str, email: str, user_role: str, limit: int, offset: int) -> dict` in `backend/routers/ai_search.py`. This must: (1) query the `work_orders` table from Supabase with left joins to `users` (creator), `departments`, and `work_order_assignments` (same join pattern as `GET /api/work-orders` in `backend/routers/work_orders.py` lines 372-395 — read that file first), (2) filter where `job_no ILIKE %query%` OR `title ILIKE %query%` OR `description ILIKE %query%`, (3) apply role-based filtering: reporter sees only own (created_by == user_id), technician sees only their department (same logic as work_orders.py lines 416-436), admin/supervisor sees all, (4) order by `created_at DESC`, (5) apply pagination (offset, limit), (6) return `{"work_orders": [...], "total": count, "filters": None, "fallback": True}`.

- [X] T009 Implement the AI-filtered search function `_filtered_search(filters: dict, email: str, user_role: str, limit: int, offset: int) -> dict` in `backend/routers/ai_search.py`. This must: (1) build a Supabase query on `work_orders` with the same joins as `_keyword_search`, (2) conditionally apply each non-None filter: `status` exact match, `type` exact match, `department_id` exact match (already resolved to UUID by T007), `location` ILIKE partial match, `created_at >= date_from` if present, `created_at <= date_to` if present, (3) if `min_resolution_days` is set: filter where `closed_at IS NOT NULL` and `(closed_at - created_at) >= min_resolution_days days`, (4) apply the same role-based filtering as T008, (5) order by `created_at DESC`, (6) apply pagination, (7) return `{"work_orders": [...], "total": count, "filters": {the validated filters with department name instead of id}, "fallback": False}`.

- [X] T010 Wire up the full `POST /search/nl` endpoint in `backend/routers/ai_search.py`. Replace the stub from T001 with the complete flow: (1) validate request (query non-empty, user_role valid), (2) fetch departments list from Supabase `departments` table, (3) call `_parse_query_with_ai(query, [d["name"] for d in departments])`, (4) if AI returns None or all filter values are None → call `_keyword_search()`, (5) else → call `_validate_filters()` then `_filtered_search()`, (6) call `log_activity(email, "search", "nl_search", target_label=query, detail="ai" if not fallback else "keyword_fallback")` using the import `from utils.activity import log_activity`, (7) return the result dict. Handle any unexpected exceptions with a try/except that falls back to keyword search.

**Checkpoint**: Backend NL search endpoint is fully functional. Test by sending POST requests directly (e.g., via curl or API client). Verify: AI-parsed queries return filtered results; stopping Ollama causes keyword fallback; empty queries return 422.

---

## Phase 3: User Story 1 — Natural Language Query Returns Filtered Results (Priority: P1) MVP

**Goal**: Users can type a natural language query into the search bar on the work orders list screen and see AI-filtered results.

**Independent Test**: Type "closed technical orders this week" → see only matching work orders. Type "plumbing issues from last month" → see department + date filtered results.

### Implementation for User Story 1

- [X] T011 [US1] Add NL search state fields to `frontend/lib/controllers/filter_controller.dart`. Read the file first. Add: `bool isNLSearchActive = false`, `NLSearchResult? nlSearchResult`, `bool isNLSearchLoading = false`. Add methods: `setNLSearchActive(bool active)`, `setNLSearchResult(NLSearchResult? result)`, `setNLSearchLoading(bool loading)`. Each method must call `notifyListeners()`. Update `clearAll()` to also reset these NL fields. Import `NLSearchResult` from `frontend/lib/models/nl_search_result.dart`.

- [X] T012 [US1] Modify the search bar submit behavior in `frontend/lib/screens/Work_Orders/work_order_home.dart`. Read the file first (especially lines 650-830 around the search bar). Currently, `ClaudeSearchBar.onChanged` calls `_filter.setSearchQuery()` for client-side filtering. Add a new method `_performNLSearch(String query)` that: (1) sets `_filter.setNLSearchLoading(true)`, (2) creates `AiSearchService(AppConfig.baseUrl, _userEmail)` (get email from existing user state), (3) calls `searchWorkOrders(query, _userRole)`, (4) on success: calls `_filter.setNLSearchResult(result)` and `_filter.setNLSearchActive(true)`, (5) on error: falls back to existing client-side search behavior, (6) always sets `_filter.setNLSearchLoading(false)`. Trigger this method when the user presses Enter in the search bar (add `onSubmitted` callback to `ClaudeSearchBar`, or wrap in a `TextField` with `onSubmitted` if `ClaudeSearchBar` supports it — read the widget to check).

- [X] T013 [US1] Update the work order list rendering in `frontend/lib/screens/Work_Orders/work_order_home.dart` to use NL search results when active. In the `build` method where `WorkOrderFilterEngine.applyFilters()` is called (around line 617), add a conditional: if `_filter.isNLSearchActive && _filter.nlSearchResult != null`, use `_filter.nlSearchResult!.workOrders` directly instead of the client-side filtered list. Also update the total count display to use `_filter.nlSearchResult!.total`. Show a loading indicator when `_filter.isNLSearchLoading` is true (e.g., a `LinearProgressIndicator` below the search bar).

- [X] T014 [US1] Implement pagination for NL search results in `frontend/lib/screens/Work_Orders/work_order_home.dart`. The existing screen uses infinite scroll (loads more at scroll bottom, ~line 276). When NL search is active, the "load more" logic should call `AiSearchService.searchWorkOrders()` with incremented offset instead of the normal `fetchWorkOrders()`. Append new results to the existing NL result list. Track the NL search offset in the filter controller or as local state.

**Checkpoint**: User Story 1 complete. Type NL queries into search bar → see AI-filtered results from backend. Pagination works. This is the MVP — stop and validate here.

---

## Phase 4: User Story 2 — Graceful Fallback to Keyword Search (Priority: P2)

**Goal**: When AI fails or is unavailable, the search bar still works using keyword matching, with a subtle fallback indicator.

**Independent Test**: Stop Ollama → type a query → see keyword-matched results with a "Using keyword search" notice.

### Implementation for User Story 2

- [X] T015 [US2] Add a fallback notice widget to the work orders list in `frontend/lib/screens/Work_Orders/work_order_home.dart`. When `_filter.isNLSearchActive` and `_filter.nlSearchResult?.fallback == true`, display a subtle banner or `Chip` below the search bar area saying "AI search unavailable — showing keyword results" with an info icon. Style it with a muted color (use the app theme — reference `frontend/lib/theme/app_theme.dart`). The banner should be dismissible or auto-dismiss after 5 seconds.

- [X] T016 [US2] Handle the case where `_performNLSearch()` (from T012) receives a response with `fallback: true`. In this case: (1) still display the results (keyword-matched), (2) do NOT hide manual filter controls (since keyword fallback doesn't produce structured filters), (3) show the fallback notice from T015. Also handle network errors in `_performNLSearch()`: if the entire HTTP call fails (not just AI timeout), fall back to the existing client-side `_filter.setSearchQuery()` behavior and show the same fallback notice.

**Checkpoint**: User Story 2 complete. AI failures produce keyword search results with a clear indicator. Network failures gracefully degrade to client-side search.

---

## Phase 5: User Story 3 — Visual Feedback for Active AI Filters (Priority: P3)

**Goal**: After a successful NL query, extracted filters appear as removable chips. Removing a chip re-queries with remaining filters. Manual filter controls are hidden while NL search is active.

**Independent Test**: Type "closed orders from last week" → see "Status: Closed" and "Date: ..." chips → remove one → results update → tap "Clear all" → manual filters restored.

### Implementation for User Story 3

- [X] T017 [US3] Hide existing manual filter controls when NL search is active in `frontend/lib/screens/Work_Orders/work_order_home.dart`. Read the file and find the status chip row (lines ~758-783), date filter button (~line 704), and employee filter button (~line 710). Wrap each in a conditional: only show when `!_filter.isNLSearchActive || _filter.nlSearchResult?.fallback == true`. This ensures manual filters are visible in normal mode and during keyword fallback, but hidden during active AI-filtered search.

- [X] T018 [US3] Build the AI filter chips row in `frontend/lib/screens/Work_Orders/work_order_home.dart`. When `_filter.isNLSearchActive && _filter.nlSearchResult?.fallback == false && _filter.nlSearchResult?.filters != null`, render a horizontal `Wrap` widget with `Chip` widgets for each non-null filter: "Status: {value}", "Type: {value}", "Dept: {value}", "Location: {value}", "From: {date}", "To: {date}", "Min {n} days resolution". Each chip should have an `onDeleted` callback. Also add a "Clear all" `ActionChip` at the end. Place this row where the existing active filters row is (~lines 789-821), using a similar visual style.

- [X] T019 [US3] Implement chip removal re-query logic in `frontend/lib/screens/Work_Orders/work_order_home.dart`. When a user taps the delete icon on a filter chip: (1) create a copy of the current `ExtractedFilters` with the removed field set to null, (2) if all filter fields are now null, clear NL search entirely (call `_filter.clearAll()` and restore manual filters), (3) otherwise, call the backend `POST /search/nl` endpoint again — but this time, instead of sending the raw NL query, pass the remaining structured filters directly. **Important design decision**: To support this, add an alternative parameter to the backend endpoint OR add a separate method in `AiSearchService` that calls the same endpoint but with pre-built filters instead of a query. The simplest approach: extend `NLSearchRequest` in `backend/routers/ai_search.py` to accept optional `filters` dict — if `filters` is provided, skip AI parsing and go straight to `_filtered_search()`. Update the Pydantic model, endpoint logic, and frontend service accordingly.

- [X] T020 [US3] Add a "Clear all" action to the filter chips that exits NL search mode. When tapped: (1) call `_filter.setNLSearchActive(false)`, `_filter.setNLSearchResult(null)`, (2) clear the search text controller (`_searchCtrl.clear()`), (3) re-fetch the original work orders list using the existing `fetchWorkOrders()` method, (4) manual filter controls become visible again (handled by T017 conditional).

**Checkpoint**: User Story 3 complete. AI-extracted filter chips are visible, individually removable (triggers re-query), and "Clear all" restores normal mode.

---

## Phase 6: User Story 4 — Role-Based Result Scoping (Priority: P3)

**Goal**: NL search respects existing RBAC. Technicians see only their department's orders, reporters see only their own.

**Independent Test**: Same NL query typed by admin, technician, and reporter returns different (correctly scoped) results.

### Implementation for User Story 4

- [X] T021 [US4] Verify role-based filtering is correctly applied in the backend endpoint `backend/routers/ai_search.py`. Read `_keyword_search()` and `_filtered_search()` from T008 and T009. Ensure both functions: (1) for `user_role == "reporter"`: look up user by email, filter `created_by == user_id`, (2) for `user_role == "technician"`: look up user by email, get `department_id`, filter `department_id == tech_dept_id`, (3) for `admin`/`supervisor`: no additional filtering. Compare against the proven pattern in `backend/routers/work_orders.py` lines 416-436 to ensure exact parity. Fix any discrepancies.

- [X] T022 [US4] Ensure the frontend passes the correct `user_role` and `email` to the NL search service in `frontend/lib/screens/Work_Orders/work_order_home.dart`. Read how the existing `WorkOrderService` is initialized and how `_userRole` and `_userEmail` (or equivalent) are obtained from the authentication state. Ensure `_performNLSearch()` passes these same values to `AiSearchService.searchWorkOrders()`. Verify the values are non-null and correctly populated before the search call.

**Checkpoint**: User Story 4 complete. RBAC is enforced on all NL search results. Technicians and reporters see correctly scoped results.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories.

- [ ] T023 [P] Add Arabic language support to the Ollama prompt in `backend/routers/ai_search.py`. Update `_build_nl_prompt()` to include an instruction: "The user may write in English or Arabic. Extract filters regardless of language." This enables FR-011 from the spec. No frontend changes needed — the search bar already accepts Arabic text input.

- [ ] T024 [P] Implement request cancellation in `frontend/lib/screens/Work_Orders/work_order_home.dart`. When the user submits a new NL query while a previous one is still loading: (1) cancel the previous HTTP request (use a `CancelToken` or track the request and discard stale results by comparing a request counter/timestamp), (2) only apply results from the most recent query. This prevents race conditions where an earlier slow response overwrites a newer fast response. Reference FR-012 from the spec.

- [ ] T025 [P] Add empty state message for NL search in `frontend/lib/screens/Work_Orders/work_order_home.dart`. When `_filter.isNLSearchActive` and `_filter.nlSearchResult?.workOrders.isEmpty == true`, show a centered message: "No work orders match your search." with a subtle icon. Keep filter chips visible (if any) so the user can adjust. Reference FR-013 from the spec.

- [ ] T026 Update `CLAUDE.md` with the new feature technology entry if not already present. Ensure the Active Technologies section includes an entry for `023-nl-search-work-orders` with: `Python 3 (backend), Dart 3.x / Flutter 3.x (frontend) + FastAPI, httpx, Supabase Python client (backend); http, Flutter Material (frontend)`.

- [ ] T027 Run the quickstart.md testing checklist at `specs/023-nl-search-work-orders/quickstart.md`. Verify each item manually: (1) "closed technical orders this week" returns correct results, (2) "plumbing issues from last month" filters by department + date, (3) Ollama stopped → keyword fallback with notice, (4) filter chips appear and are removable, (5) technician sees only department-scoped results, (6) reporter sees only own orders, (7) Arabic query works, (8) clearing NL search restores manual filters.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on T001, T002 from Setup — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion — this is the MVP
- **User Story 2 (Phase 4)**: Depends on Phase 3 (US1) — builds on the NL search flow
- **User Story 3 (Phase 5)**: Depends on Phase 3 (US1) — adds filter chip UI to existing NL flow
- **User Story 4 (Phase 6)**: Can start after Phase 2 (independent verification) — but best done after US1
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Foundational (Phase 2) — core NL search flow
- **User Story 2 (P2)**: Depends on US1 — extends the search flow with fallback handling
- **User Story 3 (P3)**: Depends on US1 — adds filter chip UI layer
- **User Story 4 (P3)**: Technically independent (RBAC is in backend) but verifiable after US1

### Within Each User Story

- Read existing files before modifying them
- Backend before frontend (where applicable)
- Models before services
- Services before UI integration
- Core implementation before polish

### Parallel Opportunities

- T003 and T004 (frontend model + service) can run in parallel
- T005, T006, T007, T008, T009 in Phase 2 are sequential (each builds on prior)
- T023, T024, T025 in Phase 7 can all run in parallel (different files/concerns)

---

## Parallel Example: Phase 1 Setup

```
# These can run in parallel (different files):
Task T003: Create NLSearchResult model in frontend/lib/models/nl_search_result.dart
Task T004: Create AiSearchService in frontend/lib/services/ai_search_service.dart
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T004)
2. Complete Phase 2: Foundational backend (T005-T010)
3. Complete Phase 3: User Story 1 (T011-T014)
4. **STOP and VALIDATE**: Type NL queries → verify filtered results appear correctly
5. This delivers the core value: NL search with AI-filtered results

### Incremental Delivery

1. Setup + Foundational → Backend fully working
2. Add User Story 1 → Core NL search in UI (MVP!)
3. Add User Story 2 → Graceful fallback handling
4. Add User Story 3 → Filter chip visibility and manipulation
5. Add User Story 4 → RBAC verification
6. Polish → Arabic support, cancellation, empty states
7. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- **Important**: Always read existing files before modifying them — understand the current patterns
- **Reference files**: `backend/routers/ai_assist.py` (Ollama pattern), `backend/routers/work_orders.py` (WO query pattern), `frontend/lib/services/ai_assist_service.dart` (service pattern), `frontend/lib/controllers/filter_controller.dart` (state pattern)
- The backend endpoint at `POST /api/search/nl` must NEVER return an error for AI failures — always fall back to keyword search
