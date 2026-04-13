# Data Model: Agentic Tool Use (Layer 5)

**Date**: 2026-04-13
**Feature**: 047-agentic-tool-use

## Overview

No new database tables or columns. This feature operates on existing tables and uses in-memory data structures for the agentic loop.

## Existing Entities Used

### work_orders (read-only access by work_orders tool)

Fields returned by the tool:

| Field | Type | Description |
|-------|------|-------------|
| job_no | integer | Work order number |
| status | string | Current status (Pending, In Progress, Completed, etc.) |
| description | text | Work order description |
| type | string | Work order type (Technical, etc.) |
| department_id | uuid | FK to departments table |
| assigned_technician_id | uuid | FK to users table |
| created_at | timestamp | Creation date |
| closed_at | timestamp | Resolution date (nullable) |
| signature_status | string | Signature workflow status |

Joined fields:
- `department_name` from `departments.name`
- `technician_name` from `users.full_name`

### manual_chunks (accessed via existing pgvector RPC)

No direct access — the manuals tool delegates to `manual_rag_service.ask()` which uses the existing `search_manual_chunks` RPC.

## In-Memory Structures

### Tool Manifest

A static Python dict/string describing the 3 available tools, their parameters, and descriptions. Injected into the system prompt for every agentic call.

### Tool Call

Parsed from model output text:

| Field | Type | Description |
|-------|------|-------------|
| tool_name | string | One of: work_orders, manuals, compare |
| params | dict | Tool-specific parameters |

### Tool Result

Returned by tool executor:

| Field | Type | Description |
|-------|------|-------------|
| tool_name | string | Which tool was called |
| success | bool | Whether the tool executed successfully |
| data | any | Tool-specific result data |
| truncated | bool | Whether results were capped (work_orders only) |

### Agentic Loop State

| Field | Type | Description |
|-------|------|-------------|
| tool_calls | list | History of tool calls and results in this loop |
| call_count | int | Number of tools called so far (max 3) |
| start_time | float | Loop start timestamp for 60s timeout |

### Response Metadata (added to existing response dict)

| Field | Type | Description |
|-------|------|-------------|
| tools_used | list[dict] | Array of {tool_name, success, has_data} per tool called |
| agentic | bool | Whether the agentic loop was used for this question |

## State Transitions

None — no persistent state changes. The agentic loop is stateless per request (tool call history lives only for the duration of one question).

## Data Volume

- Work orders tool: max 20 rows per query
- Manuals tool: delegates to existing pipeline (max 10 chunks)
- Compare tool: single LLM call with bounded input
