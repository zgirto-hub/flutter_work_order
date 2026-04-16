# Tasks: Default Q&A Generation to Gemini Flash

**Input**: `/specs/076-gemini-default-generation/plan.md` + `research.md` + `data-model.md` + `contracts/api.md` + `spec.md`
**Implementer**: opencode
**Reviewer after implementation**: Claude Code (superpowers code review)
**Branch**: `076-gemini-default-generation` (`git checkout 076-gemini-default-generation` before starting)

## Implementer orientation (read before T001)

This is a narrow, backend-only change. Before touching any code, orient yourself:

1. Read `plan.md` end-to-end. It pins the exact decisions and invariants.
2. Read `research.md` sections R-001 through R-007 — each task below is the executable form of one research decision.
3. Read the current contents of these four files; do not edit yet:
   - `backend/services/ai_providers/resolver.py`
   - `backend/main.py` (specifically the `lifespan` function)
   - `backend/services/manual_rag_service.py` (specifically `_rewrite_query` and `_generate_hypothetical_answer`)
   - `supabase/migrations/20260415_app_settings.sql`
4. Confirm the signature of `log_activity` in `backend/utils/activity.py`. It is **synchronous** (`def`, not `async def`) — calls to it must NOT be awaited.

If `git status` shows pre-existing uncommitted edits to any of the four files above, stop and tell the user. Do not try to merge or rebase — the user will tell you whether to reset or keep the edits.

## Guardrails (opencode must follow)

- **One task per commit is not required**, but **do NOT batch T001+T002 with T003+T004** in the same commit — foundational flips (T001, T002) must be observable as a separate diff from the migration function (T003, T004).
- **Do not modify** any file outside this task list. If a task tempts you to "fix a small thing nearby," resist and flag it to the user instead.
- **Do not add** new dependencies, new environment variables, new config files, new migration files, or new endpoints. This spec is constrained to: 1 constant flip, 1 new Python function, 1 lifespan wiring, 1 seed-value edit, 2 code comments, 1 test file.
- **Do not await `log_activity`**. It is synchronous.
- **Do not alter** the `_fallback_to_local`, `_classify_fallback_reason`, or `generate` functions in `resolver.py` beyond the single inline comment in T005. Their logic is load-bearing for spec 063/065 audit contracts.
- If pytest collects but any pre-existing test fails for reasons unrelated to this spec, note it in the final report rather than trying to fix it.

---

## Phase A — Foundational (T001, T002 can run in parallel)

### T001 [P] — Flip `_DEFAULT_PROVIDER` constant

**File**: `backend/services/ai_providers/resolver.py`
**Line**: 15 (the `_DEFAULT_PROVIDER = "local"` assignment near the top of the module)

**Change**:

```python
# Before
_DEFAULT_PROVIDER = "local"

# After
_DEFAULT_PROVIDER = "gemini"
```

**Do NOT** touch any other line in this file for T001. The single-character edit is intentional — research.md R-001 rejects adding a second constant.

**Done when**: `rg '_DEFAULT_PROVIDER = "gemini"' backend/services/ai_providers/resolver.py` returns exactly one match.

---

### T002 [P] — Update seed value in existing migration

**File**: `supabase/migrations/20260415_app_settings.sql`
**Line**: 24 (inside the `INSERT INTO public.app_settings (key, value) VALUES (...)` block)

**Change**:

```sql
-- Before
    ('ai_provider', 'local'),

-- After
    ('ai_provider', 'gemini'),
```

**Do NOT** touch the `ON CONFLICT DO UPDATE` clause or the `ai_providers_available` row. Only the `('ai_provider', ...)` tuple's value changes.

**Rationale**: research.md R-005 — Supabase migrations run once per database, so editing this file in place is safe for deployed environments; the lifespan migration (T003/T004) handles existing rows. Fresh deployments now seed `'gemini'` directly.

**Done when**: `rg "'ai_provider', 'gemini'" supabase/migrations/20260415_app_settings.sql` returns exactly one match.

---

## Phase B — User Story 1: One-time lifespan migration (T003 → T004, sequential)

### T003 — Add `_migrate_default_provider()` to `resolver.py`

**File**: `backend/services/ai_providers/resolver.py`
**Location**: Append the new function at the **end of the file** (after `_fallback_to_local`). Do NOT insert it above `generate` — keep existing function order stable.

**Add these imports to the top-of-file import block** (if and only if they are not already present):

- `set_setting` from `utils.app_settings` — extend the existing `from utils.app_settings import get_setting` line to `from utils.app_settings import get_setting, set_setting`.
- `log_activity` from `utils.activity` — already imported; do not duplicate.

**Append this function verbatim** (mind the docstring, the exact string comparisons, the non-awaited `log_activity`, and the try/except that never re-raises):

