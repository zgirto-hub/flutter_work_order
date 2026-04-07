# Implementation Plan: OpenClaw Telegram Ops Assistant

**Branch**: `028-openclaw-telegram-ops` | **Date**: 2026-04-07 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/028-openclaw-telegram-ops/spec.md`

## Summary

Install the OpenClaw AI agent runtime on the existing Zorin OS server, wire it to the local Ollama/Gemma model, and expose it to the admin via a private Telegram bot. OpenClaw will load four skills (workorders, server, email, heartbeat) that wrap the existing FastAPI backend over `localhost:8000`. No existing backend or frontend code is modified — this feature is purely additive and lives entirely under `~/.openclaw/` plus a single systemd unit. Scheduled jobs (daily 7 AM digest, Sunday 6 PM weekly summary, hourly push-failure check) are configured as OpenClaw cron skills.

## Technical Context

**Language/Version**:
- Python 3 (skill scripts: `workorders.py`, `email.py`, `heartbeat.py`) — same interpreter the existing backend uses
- Bash (skill script: `server.sh`, installer)
- Node.js 20+ (OpenClaw runtime)

**Primary Dependencies**:
- OpenClaw (from github.com/openclaw/openclaw) — the agent runtime, Telegram I/O, skill loader, cron scheduler
- Ollama (already running on `localhost:11434`, model `gemma4` or whichever is loaded)
- Python `requests` (stdlib `urllib` is acceptable to avoid new pip installs) for HTTP calls to FastAPI
- `systemctl`, `df`, `journalctl` (read-only) for the server skill

**Storage**:
- N/A for application data — all WO state continues to live in Supabase, accessed only via FastAPI
- Append-only audit log file: `~/.openclaw/audit.log` (per FR-025)
- OpenClaw config: `~/.openclaw/openclaw.json`
- Skills tree: `~/.openclaw/skills/{workorders,server,email,heartbeat}/`

**Testing**:
- Manual end-to-end tests via real Telegram messages from the admin account, scripted in `quickstart.md`
- Negative test: send a message from a non-admin account and verify silence
- Synthetic skill invocation: each skill script runnable directly from CLI for smoke testing without going through Telegram/LLM

**Target Platform**: Zorin OS (Ubuntu-based Linux) server, accessible only over Tailscale (`zorin.taila92fe8.ts.net`); never exposed publicly.

**Project Type**: Server-side ops add-on. No changes to the Flutter frontend or FastAPI backend codebase. New artifacts live in two places:
1. The application repo (`specs/028-openclaw-telegram-ops/`) — spec, plan, skill source-of-truth files for review/version control
2. The server filesystem (`~/.openclaw/`, `/etc/systemd/system/openclaw.service`) — runtime install

**Performance Goals**:
- < 5 s end-to-end response for natural-language work-order queries (mostly bounded by Gemma inference + one HTTP round-trip to localhost FastAPI)
- < 2 minutes from cold reboot to first usable response (SC-001)

**Constraints**:
- Hard constraint: zero changes to existing FastAPI routes or Flutter code (FR-024)
- Hard constraint: no public-internet exposure — Tailscale only (FR-002)
- Hard constraint: no third-party AI calls — local Ollama only (FR-006, SC-007)
- Hard constraint: skill scripts MUST call `http://localhost:8000/api/...` (not the Tailscale URL)
- Confirmation window for destructive actions: 60 s (FR-004)
- Single authorized Telegram user ID (FR-001); all others ignored

**Scale/Scope**: 1 admin user, ~hundreds of work orders per month, ~5–20 admin/bot interactions per day, ~25 scheduled job firings per day (24 hourly heartbeats + 1 digest, plus 1 weekly).

## Constitution Check

The Work Order System Constitution (v1.0.0) governs the main flutter_work_order codebase. This feature is an **additive, out-of-band ops tool** that does not touch the application stack. Principle-by-principle review:

