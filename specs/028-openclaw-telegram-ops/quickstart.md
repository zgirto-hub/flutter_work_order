# Quickstart: OpenClaw Telegram Ops Assistant

**Feature**: 028-openclaw-telegram-ops
**Audience**: Operator installing this on the Zorin OS server.

This guide walks through end-to-end setup and the smoke tests that prove each user story.

---

## Prerequisites

- SSH access to the Zorin OS server
- The FastAPI backend is running and reachable at `http://localhost:8000/api`
- Ollama is running locally with at least one model loaded (verify: `curl http://localhost:11434/api/tags`)
- A Telegram account for the admin
- Sudo on the server

## Step 1 — One-time manual prep

### 1a. Create the Telegram bot
1. In Telegram, message **@BotFather**.
2. Send `/newbot`, follow the prompts, choose a name and username.
3. Copy the **bot token** BotFather returns. Save it for step 2.

### 1b. Find your Telegram user ID
1. In Telegram, message **@userinfobot** (or **@RawDataBot**).
2. Copy the numeric **user ID** it returns. Save it for step 2.

### 1c. Confirm the admin email
The admin email is whatever account already has `role=admin` in the Work Order system. Save it for step 2.

## Step 2 — Set environment variables and run the installer

```bash
cd /path/to/flutter_work_order
export TELEGRAM_BOT_TOKEN="123456:ABC-..."
export ADMIN_TELEGRAM_USER_ID="987654321"
export ADMIN_EMAIL="admin@example.com"
export OLLAMA_MODEL="gemma4"   # or whatever `ollama list` shows

bash specs/028-openclaw-telegram-ops/server/install_openclaw.sh
```

The installer will:
1. Verify Node.js ≥ 20 (install via NodeSource if missing)
2. Install OpenClaw globally
3. Create `~/.openclaw/`, copy the skills tree, render `openclaw.json`
4. Install `/etc/systemd/system/openclaw.service`
5. `systemctl daemon-reload && systemctl enable --now openclaw`
6. Tail `journalctl -u openclaw` for 10 s to verify clean startup

## Step 3 — Add the sudoers rule for the server skill

Only required if you want the `restart_backend` action to work.

```bash
sudo visudo -f /etc/sudoers.d/openclaw
```

Add exactly:

```
openclaw ALL=(root) NOPASSWD: /bin/systemctl restart fastapi
```

(Replace `openclaw` with the actual user the systemd unit runs as.)

## Step 4 — Smoke tests (validates spec acceptance scenarios)

### Test 1 — User Story 1, Acceptance Scenario 1 (P1)

In Telegram, message your bot: **`show open work orders`**

✅ **Expected**: Within ~5 s, the bot replies with a bulleted list of currently Open work orders matching what the dashboard shows. If empty: `No open work orders.`

### Test 2 — User Story 1, AS 2

Send: **`how many pending work orders?`**

✅ **Expected**: `There are N pending work orders.` matching backend count.

### Test 3 — User Story 1, AS 3 (destructive + confirmation gate)

Send: **`close work order #1234`** (use a real job_no from a test order).

✅ **Expected**:
1. Bot replies: `Close work order #1234 ({title})? Reply "yes" within 60s to confirm.`
2. Send `yes` within 60 s.
3. Bot replies: `✅ Work order #1234 closed.`
4. Verify in the PWA dashboard that the work order is now Closed.
5. Verify `~/.openclaw/audit.log` contains a record with `action="close"`, `outcome="success"`.

### Test 4 — User Story 1, AS 4 (authorization)

From a DIFFERENT Telegram account, message the bot: **`show open work orders`**

✅ **Expected**: Bot does NOT reply (or replies with a refusal). `~/.openclaw/audit.log` records `outcome="unauthorized"`.

### Test 5 — User Story 3, AS 1 (server health)

Send: **`server status`**

✅ **Expected**: Bot replies with nginx + fastapi active states and disk usage.

### Test 6 — Confirmation expiry (FR-004)

Send: **`restart backend`**

✅ **Expected**: Bot prompts for confirmation. Wait > 60 s. Send `yes`. Bot must NOT restart and should reply that no pending action exists. Audit log must show one `outcome="confirmation_expired"` record.

### Test 7 — User Story 4 (email)

Send: **`Send work order #42 PDF to test@example.com`**

✅ **Expected**: Bot confirms send. Recipient receives the PDF. (Skip if the Exchange-SMTP feature is not yet deployed; in that case the bot replies `Email backend not available yet.`)

### Test 8 — User Story 2 (daily digest)

Manually trigger the daily digest skill:

```bash
sudo -u openclaw python3 ~/.openclaw/skills/heartbeat/daily_digest.py
```

✅ **Expected**: A digest message arrives in the admin Telegram chat with current counts. Compare against the dashboard.

Then verify the cron entry:

```bash
sudo systemctl status openclaw
journalctl -u openclaw --since "5 minutes ago" | grep cron
```

### Test 9 — Reboot resilience (SC-001)

```bash
sudo reboot
```

After the server is back, send the bot **`show open work orders`** within 2 minutes of the host being reachable again.

✅ **Expected**: Bot replies normally without manual intervention.

### Test 10 — Audit log inspection (SC-006)

```bash
tail -n 20 ~/.openclaw/audit.log | jq .
```

✅ **Expected**: Each test above has produced exactly one NDJSON record with the appropriate `action` and `outcome` field. No destructive `close` or `restart_backend` record exists with `outcome="success"` that lacks a preceding `outcome="confirmation_required"` for the same chat.

---

## Rollback

```bash
sudo systemctl disable --now openclaw
sudo rm /etc/systemd/system/openclaw.service
sudo systemctl daemon-reload
rm -rf ~/.openclaw
```

The Work Order app is unaffected by removal — no shared state.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Bot silent on every message | Wrong `allowFrom` user ID, or bot token bad | Check `~/.openclaw/openclaw.json`, restart service |
| `Ollama unreachable` in logs | Ollama not running | `systemctl start ollama` |
| Skill returns "Email backend not available" | Exchange-SMTP feature not deployed | Wait for parallel feature, or skip Test 7 |
| `restart_backend` says `sudo: a password is required` | Sudoers rule missing | Re-run Step 3 |
| Cron jobs never fire | systemd unit not running | `systemctl status openclaw`, `journalctl -u openclaw -n 50` |
