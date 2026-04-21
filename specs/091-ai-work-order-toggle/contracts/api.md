# API Contract: AI Work Order Toggle (091)

## Toggle Management Endpoints

### GET /api/settings/ai-work-order

Get the current state of the AI Work Order feature toggle.

**Auth**: Required. Admin-only.

**Query Parameters**:
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `admin_email` | string | yes | Email of the requesting admin user |

**Response 200**:
```json
{
  "enabled": false,
  "updated_at": "2026-04-21T12:00:00Z"
}
```

**Response 403**:
```json
{
  "detail": "Admin access required"
}
```

---

### PUT /api/settings/ai-work-order

Set the AI Work Order feature toggle state.

**Auth**: Required. Admin-only.

**Query Parameters**:
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `admin_email` | string | yes | Email of the requesting admin user |

**Request Body**:
```json
{
  "enabled": true
}
```

**Response 200**:
```json
{
  "enabled": true,
  "updated_at": "2026-04-21T14:30:00Z"
}
```

**Response 403**:
```json
{
  "detail": "Admin access required"
}
```

**Side Effects**:
- Upserts `app_settings` row with key `ai_work_order_enabled`
- Logs to `user_activity_log`: category=`admin`, action=`ai_work_order_toggled`, target_label=`"true"`/`"false"`

---

## Autofill Endpoint

### POST /api/ai/autofill-work-order

Generate structured work order field suggestions from a free-text description.

**Auth**: Required. Any authenticated user.

**Request Body**:
```json
{
  "description": "AC unit in tower 3 is leaking water onto the floor, been getting worse since yesterday",
  "language": "en",
  "departments": ["Technical", "Inspection"],
  "types": ["Technical", "Inspection", "Other"],
  "statuses": ["Pending", "In Progress", "Closed"]
}
```

| Field | Type | Required | Constraints | Description |
|-------|------|----------|-------------|-------------|
| `description` | string | yes | 20–500 chars | Free-text description of the work needed |
| `language` | string | no | `"en"` or `"ar"` | Language of the description (defaults to `"en"`) |
| `departments` | string[] | no | | Valid department names for category matching |
| `types` | string[] | no | | Valid work order type names |
| `statuses` | string[] | no | | Valid status names |

**Processing Order** (short-circuit):
1. Auth check → 401 if unauthenticated
2. Toggle check → 403 if `ai_work_order_enabled` is OFF
3. Rate limit check → 429 if exceeded
4. Input validation → 422 if description length out of bounds
5. AI generation via provider fallback → 200 or 502/503

**Response 200**:
```json
{
  "title": "AC Unit Water Leak - Tower 3",
  "description": "Air conditioning unit in tower 3 is leaking water onto the floor. The issue has been worsening since yesterday and requires immediate attention to prevent further damage.",
  "priority": "High",
  "category": "Technical",
  "asset_name": "AC Unit Tower 3",
  "fault_description": "Water leaking from AC unit onto floor",
  "action_taken": "",
  "outcome": ""
}
```

All fields are nullable in the response. Omitted or empty-string fields mean "no suggestion".

**Response 401**:
```json
{
  "detail": "Not authenticated"
}
```

**Response 403**:
```json
{
  "detail": "AI Work Order feature is disabled"
}
```

**Response 422**:
```json
{
  "detail": "Description must be between 20 and 500 characters"
}
```

**Response 429**:
```json
{
  "detail": "Too many requests. Try again in 55 seconds.",
  "retry_after": 55
}
```

**Response 502**:
```json
{
  "detail": "AI could not generate a work order draft. Please try again."
}
```

**Response 503**:
```json
{
  "detail": "AI service is currently unavailable. Please try again later."
}
```

---

## Existing Endpoint Modification

### POST /api/ai/parse-work-order

**No changes to this endpoint.** It continues to work as before. The `/ai/autofill-work-order` endpoint is a separate, dedicated endpoint with the toggle gate, rate limiting, and enhanced response shape.

---

## Frontend Service Contract

### AiProviderService (Dart) — New Methods

```dart
Future<bool> getAiWorkOrderEnabled(String userEmail);
Future<void> setAiWorkOrderEnabled(bool enabled, String userEmail);
```

- `getAiWorkOrderEnabled`: GET `/settings/ai-work-order?admin_email={email}` → returns `enabled` bool
- `setAiWorkOrderEnabled`: PUT `/settings/ai-work-order?admin_email={email}` → body `{"enabled": bool}`

### AiAssistService (Dart) — New Method

```dart
Future<Map<String, dynamic>> autofillWorkOrder({
  required String description,
  String language = 'en',
  List<String>? departments,
  List<String>? types,
  List<String>? statuses,
});
```

- POST `/ai/autofill-work-order`
- Returns the JSON response map with fields: `title`, `description`, `priority`, `category`, `asset_name`, `fault_description`, `action_taken`, `outcome`
- Throws on 403 (feature disabled), 422 (validation), 429 (rate limited), 502/503 (AI error)