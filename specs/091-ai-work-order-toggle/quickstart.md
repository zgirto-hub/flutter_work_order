# Quickstart: AI Work Order Toggle (091)

## Prerequisites

- Backend running on `localhost:8000` (or production URL per `kIsProduction`)
- Supabase project with `app_settings` table migrated
- Flutter web app connected to same backend
- Ollama running locally (or Gemini API key configured) for AI generation

## Setup

### 1. Apply Migration

```bash
# The migration seeds ai_work_order_enabled = false into app_settings
# Apply via Supabase CLI or dashboard:
supabase db push
```

### 2. Verify Toggle is OFF

```bash
curl "http://localhost:8000/api/settings/ai-work-order?admin_email=admin@example.com"
# Expected: {"enabled": false, "updated_at": "..."}
```

### 3. Enable the Toggle (Admin)

```bash
curl -X PUT "http://localhost:8000/api/settings/ai-work-order?admin_email=admin@example.com" \
  -H "Content-Type: application/json" \
  -d '{"enabled": true}'
# Expected: {"enabled": true, "updated_at": "..."}
```

### 4. Test Autofill Endpoint

```bash
curl -X POST "http://localhost:8000/api/ai/autofill-work-order" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "AC unit in tower 3 is leaking water onto the floor, been getting worse since yesterday",
    "language": "en",
    "departments": ["Technical", "Inspection"],
    "types": ["Technical", "Inspection", "Other"],
    "statuses": ["Pending", "In Progress", "Closed"]
  }'
# Expected: {"title": "...", "description": "...", "priority": "...", ...}
```

### 5. Verify Server Refuses When Disabled

```bash
# Disable the toggle
curl -X PUT "http://localhost:8000/api/settings/ai-work-order?admin_email=admin@example.com" \
  -H "Content-Type: application/json" \
  -d '{"enabled": false}'

# Try autofill
curl -X POST "http://localhost:8000/api/ai/autofill-work-order" \
  -H "Content-Type: application/json" \
  -d '{"description": "Some description that is at least twenty characters", "language": "en"}'
# Expected: 403 {"detail": "AI Work Order feature is disabled"}
```

### 6. Verify Frontend

1. Open the app as an admin user
2. Go to Settings → find the "AI Features" section
3. Toggle "AI Work Order" ON
4. Navigate to Add Work Order → verify "AI Work Order" card is visible
5. Toggle OFF → navigate back to Add Work Order → verify AI card is hidden
6. Log in as a non-admin user → verify the "AI Features" section is not visible in Settings
7. (With toggle ON) As any user, Add Work Order → AI Work Order card → type description → Generate → verify form fields fill in