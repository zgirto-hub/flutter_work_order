# Research: Entity Extraction Admin Toggle & AI Priority Queue

**Branch**: `052-extraction-toggle-queue` | **Date**: 2026-04-13

## R1: system_settings Table

**Decision**: Create new `system_settings` table — it does not exist in any migration.

**Rationale**: Grep across `supabase/migrations/` and the full codebase confirms no `system_settings` table. A generic key-value table is the simplest approach for a single toggle and is reusable for future admin settings.

**Alternatives considered**:
- Hardcoded config file — rejected: requires restart to change, no audit trail
- Environment variable — rejected: requires process restart, not toggleable from UI

## R2: Ollama Call Architecture

**Decision**: Queue wraps `ollama_generator.generate()` and `ollama_embedder.embed_single()`/`embed_many()` at the service level. Add a `priority` parameter (default HIGH=1) so callers can opt into LOW=2.

**Rationale**: Codebase audit reveals two categories of Ollama callers:
1. **Via shared services** (already use `generate()`/`embed_single()`): `entity_extractor.py`, `manual_rag_service.py`, `agentic_tools.py`, `validated_qa_service.py`, `manuals.py`
2. **Direct httpx calls** (bypass shared services): `ai_search.py`, `ai_insights.py`, `ai_assist.py` (3 call sites)

Category 2 routers must be refactored to use `ollama_generator.generate()` before queue integration. After refactoring, the queue is a single integration point in two files.

**Alternatives considered**:
- Router-level wrapping — rejected: 8+ integration points, fragile, future callers could bypass
- Middleware-level interception — rejected: over-engineered for the problem

## R3: Queue Design

**Decision**: `asyncio.PriorityQueue` with a single worker coroutine started in FastAPI lifespan. Jobs carry a priority int and an `asyncio.Future` for result delivery.

**Rationale**:
- Single-process server (no horizontal scaling) — in-memory queue is sufficient
- `asyncio.PriorityQueue` is stdlib, zero dependencies
- One worker ensures serialized Ollama access (FR-010)
- `asyncio.Future` allows HIGH-priority callers to `await` their result while LOW-priority callers fire-and-forget

**Alternatives considered**:
- Redis + Celery — rejected: external dependency, overkill for single-server
- `asyncio.Queue` (non-priority) — rejected: can't prioritize user-facing over background
- Multiple workers — rejected: defeats the purpose of serializing Ollama access

## R4: Refactoring Direct httpx Callers

**Decision**: Migrate `ai_search.py`, `ai_insights.py`, `ai_assist.py` to use `ollama_generator.generate()` instead of direct `httpx.AsyncClient` calls.

**Rationale**: All three routers duplicate the same httpx pattern with identical error handling. They already import httpx for Ollama — switching to the shared service:
- Eliminates duplicated connection/timeout/error logic
- Automatically inherits queue integration
- Preserves existing error behavior (the service raises typed exceptions that can be caught)

**Impact**: 5 call sites across 3 files. Each is a straightforward replacement of ~8 lines of httpx code with a single `await generate(prompt)` call plus exception mapping.

## R5: Admin Settings UI

**Decision**: Create a new admin settings screen at `frontend/lib/screens/admin/settings_screen.dart` with the extraction toggle. Add navigation from the existing admin area.

**Rationale**: No admin settings screen currently exists (`frontend/lib/screens/admin/` contains only `departments_screen.dart`, `user_management_screen.dart`, `department_routes_screen.dart`). A dedicated settings screen is the right place for global toggles.

**Alternatives considered**:
- Add to an existing admin screen — rejected: departments/users/routes are all entity-specific, a toggle doesn't fit
- Drawer/dialog — rejected: settings deserve a proper screen for future extensibility

## R6: Toggle Read Strategy

**Decision**: Read toggle from Supabase on each WO save (no caching). Cache is unnecessary given the low frequency of WO saves.

**Rationale**: WO saves happen at most a few per minute. A single Supabase SELECT by primary key is <5ms. Caching adds complexity (invalidation, staleness) for negligible performance gain.

**Alternatives considered**:
- In-memory cache with TTL — rejected: adds complexity, WO save rate is too low to justify
- Read on startup only — rejected: toggle changes wouldn't take effect without restart (violates FR-012)

## R7: Entity Extractor Queue Integration

**Decision**: Entity extractor passes `priority=2` (LOW) to `generate()` and `embed_single()`. All other callers default to `priority=1` (HIGH).

**Rationale**: The priority parameter defaults to HIGH, so no existing caller needs modification. Only `entity_extractor.py` explicitly opts into LOW priority. This is the minimal-change approach.

## R8: FastAPI Lifespan Worker

**Decision**: Start queue worker as an `asyncio.create_task()` in the existing lifespan function. Cancel on shutdown.

**Rationale**: `main.py` already uses `@asynccontextmanager` lifespan pattern with `seed_built_in_rules()`. Adding `create_task()` for the queue worker fits naturally. The worker runs for the lifetime of the process and is cancelled during shutdown.
