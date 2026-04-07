# Contract: Heartbeat Skill

**Skill name**: `heartbeat`
**Entrypoints**: `daily_digest.py`, `weekly_summary.py`, `push_failure_check.py`
**Requires confirmation**: `[]`
**Invocation**: cron only (no LLM routing). The LLM does not need triggers for these.

## Cron schedule (server local time)

| Job | Schedule | Script |
|---|---|---|
| Daily digest | `0 7 * * *` | `daily_digest.py` |
| Weekly summary | `0 18 * * 0` | `weekly_summary.py` |
| Push failure check | `0 * * * *` | `push_failure_check.py` |

## `daily_digest.py`

**Calls**:
- `GET $API_BASE_URL/work-orders?email=$ADMIN_EMAIL&user_role=admin&status=Open`
- `GET .../work-orders?...&status=Pending`

**Compute**:
- `open_count = len(open)`
- `pending_count = len(pending)`
- `overdue = [wo for wo in open + pending if (now - wo.updated_at) > 48h]` (per FR-009 / clarification)
- `stale_alerts = [wo for wo in open if (now - wo.updated_at) > 48h]` (per FR-021)

**Output**: posts to admin Telegram via OpenClaw's `bot.sendMessage`:

```
🌅 *Daily Work Order Digest — {date}*
- Open: {open_count}
- Pending: {pending_count}
- Overdue (>48h, no change): {len(overdue)}

⚠️ *Stale (open >48h):*
- #{job_no} — {title} (last update {age})
...
```

If `len(overdue) == 0`, omit the stale section.

## `weekly_summary.py`

**Calls**:
- `GET .../reports/closed-work-orders?start_date=<7d ago>&end_date=<today>`
- `GET .../work-orders?...&status=Open`
- `GET .../work-orders?...&status=Pending`

**Output**:

```
📅 *Weekly Summary — {start_date} → {end_date}*
- Closed this week: {closed_count}
- Currently open: {open_count}
- Currently pending: {pending_count}

*Top closed:*
- #{job_no} — {title}
...
```

## `push_failure_check.py`

**Precondition** (per Research R10): There must be a FastAPI endpoint that exposes `notification_delivery_logs` rows with `status='failed'` from a given time window. If no such endpoint exists, this script logs a single warning to the audit log and exits 0 (FR-023 is SHOULD, not MUST — graceful degradation).

**Calls** (when endpoint exists):
- `GET $API_BASE_URL/notifications/delivery-failures?since=<1h ago>` (placeholder route — to be confirmed during /speckit.tasks)

**Output**: Only sends a Telegram message if `failures > 0`:

```
🔔 *Push delivery failure alert*
{N} notification(s) failed to deliver in the last hour.
Affected:
- {notification_id}: {error_message}
...
```

If failures == 0, the script exits silently (no Telegram message). The cron run is still recorded in the audit log with `outcome=success`.

## Audit behavior

Each cron invocation appends one record to `~/.openclaw/audit.log` with `caller="cron"`, `skill="heartbeat"`, `action="<job_name>"`, `outcome=success|failure`.
