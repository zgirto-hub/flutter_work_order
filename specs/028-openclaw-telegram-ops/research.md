# Phase 0 Research: OpenClaw Telegram Ops Assistant

**Feature**: 028-openclaw-telegram-ops
**Date**: 2026-04-07

This document resolves all open technical questions surfaced when filling in the Technical Context. There are no remaining `NEEDS CLARIFICATION` markers.

---

## R1. Skill scripting language

**Decision**: Python 3 for `workorders`, `email`, and `heartbeat` skills; Bash for `server` skill.

**Rationale**:
- Python is already on the server (the FastAPI backend runs on it), so no new runtime install.
- Stdlib `urllib.request` + `json` is sufficient to call `localhost:8000/api/...` — no new pip dependencies needed.
- The `server` skill mostly invokes shell utilities (`systemctl is-active`, `df -h`, `journalctl -n 20`), where Bash is the most direct fit and avoids subprocess plumbing.

**Alternatives considered**:
- All Python: rejected for `server` skill — would wrap shell calls in `subprocess.run` for no benefit.
- Node.js: rejected — OpenClaw runs on Node, but the skill author surface is more familiar in Python and we would have to redo HTTP and time formatting in JS.
- Direct Supabase queries from skills: rejected — violates FR-003 ("Direct database access prohibited") and Constitution Principle III.

---

## R2. HTTP client

**Decision**: Stdlib `urllib.request` (Python) and `curl` (Bash).

**Rationale**: Avoids `pip install requests` on the server, keeps the install script idempotent and dependency-free. The endpoints we hit are simple JSON GET/PUT/POST against localhost — no auth headers, no streaming.

**Alternatives**: `requests` is more ergonomic but introduces a pip dependency for marginal value at this scale (≤6 endpoints).

---

## R3. Caller identity for FastAPI calls

**Decision**: Hardcode the admin email at install time into a single config file (`~/.openclaw/skills/workorders/.env` or pulled from `openclaw.json` env block) and pass it as the `email` query parameter to endpoints that take it (e.g., `GET /api/work-orders?email=<admin>&user_role=admin`).

**Rationale**: The existing API uses email + role as the caller identity (per ARCHITECTURE.md). Hardcoding once at install time mirrors how a service account would work. Per FR-001 only the admin Telegram ID can issue commands, so impersonation risk is contained.

**Alternatives**: Read admin email from a Supabase users-table lookup at startup. Rejected — extra dependency, no benefit for a single admin.

---

## R4. Telegram bot library / wiring

**Decision**: Use OpenClaw's built-in Telegram I/O channel; supply only the bot token and the allowed Telegram user ID via `openclaw.json`. No custom Telegram code.

**Rationale**: OpenClaw already ships with a Telegram channel adapter; reinventing it violates Principle VII.

**Alternatives**: Custom `python-telegram-bot` script. Rejected — duplicates work, complicates the systemd service.

---

## R5. Authorization enforcement

**Decision**: Two-layer check.
1. **Channel-layer**: `openclaw.json` `allowFrom` field whitelists exactly one Telegram user ID. OpenClaw drops messages from any other sender at the channel boundary.
2. **Skill-layer**: Each skill script ALSO verifies that the env var `OPENCLAW_CALLER_ID` matches the configured admin ID before executing, providing defense-in-depth in case OpenClaw config is misconfigured.

**Rationale**: Defense in depth aligns with Constitution Principle III's "defense-in-depth" stance on RLS. Channel-layer alone is sufficient functionally; skill-layer guarantees that even if a future skill is invoked outside the Telegram channel, it still refuses unknown callers.

**Alternatives**: Channel-layer only. Rejected — single point of failure for a security-critical guardrail.

---

## R6. Confirmation gate for destructive actions

**Decision**: Implement the 60 s confirmation window inside the OpenClaw conversation state, not in skill scripts. The skill returns a "pending confirmation" sentinel; OpenClaw holds the pending action keyed by Telegram chat ID for 60 s and re-invokes the skill with `confirmed=true` if the admin replies affirmatively in time.

**Rationale**: Keeping the timer in the runtime layer means each skill stays stateless (Principle VII). The skill itself just looks at a `confirmed` flag.

**Alternatives**: Per-skill state file with timestamp. Rejected — duplicates timer logic across skills, harder to test.

---

## R7. Audit log format & location

**Decision**: Append-only newline-delimited JSON at `~/.openclaw/audit.log`. One record per admin command:

```json
{"ts":"2026-04-07T07:00:00+03:00","caller":"<telegram_user_id>","input":"close work order #1234","skill":"workorders","action":"close","args":{"id":1234},"outcome":"success","duration_ms":820}
```

**Rationale**:
- NDJSON is append-safe, line-oriented (greppable), and parseable without a schema migration.
- Local file matches FR-025 ("append-only local log file on the server") and avoids coupling to Supabase.
- Records `outcome` field with values `success | failure | confirmation_required | confirmation_expired` so SC-006 can be audit-verified.

