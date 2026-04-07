# Phase 1 Data Model: OpenClaw Telegram Ops Assistant

**Feature**: 028-openclaw-telegram-ops
**Date**: 2026-04-07

This feature stores no application data — all Work Order state remains in Supabase, accessed only via the existing FastAPI backend. The "data model" here describes the on-server configuration artifacts and the audit log record schema. No new database tables or migrations are introduced.

---

## E1. OpenClaw Configuration (`~/.openclaw/openclaw.json`)

The runtime config that ties the bot, the LLM, and the skills together.

| Field | Type | Required | Description |
|---|---|---|---|
| `llm.provider` | string | yes | Constant: `"ollama"` |
| `llm.endpoint` | string | yes | `"http://localhost:11434"` |
| `llm.model` | string | yes | e.g. `"gemma4"` (whatever Ollama has loaded) |
| `channels.telegram.enabled` | bool | yes | `true` |
| `channels.telegram.botToken` | string | yes | From @BotFather; rendered into the file from env var at install time |
| `channels.telegram.allowFrom` | array<string> | yes | Exactly one Telegram user ID — the admin |
| `skills.directory` | string | yes | `"~/.openclaw/skills"` |
| `skills.cron` | array<CronEntry> | yes | Scheduled invocations (see E2) |
| `audit.logPath` | string | yes | `"~/.openclaw/audit.log"` |
| `confirmation.windowSeconds` | int | yes | `60` (per FR-004) |
| `env.ADMIN_EMAIL` | string | yes | Caller identity passed into skill processes |
| `env.API_BASE_URL` | string | yes | `"http://localhost:8000/api"` |

**Validation rules**:
- `allowFrom` MUST contain exactly one entry. Multiple entries are rejected at startup.
- `llm.endpoint` MUST be `localhost` (no remote LLMs allowed per SC-007).
- `env.API_BASE_URL` MUST start with `http://localhost:` or `http://127.0.0.1:` (per spec constraint that skills call localhost, not Tailscale).

---

## E2. CronEntry

| Field | Type | Description |
|---|---|---|
| `name` | string | Human label, e.g. `"daily_digest"` |
| `schedule` | string | Crontab expression in server local time |
| `skill` | string | Path under `skills/`, e.g. `"heartbeat/daily_digest.py"` |
| `enabled` | bool | Default `true` |

**Instances** (created at install time):

| name | schedule | skill |
|---|---|---|
| daily_digest | `0 7 * * *` | `heartbeat/daily_digest.py` |
| weekly_summary | `0 18 * * 0` | `heartbeat/weekly_summary.py` |
| push_failure_check | `0 * * * *` | `heartbeat/push_failure_check.py` |

---

## E3. Skill Manifest (`~/.openclaw/skills/<name>/SKILL.md`)

A Markdown file with frontmatter that OpenClaw parses to decide when to invoke the skill.

| Frontmatter Field | Type | Description |
|---|---|---|
| `name` | string | Unique skill name (`workorders`, `server`, `email`, `heartbeat`) |
| `description` | string | One-line summary the LLM uses to route intents |
| `entrypoint` | string | Relative path to the executable, e.g. `workorders.py` |
| `requiresConfirmation` | array<string> | List of action names that require the confirmation gate (e.g. `["close", "restart_backend"]`) |
| `triggers` | array<string> | Example natural-language phrases the LLM should associate with this skill |

**Body**: Free-form Markdown describing each command, its arguments, and example invocations. Used as in-context grounding for Gemma.

---

## E4. Skill Invocation Envelope

When OpenClaw invokes a skill, it spawns the entrypoint with stdin = JSON:

```json
{
  "caller_id": "<telegram_user_id>",
  "action": "list_open" | "get" | "close" | "count" | "send_pdf" | ...,
  "args": { /* action-specific */ },
  "confirmed": false,
  "raw_message": "show me open work orders"
}
```

The skill writes a JSON response to stdout:

```json
{
  "status": "ok" | "error" | "needs_confirmation",
  "reply": "Markdown text the bot should send to Telegram",
  "audit": {
    "action": "list_open",
    "args": {"status": "Open"},
    "outcome": "success",
    "duration_ms": 412
  }
}
```

**Validation**:
- `status="needs_confirmation"` is only valid for actions listed in the skill's `requiresConfirmation` frontmatter.
- `audit.outcome` ∈ `{success, failure, confirmation_required, confirmation_expired}`.
- Skills MUST NOT print to stdout outside the JSON envelope (it pollutes the parser). Diagnostics go to stderr.

---

## E5. Audit Log Record (`~/.openclaw/audit.log`, NDJSON)

One JSON object per line. Append-only. Per FR-025.

| Field | Type | Description |
|---|---|---|
| `ts` | string (ISO-8601 with offset) | When the command was processed |
| `caller` | string | Telegram user ID of the sender |
| `input` | string | Raw inbound message text (truncated to 500 chars) |
| `skill` | string | Routed skill name, or `null` if rejected before routing |
| `action` | string | Resolved action name, or `null` |
| `args` | object | Resolved action arguments (PII-safe — emails ARE recorded) |
| `outcome` | string | `success` \| `failure` \| `confirmation_required` \| `confirmation_expired` \| `unauthorized` |
| `error` | string\|null | Error message if `outcome=failure` |
| `duration_ms` | integer | Wall-clock time from inbound message to reply sent |

**Lifecycle**:
- File is created on first write by the OpenClaw service user (mode 0640).
- File is never truncated by OpenClaw. Manual rotation (logrotate) may be added later but is out of scope for v1.

**Indexes**: None — operator greps by `caller`, `action`, or `outcome` as needed.

---

## E6. Pending Confirmation State (in-memory)

Held by OpenClaw between turns of a conversation. Not persisted.

| Field | Type | Description |
|---|---|---|
| `chat_id` | string | Telegram chat to which the confirmation prompt was sent |
| `pending_action` | object | The full skill invocation envelope to re-run if confirmed |
| `created_at` | timestamp | Used to enforce 60 s expiry |
| `expires_at` | timestamp | `created_at + 60s` |

**Transitions**:

```text
(no pending) ──destructive command──▶ pending
pending      ──admin replies "yes" within 60 s──▶ executing → (no pending)
pending      ──60 s elapses──▶ confirmation_expired → (no pending)  [audit logged]
pending      ──any other message──▶ pending replaced or cleared per OpenClaw rules
```

---

## E7. Domain entities referenced (read-only, owned by FastAPI/Supabase)

These are NOT modified by this feature. Listed for traceability of which existing entities each skill consumes.

| Entity | Owner | Used by skill | Read fields |
|---|---|---|---|
| `work_orders` | Supabase | workorders, heartbeat | `id`, `job_no`, `title`, `status`, `created_at`, `updated_at`, `assigned_to`, `closed_at`, `closed_by` |
| `users` | Supabase | (caller identity only) | `email`, `role` |
| `notification_delivery_logs` | Supabase | heartbeat (push_failure_check) | `created_at`, `status`, `notification_id`, `error_message` |

All access is via FastAPI; no direct SQL.
