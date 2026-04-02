# API Contracts: Edit Resolve Date

## Modified Endpoints

### PATCH `/system-status/{report_id}/resolve`

Resolve an issue. Now accepts an optional custom resolve date.

**Request body** (changed):
```json
{
  "resolved_by": "user@example.com",         // required
  "resolved_notes": "Fixed the cable",        // optional, default ""
  "resolved_at": "2026-04-01"                 // optional, default: current UTC timestamp
}
```

**New field**: `resolved_at` (optional string, YYYY-MM-DD format)
- If omitted: uses `datetime.utcnow().isoformat()` (existing behavior)
- If provided: validates >= report_date and <= today, then stores as `YYYY-MM-DDT23:59:59`

**Error responses** (new):
- `400`: "Resolve date cannot be before the issue report date ({report_date})"
- `400`: "Resolve date cannot be in the future"

---

### PUT `/system-status/{report_id}`

Update an issue. Now accepts an optional resolve date for resolved issues.

**Request body** (changed):
```json
{
  "notes": "Updated description",             // optional
  "report_date": "2026-03-30",               // optional
  "resolved_at": "2026-04-01"                 // optional, NEW
}
```

**New field**: `resolved_at` (optional string, YYYY-MM-DD format)
- Only accepted when the issue is already resolved (ignored or error if unresolved)
- Validates >= report_date and <= today
- Stores as `YYYY-MM-DDT23:59:59`

**Error responses** (new):
- `400`: "Cannot edit resolve date on an unresolved issue"
- `400`: "Resolve date cannot be before the issue report date ({report_date})"
- `400`: "Resolve date cannot be in the future"

---

## Unchanged Endpoints

All other system status endpoints remain unchanged:
- `GET /system-status/today`
- `GET /system-status/history`
- `GET /system-status/report` (uptime — automatically uses updated `resolved_at`)
- `POST /system-status/report`
- `DELETE /system-status/{report_id}`