**Alternatives**:
- Push to existing `user_activity_log` table — rejected: would require a new backend route or direct DB write (forbidden by FR-003/FR-024).
- Plain text log — rejected: harder to grep by field.

**Rotation**: Out of scope for v1; logrotate can be added later if file grows beyond practical limits. Expected volume: ~50 lines/day.

---

## R8. Cron / scheduled job mechanism

**Decision**: Use OpenClaw's built-in cron skill format. Define each scheduled job as a cron entry in `openclaw.json` that invokes the corresponding heartbeat skill script.

**Rationale**: Built-in feature, no external scheduler. Aligns with Principle VII.

**Cron expressions** (server local time):
- Daily digest: `0 7 * * *` → `daily_digest.py`
- Weekly summary: `0 18 * * 0` → `weekly_summary.py`
- Push-failure check: `0 * * * *` → `push_failure_check.py`

**Missed-run policy**: OpenClaw cron does NOT replay missed runs; the next scheduled instant fires normally. This matches the spec assumption.

**Alternatives**: System `cron` calling skill scripts directly via `openclaw run`. Rejected — bypasses OpenClaw's audit and Telegram-output integration.

---

## R9. "Overdue" definition & query strategy

**Decision**: A work order is overdue iff its `status` is `Open` or `Pending` AND its most recent status change is more than 48 hours old (per the spec clarification). The `workorders.py` skill computes this client-side after fetching `GET /api/work-orders?status=Open` and `?status=Pending` — no new backend endpoint.

**Rationale**: The existing API exposes `created_at` / `updated_at`; computing the threshold in the skill avoids touching backend code (FR-024). At ≤ a few hundred WOs, the in-process filter is trivially fast.

**Alternatives**: Add a backend `?overdue=true` flag. Rejected — violates FR-024.

---

## R10. Push-failure check data source

**Decision**: The hourly heartbeat queries an existing FastAPI endpoint that returns recent `notification_delivery_logs` rows with `status='failed'` from the last hour. If no such endpoint exists today, fall back to the existing `GET /api/notifications?email=<admin>&unread_only=true` endpoint and look for delivery-failure markers there.

**Rationale**: The user input mentions `notification_delivery_logs` directly. Per FR-003 we must NOT touch the database directly, so this depends on a FastAPI route exposing the table. If the route is missing, FR-023 (which is SHOULD, not MUST) gracefully degrades to "no fallback alerting" rather than blocking the rest of the feature.

**Open item for `/speckit.tasks`**: First task in the heartbeat skill must verify that an endpoint exposing `notification_delivery_logs` exists. If not, FR-023 is implemented as a no-op stub and a TODO is logged in the audit file. This avoids violating FR-024.

**Alternatives**: Direct Supabase read with anon key. Rejected — violates FR-003.

---

## R11. Install / deployment mechanism

**Decision**: Single idempotent Bash install script `install_openclaw.sh` that:
1. Verifies Node.js ≥ 20 is present (installs via NodeSource if not)
2. `npm i -g openclaw` (or clones the repo if no npm package)
3. Creates `~/.openclaw/` and copies the contents of `specs/028-openclaw-telegram-ops/server/skills/` into `~/.openclaw/skills/`
4. Renders `openclaw.json` from the template, prompting for `TELEGRAM_BOT_TOKEN`, `ADMIN_TELEGRAM_USER_ID`, and `ADMIN_EMAIL` if not already set as env vars
5. Copies `openclaw.service` to `/etc/systemd/system/`
6. Runs `systemctl daemon-reload && systemctl enable --now openclaw`
7. Tails the journal for 10 s to confirm a clean start

**Rationale**: Idempotent + interactive prompts mean the operator can re-run the script after edits without manual cleanup. Matches the existing `scripts/deploy_frontend.sh` pattern.

**Alternatives**: Ansible playbook. Rejected — overkill for a one-host deployment, introduces new tooling.

---

## R12. Restart-on-boot guarantee (SC-001)

**Decision**: systemd unit with:
- `Restart=always`
- `RestartSec=5`
- `WantedBy=multi-user.target`
- `After=network-online.target ollama.service` (so Ollama is up before OpenClaw tries to connect)

**Rationale**: 5 s restart delay × ≤3 retries puts the assistant well under the 2-minute SC-001 budget on a cold boot.

---

## R13. Server skill safety boundary

**Decision**: Read-only commands (`status`, `disk`, `errors`) execute immediately. The single destructive command (`restart fastapi`) goes through the OpenClaw confirmation gate (R6) and uses a pre-defined `sudo systemctl restart` command via a sudoers rule that allows only that exact command without password for the OpenClaw service user. No other shell commands are exposed.

**Rationale**: Limits blast radius. The sudoers rule must be added during install (manual step in quickstart, since editing sudoers programmatically is risky).

**Alternatives**: Run OpenClaw as root. Rejected — violates least privilege.

---

## Summary

All Technical Context items are resolved. No `NEEDS CLARIFICATION` markers remain. Phase 1 may proceed.
