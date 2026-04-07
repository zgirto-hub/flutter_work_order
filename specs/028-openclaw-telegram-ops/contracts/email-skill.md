# Contract: Email Skill

**Skill name**: `email`
**Entrypoint**: `email.py`
**Requires confirmation**: `[]` (sending email is non-destructive at the data layer)

## Dependency

This skill consumes the email-with-PDF capability delivered by the parallel Exchange-SMTP feature. If that capability is not yet deployed, this skill returns `status=error` with reply `Email backend not available yet.`

## Actions

### `send_work_order_pdf`
- **args**: `{ "job_no": "<string>", "to": "<email>", "cc": ["<email>", ...] (optional), "subject": "<optional>" }`
- **calls**: existing FastAPI endpoint that emails a work-order PDF (e.g. `POST /api/work-orders/{id}/email`) with body `{ "to": [...], "cc": [...], "subject": ..., "from_email": "$ADMIN_EMAIL" }`.
- **validation**: `to` MUST match a basic email regex; otherwise return `status=error` with reply `Invalid email address: {to}.`
- **reply on success**: `📧 Sent work order #{job_no} PDF to {to}.`

### `send_weekly_summary`
- **args**: `{ "to": "<email>" (optional, defaults to $ADMIN_EMAIL) }`
- **calls**: generates a summary by calling `GET /api/reports/closed-work-orders?start_date=<7d ago>&end_date=<today>` then sends the resulting payload via the same email endpoint with subject `Weekly Work Order Summary — {date_range}`.
- **reply on success**: `📧 Weekly summary emailed to {to}.`

## Trigger phrases

- "send work order #42 pdf to director@example.com" → `send_work_order_pdf`
- "email me the weekly summary" → `send_weekly_summary` (to=$ADMIN_EMAIL)
