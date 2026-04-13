# Quickstart: Work Order Entity Extraction

**Date**: 2026-04-13 | **Branch**: `049-wo-entity-extraction`

## Prerequisites

- Backend server running (`document_server.service`)
- Ollama running on localhost:11434 with `gemma4:e2b` model loaded
- Supabase database accessible
- pgvector extension enabled in Supabase

## Implementation Order

```
Phase 1: Database migration
    ↓
Phase 2: Extraction prompt design
    ↓
Phase 3: Extraction service (entity_extractor.py)
    ↓
Phase 4: Background task integration (modify work_orders.py)
    ↓
Phase 5: Retry and error handling (in entity_extractor.py)
    ↓
Phase 6: Manual trigger endpoint (in work_orders.py)
    ↓
Phase 7: Bulk backfill endpoint (in work_orders.py)
    ↓
Phase 8: Validation (equipment_id check in entity_extractor.py)
```

## Files to Create/Modify

| Action | File | Purpose |
| ------ | ---- | ------- |
| CREATE | `supabase/migrations/20260413100000_create_entity_extraction.sql` | Database tables |
| CREATE | `backend/services/entity_extractor.py` | Extraction logic, prompt, JSON cleaning |
| MODIFY | `backend/routers/work_orders.py` | BackgroundTasks + new endpoints |

## Testing

1. **Migration**: Apply migration via Supabase dashboard or CLI, verify tables exist
2. **Extraction service**: Call manual trigger endpoint with a known work order ID
3. **Background task**: Create a work order via API, wait 30s, check `work_order_entities` table
4. **Failure handling**: Stop Ollama, trigger extraction, verify `extraction_failures` entry
5. **Backfill**: Run backfill endpoint, monitor batch processing via server logs
6. **Validation**: Create a work order with vague text (no equipment mentioned), verify rejection logged

## Key Patterns to Follow

- **Ollama calls**: Use existing `ollama_generator.generate(prompt, model="gemma4:e2b")`
- **Supabase writes**: Use `supabase.table("name").upsert({...}).execute()`
- **Admin check**: Use existing `_ensure_admin(user_email)` pattern from work_orders.py
- **Activity logging**: Use existing `log_activity()` from `backend/utils/activity.py`
- **Error handling**: Catch all exceptions in background tasks, log to both stderr and failure table
