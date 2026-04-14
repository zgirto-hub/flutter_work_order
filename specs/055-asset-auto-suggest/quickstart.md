# Quickstart: Auto-Suggest Asset Registry Additions (055)

**Branch**: `055-asset-auto-suggest`

## Prerequisites

- Asset Registry (spec 053) deployed and functional
- Pattern alerts exist in the database (run a full scan if needed)
- Backend running, Flutter web dev server running
- Admin user account

## Setup Steps

### 1. Deploy Backend

Pull latest and restart:
```bash
cd ~/Development/flutter_work_order && git pull
sudo systemctl restart document_server.service
```

No migration needed — this feature uses existing tables only.

### 2. Verify Suggestions Endpoint

```bash
curl -s "http://localhost:8000/api/asset-registry/suggestions?user_email=salah@admin.com" | python3 -m json.tool
```

Should return a JSON object with `suggestions` array containing unregistered equipment with 2+ alerts.

### 3. Test Full Flow

1. **View suggestions**: Open Asset Registry screen → Suggestions section at the top shows unregistered equipment
2. **Accept**: Tap "Add" on a suggestion → Add Asset form opens with name pre-filled → Save → Suggestion disappears
3. **Dismiss**: Tap "Dismiss" on a noisy suggestion → It disappears and doesn't return
4. **Verify registered assets excluded**: Equipment already in the registry should NOT appear in suggestions
5. **Verify threshold**: Equipment with only 1 alert should NOT appear

### 4. Edge Case Testing

- Delete an asset from the registry → its equipment_id should reappear in suggestions (if 2+ alerts and not dismissed)
- Dismiss an equipment_id → create new alerts for it → should still NOT appear in suggestions

## Key Files

| Layer | File | Purpose |
|-------|------|---------|
| Backend | `backend/routers/asset_registry.py` | Suggestions + dismiss endpoints |
| Frontend service | `frontend/lib/services/asset_service.dart` | fetchSuggestions() + dismissSuggestion() |
| Frontend screen | `frontend/lib/screens/admin/asset_registry_screen.dart` | Suggestions section UI |
| Frontend screen | `frontend/lib/screens/admin/asset_edit_screen.dart` | Pre-filled form from suggestion |
