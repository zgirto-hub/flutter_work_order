# Implementation Plan: Work Order Entity Extraction

**Branch**: `049-wo-entity-extraction` | **Date**: 2026-04-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/049-wo-entity-extraction/spec.md`

## Summary

Add a background entity extraction pipeline that uses Gemma (via Ollama) to parse structured data (equipment, faults, actions, parts) from work order free text on create/close events. Entities are stored in a new `work_order_entities` table with an embedding vector column for future similarity search. Failed extractions are logged to an `extraction_failures` table. Manual re-extraction and bulk backfill endpoints are provided for admin users.

## Technical Context

**Language/Version**: Python 3.10  
**Primary Dependencies**: FastAPI, httpx, Supabase Python client, existing `ollama_generator.py`  
**Storage**: Supabase (PostgreSQL) with pgvector — new `work_order_entities` and `extraction_failures` tables  
**Testing**: Manual endpoint testing, curl/httpie  
**Target Platform**: Linux server (Zorin OS) behind Nginx  
**Project Type**: Web service (backend only — no Flutter changes)  
**Performance Goals**: Extraction within 30s per work order; zero impact on API response time  
**Constraints**: 15GB server RAM, Gemma E2B model, batch size of 10 for backfill  
**Scale/Scope**: ~hundreds of existing work orders for backfill; low-frequency create/close events

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
| --------- | ------ | ----- |
| I. Full-Stack Ownership | JUSTIFIED EXCLUSION | Backend-only feature by design. No frontend entity is needed because extraction runs silently. Documented in spec as "no Flutter changes required." |
| II. Explicit Over Automatic | PASS | Extraction triggers are explicit (on create, on close, manual endpoint). No silent fallback — failures are logged. |
| III. Role-Based Access Control | PASS | Manual trigger and backfill endpoints are admin-only. Background extraction requires no role check (system-initiated). |
| IV. Server-First File Storage | N/A | No file uploads involved. |
| V. Client-Side Computation | N/A | No client-side computation involved. |
| VI. Audit Everything | PASS | Extraction failures logged to `extraction_failures` table. Activity log entries added for manual extraction triggers. |
| VII. Simplicity & YAGNI | PASS | Embedding vector column added for concrete future use (pattern similarity search — Level 4 Component 2). No other speculation. |

## Project Structure

### Documentation (this feature)

```text
specs/049-wo-entity-extraction/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
backend/
├── routers/
│   └── work_orders.py          # Modified: add BackgroundTasks to create/close, add extract/backfill endpoints
├── services/
│   ├── ollama_generator.py     # Existing: reused for Gemma calls
│   └── entity_extractor.py     # NEW: extraction logic, prompt, JSON cleaning, upsert
└── utils/
    └── activity.py             # Existing: reused for audit logging

supabase/migrations/
└── 20260413100000_create_entity_extraction.sql  # NEW: work_order_entities + extraction_failures tables
```

**Structure Decision**: All new code lives in a single new service file (`entity_extractor.py`) and modifications to the existing `work_orders.py` router. No new router file needed since the endpoints are work-order-scoped.

## Implementation Phases

### Phase 1 — Database Migration

Create Supabase migration with two tables:

**`work_order_entities`**: work_order_id (PK, FK → work_orders.id), equipment_id, equipment_type, fault_type, fault_code, action_taken, procedure_followed, parts_replaced (text[]), outcome, technician_id, date, embedding (vector(768) for nomic-embed-text), extracted_at (timestamptz), updated_at (timestamptz).

**`extraction_failures`**: id (uuid PK), work_order_id (FK), error_message (text), raw_response (text), attempt_number (int), created_at (timestamptz).

Unique constraint on `work_order_entities.work_order_id` ensures idempotent upsert.

### Phase 2 — Extraction Prompt Design

Design a Gemma prompt that:
- Instructs the model to output ONLY raw JSON, no preamble, no markdown
- Handles mixed Arabic/English work order text
- Outputs English field values consistently regardless of input language
- Specifies all 10 entity fields with descriptions
- Includes a JSON cleaning step to strip markdown code blocks (```json ... ```) if Gemma adds them despite instructions

### Phase 3 — Extraction Service

New file `backend/services/entity_extractor.py`:
- `extract_entities(work_order_id: str)` — main function
  1. Fetch work order from Supabase (description + tech_notes)
  2. Skip if text is empty/whitespace-only (log notice)
  3. Build prompt with combined text
  4. Call `ollama_generator.generate()` with the prompt
  5. Clean response (strip markdown backticks)
  6. Parse JSON, validate required fields (equipment_id must be non-empty)
  7. Embed the combined work order text using `ollama_embedder.embed()` (nomic-embed-text) to get a 768-dim vector
  8. Upsert to `work_order_entities` including the embedding vector using `supabase.table().upsert().execute()`
- `_clean_json_response(raw: str) -> str` — strips ```json``` wrappers
- `_validate_entities(data: dict) -> bool` — checks equipment_id is present
- `_embed_text(text: str) -> list[float]` — calls `ollama_embedder.embed()` to get nomic-embed-text vector; returns empty list on failure (embedding is best-effort, should not block entity storage)

### Phase 4 — Background Task Integration

Modify `create_work_order()` and `close_work_order()` in `work_orders.py`:
- Add `background_tasks: BackgroundTasks` parameter to both endpoints
- After the main operation completes, call `background_tasks.add_task(extract_entities, work_order_id)`
- The FastAPI response returns immediately; extraction runs in the background

### Phase 5 — Retry and Error Handling

Wrap extraction in try/except with one retry:
1. First attempt: call Gemma, parse JSON
2. On failure (invalid JSON, timeout, model error): retry once
3. On second failure: log to `extraction_failures` table with work_order_id, error_message, raw_response, attempt_number
4. All exceptions caught — never crash the background task

### Phase 6 — Manual Trigger Endpoint

`POST /work-orders/extract-entities/{work_order_id}`:
- Admin-only (use existing `_ensure_admin()` pattern)
- Calls `extract_entities(work_order_id)` synchronously
- Returns extraction result or error details
- Logs to `user_activity_log` via `log_activity()`

### Phase 7 — Bulk Backfill Endpoint

`POST /work-orders/extract-entities/backfill`:
- Admin-only
- Queries work orders WHERE id NOT IN (SELECT work_order_id FROM work_order_entities)
- Processes in batches of 10 with `asyncio.sleep(2)` between batches
- Runs as a BackgroundTask so it doesn't block the server
- Returns immediately with count of work orders queued for processing

### Phase 8 — Validation

In the extraction service, after JSON parsing:
- Check `equipment_id` is present and non-empty
- If missing: log to `extraction_failures` with reason "empty equipment_id"
- Do not store the entity record

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Full-Stack Ownership exclusion (no frontend) | Extraction is an invisible backend pipeline; no user-facing UI exists for entity data yet | Adding a Flutter screen would be YAGNI — future spec will add entity visualization |
| Embedding vector column | Level 4 Component 2 (pattern similarity search) needs it immediately after this ships | Adding the column in a later migration would require a second deploy cycle for no benefit |
