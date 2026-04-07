# Tasks: OpenClaw Telegram Ops Assistant

**Feature**: 028-openclaw-telegram-ops
**Branch**: `028-openclaw-telegram-ops`
**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

All source-of-truth artifacts live under `specs/028-openclaw-telegram-ops/server/`. Deployment to the server is done via the install script (T003). No Flutter / FastAPI code is touched.

---

## Phase 1 — Setup

- [X] T001 Create the server artifact directory tree at `specs/028-openclaw-telegram-ops/server/` with subfolders `skills/workorders`, `skills/server`, `skills/email`, `skills/heartbeat` and empty `.gitkeep` files in each.

- [X] T002 [P] Create `specs/028-openclaw-telegram-ops/server/openclaw.json.template` — JSON config template per data-model.md E1 with placeholders `__TELEGRAM_BOT_TOKEN__`, `__ADMIN_TELEGRAM_USER_ID__`, `__ADMIN_EMAIL__`, `__OLLAMA_MODEL__`. Includes `llm` block pointing to `http://localhost:11434`, `channels.telegram` with the placeholder `allowFrom` singleton, `skills.directory`, `skills.cron` with the three cron entries (daily_digest `0 7 * * *`, weekly_summary `0 18 * * 0`, push_failure_check `0 * * * *`), `audit.logPath` set to `~/.openclaw/audit.log`, `confirmation.windowSeconds=60`, `env.ADMIN_EMAIL`, `env.API_BASE_URL=http://localhost:8000/api`.

- [X] T003 Create `specs/028-openclaw-telegram-ops/server/install_openclaw.sh` per research.md R11: verify Node 20+, install OpenClaw globally, create `~/.openclaw/`, copy `skills/` tree, render `openclaw.json` from template using the four env vars, copy `openclaw.service` to `/etc/systemd/system/`, `daemon-reload`, `enable --now openclaw`, tail journal 10 s. Must be idempotent and fail loudly if any required env var is unset. Depends on: T001, T002, T004.

- [X] T004 [P] Create `specs/028-openclaw-telegram-ops/server/openclaw.service` systemd unit per research.md R12: `Restart=always`, `RestartSec=5`, `After=network-online.target ollama.service`, `WantedBy=multi-user.target`, `ExecStart=/usr/bin/openclaw run`, running as a non-root user (placeholder `User=openclaw`).

## Phase 2 — Foundational (blocks all skills)

- [X] T005 Create `specs/028-openclaw-telegram-ops/server/skills/_lib/wo_api.py` — shared Python helper module (stdlib only) exposing `get_admin_email() -> str`, `get_api_base() -> str`, `api_get(path: str, params: dict | None = None) -> dict | list`, `api_post(path: str, body: dict) -> dict`, `api_put(path: str, body: dict) -> dict`, `iso_now() -> str`, `parse_iso(ts: str) -> datetime`. Reads `ADMIN_EMAIL` and `API_BASE_URL` env vars; raises `RuntimeError` if missing. Enforces that `API_BASE_URL` starts with `http://localhost:` or `http://127.0.0.1:` per plan.md constraints.

- [X] T006 [P] Create `specs/028-openclaw-telegram-ops/server/skills/_lib/envelope.py` — shared I/O helper: `read_envelope() -> dict` (reads JSON from stdin, returns the envelope), `write_reply(status: str, reply: str, action: str, args: dict, outcome: str, started_at: float, error: str | None = None) -> None` (writes single-line JSON to stdout per contracts/skill-interface.md). Exits 0 always (logical errors go in envelope). Writes diagnostics to stderr.

- [X] T007 [P] Create `specs/028-openclaw-telegram-ops/server/skills/_lib/authz.py` — `assert_authorized() -> None` that reads `OPENCLAW_CALLER_ID` env var and raises `PermissionError` if empty. Second-layer defense per research.md R5.

## Phase 3 — User Story 1: Work Orders Skill (P1) 🎯 MVP

**Goal**: Admin can query and manipulate work orders from Telegram.
**Independent test**: `quickstart.md` Tests 1–4.

- [X] T008 [US1] Create `specs/028-openclaw-telegram-ops/server/skills/workorders/SKILL.md` with frontmatter (`name: workorders`, `entrypoint: workorders.py`, `requiresConfirmation: ["close", "update_status"]`, trigger phrases) and Markdown body describing every action in `contracts/workorders-skill.md`. Depends on: T001.

- [X] T009 [US1] Create `specs/028-openclaw-telegram-ops/server/skills/workorders/workorders.py` implementing all 7 actions (`list_open`, `list_pending`, `list_overdue`, `count`, `get`, `close`, `update_status`, `summary_closed_in_range`) per `contracts/workorders-skill.md`. Uses `_lib/wo_api.py` and `_lib/envelope.py`. Overdue computed locally (updated_at > 48h). Destructive actions return `needs_confirmation` when `confirmed=false`. Depends on: T005, T006, T007, T008.

