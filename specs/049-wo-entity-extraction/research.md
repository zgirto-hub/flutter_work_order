# Research: Work Order Entity Extraction

**Date**: 2026-04-13 | **Branch**: `049-wo-entity-extraction`

## R1: Ollama Integration Pattern

**Decision**: Reuse existing `backend/services/ollama_generator.py` — call `generate(prompt, model="gemma4:e2b")` with custom timeout.

**Rationale**: The project already has a proven async Ollama client with timeout handling, model error detection, and keep-alive support. No reason to build a new one.

**Alternatives considered**:
- Direct httpx calls: Rejected — duplicates existing code, violates YAGNI.
- Python ollama SDK: Rejected — would add a new dependency when httpx wrapper already works.

## R2: Idempotent Upsert Strategy

**Decision**: Use Supabase `.upsert()` with `work_order_id` as the conflict key. The `work_order_entities` table has a unique constraint on `work_order_id`.

**Rationale**: Supabase Python client supports `.upsert()` which maps to PostgreSQL `INSERT ... ON CONFLICT DO UPDATE`. This is the simplest idempotent write — a single call handles both insert and update.

**Alternatives considered**:
- SELECT then INSERT/UPDATE: Rejected — race condition under concurrent extraction; two queries instead of one.
- DELETE then INSERT: Rejected — loses `extracted_at` history; not truly idempotent.

## R3: JSON Cleaning from Gemma Output

**Decision**: Strip markdown code fences (```json ... ```) using regex before JSON parsing. Also strip any text before the first `{` and after the last `}`.

**Rationale**: Despite prompts instructing "raw JSON only," LLMs frequently wrap output in markdown code blocks. The cleaning step is a safety net, not a primary strategy — the prompt is the first line of defense.

**Alternatives considered**:
- Rely solely on prompt engineering: Rejected — Gemma sometimes adds preamble despite clear instructions. A cleaning step costs nothing and prevents failures.
- Use Ollama's JSON mode (`format: "json"`): Investigated — Ollama supports a `format` parameter. However, Gemma E2B's adherence to this varies. Using both the format hint AND cleaning is the most robust approach.

## R4: Arabic/English Mixed Text Handling

**Decision**: The extraction prompt explicitly instructs Gemma to always output field values in English, regardless of input language. The prompt includes an example showing Arabic input producing English output.

**Rationale**: Downstream consumers (analytics, search, dashboards) need consistent English labels for equipment types, fault codes, and actions. The AI model handles translation naturally as part of extraction.

**Alternatives considered**:
- Store in original language with a translation step: Rejected — adds complexity; entity values are short labels, not prose.
- Dual-language storage: Rejected — YAGNI; no current requirement for Arabic entity labels.

## R5: Background Task Model

**Decision**: Use FastAPI's built-in `BackgroundTasks` dependency. Add `background_tasks: BackgroundTasks` parameter to `create_work_order()` and `close_work_order()`, then call `background_tasks.add_task()`.

**Rationale**: FastAPI's BackgroundTasks is the simplest solution — no external task queue needed. It runs the task in the same process after the response is sent. Given low work order creation frequency (<100/day), this is sufficient.

**Alternatives considered**:
- Celery/Redis queue: Rejected — massive overkill for this volume; adds infrastructure complexity.
- asyncio.create_task: Rejected — tasks could be lost on worker restart; BackgroundTasks is the idiomatic FastAPI approach.

## R6: Embedding Vector Column

**Decision**: Add a `vector(768)` column to `work_order_entities` using pgvector, populated by `nomic-embed-text` via the existing `ollama_embedder.py`.

**Rationale**: Level 4 Component 2 (pattern similarity search) will use this column immediately after this feature ships. Adding it now avoids a second migration. The 768-dimension size matches `nomic-embed-text` output.

**Alternatives considered**:
- Add column later: Rejected — requires a second migration and deploy for no benefit when we know the exact requirements.
- Store embeddings in a separate table: Rejected — one-to-one relationship makes a column simpler.
- Populate embedding later (separate job): Rejected — embedding at extraction time costs one extra Ollama call (~1s) and avoids needing a second pass over all entities. Level 4 Component 2 needs embeddings immediately.

## R7: Embedding Generation Strategy

**Decision**: After successful entity extraction, embed the combined work order text (description + tech_notes) using `ollama_embedder.embed()` (nomic-embed-text, 768 dims) and store the vector in the same upsert. Embedding failure is best-effort — if it fails, store entities with a null embedding rather than failing the entire extraction.

**Rationale**: The embedding represents the full work order context, not just extracted entities. This allows similarity search across work orders by their narrative content. Using the existing `ollama_embedder.py` keeps the implementation consistent with the RAG pipeline (specs 040-048).

**Alternatives considered**:
- Embed the extracted JSON instead of raw text: Rejected — raw text preserves context, terminology, and nuance that structured fields lose.
- Fail extraction if embedding fails: Rejected — entity data is valuable even without the vector; embedding can be backfilled later.

## R8: Failure Logging Table vs. Application Logs

**Decision**: Log failures to a dedicated `extraction_failures` Supabase table rather than just application logs.

**Rationale**: Application logs (stdout/stderr) are transient and hard to query. A database table enables admin dashboards, retry workflows, and historical analysis of extraction quality. Aligns with Constitution Principle VI (Audit Everything).

**Alternatives considered**:
- stdout logging only: Rejected — not queryable, not persistent across restarts.
- Both table and stdout: Adopted — print to stderr for real-time debugging AND insert to table for persistence.
