# API Contracts: AI Provider Manager

**Feature**: 063-ai-provider-manager
**Date**: 2026-04-15
**Base URL**: same as existing FastAPI app (`/api` prefix via Nginx)

All endpoints return JSON. Authentication: existing bearer-token / Supabase JWT pattern used elsewhere in the app. Role enforcement happens at the endpoint handler (see per-endpoint notes).

---

## 1. `GET /api/ai/providers`

List providers available to the Admin UI (and their display names).

**Auth**: Any authenticated user.
**Role**: All roles (Admin UI and read-only chip both consume it).

**Response 200**:
```json
{
  "providers": [
    { "key": "local",  "display_name": "Local (Ollama)" },
    { "key": "gemini", "display_name": "Gemini 2.5 Flash" }
  ],
  "active": "local"
}
```

- `providers` is derived by intersecting the `ai_providers_available` setting with the keys present in the backend `PROVIDERS` registry. A key in the setting but absent from the registry is silently dropped (treated as a misconfiguration).
- `active` is the current value of `ai_provider` setting.

**Errors**:
- `500` if the `app_settings` rows are missing or malformed (should not happen after migration seed).

---

## 2. `POST /api/ai/provider`

Change the active provider.

**Auth**: Required.
**Role**: **Admin only.** Non-Admin → `403 { "error": "forbidden" }`.

**Request body**:
```json
{ "provider": "gemini" }
```

**Validation**:
- `provider` MUST be non-empty string.
- `provider` MUST exist in the current `ai_providers_available` setting.
- `provider` MUST be a registered key in the backend `PROVIDERS` registry.

**Response 200**:
```json
{ "active": "gemini", "updated_at": "2026-04-15T12:34:56Z" }
```

**Side effects**:
- Upserts `app_settings` row (`key='ai_provider'`), sets `updated_by` to the caller's user id.
- Does NOT invalidate other workers' TTL caches — convergence within 60s per FR-006.
- Logs to `user_activity_log`: category=`admin`, action=`ai_provider_changed`, target_label=new provider, detail=`old=<prev>`.

**Errors**:
- `400 { "error": "invalid_provider", "message": "..." }` — key not in available list.
- `400 { "error": "unregistered_provider", "message": "..." }` — available list references a provider class that isn't registered.
- `403 { "error": "forbidden" }` — non-Admin caller.

---

## 3. `GET /api/ai/provider/health`

Run a live health check against the currently active provider.

**Auth**: Required.
**Role**: Admin only (used by Settings UI; non-Admins have no reason to call it in phase 1). Non-Admin → `403`.

**Response 200**:
```json
{ "provider": "gemini", "healthy": true }
```

or when unhealthy:
```json
{ "provider": "gemini", "healthy": false, "reason": "timeout" }
```

**Behavior**:
- Resolves active provider (may refresh TTL cache).
- Calls `provider.health_check()` with a 10-second internal timeout.
- `reason` is a short machine-readable string: `"timeout"`, `"missing_credentials"`, `"connection_refused"`, `"upstream_error"`, or `"unknown"`.

**Errors**: Health failures do NOT return HTTP 5xx — they return 200 with `healthy: false`. HTTP 5xx is reserved for unexpected endpoint crashes.

---

## 4. Modified: `POST /api/manuals/ask` (existing endpoint)

The only existing endpoint that changes. Backward-compatible: adds two new response fields (`provider_used`, `fallback_used`). All existing fields preserved.

**Request**: Unchanged.

**Response** (added fields bolded):

```json
{
  "answer": "...",
  "sources": [...],
  "grounded": true,
  "agentic": false,
  "tools_used": [],
  "provider_used": "gemini",
  "fallback_used": false
}
```

**Internal behavior change**:
- The final answer-synthesis call previously going to `ollama_generator.generate()` now routes through `services.ai_providers.resolver.generate(prompt, chunks)` which:
  1. Resolves active provider from TTL cache.
  2. Runs `active.generate()` with `asyncio.wait_for(..., timeout=30)`.
  3. If active ≠ `local` AND call fails → runs `OllamaProvider.generate()`, sets `fallback_used=true`, logs fallback event to `user_activity_log`.
  4. If active = `local` AND call fails → raises `GeneratorUnavailableError` (existing exception, preserves existing 504 response).
  5. Both-failed or other unexpected → raises `GeneratorModelError` (existing), preserves existing error shape.

**New error branches**: none beyond the existing ones. The existing `EmbedderUnavailableError` / `GeneratorUnavailableError` / `GeneratorModelError` → HTTP error mapping in `manuals.py` is reused unchanged.

**Unchanged**: greeting-bypass short-circuit, retrieval pipeline, agentic loop, history-aware rewrite — all upstream of the provider-routed generate step.

---

## Error response envelope

All errors follow the existing project convention:

```json
{ "detail": { "error": "<code>", "message": "<human-readable>" } }
```

Codes introduced by this feature: `forbidden`, `invalid_provider`, `unregistered_provider`.
