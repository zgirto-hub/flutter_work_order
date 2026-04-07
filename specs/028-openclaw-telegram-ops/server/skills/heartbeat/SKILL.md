---
name: heartbeat
description: Scheduled (cron-only) digests and health checks
entrypoint: null
requiresConfirmation: []
triggers: []
---

# Heartbeat Skill

This skill provides scheduled (cron-only) automated tasks that run without direct user interaction.

## Cron Jobs

The following jobs are scheduled via OpenClaw cron configuration:

| Job | Schedule | Script |
|---|---|---|
| Daily digest | `0 7 * * *` | `daily_digest.py` |
| Weekly summary | `0 18 * * 0` | `weekly_summary.py` |
| Push failure check | `0 * * * *` | `push_failure_check.py` |

## Scripts

### daily_digest.py

Runs daily at 7:00 AM local time. Fetches open and pending work orders, computes overdue (no status change in >48h), and posts a digest to the admin via Telegram.

**Output format**:
```
🌅 *Daily Work Order Digest — {date}*
- Open: {open_count}
- Pending: {pending_count}
- Overdue (>48h, no change): {len(overdue)}

⚠️ *Stale (open >48h):*
- #{job_no} — {title} (last update {age})
...
```

### weekly_summary.py

Runs weekly on Sunday at 6:00 PM local time. Fetches closed work orders for the past 7 days plus current open/pending counts, and posts a summary to the admin via Telegram.

**Output format**:
```
📅 *Weekly Summary — {start_date} → {end_date}*
- Closed this week: {closed_count}
- Currently open: {open_count}
- Currently pending: {pending_count}

*Top closed:*
- #{job_no} — {title}
...
```

### push_failure_check.py

Runs hourly. Checks for failed push notification deliveries in the past hour and alerts the admin if any failures are detected.

**Output format** (only when failures > 0):
```
🔔 *Push delivery failure alert*
{N} notification(s) failed to deliver in the last hour.
Affected:
- {notification_id}: {error_message}
...
```

If no failures, the script exits silently (no Telegram message).