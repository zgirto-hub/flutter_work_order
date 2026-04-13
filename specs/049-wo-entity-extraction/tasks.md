# Tasks: Work Order Entity Extraction

**Input**: Design documents from `/specs/049-wo-entity-extraction/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api.md
**Implementer**: Opencode (LLM) — implement all tasks sequentially, following each task's instructions exactly
**Reviewer**: Claude Code with Superpowers code-review after implementation is complete

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- All file paths are relative to repository root

## Key References for Implementer

Before starting, read these files to understand existing patterns:

- `backend/services/ollama_generator.py` — how Ollama is called (async, httpx, timeout/error handling)
- `backend/services/ollama_embedder.py` — how embeddings are generated (nomic-embed-text, 768 dims)
- `backend/routers/work_orders.py` — existing create/close endpoints you will modify
- `backend/db.py` — Supabase client initialization (`from db import supabase`)
- `backend/utils/activity.py` — fire-and-forget `log_activity()` pattern

---

## Phase 1: Setup (Database Migration)

**Purpose**: Create the two new Supabase tables required by all user stories

- [x] T001 Create Supabase migration file `supabase/migrations/20260413100000_create_entity_extraction.sql` with the following SQL:

  **Table 1 — `work_order_entities`**:
  ```sql
  CREATE EXTENSION IF NOT EXISTS vector;

  CREATE TABLE work_order_entities (
    work_order_id uuid PRIMARY KEY REFERENCES work_orders(id) ON DELETE CASCADE,
    equipment_id text NOT NULL,
    equipment_type text,
    fault_type text,
    fault_code text,
    action_taken text,
    procedure_followed text,
    parts_replaced text[] DEFAULT '{}',
    outcome text,
    technician_id text,
    date text,
    embedding vector(768),
    extracted_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
  );
  ```

  **Table 2 — `extraction_failures`**:
  ```sql
  CREATE TABLE extraction_failures (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id uuid REFERENCES work_orders(id) ON DELETE CASCADE,
    error_message text NOT NULL,
    raw_response text,
    attempt_number int NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now()
  );

  CREATE INDEX idx_extraction_failures_work_order_id ON extraction_failures(work_order_id);
  ```

**Checkpoint**: Migration file created. Apply it to Supabase to create both tables.

---

## Phase 2: Foundational (Extraction Service Core)

**Purpose**: Build the entity extraction service that all user stories depend on. This is the single most important file.

**CRITICAL**: No user story work can begin until this phase is complete.

- [x] T002 Create `backend/services/entity_extractor.py` with the extraction prompt constant. The prompt MUST:
  - Instruct Gemma to output ONLY raw JSON — no preamble, no explanation, no markdown code blocks
  - List all 10 entity fields with descriptions: equipment_id (required, non-empty), equipment_type, fault_type, fault_code, action_taken, procedure_followed, parts_replaced (JSON array of strings), outcome, technician_id, date
  - Explicitly say: "The input text may be in Arabic, English, or mixed. You MUST output all field values in English regardless of input language."
  - Include one example showing Arabic input → English JSON output
  - End with: "Output ONLY the JSON object. No other text."

- [x] T003 In `backend/services/entity_extractor.py`, implement `_clean_json_response(raw: str) -> str` that:
  1. Strips markdown code fences: remove lines matching ` ```json ` or ` ``` ` using regex
  2. Finds the first `{` and last `}` in the remaining text and returns only that substring
  3. Returns the cleaned string (or raises ValueError if no `{` or `}` found)

- [x] T004 In `backend/services/entity_extractor.py`, implement `_validate_entities(data: dict) -> bool` that:
  1. Checks `data.get("equipment_id")` is a non-empty string after `.strip()`
  2. Returns `True` if valid, `False` if equipment_id is missing or empty
  3. Ensures `parts_replaced` is a list (convert to empty list if null/missing)

- [x] T005 In `backend/services/entity_extractor.py`, implement `_embed_text(text: str) -> list[float] | None` that:
  1. Imports `embed` from `backend/services/ollama_embedder.py` (check the exact function name in that file)
  2. Calls the embed function with the text
  3. Returns the embedding vector (list of 768 floats) on success
  4. Returns `None` on any exception (embedding is best-effort — print error to stderr but never raise)

- [x] T006 In `backend/services/entity_extractor.py`, implement `_log_extraction_failure(work_order_id: str, error_message: str, raw_response: str | None, attempt: int)` that:
  1. Imports `supabase` from `backend/db.py`
  2. Inserts a row into `extraction_failures` table with: work_order_id, error_message, raw_response, attempt_number
  3. Wraps the insert in try/except — print to stderr on failure but never raise (fire-and-forget)

- [x] T007 In `backend/services/entity_extractor.py`, implement the main function `async def extract_entities(work_order_id: str) -> dict | None` that:
  1. Import `supabase` from `db` and `generate` from `services.ollama_generator`
  2. Fetch the work order from Supabase: `supabase.table("work_orders").select("id, description, tech_notes").eq("id", work_order_id).execute()`
  3. If not found, print warning to stderr and return `None`
  4. Combine text: `description + "\n" + (tech_notes or "")` — strip the result
  5. If combined text is empty/whitespace, print notice `[entity_extractor] Skipping WO {id}: empty text` and return `None`
  6. Build the full prompt by inserting the combined text into the prompt template
  7. **Attempt 1**: Call `await generate(prompt, model="gemma4:e2b", timeout=120.0)`, then `_clean_json_response()`, then `json.loads()`, then `_validate_entities()`
  8. If attempt 1 fails (any exception), **Attempt 2**: Same sequence. Log attempt 1 failure via `_log_extraction_failure(..., attempt=1)`
  9. If attempt 2 also fails, log via `_log_extraction_failure(..., attempt=2)`, print to stderr, return `None`
  10. If validation fails (empty equipment_id), log via `_log_extraction_failure(work_order_id, "empty equipment_id", json.dumps(data), attempt)`, return `None`
  11. On success: call `_embed_text(combined_text)` to get the embedding vector (may be None)
  12. Build the upsert payload with all entity fields from the parsed JSON + `embedding` (the vector or None) + `updated_at` set to `datetime.utcnow().isoformat()`
  13. Upsert: `supabase.table("work_order_entities").upsert(payload, on_conflict="work_order_id").execute()`
  14. Return the parsed entity dict
  15. **CRITICAL**: Wrap the ENTIRE function body in `try: ... except Exception as e:` — print to stderr, never crash. This function runs in a background task.

**Checkpoint**: The extraction service is complete and can extract entities from any work order ID. All other phases use this service.

---

## Phase 3: User Story 1 — Automatic Entity Extraction on Create/Close (Priority: P1) MVP

**Goal**: When a work order is created or closed, entity extraction runs automatically in the background without blocking the API response.

**Independent Test**: Create a work order via POST /work-orders with descriptive text. Wait 30 seconds. Query `work_order_entities` table for that work_order_id — entities should exist.

### Implementation for User Story 1

- [x] T008 [US1] Modify `backend/routers/work_orders.py` — update the `create_work_order` function signature to accept `background_tasks: BackgroundTasks` parameter. Add `from fastapi import BackgroundTasks` to imports. After the existing `log_activity()` call (around line 708), add: `background_tasks.add_task(extract_entities_background, work_order_id)` where `extract_entities_background` is an async wrapper defined in the same file. Import `extract_entities` from `services.entity_extractor`.

- [x] T009 [US1] Modify `backend/routers/work_orders.py` — update the `close_work_order` function signature to accept `background_tasks: BackgroundTasks` parameter. After the existing `log_activity()` call (around line 1028), add: `background_tasks.add_task(extract_entities_background, work_order_id)`.

- [x] T010 [US1] In `backend/routers/work_orders.py`, add a helper function `async def extract_entities_background(work_order_id: str)` near the top of the file (after imports). This function:
  1. Calls `await extract_entities(work_order_id)`
  2. Wraps in try/except Exception — prints to stderr on failure, never crashes
  3. This wrapper exists so that BackgroundTasks has a simple callable to invoke

**Checkpoint**: User Story 1 complete. Creating or closing a work order now triggers background entity extraction. The API response time is unchanged.

---

## Phase 4: User Story 2 — Manual Re-extraction Endpoint (Priority: P2)

**Goal**: Admin can manually trigger entity re-extraction for a specific work order via `POST /work-orders/extract-entities/{work_order_id}`.

**Independent Test**: Call `POST /work-orders/extract-entities/{id}?user_email=admin@example.com` with curl. Verify entities are returned in response and stored in DB.

### Implementation for User Story 2

- [x] T011 [US2] In `backend/routers/work_orders.py`, add a new endpoint `POST /work-orders/extract-entities/{work_order_id}` with the following behavior:
  1. Accept `work_order_id: str` path param and `user_email: str = Query(...)` query param
  2. Call `_ensure_admin(user_email)` (existing helper) to verify admin access
  3. Verify the work order exists: `supabase.table("work_orders").select("id").eq("id", work_order_id).execute()` — raise 404 if not found
  4. Call `result = await extract_entities(work_order_id)`
  5. If result is None, raise HTTPException 400 with detail "Extraction failed — check extraction_failures table"
  6. Call `log_activity(user_email, "work_order", "entities_extracted", target_label=work_order_id, target_id=work_order_id)`
  7. Return `{"status": "extracted", "work_order_id": work_order_id, "entities": result}`

  **IMPORTANT**: This endpoint MUST be defined BEFORE the backfill endpoint (T012) in the file, because FastAPI matches routes top-to-bottom. But actually, the backfill route `/work-orders/extract-entities/backfill` must come BEFORE `/{work_order_id}` to avoid "backfill" being captured as a work_order_id. So define backfill first, then the `{work_order_id}` route.

**Checkpoint**: User Story 2 complete. Admins can manually trigger and verify entity extraction for any work order.

---

## Phase 5: User Story 3 — Bulk Backfill Endpoint (Priority: P3)

**Goal**: Admin can trigger bulk extraction for all work orders missing entity records, processed in batches of 10.

**Independent Test**: Call `POST /work-orders/extract-entities/backfill?user_email=admin@example.com`. Verify response shows total_pending count. After waiting, check that `work_order_entities` table has new records.

### Implementation for User Story 3

- [x] T012 [US3] In `backend/routers/work_orders.py`, add a new endpoint `POST /work-orders/extract-entities/backfill` with the following behavior:
  1. Accept `user_email: str = Query(...)` and `background_tasks: BackgroundTasks`
  2. Call `_ensure_admin(user_email)` to verify admin access
  3. Query pending work orders: use a raw SQL approach or query work_orders and filter. Query all work_order IDs, query all work_order_entities work_order_ids, compute the difference in Python. Example:
     ```python
     all_wo = supabase.table("work_orders").select("id").execute()
     existing = supabase.table("work_order_entities").select("work_order_id").execute()
     existing_ids = {r["work_order_id"] for r in (existing.data or [])}
     pending_ids = [r["id"] for r in (all_wo.data or []) if r["id"] not in existing_ids]
     ```
  4. If no pending work orders, return `{"status": "no_pending", "total_pending": 0, "message": "All work orders already have entities"}`
  5. Add background task: `background_tasks.add_task(backfill_entities, pending_ids, user_email)`
  6. Return immediately: `{"status": "backfill_started", "total_pending": len(pending_ids), "batch_size": 10, "message": f"Processing {len(pending_ids)} work orders in batches of 10"}`

- [x] T013 [US3] In `backend/routers/work_orders.py`, add the background function `async def backfill_entities(pending_ids: list[str], user_email: str)` that:
  1. Import `asyncio` at the top of the file
  2. Process in batches of 10: `for i in range(0, len(pending_ids), 10):`
  3. For each batch: iterate over the 10 IDs, call `await extract_entities(wo_id)` for each, track successes and failures
  4. After each batch, `await asyncio.sleep(2)` to avoid overwhelming Ollama
  5. After all batches complete, print a summary to stderr: `[backfill] Complete: {success} extracted, {failed} failed out of {total}`
  6. Call `log_activity(user_email, "work_order", "entities_backfill_completed", detail=f"{success} extracted, {failed} failed")`
  7. Wrap entire function in try/except — never crash

**Checkpoint**: User Story 3 complete. Admins can backfill all historical work orders with entity data.

---

## Phase 6: User Story 4 — Graceful Failure Handling (Priority: P2)

**Goal**: Ensure extraction never crashes the application, retries once on failure, and logs all failures to `extraction_failures` table.

**Note**: Most of this is already built into T007 (extract_entities function). This phase verifies and strengthens the error handling.

### Implementation for User Story 4

- [x] T014 [US4] Review `backend/services/entity_extractor.py` `extract_entities()` and verify these failure scenarios are handled:
  1. Ollama returns HTTP 500 (GeneratorModelError) → retry once, then log failure
  2. Ollama times out (GeneratorTimeoutError) → retry once, then log failure
  3. Ollama returns non-JSON text → `_clean_json_response` raises ValueError → retry once, then log failure with raw_response saved
  4. Ollama returns valid JSON but equipment_id is empty → log to extraction_failures with reason "empty equipment_id", do NOT retry (validation failure is deterministic)
  5. Ollama is completely unreachable (httpx.ConnectError) → retry once, then log failure
  6. Supabase upsert fails → catch and log to stderr (do not insert to extraction_failures since DB may be down)
  7. ALL paths end with a caught exception or a return — never an unhandled raise

  If any of these scenarios are not handled in T007's implementation, fix them now.

- [x] T015 [US4] Verify that `_log_extraction_failure` in `backend/services/entity_extractor.py` also prints to stderr for real-time debugging: `print(f"[entity_extractor] FAIL WO {work_order_id} attempt {attempt}: {error_message}", file=sys.stderr)`

**Checkpoint**: User Story 4 complete. The extraction pipeline is resilient — it never crashes regardless of Gemma or Supabase failures.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final touches that affect multiple user stories

- [x] T016 [P] Verify the `_ensure_admin` helper exists in `backend/routers/work_orders.py` and works for the new endpoints. If the pattern is `_ensure_not_reporter` instead, check what admin check pattern other admin-only endpoints use in the codebase and use the same one. The manual trigger and backfill endpoints MUST be admin-only.

- [x] T017 [P] Add imports at the top of `backend/routers/work_orders.py` for all new dependencies used by the new code: `BackgroundTasks` from fastapi, `extract_entities` from services.entity_extractor, `asyncio`. Verify no circular imports.

- [x] T018 Verify route ordering in `backend/routers/work_orders.py`: the `/work-orders/extract-entities/backfill` route MUST be defined BEFORE `/work-orders/extract-entities/{work_order_id}` to prevent FastAPI from matching "backfill" as a work_order_id parameter.

- [x] T019 Run a quick manual test: start the backend server, create a work order with descriptive text via curl or the app, wait 30 seconds, check `work_order_entities` table for the new record. Verify the embedding column has a 768-dim vector.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start here
- **Phase 2 (Foundational)**: Depends on Phase 1 (tables must exist)
- **Phase 3 (US1)**: Depends on Phase 2 (extraction service must exist)
- **Phase 4 (US2)**: Depends on Phase 2 (extraction service must exist)
- **Phase 5 (US3)**: Depends on Phase 2 (extraction service must exist)
- **Phase 6 (US4)**: Depends on Phase 2 (review of extraction service)
- **Phase 7 (Polish)**: Depends on all previous phases

### User Story Dependencies

- **US1 (P1)**: Depends only on foundational service — this is the MVP
- **US2 (P2)**: Independent of US1 — can be built right after Phase 2
- **US3 (P3)**: Independent of US1/US2 — can be built right after Phase 2
- **US4 (P2)**: Review phase — depends on Phase 2 implementation being complete

### Within Each User Story

- Read existing code patterns first
- Implement in the order listed (tasks are sequenced within each phase)
- Commit after each task or logical group

### Parallel Opportunities

- T002, T003, T004, T005, T006 can all be written in parallel (different functions in the same new file)
- T008, T009 can be done in parallel (different functions in the same file, no overlap)
- T016, T017 can be done in parallel
- US2 (Phase 4) and US3 (Phase 5) can be built in parallel after Phase 2

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Database migration
2. Complete Phase 2: Extraction service (entity_extractor.py)
3. Complete Phase 3: Background task integration on create/close
4. **STOP and VALIDATE**: Create a work order, wait 30s, check entities exist in DB
5. The system is now extracting entities automatically

### Incremental Delivery

1. Phase 1 + 2 → Foundation ready
2. Add US1 (Phase 3) → Automatic extraction works → **MVP deployed**
3. Add US2 (Phase 4) → Admin can manually re-extract
4. Add US3 (Phase 5) → Admin can backfill history
5. Add US4 (Phase 6) → Error handling hardened
6. Phase 7 → Polish and verify

### Post-Implementation Review

After ALL tasks are complete, request a **Claude Code Superpowers code review** (`superpowers:requesting-code-review`) covering:
- All changes in `backend/services/entity_extractor.py` (new file)
- All changes in `backend/routers/work_orders.py` (modified file)
- Migration file `supabase/migrations/20260413100000_create_entity_extraction.sql`
- Verify constitution compliance (Principle II, III, VI, VII)
- Verify no security issues (admin-only endpoints properly gated)

---

## Notes

- All code is Python 3.10, async where Ollama is called
- Use `from db import supabase` for database access
- Use `from services.ollama_generator import generate` for Gemma calls
- Use `from services.ollama_embedder import embed` (check exact function name) for embedding
- Use `from utils.activity import log_activity` for audit logging
- The model to use is `gemma4:e2b` (NOT gemma3 — check that you pass the correct model name)
- Never commit `backend/version.json`
- Background tasks MUST catch all exceptions — a crash in a background task can destabilize the server
