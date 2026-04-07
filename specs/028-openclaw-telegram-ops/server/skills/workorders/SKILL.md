---
name: workorders
description: Query and manage Work Orders in the WO system
entrypoint: workorders.py
requiresConfirmation:
  - close
  - update_status
triggers:
  - "show open work orders"
  - "show pending work orders"
  - "how many pending"
  - "how many open"
  - "what's overdue"
  - "show overdue work orders"
  - "close work order #1234"
  - "close #1234"
  - "show me #1234"
  - "details on 1234"
  - "get work order 1234"
  - "what did we complete this week"
  - "update status of #1234 to Open"
  - "how many work orders are closed"
---

# Work Orders Skill

This skill allows querying and managing work orders in the Work Order system via natural language commands.

## Actions

### list_open

Lists all work orders with status "Open".

**Arguments**: None

**Example invocations**:
- "show open work orders"
- "list open WOs"

**Response**: Markdown bullet list of up to 20 open work orders in format:
- #{job_no} — {title} ({assigned_to or "unassigned"})

If more than 20, append "...and N more"

---

### list_pending

Lists all work orders with status "Pending".

**Arguments**: None

**Example invocations**:
- "show pending work orders"
- "list pending WOs"
- "how many pending"

**Response**: Same format as list_open

---

### list_overdue

Lists work orders that are Open or Pending with no status change in over 48 hours.

**Arguments**: None

**Example invocations**:
- "what's overdue"
- "show overdue work orders"
- "list overdue WOs"

**Response**: Markdown list with header "*Overdue work orders (>48h, no status change)*"

---

### count

Returns the count of work orders by status.

**Arguments**:
- `status` (string): "Open", "Pending", or "Closed"

**Example invocations**:
- "how many open work orders"
- "count of pending WOs"
- "how many closed this month"

**Response**: "There are {N} {status} work orders."

---

### get

Returns detailed information about a specific work order.

**Arguments**:
- `job_no` (string): The job number (e.g., "1234")
- OR `id` (integer): The work order ID

**Example invocations**:
- "show me #1234"
- "details on 1234"
- "get work order 1234"

**Response**: Structured fields including title, status, assigned_to, created_at, last update

**Errors**: 404 → "Work order #{job_no} not found."

---

### close

Closes a work order with an optional reason.

**Arguments**:
- `job_no` (string): The job number to close
- `reason` (string, optional): Reason for closing

**Example invocations**:
- "close work order #1234"
- "close #1234 because it's done"

**Confirmation**: Required. First call returns needs_confirmation with prompt: "Close work order #{job_no} ({title})? Reply 'yes' within 60s to confirm."

**Response on success**: "✅ Work order #{job_no} closed."

---

### update_status

Updates the status of a work order.

**Arguments**:
- `job_no` (string): The job number
- `new_status` (string): "Open", "Pending", or "In Progress"

**Example invocations**:
- "update status of #1234 to Open"
- "change #1234 to Pending"

**Confirmation**: Not required (use close action for closing)

**Response**: "Work order #{job_no} status updated to {new_status}."

---

### summary_closed_in_range

Returns a summary of work orders closed within a date range.

**Arguments**:
- `start_date` (string): Start date in YYYY-MM-DD format
- `end_date` (string): End date in YYYY-MM-DD format

**Example invocations**:
- "what did we complete this week"
- "show closed WOs from 2026-01-01 to 2026-01-31"

**Response**: Count + bullet list of titles (max 20), capped with "...and N more" if truncated