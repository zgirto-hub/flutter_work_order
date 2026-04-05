# Quickstart: AI-Powered Analytics & Insights

**Feature**: 021-ai-analytics-insights

## What This Feature Does

Adds an AI-powered insights card to the admin/supervisor dashboard that generates natural language summaries (3-5 bullet points) of work order statistics and system status health. Supports English and Arabic output.

## Key Files

### Backend (new)
- `backend/routers/ai_insights.py` — endpoint + data aggregation + prompt construction

### Backend (modified)
- `backend/main.py` — register new router

### Frontend (new)
- `frontend/lib/services/ai_insights_service.dart` — HTTP service for insights endpoint
- `frontend/lib/features/analytics/ai_insights_card.dart` — dashboard card widget

### Frontend (modified)
- `frontend/lib/screens/dashboard_screen.dart` — integrate insights card

### Reference (do not modify)
- `backend/routers/ai_assist.py` — existing Ollama integration pattern
- `backend/routers/system_status.py` — data aggregation pattern (uptime report)
- `frontend/lib/services/ai_assist_service.dart` — existing AI service pattern
- `frontend/lib/widgets/form_fields.dart` — RTL detection pattern (lines 50-64)

## API Endpoint

```
POST /api/ai/insights?email={email}&user_role={role}
Body: { "insight_type": "overview|system_status|trends", "date_range_days": 30, "language": "en|ar" }
Response: { "insight": "• bullet 1\n• bullet 2...", "generated_at": "...", "data_summary": {...} }
```

## Testing

1. **Backend**: `curl -X POST "http://localhost:8000/api/ai/insights?email=admin@test.com&user_role=admin" -H "Content-Type: application/json" -d '{"insight_type":"overview"}'`
2. **Role guard**: Same curl with `user_role=reporter` → expect 403
3. **Arabic**: Add `"language": "ar"` to request body → expect Arabic bullet points
4. **Frontend**: Log in as admin, navigate to dashboard, verify insights card appears with type selector
5. **Error handling**: Stop Ollama, request insight → expect "AI service unavailable" message

## Architecture Notes

- No new database tables — reads from existing `work_orders`, `system_status_reports`, `departments`
- Data is aggregated server-side into compact stats before feeding to Ollama prompt
- Follows existing patterns: Ollama call from `ai_assist.py`, aggregation from `system_status.py`
- Activity logging via `log_activity()` for audit compliance
