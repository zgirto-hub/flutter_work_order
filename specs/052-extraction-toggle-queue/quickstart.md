# Quickstart: Entity Extraction Admin Toggle & AI Priority Queue

**Branch**: `052-extraction-toggle-queue` | **Date**: 2026-04-13

## Prerequisites

- Spec 049 (entity extraction) merged and functional
- Supabase CLI or direct SQL access for migration
- Ollama running locally with `gemma4:e2b` model
- Flutter dev environment configured

## Setup Steps

1. **Apply migration**: Run `supabase/migrations/20260413300000_create_system_settings.sql` to create the `system_settings` table and seed the extraction toggle.

2. **Restart backend**: The FastAPI lifespan now starts the queue worker on boot. After pulling the code changes, restart the backend service.

3. **Verify queue**: Check backend logs for `[ai_queue] Worker started` on startup.

4. **Test toggle**: 
   - Open Admin Settings in the Flutter app
   - Toggle "Entity Extraction" ON
   - Create a work order — check backend logs for `[ai_queue] Processing LOW priority job`
   - Toggle OFF — next WO save should NOT log extraction

## Key Files Changed

| File | Change |
| ---- | ------ |
| `backend/services/ai_queue.py` | NEW: Priority queue, worker, submit functions |
| `backend/services/ollama_generator.py` | Modified: generate() submits to queue |
| `backend/services/ollama_embedder.py` | Modified: embed_single()/embed_many() submit to queue |
| `backend/main.py` | Modified: lifespan starts queue worker |
| `backend/routers/work_orders.py` | Modified: toggle check before extraction |
| `backend/routers/ai_search.py` | Modified: use generate() instead of direct httpx |
| `backend/routers/ai_insights.py` | Modified: use generate() instead of direct httpx |
| `backend/routers/ai_assist.py` | Modified: use generate() instead of direct httpx |
| `backend/routers/settings.py` | NEW: GET/PUT /api/settings/{key} |
| `frontend/lib/screens/admin/settings_screen.dart` | NEW: Admin settings with extraction toggle |
| `frontend/lib/services/settings_service.dart` | NEW: Settings API client |
| `supabase/migrations/20260413300000_create_system_settings.sql` | NEW: system_settings table |

## Verification Checklist

- [ ] Backend starts without errors, logs `[ai_queue] Worker started`
- [ ] Toggle defaults to OFF — WO save does not trigger extraction
- [ ] Toggle ON — WO save triggers extraction via queue (visible in logs)
- [ ] During extraction, AI search responds without waiting behind extraction jobs
- [ ] Toggle OFF mid-queue — already-queued jobs complete, no new ones accepted
- [ ] All existing AI features (search, insights, assistant, manuals) work through queue with no behavior change
