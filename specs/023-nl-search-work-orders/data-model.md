# Data Model: Natural Language Search for Work Orders

**Feature**: 023-nl-search-work-orders  
**Date**: 2026-04-06

## Overview

This feature requires **no database schema changes**. All data structures are transient (request/response only). The feature queries existing tables (`work_orders`, `departments`, `users`) using structured filters extracted from natural language.

## Existing Entities (Referenced, Not Modified)

### work_orders
| Field | Type | Relevance to NL Search |
|-------|------|----------------------|
| id | UUID | Primary key, returned in results |
| job_no | TEXT | Keyword fallback search field |
| title | TEXT | Keyword fallback search field |
| description | TEXT | Keyword fallback search field |
| status | TEXT | Filter: "Pending", "In Progress", "Resolved", "Closed" |
| type | TEXT | Filter: "Technical", "Inspection", "Other" |
| department_id | UUID | Filter: matched via department name lookup |
| location | TEXT | Filter: partial text match |
| created_at | TIMESTAMP | Filter: date range (date_from, date_to) |
| closed_at | TIMESTAMP | Filter: resolution time calculation (closed_at - created_at) |
| created_by | UUID | Role-based filtering (reporter sees own) |

### departments
| Field | Type | Relevance to NL Search |
|-------|------|----------------------|
| id | UUID | Looked up from department name extracted by AI |
| name | TEXT | Matched against AI-extracted department name (case-insensitive partial match) |

### users
| Field | Type | Relevance to NL Search |
|-------|------|----------------------|
| id | UUID | Role-based filtering |
| email | TEXT | Identifies requesting user |
| user_type | TEXT | Determines result scoping (admin/supervisor/technician/reporter) |
| department_id | UUID | Technician department scoping |

## Transient Data Structures

### NLSearchRequest (Backend Input)
```
query: string (required)     — Raw natural language text from user
email: string (required)     — Requesting user's email
user_role: string (required) — "admin" | "supervisor" | "technician" | "reporter"
limit: integer (optional)    — Page size, default 30
offset: integer (optional)   — Pagination offset, default 0
```

### ExtractedFilters (Internal — AI Output)
```
status: string | null        — One of: "Pending", "In Progress", "Resolved", "Closed"
type: string | null          — One of: "Technical", "Inspection", "Other"
department: string | null    — Department name (fuzzy matched to departments table)
location: string | null      — Location text (partial match)
date_from: date | null       — Start of date range (ISO format)
date_to: date | null         — End of date range (ISO format)
min_resolution_days: number | null — Minimum resolution time in days
```

All fields are nullable. Only fields explicitly mentioned in the user's query are populated. Null fields are not applied as filters.

### NLSearchResponse (Backend Output)
```
work_orders: list            — Array of work order objects (same shape as GET /api/work-orders)
total: integer               — Total count matching filters (for pagination)
filters: ExtractedFilters    — The filters that were applied (for chip display)
fallback: boolean            — True if keyword search was used instead of AI parsing
```

## State Transitions

No state transitions. This feature is stateless — each search is an independent request/response cycle. No data is persisted between searches.

## Validation Rules

- `query` must be non-empty string (reject empty queries)
- `user_role` must be one of the four known roles
- `email` must match an existing user
- Extracted `status` must match a known status enum or be dropped
- Extracted `type` must match a known type enum or be dropped
- Extracted `department` must partially match a department name or be dropped
- Extracted `date_from` must be before or equal to `date_to` (if both present)
- Extracted `min_resolution_days` must be positive number or be dropped
