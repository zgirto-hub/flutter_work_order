# Data Model: AI Provider Manager

**Feature**: 063-ai-provider-manager
**Date**: 2026-04-15

## Persistent entities

### `app_settings` (NEW table)

Generic key-value configuration store used in phase 1 for the provider manager. Scoped narrowly per YAGNI; additional keys added only as concrete needs appear.

| Column        | Type          | Null | Default       | Notes                                                           |
|---------------|---------------|------|---------------|-----------------------------------------------------------------|
| `key`         | text          | no   | —             | **PK**. Stable identifier (e.g., `ai_provider`).                |
| `value`       | text          | no   | —             | Raw value. JSON-encoded when the logical type is a list/object. |
| `updated_at`  | timestamptz   | no   | `now()`       | Updated by trigger on write.                                    |
| `updated_by`  | uuid          | yes  | null          | FK → `auth.users(id)`. Null for seed rows.                      |

**Seed rows** (phase 1):

| key                       | value                 | notes                                                   |
|---------------------------|-----------------------|---------------------------------------------------------|
| `ai_provider`             | `local`               | Currently active provider key                           |
| `ai_providers_available`  | `["local","gemini"]`  | JSON array of provider keys the Admin UI may select    |

**Validation rules**:
- `ai_provider` value MUST be a member of the JSON array parsed from `ai_providers_available`.
- Values for `ai_providers_available` MUST parse as a non-empty JSON array of unique lowercase strings.
- Enforcement point: backend endpoint `POST /api/ai/provider` validates before writing; DB has no CHECK constraint (would couple schema to business logic).

**RLS**: Enable RLS. Read allowed for authenticated users (frontend needs `ai_providers_available` and `ai_provider` display). Writes go through backend service-role key; no direct client writes needed.

### `user_activity_log` (EXISTING table — reused)

Fallback events write a new entry here. No schema change.

| Field           | Value (for fallback event)                                      |
|-----------------|------------------------------------------------------------------|
| `user_email`    | Requesting user's email                                          |
| `category`      | `admin` (re-uses existing category)                              |
| `action`        | `ai_provider_fallback`                                           |
| `target_label`  | Active provider key (e.g., `gemini`)                             |
| `target_id`     | Fallback provider key (e.g., `local`)                            |
| `detail`        | Short reason string (e.g., `timeout>30s`, `quota_exceeded`, `exception:<ClassName>`) |

**Why reuse**: FR-010 + Constitution VI (Audit Everything) + no new audit table (simplicity, YAGNI).

---

## In-memory / transient entities

### `AIProvider` (ABC)

```text
AIProvider
  - display_name: str (property)
  - async generate(prompt, context_chunks) -> str
  - async health_check() -> bool
  - async embed(text) -> list[float]   # RESERVED — raises NotImplementedError in base
```

Concrete: `OllamaProvider` (key: `local`), `GeminiProvider` (key: `gemini`).

### `PROVIDERS` registry

```text
PROVIDERS: dict[str, type[AIProvider]] = {
  "local":  OllamaProvider,
  "gemini": GeminiProvider,
}
```

Adding a future provider: append one entry and add `"<key>"` to the `ai_providers_available` setting. No other code changes.

### `AiRequestOutcome` (response shape)

Returned by the `/manuals/ask` endpoint as JSON. Extends the current response shape additively — existing fields preserved (FR-018).

| Field             | Type   | Notes                                                  |
|-------------------|--------|--------------------------------------------------------|
| `answer`          | string | (existing) generated answer text                       |
| `sources`         | list   | (existing) retrieved chunks                            |
| `grounded`        | bool   | (existing)                                             |
| `provider_used`   | string | **NEW**. Key of provider that produced the answer.     |
| `fallback_used`   | bool   | **NEW**. `true` if active provider failed and Local served the answer. |

### Active-provider cache entry

```text
_cache = {"value": "local", "expires_at": 1718900000.0}
```

Module-level in `resolver.py`. TTL 60s. Invalidated on TTL expiry only (no explicit broadcast on write — convergence within one TTL cycle is acceptable per FR-006).

---

## State & lifecycle

- **Provider switch**: Admin calls `POST /api/ai/provider` → backend validates key is in `ai_providers_available` → upsert `app_settings` row → returns 200. Next resolution after TTL expiry picks up the new value on every worker.
- **Health check**: No persisted state — on-demand only. `GET /api/ai/provider/health` runs `active.health_check()` and returns `{provider, healthy, reason?}`. No caching of health results in phase 1.
- **Fallback event**: Transient — one row appended to `user_activity_log` per occurrence. No dedicated counter or aggregation in phase 1.

## Out of scope (for this data model)

- Per-user provider preference tables (FR-020).
- Cost/usage tracking tables (FR-020).
- Separate audit table for provider events (reusing `user_activity_log` per R5/Constitution VI).
- Health-history table (only on-demand health checks in phase 1).
