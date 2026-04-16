# Phase 1 Data Model: Phase 2 Cleanups

**Feature**: 065-fix-provider-display-audit
**Date**: 2026-04-15

## Scope

**No database schema changes.** This spec extends an existing response payload and writes to an existing table. Below is a reference of the entities touched.

---

## Entity: `/manuals/ask` response (extended)

Existing JSON response body from the Ask-the-AI flow. This spec adds one field and retains one legacy alias.

| Field | Type | Direction | Notes |
|---|---|---|---|
| `answer` | string | unchanged | Generated answer text. |
| `provider_used` | string | unchanged | Provider key (e.g., `"groq"`, `"local"`). Already present from spec 063. |
| `fallback_used` | boolean | unchanged | True if active provider failed and Local served. Already present from spec 063. |
| **`provider_display_name`** | string | **NEW** | Human-readable provider name from `AIProvider.display_name` — matches the provider that actually generated the answer (not the configured active provider when fallback occurs). |
| `model` | string | retained as alias | Now stamped with the same string as `provider_display_name`. Scheduled for removal in a future spec (FR-009). |
| `sources`, `grounded`, `duration_seconds`, `manuals_consulted`, etc. | — | unchanged | All other fields preserved verbatim. |

### Validation Rules

- `provider_display_name` MUST be non-empty string matching the `display_name` of the provider referenced by `provider_used`.
- When `fallback_used: true`, `provider_used` and `provider_display_name` refer to the *fallback* provider (Local Ollama), not the originally-active cloud provider.
- `model` MUST equal `provider_display_name` byte-for-byte while the alias is in effect.

---

## Entity: `user_activity_log` row for fallback (existing table, new action)

Written exactly once per fallback event (see FR-003). Uses existing schema; no migration needed.

| Column | Value | Notes |
|---|---|---|
| `user_email` (actor) | requesting user's email | Threaded down from the `/manuals/ask` handler. |
| `category` | `'admin'` or existing AI category | Follow the pattern used by `ai_provider_changed` in spec 063. |
| `action` | `'ai_provider_fallback'` | Canonical action verb for this event. |
| `target_label` | failed provider key (e.g., `'gemini'`) | The provider that the Admin *selected* but which failed for this request. |
| `target_id` | fallback provider key (`'local'` in phase 1) | The provider that ultimately served the answer. |
| `detail` | one of `{quota_exceeded, timeout_30s, empty_response, missing_credentials, unknown}` | Closed taxonomy per Q3 clarification. Raw exception text is NEVER stored here. |
| `created_at` | server timestamp | Default. |

### Validation Rules

- Write happens only when fallback actually fires (`fallback_used: true` in the response).
- Write does NOT happen when the active provider IS Local and Local fails (no fallback occurred).
- Write does NOT happen on a successful active-provider response.
- One row per fallback event — no batching, no suppression, no deduplication.

---

## Entity: Flutter `ManualAskResponse` model

Dart-side mirror of the backend response. This spec adds one nullable field; legacy `model` retained during compat window.

| Dart field | Type | Notes |
|---|---|---|
| `providerUsed` | `String?` | Unchanged. |
| `fallbackUsed` | `bool` | Unchanged (default `false`). |
| **`providerDisplayName`** | `String?` | **NEW**. Parsed from JSON. Null-safe in case of older/cached responses. |
| `model` | `String?` | Retained alias; falls back to `providerDisplayName` if backend stops sending it. |

### Consumer behavior

- Chat footer renders `providerDisplayName ?? model ?? 'Unknown'`.
- `AiProviderChip` receives `fallbackUsed` and `providerDisplayName` as the per-response override.

---

## Summary

One new string field in the response, one new row type in an existing audit table, one new nullable field in a Dart model. No migrations. No new tables. No new endpoints.
