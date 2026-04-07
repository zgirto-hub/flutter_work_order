# Contract: Skill Interface

**Feature**: 028-openclaw-telegram-ops
**Applies to**: All skills under `~/.openclaw/skills/`

## Invocation

OpenClaw spawns a skill's `entrypoint` (declared in `SKILL.md` frontmatter) as a subprocess and writes a JSON envelope to its stdin. The subprocess inherits these environment variables from `openclaw.json` `env`:

| Env var | Example | Required |
|---|---|---|
| `ADMIN_EMAIL` | `admin@example.com` | yes |
| `API_BASE_URL` | `http://localhost:8000/api` | yes |
| `OPENCLAW_CALLER_ID` | `123456789` | yes |
| `OPENCLAW_CONFIRMED` | `true` / `false` | yes |

## Stdin envelope

```json
{
  "caller_id": "123456789",
  "action": "<action-name>",
  "args": { /* action-specific */ },
  "confirmed": false,
  "raw_message": "original user text"
}
```

## Stdout response

```json
{
  "status": "ok" | "error" | "needs_confirmation",
  "reply": "Markdown body for Telegram",
  "audit": {
    "action": "<action-name>",
    "args": { /* sanitized */ },
    "outcome": "success" | "failure" | "confirmation_required" | "confirmation_expired",
    "duration_ms": 0
  }
}
```

### Status semantics

- `ok` — action ran successfully; `reply` will be sent to the user; outcome=`success`.
- `error` — action failed (HTTP 5xx, network down, validation, etc.); `reply` is the error message to show; outcome=`failure`; `audit.error` is populated.
- `needs_confirmation` — action requires user confirmation; OpenClaw stores the pending envelope for 60 s; `reply` MUST contain the confirmation prompt; outcome=`confirmation_required`.

## Required behavior of every skill

1. MUST verify `caller_id == ADMIN_EMAIL`-mapped Telegram ID OR rely on OpenClaw's channel-layer check (defense in depth — at minimum, refuse if env var `OPENCLAW_CALLER_ID` is empty).
2. MUST emit only one JSON object on stdout. Diagnostics → stderr.
3. MUST exit 0 even on logical errors (use `status=error` in the envelope). Non-zero exit means OpenClaw failed to parse the response and reports a generic error.
4. MUST NOT call any URL that is not under `$API_BASE_URL` (skills MUST stay on localhost).
5. MUST be idempotent for read-only actions and re-runnable safely for write actions when `confirmed=true`.
6. MUST set realistic `args` in the audit block, omitting any secrets.
