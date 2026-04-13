# Quickstart: Asset Registry (053)

**Branch**: `053-asset-registry`

## Prerequisites

- Backend running (`document_server.service` on Zorin or local `uvicorn`)
- Supabase database accessible
- Flutter web dev server (`flutter run -d chrome`)
- Admin user account

## Setup Steps

### 1. Apply Migration

```bash
# Apply the new migration to create assets + asset_system_links tables
# If using Supabase CLI:
supabase db push

# If applying manually:
psql -f supabase/migrations/20260414100000_create_asset_registry.sql
```

### 2. Restart Backend

```bash
sudo systemctl restart document_server.service
```

The new `asset_registry` router is auto-registered via `main.py`.

### 3. Verify

1. Log in as an Admin user
2. Navigate to Settings > Administration section
3. Tap "Asset Registry"
4. Add a test asset: name="TEST-01", type=workstation, location="Test Location"
5. Add a system link: CADAS-ATS, role=client
6. Verify the asset and link appear in the list

### 4. Test Extraction Integration

1. Ensure at least one asset exists in the registry
2. Create a work order mentioning the asset name (e.g., "TEST-01 not responding")
3. Wait for extraction to run (or trigger manually)
4. Check `work_order_entities` for the extracted record — it should reference the correct system

### 5. Test Alert Enrichment

1. If pattern alerts exist for a registered equipment_id, check the Alerts tab
2. Verify the alert card shows asset location and associated systems

## Key Files

| Layer | File | Purpose |
|-------|------|---------|
| Migration | `supabase/migrations/20260414100000_create_asset_registry.sql` | DB schema |
| Backend router | `backend/routers/asset_registry.py` | CRUD API |
| Backend service | `backend/services/entity_extractor.py` | Dynamic prompt |
| Backend service | `backend/services/pattern_engine.py` | Alert enrichment |
| Frontend model | `frontend/lib/models/asset.dart` | Data classes |
| Frontend service | `frontend/lib/services/asset_service.dart` | HTTP client |
| Frontend screen | `frontend/lib/screens/admin/asset_registry_screen.dart` | List view |
| Frontend screen | `frontend/lib/screens/admin/asset_edit_screen.dart` | Add/edit form |
| Frontend nav | `frontend/lib/screens/settings_page.dart` | Admin nav entry |
| Frontend widget | `frontend/lib/screens/manual_assistant/widgets/alert_card.dart` | Alert enrichment UI |
