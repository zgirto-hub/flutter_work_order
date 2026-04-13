# Implementation Plan: Entity Extraction Admin Toggle & AI Priority Queue

**Branch**: `052-extraction-toggle-queue` | **Date**: 2026-04-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/052-extraction-toggle-queue/spec.md`

## Summary

Add an admin toggle for entity extraction and a shared AI priority queue that serializes all Ollama calls. The queue ensures user-facing AI (search, insights, assistant) always runs before background extraction. The toggle is stored in a new `system_settings` table and controlled from a new admin settings screen. The queue integrates at the service level (`ollama_generator` and `ollama_embedder`) so all callers are automatically covered. Three routers with direct httpx Ollama calls are refactored to use the shared services.

## Technical Context

**Language/Version**: Python 3.10 (backend), Dart 3.x / Flutter 3.x (frontend)  
**Primary Dependencies**: FastAPI, httpx, Supabase Python client (backend); http, supabase_flutter, Flutter Material (frontend)  
**Storage**: Supabase (PostgreSQL) — new `system_settings` table  
**Testing**: Manual endpoint testing, curl/httpie, Flutter run  
**Target Platform**: Linux server (Zorin OS) behind Nginx (backend); Web PWA (frontend)  
**Project Type**: Full-stack web application  
**Performance Goals**: Zero added latency to WO saves; user-facing AI queries unaffected by background extraction  
**Constraints**: 15GB server RAM, single-process FastAPI, no external dependencies (no Redis/Celery), Gemma E2B via Ollama  
**Scale/Scope**: Low WO save volume (~few per minute); 8 Ollama caller modules to serialize

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
| --------- | ------ | ----- |
| I. Full-Stack Ownership | PASS | Full stack: migration (system_settings), backend (queue + settings router + toggle check), frontend (admin settings screen). All layers covered. |
| II. Explicit Over Automatic | PASS | Toggle is explicit admin action. Queue priorities are explicit (HIGH=1, LOW=2). No silent fallback — disabled means disabled. |
| III. Role-Based Access Control | PASS | Settings endpoints are admin-only. Toggle check is system-level (no role needed). |
| IV. Server-First File Storage | N/A | No file storage involved. |
| V. Client-Side Computation | N/A | No client-side computation involved. |
| VI. Audit Everything | PASS | Queue worker logs all job events (start, complete, error). Toggle changes logged via activity log. |
| VII. Simplicity & YAGNI | PASS | asyncio.PriorityQueue is stdlib. No external deps. No caching (unnecessary at current scale). No persistent queue. |

## Project Structure

### Documentation (this feature)

```text
specs/052-extraction-toggle-queue/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── api.md           # Settings API contracts
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── main.py                              # Modified: lifespan starts queue worker
├── routers/
│   ├── settings.py                      # NEW: GET/PUT /api/settings/{key}
│   ├── work_orders.py                   # Modified: toggle check before extraction
│   ├── ai_search.py                     # Modified: use generate() instead of direct httpx
│   ├── ai_insights.py                   # Modified: use generate() instead of direct httpx
│   └── ai_assist.py                     # Modified: use generate() instead of direct httpx
└── services/
    ├── ai_queue.py                      # NEW: PriorityQueue, worker, submit functions
    ├── ollama_generator.py              # Modified: generate() submits to queue
    └── ollama_embedder.py               # Modified: embed_single()/embed_many() submit to queue

frontend/lib/
├── screens/admin/
│   └── settings_screen.dart             # NEW: admin settings with extraction toggle
└── services/
    └── settings_service.dart            # NEW: settings API client