| Principle | Applicability | Status |
|---|---|---|
| I. Full-Stack Ownership | Does not apply — feature explicitly does not span backend router / migration / Flutter screens (FR-024 forbids it). The feature lives in `~/.openclaw/` on the server. | ✅ Documented exclusion |
| II. Explicit Over Automatic | Honored. Destructive actions require explicit confirmation (FR-004); confirmation has explicit 60 s expiry; scheduled-job missed-runs are explicitly skipped (Assumptions). No silent fallbacks. | ✅ Pass |
| III. Role-Based Access Control | Honored. Single hardcoded admin Telegram user ID; all other senders ignored (FR-001). Skills call FastAPI as the admin email, so existing backend RBAC still gates every action. | ✅ Pass |
| IV. Server-First File Storage | N/A — feature does not handle file uploads. The email skill emails existing PDFs already produced by the backend. | ✅ N/A |
| V. Client-Side Computation | N/A — no client; the assistant fetches authoritative data from FastAPI per request. | ✅ N/A |
| VI. Audit Everything | Honored and extended. FR-025 mandates an append-only local audit log of every admin command, action, and outcome. Additionally, all WO state changes still flow through FastAPI and therefore continue to land in `user_activity_log` and `work_order_status_logs`. | ✅ Pass |
| VII. Simplicity & YAGNI | Honored. Skill scripts use stdlib HTTP, no ORM, no abstractions; one file per skill; cron is provided by OpenClaw rather than introducing a new scheduler; no new database tables; no new backend endpoints. | ✅ Pass |

**Initial gate**: PASS — no violations to justify in Complexity Tracking.

**Note on Principle I exclusion**: Principle I targets product features that ship to end-users via the WO app. This feature ships an external ops bot for a single internal admin and is *forbidden* from touching the app stack by FR-024. Documenting the exclusion here per the principle's own escape clause.

## Project Structure

### Documentation (this feature)

```text
specs/028-openclaw-telegram-ops/
├── plan.md                    # This file (/speckit.plan output)
├── spec.md                    # Feature spec
├── research.md                # Phase 0 output
├── data-model.md              # Phase 1 output (skill / config schemas)
├── quickstart.md              # Phase 1 output (install + smoke test)
├── contracts/
│   ├── skill-interface.md     # Contract: how OpenClaw invokes a skill
│   ├── workorders-skill.md    # Contract: workorders skill commands
│   ├── server-skill.md        # Contract: server skill commands
│   ├── email-skill.md         # Contract: email skill commands
│   └── heartbeat-skill.md     # Contract: heartbeat cron jobs
├── checklists/
│   └── requirements.md
└── tasks.md                   # Phase 2 output (/speckit.tasks)
```

### Source Code (server-side install layout)

This feature does not add code to the Flutter or FastAPI source trees. Source-of-truth versions of all server artifacts live under `specs/028-openclaw-telegram-ops/server/` in this repo and are deployed to the server by the install script.

```text
specs/028-openclaw-telegram-ops/server/
├── install_openclaw.sh                      # Phase 1 deliverable
├── openclaw.service                         # systemd unit (Phase 1)
├── openclaw.json.template                   # config template with placeholders
└── skills/
    ├── workorders/
    │   ├── SKILL.md
    │   └── workorders.py
    ├── server/
    │   ├── SKILL.md
    │   └── server.sh
    ├── email/
    │   ├── SKILL.md
    │   └── email.py
    └── heartbeat/
        ├── SKILL.md
        ├── daily_digest.py
        ├── weekly_summary.py
        └── push_failure_check.py
```

On the server, the deployed layout is:

```text
/etc/systemd/system/openclaw.service        # copied from openclaw.service
~/.openclaw/openclaw.json                   # rendered from openclaw.json.template
~/.openclaw/audit.log                       # append-only audit log (FR-025)
~/.openclaw/skills/                         # mirrored from specs/.../server/skills/
```

**Structure Decision**: Out-of-tree server install. The `flutter_work_order` repo does not gain a new top-level directory; instead all server-side artifacts live under `specs/028-openclaw-telegram-ops/server/` so they are version-controlled with the spec that defines them. The install script reads from this directory and copies into the home directory of the service user on the Zorin server. This keeps Principle VII (simplicity) intact and matches the existing pattern of `scripts/` for deploy automation without polluting `backend/` or `frontend/`.

## Complexity Tracking

No constitutional violations require justification.
