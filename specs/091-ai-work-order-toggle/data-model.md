# Data Model: AI Work Order Toggle (091)

## Entities

### 1. App Setting: `ai_work_order_enabled`

This is not a new table — it's a new row in the existing `app_settings` table.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `key` | TEXT | PRIMARY KEY | `'ai_work_order_enabled'` |
| `value` | TEXT | NOT NULL | `'true'` or `'false'` |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT NOW() | Last modification timestamp |
| `updated_by` | UUID | FK → `users.id`, NULLABLE | Who last changed this setting |

**Default state**: `'false'` (OFF) — per FR-007.

**Relations**: `updated_by` references `users.id` for audit trail of who toggled the feature.

**Migration**: Single seed insert:
```sql
INSERT INTO app_settings (key, value) VALUES ('ai_work_order_enabled', 'false')
ON CONFLICT (key) DO NOTHING;
```

No schema changes needed — the table already exists with all required columns.

### 2. Work Order Draft Suggestion (Transient)

Not persisted. This is the in-memory response from the `/ai/autofill-work-order` endpoint.

| Field | Type | Source | Description |
|-------|------|--------|-------------|
| `title` | string? | AI generation | Suggested work order title |
| `description` | string? | AI generation | Suggested detailed description |
| `priority` | string? | AI generation | Suggested priority level |
| `category` | string? | AI generation | Suggested department/category name |
| `asset_name` | string? | AI generation | Suggested asset/equipment name |
| `fault_description` | string? | AI generation | Suggested fault description |
| `action_taken` | string? | AI generation | Suggested action taken |
| `outcome` | string? | AI generation | Suggested outcome |

All fields are optional — the AI may omit any field. Fields that don't match known dropdown values are dropped by the frontend validation.

### 3. Rate Limit Counter (In-Memory)

Not persisted. Lives in `backend/services/rate_limiter.py` as module-level state.

| Entry | Type | Description |
|-------|------|-------------|
| Key | string | User email |
| Window: minute | list[datetime] | Timestamps of requests in the last 60 seconds |
| Window: day | list[datetime] | Timestamps of requests in the last 24 hours |

Pruned on every check: remove entries older than the window. Reject if count ≥ limit.

## State Transitions

### Toggle State

```
OFF ───(admin enables)──→ ON ───(admin disables)──→ OFF
 │                          │
 │  (default)               │
 ▼                          ▼
 AI hidden                  AI visible
 on Add WO screen           on Add WO screen
 Server refuses autofill    Server accepts autofill
```

### Autofill Request Flow

```
Client: POST /ai/autofill-work-order
  │
  ├─ ❌ Auth check fails → 401 Unauthorized
  │
  ├─ ❌ Toggle OFF → 403 "AI Work Order feature is disabled"
  │
  ├─ ❌ Rate limit exceeded → 429 "Too many requests. Try again in {retry_after}s"
  │
  ├─ ❌ Validation fails (length) → 422 "Description must be between 20 and 500 characters"
  │
  ├─ ❌ AI generation fails (all providers) → 502/503 error
  │
  └─ ✅ Success → 200 with Work Order Draft Suggestion JSON
```

### Frontend Overwrite Flow

```
AI response received
  │
  ├─ Apply all non-conflicting (empty-field) fills immediately
  │
  ├─ Any conflicting fields? (user already typed a value)
  │   ├─ YES → Show AiOverwriteDialog with per-field radios
  │   │        ├─ User taps "Apply" → overwrite selected fields
  │   │        └─ User cancels → keep all originals, preserve empty-field fills
  │   └─ NO → done, no dialog needed
  │
  └─ Done
```

## Validation Rules

| Rule | Scope | Details |
|------|-------|---------|
| Toggle default OFF | DB | `ai_work_order_enabled` seeds as `'false'` |
| Toggle admin-only | Backend | Email verified as `user_type='admin'` before allowing PUT |
| Toggle fresh fetch | Frontend | `_aiWorkOrderEnabled` fetched in `initState()`, default `false` on failure |
| Description min length | Backend | ≥ 20 characters, validated before AI call |
| Description max length | Backend | ≤ 500 characters, validated before AI call |
| Rate limit minute | Backend | ≤ 10 requests per user per rolling 60 seconds |
| Rate limit day | Backend | ≤ 100 requests per user per rolling 24 hours |
| AI value validation | Frontend | Dropdown/priority values validated against known options; unknown values dropped |
| Auth required | Backend | User email must be present and valid |