**Checkpoint US1**: Install to server, run quickstart Tests 1–4. MVP deliverable.

## Phase 4 — User Story 3: Server Management Skill (P2)

**Goal**: Admin can check server health and restart the backend from Telegram.
**Independent test**: `quickstart.md` Tests 5, 6.

- [X] T010 [P] [US3] Create `specs/028-openclaw-telegram-ops/server/skills/server/SKILL.md` with frontmatter and body describing the 4 actions (`status`, `disk`, `errors`, `restart_backend`) per `contracts/server-skill.md`. Depends on: T001.

- [X] T011 [US3] Create `specs/028-openclaw-telegram-ops/server/skills/server/server.sh` implementing the 4 actions. Reads JSON envelope from stdin using `jq`, whitelists the action name (no eval), emits single-line JSON reply to stdout. `restart_backend` obeys `$OPENCLAW_CONFIRMED` env var and calls `sudo /bin/systemctl restart fastapi`. Depends on: T010.

## Phase 5 — User Story 2: Daily Digest + Weekly Summary (P2)

**Goal**: Automated scheduled Telegram messages.
**Independent test**: `quickstart.md` Test 8.

- [X] T012 [P] [US2] Create `specs/028-openclaw-telegram-ops/server/skills/heartbeat/SKILL.md` with frontmatter `name: heartbeat`, cron-only note, and body per `contracts/heartbeat-skill.md`. Depends on: T001.

- [X] T013 [US2] Create `specs/028-openclaw-telegram-ops/server/skills/heartbeat/daily_digest.py` — fetches open + pending via `_lib/wo_api`, computes 48h overdue + stale lists, emits envelope with Markdown per contract. Depends on: T005, T006, T012.

- [X] T014 [P] [US2] Create `specs/028-openclaw-telegram-ops/server/skills/heartbeat/weekly_summary.py` — calls `/reports/closed-work-orders` for last 7 days plus open/pending counts, emits Markdown summary per contract. Depends on: T005, T006, T012.

## Phase 6 — User Story 4: Email Skill (P3)

**Goal**: Admin can email work order PDFs and summaries from Telegram.
**Independent test**: `quickstart.md` Test 7.

- [X] T015 [P] [US4] Create `specs/028-openclaw-telegram-ops/server/skills/email/SKILL.md` per `contracts/email-skill.md`. Depends on: T001.

- [X] T016 [US4] Create `specs/028-openclaw-telegram-ops/server/skills/email/email.py` — actions `send_work_order_pdf`, `send_weekly_summary`. Validates `to` with a basic email regex. Calls the (parallel-feature) email endpoint; on HTTP 404/501 returns `status=error` with reply `Email backend not available yet.` Depends on: T005, T006, T015.

## Phase 7 — User Story 5: Push Failure Fallback (P3)

**Goal**: Hourly check for failed push deliveries, alert admin on failure.
**Independent test**: Simulate a failed push and verify Telegram alert within the next hourly window.

- [X] T017 [US5] Create `specs/028-openclaw-telegram-ops/server/skills/heartbeat/push_failure_check.py` — per research.md R10, attempts `GET /notifications/delivery-failures?since=<1h ago>`. On 404/501 (endpoint not yet present) exits 0 silently after logging one stderr warning per run. On success: if failures > 0, emits envelope with Telegram message; else exits silently (no message). Depends on: T005, T006, T012.

## Phase 8 — Polish & Cross-Cutting

- [X] T018 Update `specs/028-openclaw-telegram-ops/checklists/requirements.md` post-implementation validation notes if any deviations were made.

- [ ] T019 Run full `quickstart.md` smoke test suite (Tests 1–10) on the server and record outcomes in a new `specs/028-openclaw-telegram-ops/test-results-$(date).md`. Verifies SC-001 through SC-008.

- [X] T020 [P] Add a brief entry under "Recent Changes" in `CLAUDE.md` noting feature 028 shipped as an out-of-tree server ops tool.

---

## Dependencies

```
Setup:  T001 → T002,T004 → T003
Foundational: T005,T006,T007 (block all skill phases)
US1 (P1 MVP): T008 → T009 [depends T005/T006/T007]
US3 (P2):     T010 → T011
US2 (P2):     T012 → T013, T014 [depends T005/T006]
US4 (P3):     T015 → T016 [depends T005/T006]
US5 (P3):     T017 [depends T005/T006/T012]
Polish:       T018, T019, T020
```

User stories US1, US3, US2, US4, US5 are independent after Phase 2 and can proceed in parallel by different developers.

## Parallel execution examples

