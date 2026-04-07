# Contract: Work Orders Skill

**Skill name**: `workorders`
**Entrypoint**: `workorders.py`
**Requires confirmation**: `["close", "update_status"]`

## Actions

### `list_open`
List currently Open work orders.
- **args**: `{}`
- **calls**: `GET $API_BASE_URL/work-orders?email=$ADMIN_EMAIL&user_role=admin&status=Open`
- **reply**: Markdown bullet list `- #{job_no} — {title} ({assigned_to or "unassigned"})`, max 20 entries with "...and N more" footer.

### `list_pending`
- **args**: `{}`
- **calls**: `GET .../work-orders?...&status=Pending`
- **reply**: same format as `list_open`.

### `list_overdue`
Compute overdue locally per Spec FR-009 (Open or Pending, no status change in 48h).
- **args**: `{}`
- **calls**: two calls — `?status=Open` and `?status=Pending` — then filter where `now - updated_at > 48h`.
- **reply**: Markdown list, header `*Overdue work orders (>48h, no status change)*`.

### `count`
- **args**: `{ "status": "Open" | "Pending" | "Closed" }`
- **calls**: same list endpoint, returns `len(results)`.
- **reply**: `There are {N} {status} work orders.`

### `get`
- **args**: `{ "job_no": "<string>" }` or `{ "id": <int> }`
- **calls**: `GET .../work-orders/{id}` (resolving job_no→id by listing if needed).
- **reply**: structured fields (title, status, assigned_to, created_at, last update).
- **errors**: 404 → `Work order #{job_no} not found.`

### `close`
- **args**: `{ "job_no": "<string>", "reason": "<optional string>" }`
- **calls**: `POST .../work-orders/{id}/close` body `{ "closed_by_email": "$ADMIN_EMAIL", "reason": ... }`
- **confirmation**: requires `confirmed=true`. On first call, returns `needs_confirmation` with prompt: `Close work order #{job_no} ({title})? Reply "yes" within 60s to confirm.`
- **reply on success**: `✅ Work order #{job_no} closed.`

### `update_status`
- **args**: `{ "job_no": "<string>", "new_status": "Open"|"Pending"|"In Progress" }`
- **calls**: `PUT .../work-orders/{id}` body `{ "status": new_status, "updated_by_email": "$ADMIN_EMAIL" }`
- **confirmation**: required if new_status is `Closed` (use `close` action instead).

### `summary_closed_in_range`
"What did we complete this week?"
- **args**: `{ "start_date": "YYYY-MM-DD", "end_date": "YYYY-MM-DD" }`
- **calls**: `GET .../reports/closed-work-orders?start_date=...&end_date=...`
- **reply**: count + bullet list of titles, capped at 20.

## Trigger phrases (LLM grounding)

- "show open work orders" → `list_open`
- "how many pending" → `count` with `status=Pending`
- "what's overdue" / "show overdue" → `list_overdue`
- "close work order #1234" → `close`
- "what did we complete this week" → `summary_closed_in_range` with current week's range
- "show me #1234" / "details on 1234" → `get`