```python
async def _migrate_default_provider() -> None:
    """One-time migration: rewrite stored 'local' default to 'gemini' (spec 076).

    Idempotent — runs on every startup but only mutates state when the stored
    value is exactly 'local'. Safe across Uvicorn worker restarts: whichever
    worker wins the first UPDATE observes `current == "local"` exactly once;
    subsequent starts (same worker or new) observe 'gemini' and skip.
    Failures are logged and swallowed — migration MUST NOT block startup.
    """
    try:
        current = await get_setting("ai_provider")
        if current == "local":
            await set_setting("ai_provider", "gemini")
            invalidate_cache()
            log_activity(
                "system",
                category="admin",
                action="ai_provider_migrated",
                target_label="gemini",
                detail="old=local",
            )
            logger.info("spec 076: migrated ai_provider from 'local' to 'gemini'")
    except Exception as e:
        logger.error(f"spec 076: ai_provider migration failed: {e}")
```

**Invariants**:

- `log_activity` is synchronous — **no `await`**.
- The `if current == "local":` uses exact string equality. Do not use `current.lower() == "local"` or any loose comparison.
- The try/except must catch `Exception`, not `BaseException`. Startup must survive a failed migration.

**Done when**: `python -c "from backend.services.ai_providers import resolver; import inspect; print(inspect.iscoroutinefunction(resolver._migrate_default_provider))"` prints `True`.

---

### T004 — Wire migration into the FastAPI lifespan

**File**: `backend/main.py`
**Location**: Inside the `async def lifespan(app: FastAPI):` function, in the **startup** section (before `yield`), **after** the existing `await seed_built_in_rules()` call. Match the existing lazy-import pattern — add the import inside the function body, not at the top of the module.

**Change**: Add two lines.

1. Immediately after the existing `from services.pattern_engine import seed_built_in_rules` (or nearby with the other lazy imports), add:

   ```python
   from services.ai_providers.resolver import _migrate_default_provider
   ```

2. Immediately after `await seed_built_in_rules()`, add:

   ```python
   await _migrate_default_provider()
   ```

**Do NOT** modify the shutdown section (the code after `yield`). Do NOT reorder existing startup calls.

**Done when**:
- `rg 'await _migrate_default_provider' backend/main.py` returns exactly one match.
- The match appears on a line after `await seed_built_in_rules()` in `backend/main.py`.

---

## Phase C — User Story 2: Document fallback behavior (T005, documentation-only)

### T005 — Inline comment: 429 handling in `resolver.generate`

**File**: `backend/services/ai_providers/resolver.py`
**Location**: Inside the `async def generate(...)` function, in the block of comments that already begins with `# spec-065 contract: ...` (around line 53–58 in the pre-spec-076 file).

**Add exactly one comment line** immediately after the existing `# spec-065 contract ...` comment block and before the line `active_key = await get_active_provider_key()`:

```python
# Spec 076: All failures (timeout, error, 429/quota-exceeded, empty response, missing credentials) trigger identical per-request fallback to Ollama. No circuit-breaker.
```

**Do NOT** change the logic. This is a docs-only task that makes the clarified FR-004 behavior discoverable from the call site. research.md R-004 confirms the code already does the right thing.

**Done when**: `rg 'Spec 076: All failures' backend/services/ai_providers/resolver.py` returns exactly one match.

---

## Phase D — User Story 3: Document pipeline-stage isolation (T006, documentation-only)

### T006 — Inline comments on rewrite and HyDE

**File**: `backend/services/manual_rag_service.py`
**Locations**: Two functions, each gets one comment line immediately **inside** the function body, above the existing docstring or first line of code — whichever comes first.

1. `async def _rewrite_query(question: str, history: list[dict] | None) -> str:` — add:

   ```python
       # Spec 076 / FR-007: Intentionally hardcoded to Ollama — NOT routed through provider resolver.
   ```

2. `async def _generate_hypothetical_answer(query: str) -> str | None:` — add the same comment:

   ```python
       # Spec 076 / FR-007: Intentionally hardcoded to Ollama — NOT routed through provider resolver.
   ```

**Do NOT** add this comment to any other function. Pipeline stages that DO currently route through the resolver (the two `provider_generate` call sites in `manual_rag_service.py` around lines 638 and 768) must be left untouched.

**Done when**: `rg 'Spec 076 / FR-007' backend/services/manual_rag_service.py` returns exactly two matches.

---

## Phase E — Tests (T007, depends on T001 + T003)

### T007 — Create `backend/tests/test_provider_default.py`

**File**: `backend/tests/test_provider_default.py` (NEW)