- After T007: T009 (US1), T011 (US3 needs T010 first), T013+T014 (US2 after T012), T016 (US4 after T015), T017 (US5 after T012) can all be developed simultaneously.
- T002 and T004 in Phase 1 are parallelizable.
- T010, T012, T015 are parallelizable (independent SKILL.md files).

## MVP scope

**US1 only** (T001–T009). Deploy to server, run quickstart Tests 1–4. Delivers the primary value: natural-language work order queries and controlled destructive actions via Telegram.

---

## Implementation Prompts

--- IMPLEMENTATION PROMPT T001 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Bash (shell commands only)
File: Multiple empty directories + `.gitkeep` files under `specs/028-openclaw-telegram-ops/server/`
Task: Create the directory tree `specs/028-openclaw-telegram-ops/server/` with subdirectories `skills/workorders/`, `skills/server/`, `skills/email/`, `skills/heartbeat/`, and `skills/_lib/`. Place an empty `.gitkeep` file in each leaf directory so git tracks them.
Signatures required: none
Constraints: Use only `mkdir -p` and `touch`. Do not create any other files. Do not overwrite existing files.
Acceptance criteria: `ls specs/028-openclaw-telegram-ops/server/skills/` lists exactly 5 directories; each contains a `.gitkeep` file.
--- END PROMPT T001 ---

