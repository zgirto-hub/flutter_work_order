# Contract — `POST /activity-log/shared`

**Feature**: 038-ios-pwa-share
**Purpose**: Satisfy Principle VI (Audit Everything) by recording one row per share-button tap in `user_activity_log`. Fire-and-forget — the client never blocks on this endpoint.

---

## Endpoint

```
POST {AppConfig.baseUrl}/activity-log/shared
Content-Type: application/json
```

## Request body

```json
{
  "user_email":    "admin@example.com",
  "document_type": "letter",
  "document_id":   "a1b2c3d4-..."
}
```

### Field constraints

| Field | Type | Required | Allowed values / format |
|-------|------|----------|-------------------------|
| `user_email` | string | yes | Any non-empty string. Server does NOT validate against the auth token — the fire-and-forget pattern mirrors existing `/activity-log/sign-in`, `/activity-log/sign-out`, `/activity-log/update-check` endpoints, which also accept the email in the body. |
| `document_type` | string | yes | Exactly one of: `"letter"`, `"work_order"`. Server rejects other values with 400. |
| `document_id` | string | yes | Non-empty string (UUID for letters, UUID for work orders). Server does NOT validate the referenced record exists — audit is a best-effort log, not a referential integrity check. |

## Response

### 200 OK

```json
{ "status": "logged" }
```

Body is not used by the client (fire-and-forget), but returned for debugging and parity with existing activity-log endpoints.

### 400 Bad Request

Returned when `document_type` is not one of the allowed values, or when a required field is missing. Body:

```json
{ "detail": "document_type must be 'letter' or 'work_order'" }
```

### 5xx / network failure

The client MUST treat any non-200 status or network failure as a silent no-op and MUST NOT surface an error to the user. The share action proceeds regardless.

## Side effects

On 200: exactly one row is inserted into `user_activity_log` via `backend/utils/activity.py` with:

- `user_email` = request body field
- `category` = `"work_order"` if `document_type == "work_order"`, otherwise `"file"` (confirm final category at implementation time by inspecting how existing letter-related actions are categorised in `backend/utils/activity.py`)
- `action` = `"shared"`
- `target_type` = `document_type` value
- `target_id` = `document_id` value
- `created_at` = `now()` UTC (set by the helper)

No other DB writes, no notifications, no webhooks, no downstream effects.

## Authorization

The endpoint MUST be accessible to any authenticated user. It MUST NOT be called anonymously — the Flutter caller wraps the call inside a screen that is already behind the app's auth guard, so the endpoint itself does not need to re-check auth beyond the existing middleware in `backend/main.py`. This matches the pattern of `/activity-log/sign-in`.

## Idempotency

Not idempotent. Two rapid taps produce two rows. The client prevents double-taps at the UI level (FR-012: disabled/loading state on the share button until the first share invocation resolves). If a second row slips through due to a race, that is acceptable — the audit log is append-only and duplicates are not a correctness issue.

## Rate limiting

None beyond the global FastAPI rate limits (if any) already in place for `backend/routers/activity_log.py`. The call volume is bounded by real user actions (one tap = one call) and is negligible.

---

## Client contract

**File**: `frontend/lib/services/activity_log_service.dart` (extend existing class)

**New method**:

```dart
Future<void> logShared({
  required String documentType,  // 'letter' or 'work_order'
  required String documentId,
}) async {
  try {
    await http.post(
      Uri.parse('${AppConfig.baseUrl}/activity-log/shared'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_email': Supabase.instance.client.auth.currentUser?.email ?? '',
        'document_type': documentType,
        'document_id': documentId,
      }),
    );
  } catch (_) {}
}
```

**Call-site pattern** (in the share button `onPressed` handler):

```dart
// Fire-and-forget audit write — don't await, don't block
ActivityLogService().logShared(
  documentType: 'letter', // or 'work_order'
  documentId: letter.id,  // or wo.id
);
// Then proceed with the share action
final bytes = await widget.onShare!();
await sharePdfBytes(bytes, fileName, title);
```

Note: the `logShared` call is NOT awaited in the call site. The `Future<void>` return type is a convention for "the call has been dispatched"; any error is swallowed inside the method. This mirrors the existing `logSignIn` / `logSignOut` pattern in `activity_log_service.dart`.

---

## Server implementation sketch

**File**: `backend/routers/activity_log.py` (add to existing router)

```python
from pydantic import BaseModel
from fastapi import HTTPException
from backend.utils.activity import log_activity

class SharedLogBody(BaseModel):
    user_email: str
    document_type: str
    document_id: str

@router.post("/activity-log/shared")
async def log_shared(body: SharedLogBody):
    if body.document_type not in ("letter", "work_order"):
        raise HTTPException(
            status_code=400,
            detail="document_type must be 'letter' or 'work_order'",
        )
    category = "work_order" if body.document_type == "work_order" else "file"
    # Fire-and-forget write (helper handles its own exception swallowing)
    log_activity(
        user_email=body.user_email,
        category=category,
        action="shared",
        target_type=body.document_type,
        target_id=body.document_id,
    )
    return {"status": "logged"}
```

Exact import paths and the `log_activity` helper signature must be verified against the current `backend/utils/activity.py` at implementation time; this sketch is shape-only.
