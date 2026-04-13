# Quickstart: Pattern Rules Engine

**Branch**: `051-pattern-rules-engine`

## Prerequisites

- Backend running (FastAPI on Uvicorn)
- Supabase PostgreSQL accessible
- Existing `work_order_entities` table populated (spec 049)
- `entity_extractor.py` functional
- Admin user account

## Setup Steps

1. **Apply migration**:
   ```bash
   # Apply the pattern engine migration to Supabase
   # File: supabase/migrations/20260413200000_create_pattern_engine.sql
   ```

2. **Restart backend**:
   ```bash
   sudo systemctl restart document_server.service
   ```
   On startup, the pattern engine seeds 6 built-in rules if `pattern_rules` table is empty.

3. **Verify seeding**:
   ```bash
   curl -H "Authorization: Bearer $TOKEN" https://zorin.taila92fe8.ts.net/api/patterns/rules
   ```
   Should return 6 rules.

4. **Test triggered evaluation**:
   - Extract entities for a work order that matches a rule pattern
   - Check alerts: `GET /api/patterns/alerts?status=new`

5. **Test full scan**:
   ```bash
   curl -X POST -H "Authorization: Bearer $TOKEN" https://zorin.taila92fe8.ts.net/api/patterns/scan
   ```

6. **Frontend**:
   - Log in as admin
   - Navigate to "Ask the AI" screen
   - Verify 5 tabs visible: Chat, Knowledge, Review Queue, Rules, Alerts

## Key Files

| Layer | File | Purpose |
|-------|------|---------|
| Migration | `supabase/migrations/20260413200000_create_pattern_engine.sql` | Tables + indexes |
| Backend | `backend/services/pattern_engine.py` | Rule evaluation engine |
| Backend | `backend/routers/patterns.py` | API endpoints |
| Backend | `backend/services/entity_extractor.py` | Modified: hooks pattern eval |
| Frontend | `frontend/lib/models/pattern_rule.dart` | Rule model |
| Frontend | `frontend/lib/models/pattern_alert.dart` | Alert model |
| Frontend | `frontend/lib/services/pattern_service.dart` | API client |
| Frontend | `frontend/lib/screens/manual_assistant/rules_tab.dart` | Rules management |
| Frontend | `frontend/lib/screens/manual_assistant/alerts_tab.dart` | Alert management |
| Frontend | `frontend/lib/screens/manual_assistant/rule_edit_screen.dart` | Rule create/edit |
| Frontend | `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart` | Tab wiring |
