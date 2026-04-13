# Tasks: Entity Extraction Admin Toggle & AI Priority Queue

**Input**: Design documents from `/specs/052-extraction-toggle-queue/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/api.md

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks are grouped by user story. Both user stories are P1 priority. The queue (US2) is foundational infrastructure but also a user story in its own right. The admin toggle (US1) depends on the queue being in place for extraction to route through it.

**IMPORTANT FOR IMPLEMENTOR**: This is a Flutter + FastAPI + Supabase project. Read the plan.md and referenced source files before starting each task. Follow existing code patterns (e.g., router structure, service patterns, Flutter screen patterns). The backend is Python 3.10 with FastAPI. The frontend is Flutter/Dart targeting web (PWA).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Database migration for the system_settings table needed by both user stories.

- [X] T001 Create Supabase migration file at `supabase/migrations/20260413300000_create_system_settings.sql`. The migration must: (1) CREATE TABLE `system_settings` with columns `key TEXT PRIMARY KEY`, `value TEXT NOT NULL`, `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`; (2) INSERT seed row with key `'entity_extraction_enabled'`, value `'false'`, updated_at `now()`. See `data-model.md` for full schema. Follow the pattern of existing migrations in `supabase/migrations/` (e.g., `20260413100000_create_entity_extraction.sql`).

---

## Phase 2: Foundational (AI Priority Queue — Blocking Prerequisites)

**Purpose**: Core queue infrastructure that MUST be complete before either user story can be implemented. This creates the serialization layer that all Ollama calls will route through.

**CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 Create new file `backend/services/ai_queue.py` implementing the AI priority queue. Must include: (1) `PRIORITY_HIGH = 1` and `PRIORITY_LOW = 2` constants; (2) `AIJob` dataclass with fields: `priority` (int), `seq` (int), `func` (Callable), `args` (tuple), `kwargs` (dict), `future` (asyncio.Future | None) — must implement `__lt__` comparing `(self.priority, self.seq)` for PriorityQueue ordering; (3) Module-level `_queue = asyncio.PriorityQueue()` and `_seq = 0` counter; (4) `async def submit(func, *args, priority=PRIORITY_HIGH, fire_and_forget=False, **kwargs)` — increments `_seq`, creates AIJob, puts on queue, if not fire_and_forget creates `asyncio.get_event_loop().create_future()` and awaits it to return the result, if fire_and_forget returns None immediately; (5) `async def worker()` — infinite loop that gets jobs from queue, calls `await job.func(*job.args, **job.kwargs)`, sets result on `job.future` if not None (or sets exception on failure), logs `[ai_queue]` prefixed messages for start/complete/error, uses try/except so one failed job never kills the worker; (6) A `_initialized = False` flag and `def is_initialized() -> bool` function so callers can check if the queue is active. See `plan.md` Phase 2 for full design.

- [X] T003 Modify `backend/services/ollama_generator.py` to route through the queue. Steps: (1) Add `from services.ai_queue import submit, PRIORITY_HIGH, is_initialized` import; (2) Rename the existing `async def generate(...)` function to `async def _generate_direct(prompt, model=None, timeout=180.0)`; (3) Create a new `async def generate(prompt, model=None, timeout=180.0, priority=PRIORITY_HIGH)` that checks `is_initialized()` — if True, calls `return await submit(_generate_direct, prompt, model=model, timeout=timeout, priority=priority, fire_and_forget=(priority > PRIORITY_HIGH))`, if False (startup/testing), calls `return await _generate_direct(prompt, model=model, timeout=timeout)` directly. Keep all existing exports (`GeneratorTimeoutError`, `GeneratorModelError`, `get_default_model`, `set_default_model`, `list_models`) unchanged.

- [X] T004 Modify `backend/services/ollama_embedder.py` to route through the queue. Steps: (1) Add `from services.ai_queue import submit, PRIORITY_HIGH, is_initialized` import; (2) Rename existing `async def embed_single(text)` to `async def _embed_single_direct(text)`; (3) Create new `async def embed_single(text, priority=PRIORITY_HIGH)` with same queue check pattern as T003; (4) Update `embed_many(texts, concurrency=4)` — remove the `asyncio.Semaphore` concurrency control since the queue now serializes all calls; instead, loop through texts calling `await embed_single(text, priority=priority)` sequentially (add `priority` parameter to `embed_many` as well, defaulting to `PRIORITY_HIGH`). Keep `EmbedderTimeoutError` export unchanged.

- [X] T005 Modify `backend/main.py` to start the queue worker in the lifespan. Steps: (1) Add `import asyncio` and `from services.ai_queue import worker as ai_worker, _initialized` (or whatever flag mechanism is used); (2) In the existing `lifespan()` async context manager function (which currently calls `seed_built_in_rules()`), AFTER the seed call: set the initialized flag to True, then `worker_task = asyncio.create_task(ai_worker())`, log `print("[ai_queue] Worker started")`; (3) After the `yield` statement (shutdown): `worker_task.cancel()`, wrap in `try/except asyncio.CancelledError: pass`, log `print("[ai_queue] Worker stopped")`. The existing `seed_built_in_rules()` call and all router includes MUST remain unchanged.

**Checkpoint**: At this point, the queue worker starts on app boot. All existing Ollama callers (via `generate()` and `embed_single()`) automatically route through the queue with HIGH priority. Existing behavior is preserved — the queue is transparent to current callers. Verify by restarting the backend and checking logs for `[ai_queue] Worker started`, then testing any AI feature (e.g., AI search) to confirm it still works.

---

## Phase 3: User Story 1 — Admin Disables Entity Extraction (Priority: P1) MVP

**Goal**: Give the admin a single toggle to enable/disable entity extraction globally. When OFF (the default), WO saves do not trigger extraction. When ON, extraction enqueues as before.

**Independent Test**: Toggle the setting ON/OFF in the admin screen and verify that WO saves do or do not trigger extraction jobs (visible in backend logs).

### Implementation for User Story 1

- [X] T006 [P] [US1] Create new file `backend/routers/settings.py` with admin-only settings endpoints. Must include: (1) `router = APIRouter(prefix="/api/settings", tags=["settings"])`; (2) `GET /{key}` endpoint — query `supabase.table("system_settings").select("*").eq("key", key).maybe_single().execute()`; return 404 if not found, return the row dict if found; (3) `PUT /{key}` endpoint — accept Pydantic model with `value: str` field; upsert with `supabase.table("system_settings").upsert({"key": key, "value": body.value, "updated_at": "now()"}).execute()`; log via `log_activity()` (import from `utils.activity`) with category `"admin"` and action `"updated_setting"`; return updated row; (4) Both endpoints must be admin-only — follow the existing `_ensure_admin()` pattern used in `backend/routers/work_orders.py` (check user role from auth header). See `contracts/api.md` for exact request/response shapes.

- [X] T007 [P] [US1] Modify `backend/routers/work_orders.py` to check the entity extraction toggle before enqueuing. In the existing `extract_entities_background(work_order_id)` async function (around line 330), add at the TOP of the function (before calling `extract_entities()`): `from db import supabase` (already imported), then `result = supabase.table("system_settings").select("value").eq("key", "entity_extraction_enabled").maybe_single().execute()`; if `result.data` is None or `result.data.get("value") != "true"`, `return` immediately (skip extraction). Add a log: `print(f"[entity_extraction] Skipping WO {work_order_id} — extraction disabled")`. The two trigger points (`create_work_order` and `close_work_order`) that call `background_tasks.add_task(extract_entities_background, ...)` remain unchanged.

- [X] T008 [US1] Register the settings router in `backend/main.py`. Add `from routers.settings import router as settings_router` in the imports section (follow the pattern of existing router imports around lines 10-30). Add `app.include_router(settings_router)` in the router registration section (around lines 83-101, follow existing pattern).

- [X] T009 [P] [US1] Create new file `frontend/lib/services/settings_service.dart` with a SettingsService class. Must include: (1) Import `dart:convert` and `package:http/http.dart`; (2) Import the app's config for base URL (follow pattern from existing services like `frontend/lib/services/work_order_service.dart`); (3) `Future<Map<String, dynamic>> getSetting(String key)` — GET to `$baseUrl/api/settings/$key` with auth headers, parse JSON response; (4) `Future<Map<String, dynamic>> updateSetting(String key, String value)` — PUT to `$baseUrl/api/settings/$key` with JSON body `{"value": value}` and auth headers, parse JSON response. Follow the HTTP client and auth header patterns from existing services.

- [X] T010 [US1] Create new file `frontend/lib/screens/admin/settings_screen.dart` implementing the admin settings screen. Must include: (1) `SettingsScreen` StatefulWidget; (2) On `initState`, call `SettingsService().getSetting("entity_extraction_enabled")` and set a `_extractionEnabled` bool state variable (default false if setting not found); (3) Build a Scaffold with AppBar titled "Settings"; (4) Body contains a `SwitchListTile` with: title "Entity Extraction", subtitle "Automatically extract equipment, faults, and actions from work orders", value bound to `_extractionEnabled`, `onChanged` calls `SettingsService().updateSetting("entity_extraction_enabled", value ? "true" : "false")` and updates state; (5) Show a loading indicator while fetching initial value; (6) Show error snackbar on API failure. Follow the visual style and patterns of existing admin screens in `frontend/lib/screens/admin/` (e.g., `departments_screen.dart`).

- [X] T011 [US1] Add navigation to the admin settings screen. Find the app's navigation/drawer that lists admin screens (search for references to `DepartmentsScreen` or `UserManagementScreen` in the navigation code). Add a "Settings" entry that navigates to `SettingsScreen`. Ensure it's only visible to admin role users (follow existing admin-only visibility pattern).

**Checkpoint**: Admin can toggle entity extraction ON/OFF from the settings screen. When OFF, WO saves skip extraction (visible in logs). When ON, extraction runs as before. All existing AI features still work. Verify: (1) Open Admin > Settings, see toggle defaulted to OFF. (2) Create a WO — check logs for "Skipping... extraction disabled". (3) Toggle ON, create another WO — check logs for extraction running. (4) Toggle OFF again — next WO skips extraction.

---

## Phase 4: User Story 2 — User-Facing AI Stays Responsive During Extraction Bursts (Priority: P1)

**Goal**: Ensure user-facing AI (search, insights, assistant) always runs before background extraction by assigning LOW priority to extraction and refactoring direct httpx callers to use the shared services (which route through the queue).

**Independent Test**: Enable extraction, save 5 WOs rapidly to queue up extraction jobs, then immediately trigger an AI search — the search should complete before all extraction jobs finish (visible in queue worker logs showing HIGH priority job cutting ahead of LOW priority jobs).

### Implementation for User Story 2

- [X] T012 [P] [US2] Modify `backend/services/entity_extractor.py` to use LOW priority for all Ollama calls. Steps: (1) Add `from services.ai_queue import PRIORITY_LOW` import; (2) Find the `generate()` call (around line 125, currently `await generate(prompt, model="gemma4:e2b", timeout=120.0)`) and add `priority=PRIORITY_LOW` parameter; (3) Find the `embed_single()` call and add `priority=PRIORITY_LOW` parameter. No other changes needed — the queue handles serialization.

- [X] T013 [P] [US2] Refactor `backend/routers/ai_search.py` to use `ollama_generator.generate()` instead of direct httpx. Steps: (1) Remove the `OLLAMA_URL`, `OLLAMA_MODEL`, `OLLAMA_TIMEOUT` constants (lines 13-15); (2) Remove the `import os` if only used for those constants; (3) Add `from services.ollama_generator import generate, GeneratorTimeoutError, GeneratorModelError` import; (4) In `_parse_query_with_ai()` function (around line 80), replace the entire `async with httpx.AsyncClient...` block with: `try: response_text = await generate(prompt, model="gemma4:e2b", timeout=60.0)` followed by `except (GeneratorTimeoutError, GeneratorModelError): return None` (this matches the current graceful-fallback behavior where AI failure returns None and the search falls back to keyword search). Remove unused `httpx` import if no other code uses it.

- [X] T014 [P] [US2] Refactor `backend/routers/ai_insights.py` to use `ollama_generator.generate()` instead of direct httpx. Steps: (1) Remove `OLLAMA_MODEL`, `OLLAMA_URL`, `OLLAMA_TIMEOUT` constants (lines 12-14); (2) Add `from services.ollama_generator import generate, GeneratorTimeoutError, GeneratorModelError` import; (3) In the insight generation function (around line 405), replace the `async with httpx.AsyncClient...` block with: `try: response_text = await generate(prompt, model="gemma4:e2b", timeout=60.0)` then extract `response_text` from the result; (4) Replace exception handling: `except GeneratorTimeoutError: raise HTTPException(status_code=503, detail="AI service timed out")` and `except GeneratorModelError: raise HTTPException(status_code=502, detail="AI model error")`. Match the current error behavior exactly. Remove unused `httpx` import if no other code uses it.

- [X] T015 [US2] Refactor `backend/routers/ai_assist.py` to use `ollama_generator.generate()` instead of direct httpx for ALL 3 call sites. Steps: (1) Remove `OLLAMA_URL`, `OLLAMA_MODEL`, `OLLAMA_TIMEOUT` constants (lines 10-12); (2) Add `from services.ollama_generator import generate, GeneratorTimeoutError, GeneratorModelError` import; (3) For EACH of the 3 call sites (around lines 235, 280, 336 — `/ai/suggest`, `/ai/parse-work-order`, `/ai/document-expert`): replace the `async with httpx.AsyncClient...` block with `response_text = await generate(prompt, model="gemma4:e2b", timeout=120.0)` and update exception handling to map `GeneratorTimeoutError` → HTTPException 503, `GeneratorModelError` → HTTPException 502, matching current error responses. (4) Remove unused `httpx` import if no other code in the file uses it. This is the largest single task — 3 identical refactors in one file.

**Checkpoint**: All Ollama calls now route through the queue. Extraction uses LOW priority, everything else uses HIGH (default). Verify: (1) Enable extraction toggle. (2) Save 5 WOs quickly. (3) Immediately do an AI search. (4) Check backend logs — you should see `[ai_queue]` log entries showing the HIGH priority search job processed before remaining LOW priority extraction jobs. (5) Test all AI features (search, insights, suggest, parse-work-order, document-expert) to confirm they still work correctly.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and cleanup across both user stories.

- [X] T016 Verify all existing AI features work through the queue by manually testing each endpoint: (1) AI search (`/api/work-orders/search-nl`), (2) AI insights (`/api/ai-insights/*`), (3) AI suggest (`/ai/suggest`), (4) AI parse work order (`/ai/parse-work-order`), (5) AI document expert (`/ai/document-expert`), (6) Manual RAG assistant (ask a question in the manual assistant), (7) Entity extraction (save a WO with toggle ON). All should work identically to before with `[ai_queue]` log entries visible.

- [X] T017 Run the quickstart.md verification checklist at `specs/052-extraction-toggle-queue/quickstart.md`. Confirm each item passes.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (migration must exist before queue code references settings). T002 can start in parallel with T001 since it doesn't read the DB. T003-T004 depend on T002. T005 depends on T002.
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion (queue must be active)
- **User Story 2 (Phase 4)**: Depends on Phase 2 completion (queue must be active)
- **US1 and US2 can run in parallel** after Phase 2 completes
- **Polish (Phase 5)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1 — Admin Toggle)**: Requires Phase 2. Independent of US2.
- **User Story 2 (P1 — Queue Priority)**: Requires Phase 2. Independent of US1.

### Within Each Phase

- Tasks marked [P] can run in parallel (different files)
- T006 and T007 are parallel (different files: settings.py vs work_orders.py)
- T009 and T010 are sequential (T010 depends on T009 service)
- T012, T013, T014 are parallel (different files: entity_extractor, ai_search, ai_insights)
- T015 depends on no other US2 tasks but is NOT parallel with T013/T014 since it requires careful 3-site refactoring

---

## Parallel Example: Foundational Phase

```text
# These can run in parallel (different files):
T003: Modify ollama_generator.py (queue integration)
T004: Modify ollama_embedder.py (queue integration)

# These depend on T002 (ai_queue.py must exist first):
T003 depends on T002
T004 depends on T002
T005 depends on T002
```

## Parallel Example: User Stories (after Phase 2)

```text
# US1 and US2 can run in parallel after Phase 2:

# US1 parallel tasks (different files):
T006: backend/routers/settings.py (NEW)
T007: backend/routers/work_orders.py (MODIFY)
T009: frontend/lib/services/settings_service.dart (NEW)

# US2 parallel tasks (different files):
T012: backend/services/entity_extractor.py (MODIFY)
T013: backend/routers/ai_search.py (MODIFY)
T014: backend/routers/ai_insights.py (MODIFY)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (migration)
2. Complete Phase 2: Foundational (queue + integration)
3. Complete Phase 3: User Story 1 (admin toggle)
4. **STOP and VALIDATE**: Toggle ON/OFF, verify extraction is controlled
5. This gives a working kill switch even without priority enforcement

### Incremental Delivery

1. Phase 1 + Phase 2 → Queue active, all AI serialized (transparent to users)
2. Add User Story 1 → Admin toggle works → Deploy (kill switch available!)
3. Add User Story 2 → Priority enforcement → Deploy (extraction no longer starves AI)
4. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- The queue is transparent to existing callers — all get HIGH priority by default
- Only entity_extractor.py explicitly opts into LOW priority
- Direct httpx Ollama calls in 3 routers MUST be refactored (T013-T015) for the queue to cover all callers
