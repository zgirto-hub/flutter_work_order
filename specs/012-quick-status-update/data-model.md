# Data Model: Quick Status Update

**Feature**: 012-quick-status-update  
**Date**: 2026-04-03

## Overview

No new entities, tables, or migrations required. This feature operates entirely on existing data structures.

## Existing Entities Used

### WorkOrder

Existing model at `frontend/lib/models/work_order.dart`. Relevant fields:

| Field | Type | Relevance |
|-------|------|-----------|
| id | String | Used to identify which work order to update |
| status | String | The field being modified. Values: "Pending", "In Progress", "Resolved", "Closed" |
| closedBy | String? | Set when closing via the close endpoint |
| closedAt | String? | Set server-side when closing |
| techNotes | String? | Optional notes provided during close flow |

### Status Transition Map (client-side logic, not persisted)

```
Pending      → [In Progress]
In Progress  → [Resolved]
Resolved     → [Closed]  (triggers close flow with optional techNotes)
Closed       → []         (terminal state, no transitions)
```

### Audit Records (existing, server-managed)

**work_order_status_logs** — automatically populated by backend on status change:
- old_status, new_status, changed_by (UUID), timestamp

**work_order_comments** — system comment auto-created:
- type: "status_change", metadata: {"from": old_status, "to": new_status}

## Database Changes

None required. No new migrations.
