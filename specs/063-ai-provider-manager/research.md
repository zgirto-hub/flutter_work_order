# Phase 0 Research: AI Provider Manager

**Feature**: 063-ai-provider-manager
**Date**: 2026-04-15

## Scope of research

No `NEEDS CLARIFICATION` markers remain in plan or spec; all ambiguities were resolved in the Clarifications session (2026-04-15). This document captures the short research decisions backing the plan.

---

## R1 — Gemini SDK choice

**Decision**: Use the official `google-generativeai` Python SDK (synchronous client wrapped in `httpx`-style async pattern via `asyncio.to_thread` or the SDK's async methods where available). Model: `gemini-2.5-flash`.

**Rationale**:
- First-party SDK, well-maintained, handles retries/auth uniformly.
- Gemini 2.5 Flash matches the spec's explicit model choice, has generous free-tier for low volume, and p99 typically well below the 30s fallback threshold set in Q3.
- Supports Arabic and English natively (FR-019).

**Alternatives considered**:
- Raw `httpx` calls to the REST endpoint — rejected: reinvents auth/retry for no benefit.
- LiteLLM / OpenAI-compatible wrappers — rejected: adds a dependency layer and hides provider-specific error types we need for precise fallback classification.

---

## R2 — Provider interface shape

**Decision**: Single ABC `AIProvider` with:
- `async def generate(self, prompt: str, context_chunks: list[str]) -> str` (phase 1 active)
- `async def health_check(self) -> bool`
- `display_name: str` (property)
- `async def embed(self, text: str) -> list[float]` — **reserved; base class raises `NotImplementedError`** (per Q2 clarification). No provider implements this in phase 1.

**Rationale**:
- Exactly matches the brief and the clarified scope.
- Keeping `embed()` as NotImplemented on the base — rather than an optional protocol — ensures a future provider that does implement it has a stable method name to override, while today's providers can safely omit it.

**Alternatives considered**:
- Protocol/duck typing instead of ABC — rejected: ABC gives clearer registration contract and error messages when a provider is half-implemented.
- Separate `Generator` and `Embedder` ABCs — rejected: YAGNI for phase 1; simpler to keep one class with reserved capability.

---

## R3 — TTL cache for active provider

**Decision**: Module-level dict holding `{value, expires_at}`, cache TTL = 60s. Reads are cheap Supabase `.select()` calls when the cache is cold. Writes (via `POST /api/ai/provider`) do NOT immediately invalidate other workers' caches — convergence is bounded by the 60s TTL (matches FR-006 and Q1 acceptance scenario).

**Rationale**:
- Deployment is a single FastAPI process on one server (Zorin). Even if multi-worker, 60s convergence is explicitly acceptable per spec.
- No need for Redis / pub-sub for this scale.

**Alternatives considered**:
- In-memory pub-sub / broadcast — rejected: overkill for 1-server deployment.
- Zero cache, read from Supabase every request — rejected: doubles Supabase round-trips per AI call.

---

## R4 — Fallback semantics

**Decision**: Implement fallback in a thin orchestrator (`resolver.py`) that wraps `provider.generate()`. Logic:
1. Resolve active provider from TTL cache.
2. Call `active.generate()` with a 30s wall-clock timeout (`asyncio.wait_for`).
3. If active is Local and fails → raise user-facing error (per Q4).
4. If active is non-Local and fails (exception / timeout / quota / empty) → call `OllamaProvider.generate()`, set `fallback_used=True`, log to `user_activity_log`.
5. If fallback also fails → raise user-facing error (FR-011).

**Rationale**: Aligns exactly with FR-008, FR-009, FR-010, FR-011 and Q3/Q4 clarifications.

**Alternatives considered**:
- Retry the same provider before falling back — rejected: Q4 ruled out self-retry for Local; symmetry argues against it for cloud too in phase 1 (YAGNI).

---

## R5 — Supabase `app_settings` table shape

**Decision**: Generic key-value table with RLS, Admin-write enforced at the backend (service-role key) since the backend mediates all writes.

```sql
create table public.app_settings (
  key         text primary key,
  value       text not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id)
);
```

Seeded rows:
- `('ai_provider', 'local', now(), null)`
- `('ai_providers_available', '["local","gemini"]', now(), null)`

**Rationale**:
- Generic enough to hold future phase-1-adjacent settings (e.g., later: `ai_fallback_enabled`).
- Avoids a dedicated single-row table anti-pattern.

**Alternatives considered**:
- Dedicated `ai_settings` table — rejected: overly specific.
- Environment variable — rejected: can't change at runtime without redeploy.

---

## R6 — Gemini API key handling

**Decision**: `GEMINI_API_KEY` read from `.env` via existing dotenv pattern in `backend/main.py`. `GeminiProvider.__init__` reads once at construction; health check fails (returns `False`) if missing. Key never appears in any response body, log line, or error message (scrub at error-handling boundary).

**Rationale**: FR-016 + SC-006. Keeps ops simple.

**Alternatives considered**:
- Supabase Vault — rejected: not currently used in this project; premature.
- Per-deploy rotation tooling — rejected: out of scope for phase 1.

---

## R7 — Flutter provider chip placement

**Decision**: Chip shown only in the Ask-the-AI chat UI (per Q5). Chip reads active provider from `AiProviderService.getActiveProvider()` on screen open; updates `fallback_used` state from the last `/manuals/ask` response JSON.

**Rationale**: Matches Q5. Keeps UX truthful — chip reflects what actually ran.

**Alternatives considered**:
- Chip on every AI-touching screen — rejected (Q5 Option B): misleading for screens not routed through the abstraction in phase 1.

---

## Summary

All decisions align with the spec's clarifications. No open research items.
