# Data Model: AI-Powered Analytics & Insights

**Feature**: 021-ai-analytics-insights  
**Date**: 2026-04-05

## Overview

This feature does not introduce new database tables or modify existing schemas. All data is transient (request/response only). The feature reads from existing tables and returns AI-generated text.

## Existing Tables Used (read-only)

### work_orders
- `id` (UUID) — primary key
- `status` (text) — Pending | In Progress | Resolved | Closed
- `type` (text) — Technical | Inspection | Other
- `department_id` (UUID, FK → departments.id)
- `location` (text)
- `created_at` (timestamptz)
- `closed_at` (timestamptz, nullable)

### system_status_reports
- `id` (UUID) — primary key
- `system_name` (text) — one of 33 allowed system names
- `report_date` (date)
- `notes` (text)
- `resolved_at` (timestamptz, nullable)
- `resolved_notes` (text, nullable)

### departments
- `id` (UUID) — primary key
- `name` (text)

### users
- `id` (UUID) — primary key
- `email` (text)
- `user_type` (text) — reporter | technician | admin

## Transient Entities

### AiInsightRequest
| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| insight_type | string | yes | — | "overview" \| "system_status" \| "trends" |
| date_range_days | integer | no | 30 | Number of days to look back |
| language | string | no | "en" | "en" \| "ar" — language for generated text |

### AiInsightResponse
| Field | Type | Description |
|-------|------|-------------|
| insight | string | Generated 3-5 bullet points (may be RTL if Arabic) |
| generated_at | string (ISO 8601) | Timestamp of generation |
| data_summary | object | Aggregated stats used for generation (for transparency) |

### WorkOrderStats (internal aggregation)
| Field | Type | Description |
|-------|------|-------------|
| total | integer | Total work orders in range |
| by_status | map<string, int> | Count per status |
| by_type | map<string, int> | Count per type |
| by_department | list<{name, count}> | Count per department with name |
| avg_resolution_hours | float | Average hours from created_at to closed_at |
| weekly_volumes | list<{week, count}> | Work order count per ISO week |
| top_locations | list<{location, count}> | Top 5 locations by frequency |

### SystemStatusStats (internal aggregation)
| Field | Type | Description |
|-------|------|-------------|
| currently_unresolved | list<{system_name, report_date, notes}> | Active unresolved issues |
| issues_per_system | list<{system_name, count}> | Issue count per system in range |
| avg_resolution_hours_per_system | list<{system_name, hours}> | Avg resolution time |
| clean_systems | list<string> | Systems with zero issues in range |
| worst_systems | list<{system_name, count}> | Top 5 most problematic |

## State Transitions

None — this feature is stateless. Each request generates a fresh insight from current data.

## Validation Rules

- `insight_type` must be one of: "overview", "system_status", "trends"
- `date_range_days` must be between 1 and 365
- `language` must be one of: "en", "ar"
- Requesting user must have role "admin" or "supervisor"
- If total work orders in date range < 5, return insufficient data message instead of calling LLM