--- IMPLEMENTATION PROMPT T002 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: JSON
File: specs/028-openclaw-telegram-ops/server/openclaw.json.template
Task: Create the OpenClaw configuration template. Structure must match data-model.md E1. Use the literal placeholder strings `__TELEGRAM_BOT_TOKEN__`, `__ADMIN_TELEGRAM_USER_ID__`, `__ADMIN_EMAIL__`, `__OLLAMA_MODEL__` which the install script will substitute via sed. Include `llm` (provider=ollama, endpoint=http://localhost:11434, model=__OLLAMA_MODEL__), `channels.telegram` (enabled=true, botToken=__TELEGRAM_BOT_TOKEN__, allowFrom=["__ADMIN_TELEGRAM_USER_ID__"]), `skills.directory="~/.openclaw/skills"`, `skills.cron` array with exactly three entries (daily_digest `0 7 * * *` → `heartbeat/daily_digest.py`, weekly_summary `0 18 * * 0` → `heartbeat/weekly_summary.py`, push_failure_check `0 * * * *` → `heartbeat/push_failure_check.py`, all enabled=true), `audit.logPath="~/.openclaw/audit.log"`, `confirmation.windowSeconds=60`, `env.ADMIN_EMAIL=__ADMIN_EMAIL__`, `env.API_BASE_URL="http://localhost:8000/api"`.
Signatures required: none (data file)
Constraints: Valid JSON (will be parsed after placeholder substitution). 2-space indentation. No comments.
Acceptance criteria: `jq . openclaw.json.template` succeeds after replacing the four placeholders with sample values. Structure matches data-model.md E1 and E2 exactly.
--- END PROMPT T002 ---

--- IMPLEMENTATION PROMPT T003 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Bash
File: specs/028-openclaw-telegram-ops/server/install_openclaw.sh
Task: Write an idempotent Bash installer. Steps: (1) `set -euo pipefail`; (2) verify env vars `TELEGRAM_BOT_TOKEN`, `ADMIN_TELEGRAM_USER_ID`, `ADMIN_EMAIL`, `OLLAMA_MODEL` are all set (exit 1 with clear message if any missing); (3) verify Node.js >=20 (install via NodeSource setup_20.x if missing); (4) `npm install -g openclaw` (skip if already installed, checked via `command -v openclaw`); (5) `mkdir -p ~/.openclaw/skills`; (6) `cp -r "$(dirname "$0")/skills/"* ~/.openclaw/skills/`; (7) render openclaw.json from template via `sed` replacing the four placeholders, write to `~/.openclaw/openclaw.json` with mode 0600; (8) `touch ~/.openclaw/audit.log && chmod 0640 ~/.openclaw/audit.log`; (9) `sudo cp "$(dirname "$0")/openclaw.service" /etc/systemd/system/openclaw.service`; (10) `sudo systemctl daemon-reload && sudo systemctl enable --now openclaw`; (11) `sudo journalctl -u openclaw -n 50 --no-pager` and tail for 10 seconds; (12) print green "OpenClaw installed and running." on success.
Signatures required: Bash functions `require_env()`, `install_node_if_needed()`, `install_openclaw_if_needed()`, `render_config()`, `install_systemd_unit()`, `main()`.
Constraints: Bash only. Idempotent — safe to re-run. Fail loudly and early. Do not hardcode user home — use `$HOME`. Use `sed -e "s|__PLACEHOLDER__|$VAL|g"` (pipe delimiter because values may contain colons). Quote all variables.
Acceptance criteria: Running with the 4 env vars set on a fresh Zorin VM produces a running `openclaw` systemd unit and a valid `~/.openclaw/openclaw.json`. Re-running is a no-op and does not error. Running without env vars exits 1 before making any changes.
--- END PROMPT T003 ---

--- IMPLEMENTATION PROMPT T004 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: systemd unit file (INI)
File: specs/028-openclaw-telegram-ops/server/openclaw.service
Task: Create a systemd service unit for OpenClaw. [Unit]: Description="OpenClaw Telegram Ops Assistant for Work Order System", After=network-online.target ollama.service, Wants=network-online.target. [Service]: Type=simple, User=openclaw, Group=openclaw, WorkingDirectory=/home/openclaw, Environment="HOME=/home/openclaw", ExecStart=/usr/bin/openclaw run --config /home/openclaw/.openclaw/openclaw.json, Restart=always, RestartSec=5, StandardOutput=journal, StandardError=journal. [Install]: WantedBy=multi-user.target.
Signatures required: none
Constraints: Plain INI format. Do not quote values that aren't environment variables. Use absolute paths.
Acceptance criteria: `systemd-analyze verify openclaw.service` passes. After install, `systemctl is-active openclaw` returns `active`.
--- END PROMPT T004 ---

--- IMPLEMENTATION PROMPT T005 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: specs/028-openclaw-telegram-ops/server/skills/_lib/wo_api.py
Task: Create a shared HTTP helper module for skill scripts. Uses only Python stdlib (`os`, `json`, `urllib.request`, `urllib.parse`, `datetime`). Reads `ADMIN_EMAIL` and `API_BASE_URL` from env at call time. Raises `RuntimeError` with a clear message if either is unset. Enforces that `API_BASE_URL` starts with `http://localhost:` or `http://127.0.0.1:` (raise RuntimeError otherwise). Provides `api_get/post/put` that send JSON, set `Content-Type: application/json`, 10 s timeout, raise `urllib.error.HTTPError` on non-2xx, return parsed JSON response.
Signatures required:
  - `def get_admin_email() -> str:`
  - `def get_api_base() -> str:`
  - `def api_get(path: str, params: dict | None = None) -> dict | list:`
  - `def api_post(path: str, body: dict) -> dict:`
  - `def api_put(path: str, body: dict) -> dict:`
  - `def iso_now() -> str:`  # returns ISO-8601 with local offset
  - `def parse_iso(ts: str) -> "datetime":`
Constraints: stdlib only — no `requests`, no `httpx`. Do not catch HTTPError internally; let callers handle. `path` is relative to `API_BASE_URL` and may or may not start with `/`. `params` dict values must be URL-encoded via `urllib.parse.urlencode`. Use `datetime.datetime.now().astimezone()` for `iso_now`. Use `datetime.datetime.fromisoformat` for `parse_iso` (handle trailing `Z` by replacing with `+00:00`).
Acceptance criteria: `python3 -c "from wo_api import get_api_base; print(get_api_base())"` with `API_BASE_URL=http://localhost:8000/api` prints that URL. With a non-localhost URL it raises RuntimeError. `api_get("/health")` returns parsed JSON against a running backend. `parse_iso("2026-04-07T07:00:00Z")` returns a timezone-aware datetime.
--- END PROMPT T005 ---

--- IMPLEMENTATION PROMPT T006 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: specs/028-openclaw-telegram-ops/server/skills/_lib/envelope.py
Task: Shared stdin/stdout envelope helpers per contracts/skill-interface.md. `read_envelope()` reads a single JSON document from stdin and returns it as a dict. `write_reply()` prints exactly one JSON object on stdout (no trailing characters). Must include an `audit` sub-object with `action`, `args`, `outcome`, `duration_ms`, and optional `error`. `duration_ms` computed from `started_at` (float, from `time.monotonic()`) to now. Always exits the process 0 after writing reply (caller may still `sys.exit(0)` explicitly).
Signatures required:
  - `def read_envelope() -> dict:`
  - `def write_reply(status: str, reply: str, action: str, args: dict, outcome: str, started_at: float, error: str | None = None) -> None:`
  - `def log_stderr(msg: str) -> None:`  # convenience
Constraints: stdlib only (`sys`, `json`, `time`). `status` must be one of `"ok" | "error" | "needs_confirmation"` — assert this. `outcome` must be one of `"success" | "failure" | "confirmation_required" | "confirmation_expired" | "unauthorized"` — assert. Print a single line with `json.dumps(..., separators=(",",":"))` followed by `\n`, flush stdout.
Acceptance criteria: `echo '{"action":"x"}' | python3 -c "from envelope import read_envelope; print(read_envelope())"` prints `{'action': 'x'}`. Calling `write_reply(status="ok", reply="hi", action="ping", args={}, outcome="success", started_at=time.monotonic())` prints a one-line valid JSON object with all required fields and a positive `duration_ms`.
--- END PROMPT T006 ---

--- IMPLEMENTATION PROMPT T007 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: specs/028-openclaw-telegram-ops/server/skills/_lib/authz.py
Task: Second-layer authorization guard per research.md R5. Reads `OPENCLAW_CALLER_ID` env var. Raises `PermissionError("unauthorized caller")` if empty or missing. On success returns the caller ID as a string.
Signatures required:
  - `def assert_authorized() -> str:`
Constraints: stdlib only (`os`). No logging, no writes. Simple and fast.
Acceptance criteria: With `OPENCLAW_CALLER_ID=123`, returns `"123"`. Without it, raises `PermissionError`.
--- END PROMPT T007 ---

--- IMPLEMENTATION PROMPT T008 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Markdown with YAML frontmatter
File: specs/028-openclaw-telegram-ops/server/skills/workorders/SKILL.md
Task: Create the work orders skill manifest. YAML frontmatter: `name: workorders`, `description: "Query and manage Work Orders in the WO system"`, `entrypoint: workorders.py`, `requiresConfirmation: ["close", "update_status"]`, `triggers: [...]` (12+ natural-language examples from contracts/workorders-skill.md including "show open work orders", "how many pending", "overdue", "close #1234", "show me #1234", "what did we complete this week"). Body: one section per action (list_open, list_pending, list_overdue, count, get, close, update_status, summary_closed_in_range) copied/adapted from contracts/workorders-skill.md. Each section shows arg schema and example invocations.
Signatures required: none
Constraints: Valid YAML frontmatter delimited by `---`. Markdown body. No code blocks inside frontmatter.
Acceptance criteria: YAML frontmatter parses cleanly with `python3 -c "import yaml,sys; print(yaml.safe_load(open('SKILL.md').read().split('---')[1]))"`. Body documents all 7 actions listed in contracts/workorders-skill.md.
--- END PROMPT T008 ---

--- IMPLEMENTATION PROMPT T009 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: specs/028-openclaw-telegram-ops/server/skills/workorders/workorders.py
Task: Implement the workorders skill. The file is an executable script: `#!/usr/bin/env python3`, shebang + `if __name__ == "__main__": main()`. At startup: record `started_at = time.monotonic()`, call `assert_authorized()`, call `read_envelope()`. Dispatch on `envelope["action"]` to handlers. Each handler uses helpers from `_lib/wo_api.py` and returns `(status, reply, outcome, error)`. `main` catches any exception, writes `status=error, outcome=failure, error=str(e)`.

Actions to implement (per contracts/workorders-skill.md):
  1. `list_open` — GET `/work-orders?email=X&user_role=admin&status=Open`, format up to 20 entries as Markdown bullets.
  2. `list_pending` — same with status=Pending.
  3. `list_overdue` — fetch open AND pending, filter where `(iso_now - parse_iso(updated_at)) > 48h`, format.
  4. `count` — args `{status}`, returns scalar count string.
  5. `get` — args `{job_no}` or `{id}`; if job_no provided, list and find match; then GET `/work-orders/{id}`. 404 → reply "Work order #... not found." with outcome=failure.
  6. `close` — args `{job_no, reason?}`. If `confirmed=False`, return `status=needs_confirmation`, `outcome=confirmation_required`, reply prompting confirmation. If confirmed, resolve id, POST `/work-orders/{id}/close` with body `{closed_by_email, reason}`, reply success.
  7. `update_status` — args `{job_no, new_status}`. Same confirmation gate. PUT `/work-orders/{id}` body `{status, updated_by_email}`.
  8. `summary_closed_in_range` — args `{start_date, end_date}`. GET `/reports/closed-work-orders?...`, format count + up to 20 titles.

Signatures required:
  - `def main() -> None:`
  - `def handle_list(status: str) -> tuple[str, str, str, str | None]:`
  - `def handle_list_overdue() -> tuple[str, str, str, str | None]:`
  - `def handle_count(args: dict) -> tuple[str, str, str, str | None]:`
  - `def handle_get(args: dict) -> tuple[str, str, str, str | None]:`
  - `def handle_close(args: dict, confirmed: bool) -> tuple[str, str, str, str | None]:`
  - `def handle_update_status(args: dict, confirmed: bool) -> tuple[str, str, str, str | None]:`
  - `def handle_summary(args: dict) -> tuple[str, str, str, str | None]:`
  - `def resolve_id(job_no_or_id: str | int) -> int | None:`
  - `def format_wo_list(items: list[dict], header: str) -> str:`

Constraints:
- Must import from `_lib` using `sys.path` manipulation: `sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "_lib"))`.
- Return tuple return type is `(status, reply, outcome, error)` where each str; caller passes to `write_reply`.
- Overdue threshold uses `datetime.timedelta(hours=48)`.
- Cap Markdown lists at 20 items and append `\n…and N more` if truncated.
- Emails for `closed_by_email` / `updated_by_email` come from `get_admin_email()`.
- Do not catch `PermissionError` from `assert_authorized()` — let it propagate so the process exits non-zero (OpenClaw will record unauthorized).

Acceptance criteria:
- Passing `{"action":"count","args":{"status":"Pending"},"confirmed":false,"raw_message":"how many pending","caller_id":"X"}` on stdin (with `OPENCLAW_CALLER_ID=X`, `ADMIN_EMAIL=...`, `API_BASE_URL=http://localhost:8000/api`) against a running backend prints a single-line JSON reply with `status=ok`, `outcome=success`, and `reply` matching `There are N pending work orders.`.
- Passing action `close` with `confirmed=false` returns `status=needs_confirmation` without hitting the close endpoint.
- Passing action `close` with `confirmed=true` calls the close endpoint and returns `status=ok` on 200.
- A 404 from `get` maps to reply `Work order #... not found.` and `outcome=failure`.
--- END PROMPT T009 ---

--- IMPLEMENTATION PROMPT T010 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Markdown + YAML frontmatter
File: specs/028-openclaw-telegram-ops/server/skills/server/SKILL.md
Task: Create the server management skill manifest. Frontmatter: `name: server`, `description: "Check server health and restart the FastAPI backend"`, `entrypoint: server.sh`, `requiresConfirmation: ["restart_backend"]`, triggers: ["server status", "disk usage", "last errors", "restart backend", "restart fastapi"]. Body: one section per action (status, disk, errors, restart_backend) from contracts/server-skill.md.
Signatures required: none
Constraints: Valid YAML frontmatter. No emoji in frontmatter.
Acceptance criteria: Parses as YAML; documents all 4 server actions.
--- END PROMPT T010 ---

--- IMPLEMENTATION PROMPT T011 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Bash
File: specs/028-openclaw-telegram-ops/server/skills/server/server.sh
Task: Implement the server skill. `#!/usr/bin/env bash`, `set -euo pipefail`. Read JSON envelope from stdin via `jq`: extract `.action`, `.args`, `.confirmed`. Dispatch on action with a case statement; any unknown action → emit `status=error, reply="Unknown server action.", outcome=failure`. Actions:
  - `status` → `systemctl is-active nginx`, `systemctl is-active fastapi`, `df -h /` — assemble Markdown reply.
  - `disk` → `df -h` limited to root and `/home` (or the disk containing uploads) in a Markdown code block.
  - `errors` → `.args.lines` (default 20, clamp max 100) — run `journalctl -u fastapi -p err -n $lines --no-pager`. If empty, reply `No recent errors.`
  - `restart_backend` → if `.confirmed == false`, emit `status=needs_confirmation, reply="⚠️ Restart the FastAPI backend? ... Reply \"yes\" within 60s."`, `outcome=confirmation_required`. If true, run `sudo -n /bin/systemctl restart fastapi`, then `systemctl is-active fastapi`, reply with result.
Output: single-line JSON on stdout using `jq -nc --arg ... '{status:..., reply:..., audit:{...}}'`. Use `date +%s%3N` for millisecond timings.

Signatures required: Bash functions `emit_reply()`, `action_status()`, `action_disk()`, `action_errors()`, `action_restart_backend()`, `main()`.
Constraints: Pure Bash + `jq` + `systemctl`, `df`, `journalctl`, `sudo`. No Python. No eval. No variable interpolation from user input into command strings (action name is matched against a literal case list). `restart_backend` must fail with a clean error if sudoers is not configured (do not hang).
Acceptance criteria: `echo '{"action":"status","args":{},"confirmed":false,"caller_id":"X","raw_message":""}' | bash server.sh` prints a single-line JSON with `status=ok` and Markdown `reply` listing nginx + fastapi active states. `echo '{"action":"restart_backend","args":{},"confirmed":false,...}' | bash server.sh` prints `status=needs_confirmation` and does NOT call systemctl restart.
--- END PROMPT T011 ---

--- IMPLEMENTATION PROMPT T012 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Markdown + YAML frontmatter
File: specs/028-openclaw-telegram-ops/server/skills/heartbeat/SKILL.md
Task: Create the heartbeat skill manifest. Frontmatter: `name: heartbeat`, `description: "Scheduled (cron-only) digests and health checks"`, `entrypoint: null` (cron-invoked per-script), `requiresConfirmation: []`, `triggers: []` (intentionally empty — LLM should not route here). Body: describe the three cron jobs per contracts/heartbeat-skill.md with their schedules and scripts.
Signatures required: none
Constraints: Valid YAML. An empty `triggers` array is required so the LLM router does not invoke these on user messages.
Acceptance criteria: Parses as YAML; `triggers` is empty list.
--- END PROMPT T012 ---

--- IMPLEMENTATION PROMPT T013 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: specs/028-openclaw-telegram-ops/server/skills/heartbeat/daily_digest.py
Task: Cron-invoked daily digest script. Executable (`#!/usr/bin/env python3`, `if __name__ == "__main__": main()`). No stdin envelope (cron doesn't provide one). Fetches:
  - `api_get("/work-orders", {"email": get_admin_email(), "user_role": "admin", "status": "Open"})`
  - `api_get("/work-orders", {"email": get_admin_email(), "user_role": "admin", "status": "Pending"})`
Computes counts. Overdue = items in (open ∪ pending) where `iso_now - parse_iso(updated_at) > 48h`. Stale alerts = items in open where same condition holds. Builds Markdown message per contracts/heartbeat-skill.md. Writes an envelope to stdout via `write_reply(status="ok", reply=message, action="daily_digest", args={}, outcome="success", started_at=...)` so OpenClaw can deliver it as a Telegram message.

Signatures required:
  - `def main() -> None:`
  - `def build_digest(open_wos: list[dict], pending_wos: list[dict], now_iso: str) -> str:`
  - `def filter_stale(wos: list[dict], threshold_hours: int = 48) -> list[dict]:`

Constraints: Uses `_lib/wo_api.py` and `_lib/envelope.py`. No Telegram API calls — delegate to OpenClaw via the reply envelope. On any exception, emit `status=error, outcome=failure, error=str(e)` and exit 0.
Acceptance criteria: Against a live backend with >0 open work orders, stdout is a single-line JSON with `status=ok` and `reply` containing the header `🌅 *Daily Work Order Digest — ...*` and accurate counts. If nothing is stale, the stale section is omitted. If the API is unreachable, script exits 0 with `status=error`.
--- END PROMPT T013 ---

--- IMPLEMENTATION PROMPT T014 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: specs/028-openclaw-telegram-ops/server/skills/heartbeat/weekly_summary.py
Task: Cron-invoked weekly summary (Sunday 6 PM local). Executable script. Computes `end_date = today`, `start_date = today - 7 days`. Fetches:
  - `api_get("/reports/closed-work-orders", {"start_date": ..., "end_date": ...})`
  - open + pending counts as in daily_digest
Builds Markdown output per contracts/heartbeat-skill.md weekly_summary section (closed count, open count, pending count, top closed list). Writes via `write_reply(..., action="weekly_summary", ...)`.

Signatures required:
  - `def main() -> None:`
  - `def build_weekly(closed: list[dict], open_count: int, pending_count: int, start_date: str, end_date: str) -> str:`

Constraints: Uses `_lib/wo_api.py` and `_lib/envelope.py`. stdlib only. Cap top closed list at 20 entries with `…and N more`. On exception, emit error envelope and exit 0.
Acceptance criteria: Stdout contains a single-line JSON with `status=ok` and reply containing `📅 *Weekly Summary — YYYY-MM-DD → YYYY-MM-DD*` and valid counts matching the backend.
--- END PROMPT T014 ---

--- IMPLEMENTATION PROMPT T015 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Markdown + YAML frontmatter
File: specs/028-openclaw-telegram-ops/server/skills/email/SKILL.md
Task: Create the email skill manifest per contracts/email-skill.md. Frontmatter: `name: email`, `description: "Email work order PDFs and weekly summaries to recipients"`, `entrypoint: email.py`, `requiresConfirmation: []`, `triggers: ["send work order # to <email>", "email the weekly summary", "send pdf to ..."]`. Body documents `send_work_order_pdf` and `send_weekly_summary` actions with arg schemas.
Signatures required: none
Constraints: Valid YAML frontmatter.
Acceptance criteria: Parses as YAML; documents both actions.
--- END PROMPT T015 ---

--- IMPLEMENTATION PROMPT T016 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: specs/028-openclaw-telegram-ops/server/skills/email/email.py
Task: Implement the email skill. Executable script. Reads envelope from stdin, asserts authorized, dispatches on action. Actions:
  - `send_work_order_pdf(args)`: validates `to` matches `^[^@\s]+@[^@\s]+\.[^@\s]+$`; looks up work order id from job_no (like workorders.resolve_id); POSTs to `/work-orders/{id}/email` with body `{"to":[to], "cc": args.get("cc", []), "subject": args.get("subject"), "from_email": get_admin_email()}`. On HTTP 404 from lookup, reply `Work order #... not found.`. On HTTP 404/501 from the email endpoint, reply `Email backend not available yet.` with outcome=failure (graceful degradation). On success, reply `📧 Sent work order #{job_no} PDF to {to}.` outcome=success.
  - `send_weekly_summary(args)`: `to = args.get("to") or get_admin_email()`. Fetches `/reports/closed-work-orders?start_date=<-7d>&end_date=<today>`. POSTs to the same email endpoint with a Markdown summary body. Same graceful degradation.

Signatures required:
  - `def main() -> None:`
  - `def handle_send_work_order_pdf(args: dict) -> tuple[str, str, str, str | None]:`
  - `def handle_send_weekly_summary(args: dict) -> tuple[str, str, str, str | None]:`
  - `def validate_email(addr: str) -> bool:`
  - `def resolve_id(job_no: str) -> int | None:`  # duplicate minimal helper — do NOT import from workorders.py to keep skills independent

Constraints: stdlib only. Catches `urllib.error.HTTPError` with `.code in (404, 501)` for the email endpoint and maps to the graceful reply. Any other exception → outcome=failure. `resolve_id` here is a tiny helper that calls `api_get("/work-orders", {"email": ..., "user_role": "admin"})` and filters by job_no.
Acceptance criteria: Invalid `to` → reply `Invalid email address: ...`, outcome=failure. Missing email endpoint (404/501) → reply `Email backend not available yet.`, outcome=failure, script exits 0. Valid send → reply contains `📧 Sent work order #...`.
--- END PROMPT T016 ---

--- IMPLEMENTATION PROMPT T017 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: specs/028-openclaw-telegram-ops/server/skills/heartbeat/push_failure_check.py
Task: Cron-invoked hourly push-failure check. Executable script, no stdin envelope. Attempts `api_get("/notifications/delivery-failures", {"since": (now - 1h).isoformat()})`. Three possible outcomes:
  1. HTTP 404 or 501 (endpoint not present) → log one stderr line, emit `write_reply(status="ok", reply="", action="push_failure_check", args={}, outcome="success", ...)` with empty reply (OpenClaw should not send empty replies to Telegram — see constraint), exit 0.
  2. Success, `failures == 0` → same as above (empty reply, outcome=success, no Telegram message).
  3. Success, `failures > 0` → build a Markdown message per contracts/heartbeat-skill.md push_failure_check section and emit via write_reply with the message as reply, outcome=success.
  4. Any other exception → emit error envelope, outcome=failure, exit 0.

Signatures required:
  - `def main() -> None:`
  - `def build_failure_message(failures: list[dict]) -> str:`

Constraints: Uses `_lib/wo_api.py` and `_lib/envelope.py`. When reply is empty, OpenClaw convention is to skip the Telegram post — ensure `reply == ""` is the signal. Handles `urllib.error.HTTPError` with `.code in (404, 501)` explicitly.
Acceptance criteria: With a missing endpoint, exits 0 and stderr has one warning line; stdout envelope has empty `reply`. With 3 failures, stdout reply contains `🔔 *Push delivery failure alert*` and lists 3 notification IDs. With 0 failures, reply is empty.
--- END PROMPT T017 ---

--- IMPLEMENTATION PROMPT T018 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Markdown
File: specs/028-openclaw-telegram-ops/checklists/requirements.md
Task: After implementation, append a "## Post-Implementation Notes" section documenting any deviations from the spec/plan/contracts discovered during implementation, or "None — implementation matched plan exactly." if clean. Do not modify any other section of the file.
Signatures required: none
Constraints: Append only; preserve existing content.
Acceptance criteria: File still passes the original checklist and has a new trailing section.
--- END PROMPT T018 ---

--- IMPLEMENTATION PROMPT T019 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Markdown (test report)
File: specs/028-openclaw-telegram-ops/test-results-YYYY-MM-DD.md (filename uses today's date)
Task: Run every test in quickstart.md (Tests 1–10) on the production server. For each test, record: test name, command/action used, observed result, pass/fail, audit log snippet (`tail -n 1 ~/.openclaw/audit.log`), any deviations. Map pass/fail to SC-001..SC-008 at the end.
Signatures required: none
Constraints: Do not automate the tests — this is a manual execution record. Include timestamps.
Acceptance criteria: File exists, all 10 tests documented with pass/fail and audit evidence; SC-001..SC-008 mapping table at bottom.
--- END PROMPT T019 ---

--- IMPLEMENTATION PROMPT T020 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Markdown
File: CLAUDE.md
Task: Add a single line to the "## Recent Changes" section at the top: `- 028-openclaw-telegram-ops: Added out-of-tree server ops assistant (OpenClaw + local Gemma + Telegram bot); no backend/frontend code changes`.
Signatures required: none
Constraints: Append one bullet only; do not touch other sections.
Acceptance criteria: `CLAUDE.md` Recent Changes section has exactly one new bullet at the top referring to feature 028.
--- END PROMPT T020 ---
