# Quickstart: Shared Systems Table

**Branch**: `056-shared-systems-table`

## What this feature does

Replaces hardcoded system name lists (ALLOWED_SYSTEMS in Python, systemSuggestions in Dart) and free-text system columns with a single `systems` database table. All system references use FK to this table. Administrators can add, rename, and retire systems from a new admin screen without code deploys.

## Key files to touch

### Phase 1 — Database Migration
- `supabase/migrations/YYYYMMDDHHMMSS_create_systems_table.sql` — NEW: creates `systems` table, seeds 24 rows, adds `system_id` FK to `asset_system_links` and `system_status_reports`, drops old text columns

### Phase 2 — Backend
- `backend/routers/systems.py` — NEW: CRUD router for systems (GET, POST, PATCH, retire, activate)
- `backend/routers/system_status.py` — MODIFY: remove ALLOWED_SYSTEMS constant, query `systems` table instead
- `backend/routers/ai_insights.py` — MODIFY: remove ALLOWED_SYSTEMS constant, query `systems` table instead
- `backend/routers/asset_registry.py` — MODIFY: update `get_domain_knowledge_block()` to JOIN through `system_id`
- `backend/main.py` — MODIFY: register the new systems router

### Phase 3 — Frontend: Asset Registry
- `frontend/lib/models/system.dart` — NEW: System model class
- `frontend/lib/services/systems_service.dart` — NEW: SystemsService calling `/api/systems`
- `frontend/lib/models/asset.dart` — MODIFY: remove `systemSuggestions` constant
- `frontend/lib/screens/admin/asset_edit_screen.dart` — MODIFY: replace Autocomplete with searchable dropdown from SystemsService

### Phase 4 — Frontend: Admin UI
- `frontend/lib/screens/admin/systems_screen.dart` — NEW: Systems management screen (list, add, rename, retire)
- `frontend/lib/screens/settings_page.dart` — MODIFY: add "Systems" SettingsRow in admin section

## Migration sequence

1. Apply SQL migration (creates table, seeds data, migrates FKs)
2. Deploy backend (new router + modified routers)
3. Deploy frontend (new service + modified screens)

## Testing checklist

- [ ] Migration: all 24 systems seeded correctly
- [ ] Migration: all existing `system_status_reports` linked by `system_id`
- [ ] Migration: all existing `asset_system_links` linked by `system_id`
- [ ] Migration: unknown free-text values created with `needs_review=true`
- [ ] GET /api/systems returns 24 active systems in sort order
- [ ] POST /api/systems creates a new system (admin only)
- [ ] PATCH /api/systems/{id} renames a system
- [ ] PATCH /api/systems/{id}/retire soft-deletes a system
- [ ] System Status screen shows systems from DB, not hardcoded list
- [ ] Asset Registry system selector shows all active systems
- [ ] Asset Registry prevents free-text system entry
- [ ] Admin Systems screen: add, rename, retire all work
- [ ] Retired system hidden from dropdowns but visible in history
