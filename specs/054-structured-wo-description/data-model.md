# Data Model: Structured Work Order Description Fields

**Branch**: `054-structured-wo-description` | **Date**: 2026-04-14

## No Schema Changes

This feature does **not** modify the database schema. The `work_orders.description` column (TEXT) continues to store the description string. The structured sub-fields are stitched into this single column by the backend.

## Stitched Description Format

The backend produces a bracket-labeled string stored in `work_orders.description`:

```
[Asset] <asset_name>
[Fault] <fault_description>
[Action] <action_taken>
[Outcome] <outcome>
[Notes] <notes>
```

- `[Notes]` line is omitted when notes are empty.
- Each label is on its own line, followed by the value.
- Legacy descriptions (pre-feature) do not have bracket labels and are displayed as-is.

### Detection Logic

A description is considered "structured" if it starts with `[Asset] `. This is the discriminator for the detail view parser.

## Entities (unchanged)

### Work Order (existing — no changes)

| Field | Type | Notes |
|-------|------|-------|
| description | TEXT | Now stores stitched structured format for new WOs |

### Asset (existing — no changes)

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| name | TEXT | Used for autocomplete suggestions |
| type | TEXT | Asset type category |
| location | TEXT | Physical location |

## API Request Model Changes

### CreateWorkOrderBody (backend)

New optional fields added alongside existing `description`:

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| asset_name | string | No* | Asset name (free text or from registry) |
| fault_description | string | No* | What went wrong |
| action_taken | string | No* | What was done |
| outcome | string | No* | One of: Resolved, Pending Parts, Escalated, Monitoring |
| notes | string | No | Optional free-text notes |

*Required when using structured mode. If all four are present, backend stitches them. If absent, falls back to `description` field (backward compatibility).

## Outcome Enum

Fixed set of allowed values:
- `Resolved`
- `Pending Parts`
- `Escalated`
- `Monitoring`

Backend validates outcome against this set when structured fields are provided.
