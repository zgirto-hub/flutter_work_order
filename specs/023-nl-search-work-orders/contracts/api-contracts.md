# API Contracts: Natural Language Search for Work Orders

**Feature**: 023-nl-search-work-orders  
**Date**: 2026-04-06

## POST /api/search/nl

Natural language search for work orders. Parses user query via AI to extract structured filters, queries the database, and returns matching work orders. Falls back to keyword search on AI failure.

### Request

**Method**: POST  
**Path**: `/api/search/nl`  
**Content-Type**: `application/json`

**Body**:
```json
{
  "query": "closed technical orders from last month that took over 3 days",
  "email": "admin@example.com",
  "user_role": "admin",
  "limit": 30,
  "offset": 0
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| query | string | Yes | Natural language search query (non-empty) |
| email | string | Yes | Requesting user's email for RBAC |
| user_role | string | Yes | One of: "admin", "supervisor", "technician", "reporter" |
| limit | integer | No | Results per page (default: 30) |
| offset | integer | No | Pagination offset (default: 0) |

### Response — 200 OK (AI parsed)

```json
{
  "work_orders": [
    {
      "id": "uuid",
      "job_no": "WO-2026-0042",
      "title": "Fix HVAC unit in Building A",
      "description": "...",
      "status": "Closed",
      "type": "Technical",
      "location": "Building A",
      "department_name": "Mechanical",
      "created_at": "2026-03-10T08:30:00Z",
      "closed_at": "2026-03-14T16:45:00Z",
      "creator_name": "John Smith",
      "assigned_technician": "Jane Doe"
    }
  ],
  "total": 15,
  "filters": {
    "status": "Closed",
    "type": "Technical",
    "department": null,
    "location": null,
    "date_from": "2026-03-01",
    "date_to": "2026-03-31",
    "min_resolution_days": 3
  },
  "fallback": false
}
```

### Response — 200 OK (Keyword fallback)

Returned when AI parsing fails, times out (>5s), or extracts no filters.

```json
{
  "work_orders": [...],
  "total": 5,
  "filters": null,
  "fallback": true
}
```

### Response — 422 Validation Error

```json
{
  "detail": "Query must not be empty"
}
```

### Response — 503 Service Unavailable

Only returned if both AI parsing AND keyword fallback fail (should not happen in practice since keyword search has no external dependency).

```json
{
  "detail": "Search service temporarily unavailable"
}
```

### Error Handling Summary

| Scenario | Behavior | HTTP Status |
|----------|----------|-------------|
| AI parses successfully | Return filtered results + `fallback: false` | 200 |
| AI times out (>5s) | Keyword search + `fallback: true` | 200 |
| AI connection refused | Keyword search + `fallback: true` | 200 |
| AI returns unparseable response | Keyword search + `fallback: true` | 200 |
| AI returns no filters | Keyword search + `fallback: true` | 200 |
| Empty query string | Validation error | 422 |
| Invalid user role | Validation error | 422 |

### Notes

- Work order objects in the response have the same shape as those returned by `GET /api/work-orders`
- `filters` is null when `fallback` is true
- `filters` fields are null when the AI did not extract a value for that dimension
- Pagination works identically to `GET /api/work-orders` (limit/offset)
- Role-based filtering is applied server-side regardless of whether AI or keyword search is used
