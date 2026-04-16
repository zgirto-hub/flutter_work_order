# Contract: `/manuals/ask` response (phase 2 extension)

**Feature**: 065-fix-provider-display-audit
**Date**: 2026-04-15
**Scope**: Non-breaking extension of an existing endpoint.

## Endpoint

- Method: `POST /manuals/ask` (unchanged)
- Request body: unchanged from spec 040/062
- Response body: extended with one new field

## Response fields affected

### New field

```json
"provider_display_name": "Groq (Llama 3.3 70B)"
```

- Type: `string`
- Required: yes (from phase 2 forward)
- Source: `AIProvider.display_name` property on the provider that actually generated the answer.

### Alias retained (removal scheduled in future spec)

```json
"model": "Groq (Llama 3.3 70B)"
```

- Type: `string`
- Required: yes, for backwards compatibility with consumers that read `model`
- Value: **byte-identical** to `provider_display_name` for the duration of the compat window.
- Note: Remove in a future spec (TODO marker in code will reference the removal spec number).

### Unchanged fields

All existing response fields — `answer`, `provider_used`, `fallback_used`, `sources`, `grounded`, `duration_seconds`, `manuals_consulted`, `has_conflicts`, `retrieval_info`, `session_summary`, `agentic`, `tools_used` — retain their current shape, type, and semantics.

## Example responses

### Active provider succeeds (no fallback)

```json
{
  "answer": "The backup procedure is ...",
  "provider_used": "groq",
  "provider_display_name": "Groq (Llama 3.3 70B)",
  "fallback_used": false,
  "model": "Groq (Llama 3.3 70B)",
  "...": "other fields unchanged"
}
```

### Active provider fails, fallback to Local fires

```json
{
  "answer": "Based on the manuals ...",
  "provider_used": "local",
  "provider_display_name": "Local (Ollama)",
  "fallback_used": true,
  "model": "Local (Ollama)",
  "...": "other fields unchanged"
}
```

## Side effect: audit row (fallback case only)

When `fallback_used: true`, a row is written to `user_activity_log`:

| Column | Example value |
|---|---|
| `user_email` | `salah@admin.com` |
| `category` | `admin` |
| `action` | `ai_provider_fallback` |
| `target_label` | `gemini` |
| `target_id` | `local` |
| `detail` | `quota_exceeded` |

`detail` is constrained to: `quota_exceeded`, `timeout_30s`, `empty_response`, `missing_credentials`, `unknown`.

## Compatibility

- Clients reading only existing fields (`answer`, `provider_used`, `fallback_used`, `model`) continue to work unchanged.
- The Flutter client is updated in this same release to prefer `provider_display_name` over `model`.
- No breaking changes; no versioning required.