supabase/migrations/
└── 20260413300000_create_system_settings.sql  # NEW: system_settings table + seed
```

**Structure Decision**: Queue lives in `backend/services/ai_queue.py` as a service module — consistent with existing `ollama_generator.py` and `ollama_embedder.py` placement. Settings router follows existing router pattern. Admin settings screen follows existing admin screen pattern.

## Implementation Phases

### Phase 1 — Database Migration

Create `supabase/migrations/20260413300000_create_system_settings.sql`:

**`system_settings`** table:
- `key` (TEXT, PRIMARY KEY)
- `value` (TEXT, NOT NULL)
- `updated_at` (TIMESTAMPTZ, NOT NULL, DEFAULT now())

**Seed data**: INSERT `entity_extraction_enabled` = `'false'`.

Single migration file. No changes to existing tables.

### Phase 2 — AI Priority Queue Service

New file `backend/services/ai_queue.py`:

**AIJob dataclass**: `priority` (int), `seq` (int, monotonic counter), `func` (Callable), `args` (tuple), `kwargs` (dict), `future` (asyncio.Future | None). Implements `__lt__` comparing `(priority, seq)` for PriorityQueue ordering.

**Module-level state**:
- `_queue`: `asyncio.PriorityQueue` instance
- `_seq`: monotonic counter (int)

**Functions**:
- `async submit(func, *args, priority=1, fire_and_forget=False, **kwargs) -> Any`: Creates AIJob, puts on queue. If `fire_and_forget=False`, creates a Future, awaits it, returns result. If `True`, no Future, returns immediately.
- `async worker()`: Infinite loop — gets job from queue, calls `job.func(*job.args, **job.kwargs)`, sets result on Future (or exception). Logs start/complete/error for each job. Uses try/except to ensure one failed job doesn't kill the worker.

**Priority constants**: `PRIORITY_HIGH = 1`, `PRIORITY_LOW = 2`.

### Phase 3 — Integrate Queue into Ollama Services

**`ollama_generator.py`** modifications:
- Rename current `generate()` to `_generate_direct()` (the actual httpx call)
- New `generate(prompt, model=None, timeout=180.0, priority=PRIORITY_HIGH)`:
  - If queue is initialized: `return await submit(_generate_direct, prompt, model=model, timeout=timeout, priority=priority, fire_and_forget=(priority > PRIORITY_HIGH))`
  - If queue not initialized (e.g., during startup/testing): call `_generate_direct()` directly as fallback

**`ollama_embedder.py`** modifications:
- Rename current `embed_single()` to `_embed_single_direct()`
- New `embed_single(text, priority=PRIORITY_HIGH)`:
  - Same pattern: submit to queue if initialized, direct call if not
- `embed_many()`: Each embedding call goes through `embed_single()` (which now queues). The existing semaphore (concurrency=4) is removed since the queue serializes all calls.

**Key design**: `priority` defaults to `PRIORITY_HIGH`, so **all existing callers get HIGH priority with zero code changes**. Only `entity_extractor.py` will explicitly pass `PRIORITY_LOW`.

### Phase 4 — Refactor Direct httpx Ollama Callers

Three routers currently bypass `ollama_generator.generate()` with direct httpx calls. Refactor each to use the shared service:

**`ai_search.py`** (`_parse_query_with_ai`):
- Remove: `OLLAMA_URL`, `OLLAMA_MODEL`, `OLLAMA_TIMEOUT` constants
- Remove: httpx.AsyncClient block (~8 lines)
- Replace with: `from services.ollama_generator import generate, GeneratorTimeoutError, GeneratorModelError`
- Call: `response_text = await generate(prompt, model="gemma4:e2b", timeout=60.0)`
- Map exceptions: `GeneratorTimeoutError` → return None (graceful fallback, same as current), `GeneratorModelError` → return None

**`ai_insights.py`** (insight generation):
- Same pattern: remove httpx block, use `generate()`
- Map exceptions: `GeneratorTimeoutError` → HTTPException 503 "AI service timed out", `GeneratorModelError` → HTTPException 502 "AI model error"

**`ai_assist.py`** (3 call sites: suggest, parse-work-order, document-expert):
- Same pattern for all 3 sites: remove httpx block, use `generate()`
- Remove: `OLLAMA_URL`, `OLLAMA_MODEL`, `OLLAMA_TIMEOUT` constants (shared across all 3)
- Map exceptions consistently with current error responses

### Phase 5 — Entity Extractor Toggle + Priority

**`entity_extractor.py`** modifications:
- Import `PRIORITY_LOW` from `ai_queue`
- Pass `priority=PRIORITY_LOW` to `generate()` and `embed_single()` calls
- No other changes — the queue handles serialization

**`work_orders.py`** modifications:
- In `extract_entities_background()`: Before calling `extract_entities()`, query `system_settings` for `entity_extraction_enabled`. If not `'true'`, return immediately (skip extraction).
- Both trigger points (create and close) unchanged — they still call `background_tasks.add_task(extract_entities_background, ...)`, but the background function now checks the toggle first.

### Phase 6 — Settings Backend

New file `backend/routers/settings.py`:

**`GET /api/settings/{key}`**: Admin-only. Query `system_settings` by key. Return 404 if not found.

**`PUT /api/settings/{key}`**: Admin-only. Upsert `system_settings` row. Log activity via `log_activity()`. Return updated setting.

Register router in `main.py`.

### Phase 7 — Queue Worker Startup

**`main.py`** modifications:
- Import `worker` from `ai_queue`
- In lifespan function: `worker_task = asyncio.create_task(worker())`
- On shutdown (after yield): `worker_task.cancel()` with try/except for CancelledError
- Log `[ai_queue] Worker started` and `[ai_queue] Worker stopped`

### Phase 8 — Admin Settings Flutter Screen

**New `frontend/lib/services/settings_service.dart`**:
- `Future<Map<String, dynamic>> getSetting(String key)` — GET /api/settings/{key}
- `Future<Map<String, dynamic>> updateSetting(String key, String value)` — PUT /api/settings/{key}

**New `frontend/lib/screens/admin/settings_screen.dart`**:
- Scaffold with AppBar "Settings"
- SwitchListTile for "Entity Extraction":
  - Title: "Entity Extraction"
  - Subtitle: "Automatically extract equipment, faults, and actions from work orders"
  - ON/OFF maps to setting value `'true'`/`'false'`
- Loads current value on init, updates via settings service on toggle
- Admin-only access (consistent with existing admin screens)

**Navigation**: Add settings entry to the admin section of the app drawer/navigation.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Refactoring 3 routers (ai_search, ai_insights, ai_assist) | Required to unify all Ollama calls through the queue at the service level | Leaving direct httpx calls would bypass the queue, defeating the purpose of priority serialization |
| embed_many() serialization change | Removing the semaphore-based concurrency in embed_many() since queue serializes all calls | Keeping the semaphore would conflict with the queue's one-at-a-time guarantee; embedding batches now process sequentially |
