# Research: 076 — Default Q&A Generation to Gemini Flash

**Date**: 2026-04-16

## R-001: Where is the default provider constant?

**Decision (amended 2026-04-17)**: Introduce **two** provider-level constants in `backend/services/ai_providers/resolver.py`, splitting the formerly-overloaded `_DEFAULT_PROVIDER` into two semantically distinct symbols:

- `_DEFAULT_PROVIDER = "gemini"` — the default **active** provider. Read by `get_active_provider_key()` when no `app_settings` row exists or the DB lookup fails. Satisfies FR-001 and FR-003.
- `_FALLBACK_PROVIDER = "local"` — the **always-local** fallback target. Used by `_fallback_to_local()` to know which provider to route to after a Gemini failure, and by the two guards inside `generate()` / `_fallback_to_local()` that decide whether a fallback attempt is possible (`if active_key != _FALLBACK_PROVIDER: return await _fallback_to_local(...)`).

**Rationale (amended)**: The original R-001 proposed a single-line change to `_DEFAULT_PROVIDER`. Code review of opencode's implementation (2026-04-17) surfaced a latent bug that the single-constant model silently introduces after T001:

- Before T001: `_DEFAULT_PROVIDER = "local"`. The guard `if active_key != _DEFAULT_PROVIDER:` fires iff the active provider is NOT local — exactly when a fallback to local is needed. Correct.
- After T001 with a single constant: `_DEFAULT_PROVIDER = "gemini"`. The same guard `if active_key != _DEFAULT_PROVIDER:` now fires iff the active provider is NOT gemini — which inverts fallback direction. When active is gemini and Gemini fails, the guard is FALSE and the exception re-raises to the caller instead of falling back to Ollama. This breaks FR-004.

The single constant was overloaded, simultaneously meaning "default active provider" (read at startup) AND "fallback target" (read during failure handling). Those two concepts diverge the moment the default active provider stops being the same as the fallback target — exactly what this spec does. The amended decision splits the overload into two named symbols so each call site reads the one that matches its intent, and neither flips semantics silently when the default changes again in the future.

**Alternatives considered (amended)**:

- *Single `_DEFAULT_PROVIDER = "gemini"` constant + naive T001 edit.* Rejected — introduces the fallback-direction bug described above.
- *Single `_DEFAULT_PROVIDER` constant + hardcoded `"local"` string literal in the two fallback guards.* Rejected — the magic string duplicated across two guards is brittle and mutes future audibility when another provider is added.
- *Rename `_DEFAULT_PROVIDER` → `_FALLBACK_PROVIDER` (always "local") and add a separate `_DEFAULT_ACTIVE_PROVIDER = "gemini"`.* Equivalent semantically but requires more churn in existing spec 063/065 test patches that reference `_DEFAULT_PROVIDER` by that name. Kept `_DEFAULT_PROVIDER` for the active default and added `_FALLBACK_PROVIDER` as the new symbol to minimize cross-spec test disruption.

**History note**: The original pre-amendment text of R-001 claimed "Adding a second constant for 'generation default' vs 'pipeline default' — rejected because all pipeline stages that must stay local already call `ollama_generator.generate()` directly and never touch the resolver." That rejection was correct for the *pipeline-isolation* use of a second constant (which remains rejected — see R-003). It did not anticipate the *fallback-target* use of a second constant, which this amendment adds.

## R-002: How does the resolver fall back when no DB row exists?

**Decision**: No change needed. The function `get_active_provider_key()` (resolver.py lines 18–33) follows: cache → DB → stale cache → `_DEFAULT_PROVIDER`. Changing the constant is sufficient.

**Rationale**: The flow returns `_DEFAULT_PROVIDER` only when both DB and cache miss. With the constant changed to `"gemini"`, fresh deployments automatically get Gemini.

## R-003: Are query rewrite and HyDE isolated from the resolver?

**Decision**: Confirmed isolated. Both `_rewrite_query()` (manual_rag_service.py:409) and `_generate_hypothetical_answer()` (manual_rag_service.py:515) import and call `ollama_generator.generate()` directly. They never call the resolver.

**Rationale**: No code change needed for FR-002/FR-007 — the isolation already exists. The plan should add a code comment documenting this as intentional.

## R-004: How to handle existing deployments with `app_settings.ai_provider = "local"`?

**Decision**: One-time startup migration in the `lifespan` event handler (main.py). Read `app_settings` for key `"ai_provider"` — if the value is exactly `"local"`, update it to `"gemini"` and log an audit event.

**Rationale**: The `lifespan` context manager in main.py is the established pattern for startup tasks (e.g., `seed_built_in_rules()`). Adding an async migration call there is consistent. The migration must be idempotent — if the value is already `"gemini"` or anything else, it's a no-op.

**Alternatives considered**:
- SQL migration (`UPDATE app_settings SET value='gemini' WHERE key='ai_provider' AND value='local'`) — rejected because Supabase migrations run once at deploy time but not on every app restart; if the migration ran before the code deploys, timing issues arise. Code-level migration in lifespan is safer.
- Environment variable flag — rejected as over-engineering for a one-time operation.

## R-005: Does the seed migration need updating?

**Decision**: Yes. Update `supabase/migrations/20260415_app_settings.sql` seed value from `'local'` to `'gemini'` so that fresh databases (new deployments) start with Gemini as default.

**Rationale**: The `ON CONFLICT DO UPDATE` clause means re-running the migration on an existing DB would overwrite admin choices — but Supabase migrations only run once, so this is safe. For fresh DBs, the seed should reflect the new default.

**Alternative**: Leave the seed as `'local'` and rely solely on the code-level migration — rejected because a brand-new deployment would briefly start with `"local"` until the lifespan handler runs and overwrites it. Better to seed correctly.

## R-006: Activity logging pattern for migration audit event

**Decision**: Use existing `log_activity()` from `backend/utils/activity.py` with `category="admin"`, `action="ai_provider_migrated"`, `target_label="gemini"`, `detail="old=local"`.

**Rationale**: Fire-and-forget, synchronous, consistent with the provider-change logging in `ai_providers.py:88–95`. Uses `user_email="system"` since no user triggers this.

## R-007: Test strategy

**Decision**: Add `backend/tests/test_provider_default.py` with:
1. Test that `_DEFAULT_PROVIDER` is `"gemini"`.
2. Test that `get_active_provider_key()` returns `"gemini"` when no DB row exists (mock `get_setting` to return `None`).
3. Test migration function: given value `"local"` → updates to `"gemini"`; given value `"gemini"` → no-op.

**Rationale**: Existing test patterns use pytest-asyncio auto-mode with mocked Supabase. No dedicated resolver tests exist yet, so this is greenfield.