**Test-framework conventions** (from `backend/tests/conftest.py`): pytest-asyncio auto-mode is enabled — define `async def test_*` directly; no `@pytest.mark.asyncio` decorator. Use `unittest.mock.patch` and `unittest.mock.AsyncMock`.

**Write exactly these five tests**, each in its own function, in this order:

1. `test_default_provider_constant_is_gemini()` — synchronous test; import `_DEFAULT_PROVIDER` from `services.ai_providers.resolver`; assert it equals `"gemini"`.

2. `test_get_active_provider_falls_through_to_gemini_when_db_empty()` — async test; clear the resolver cache (`resolver._cache["value"] = None; resolver._cache["expires_at"] = 0.0`); patch `services.ai_providers.resolver.get_setting` with `AsyncMock(return_value=None)`; `await resolver.get_active_provider_key()`; assert the result is `"gemini"`.

3. `test_migrate_rewrites_local_to_gemini()` — async test; patch `services.ai_providers.resolver.get_setting` with `AsyncMock(return_value="local")`; patch `services.ai_providers.resolver.set_setting` with `AsyncMock()`; patch `services.ai_providers.resolver.log_activity` with a regular `MagicMock()` (it's synchronous); patch `services.ai_providers.resolver.invalidate_cache` with `MagicMock()`; `await resolver._migrate_default_provider()`; assert `set_setting` was called exactly once with positional or keyword args equivalent to `("ai_provider", "gemini")`; assert `log_activity` was called exactly once; assert `invalidate_cache` was called exactly once.

4. `test_migrate_is_noop_when_value_already_gemini()` — async test; patch `get_setting` → `AsyncMock(return_value="gemini")`; patch `set_setting` → `AsyncMock()`; patch `log_activity` → `MagicMock()`; call `_migrate_default_provider()`; assert `set_setting` was NOT called; assert `log_activity` was NOT called.

5. `test_migrate_is_noop_when_row_missing()` — async test; patch `get_setting` → `AsyncMock(return_value=None)`; patch `set_setting` → `AsyncMock()`; call `_migrate_default_provider()`; assert `set_setting` was NOT called.

**Do NOT** add tests that exercise the real Supabase client. All external side-effects must be mocked.

**Do NOT** add tests for the fallback path — spec 063/065 already cover it.

**Done when**: `cd backend && python -m pytest tests/test_provider_default.py -v` reports 5 passed.

---

## Phase F — Verification (T008, T009)

### T008 — Run the backend test suite

Run from repo root:

```bash
cd backend && python -m pytest tests/ -v 2>&1 | tail -60
```

**Acceptance**: all tests that passed before T001 still pass; the 5 new tests in T007 pass. If any pre-existing test fails and the failure is clearly unrelated to spec 076 (e.g., a flaky OCR test, an unrelated Supabase test), capture the failing test name and continue — do not attempt to fix it. If any pre-existing test fails in a way plausibly caused by T001–T006 (anything touching `resolver`, `main`, or `manual_rag_service`), stop and report.

### T009 — Manual end-to-end smoke (report-only; do not run automatically)

**Do not execute this locally** — production smoke happens on the Zorin server after deployment. Instead, write a 3-line summary at the bottom of your final report describing what the operator should check:

1. Check server logs for `spec 076: migrated ai_provider from 'local' to 'gemini'` on first restart after deploy. Should appear **once**.
2. Hit `POST /manuals/ask` with any question. Check the response's `latency_breakdown` (from spec 066) — the generator stage should now show `provider: "gemini"`.
3. Temporarily unset `GEMINI_API_KEY` on the server and repeat step 2. The response should still succeed (via Ollama fallback), and `user_activity_log` should show one `ai_provider_fallback` row per request. Restore `GEMINI_API_KEY` afterward.

---

## Dependency graph

```
T001 ──┐
       ├──▶ T003 ──▶ T004 ──▶ T007 ──▶ T008 ──▶ T009
T002 ──┘                            ↑
                                    │
T005, T006 (parallel, docs-only)────┘
```

**Parallel-safe groups**:
- Before any dependent starts: `{T001, T002}` in parallel.
- After T001 + T003 exist: `{T005, T006}` can run in parallel with `{T007}` because they touch different files.

---

## Handoff to reviewer

When all tasks above are done:

1. Run `git status` and `git diff --stat` and include the output at the top of your final message.
2. Confirm `cd backend && python -m pytest tests/ -v` is green (or only pre-existing unrelated failures).
3. Do NOT commit. Leave the diff uncommitted.
4. Tell the user: "076 implementation complete. Ready for Claude Code superpowers code review."

Claude Code will then run a superpowers code review — it will read every touched file, compare against spec.md + plan.md + research.md, and either approve, request fixes, or flag gaps before the change is committed and deployed.
