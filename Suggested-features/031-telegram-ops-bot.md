# 031 — Telegram Ops Bot (Python, no AI framework)

## Summary
A lightweight Python Telegram bot that lets the admin query and manage work orders via Telegram chat, without any AI framework dependency.

## Background
Feature 028 attempted this using OpenClaw + local Ollama LLM. It was dropped because 7B models on the server GPU (GTX 1080, 8GB VRAM) don't emit structured tool calls — they write tool-call JSON as markdown text, which OpenClaw cannot execute. The shell scripts built for 028 are functional and ready to reuse.

## Approach
Plain Python bot using `python-telegram-bot` library:
- Long-polling loop (no webhook needed)
- Regex/keyword matching maps user messages to shell scripts
- Scripts call the FastAPI backend at `localhost:8000`
- Results sent back as formatted Telegram messages
- Admin-only allowlist (TG user ID `178510554`)
- Runs as a systemd user service

## Reusable Assets from 028
All scripts at `~/.openclaw/skills/workorders/scripts/` are production-ready:
- `list_by_status.sh <status>` — list Open / Pending / Closed WOs
- `list_overdue.sh` — WOs not updated in 48h+
- `count.sh <status>` — count by status
- `get.sh <job_no>` — full details for one WO
- `close.sh <job_no> [reason]` — close a WO (with confirmation step)
- `summary_closed.sh <start> <end>` — closed WOs in date range
- `lib.sh` — shared helpers (audit log, API calls, formatting)

## Command Map
| User says | Script called |
|---|---|
| `pending` / `show pending` | `list_by_status.sh Pending` |
| `open` / `show open` | `list_by_status.sh Open` |
| `overdue` | `list_overdue.sh` |
| `count open` | `count.sh Open` |
| `get WO260406-142808` | `get.sh WO260406-142808` |
| `close WO260406-142808` | `close.sh WO260406-142808` (asks confirm) |
| `summary this week` | `summary_closed.sh <monday> <today>` |
| `help` | static help text |

## Scheduled Digests (optional)
Use APScheduler inside the bot process:
- 07:00 daily — open + pending count
- Sunday 18:00 — weekly closed summary
- Hourly — check for overdue WOs, alert if any new ones

## Estimated Size
~120 lines Python + systemd unit file. No new backend endpoints needed.

## Dependencies
- `python-telegram-bot>=20.0` (async)
- `APScheduler>=3.10` (for digests)
- Bot token: already configured (reuse from 028)
