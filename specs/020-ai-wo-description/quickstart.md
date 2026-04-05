# Quickstart: AI-Assisted Work Order Description

**Feature**: 020-ai-wo-description

## Prerequisites

- Ollama installed and running on the Linux server at `http://localhost:11434`
- Gemma 4 E2B model pulled: `ollama pull gemma4:e2b`
- Backend FastAPI server running
- Flutter frontend running (web)

## Implementation Order

### Phase 1: Backend Endpoint

1. Create `backend/routers/ai_assist.py`:
   - Define `router = APIRouter()`
   - Define Pydantic model `AiSuggestRequest` with `title` (str), `location` (Optional[str]), `type` (Optional[str])
   - Implement `POST /ai/suggest` endpoint
   - Use `httpx.AsyncClient` with 60s timeout to call `http://localhost:11434/api/generate`
   - Build prompt from title + optional location/type context
   - Strip preamble from response
   - Return `{"description": "..."}` on success
   - Return 503 on connection/timeout errors, 502 on empty/bad model response

2. Register router in `backend/main.py`:
   - Add `ai_assist` to the router import line
   - Add `app.include_router(ai_assist.router, prefix="/api")`

### Phase 2: Flutter Service

3. Create `frontend/lib/services/ai_assist_service.dart`:
   - Stateless class `AiAssistService`
   - Method `Future<String> suggestDescription({required String title, String? location, String? type})`
   - POST to `${AppConfig.baseUrl}/ai/suggest`
   - Parse `description` from JSON response
   - Throw descriptive exceptions for 503 (service unavailable), 502 (model error), other errors
   - 65-second client-side timeout

### Phase 3: Flutter UI

4. Modify `frontend/lib/screens/Work_Orders/add_work_order.dart`:
   - Add `_aiLoading` state variable (bool, default false)
   - Add `AiAssistService` instance
   - Add Suggest button (`TextButton.icon`) near description field
     - Hidden when `!canEdit || !_roleLoaded`
     - Disabled when `titleController.text.trim().isEmpty || _aiLoading`
     - Shows spinner when `_aiLoading`
   - Implement `_suggestDescription()` method:
     - Set `_aiLoading = true`
     - Call `AiAssistService.suggestDescription()`
     - If description field empty: set text directly
     - If description field has text: show bottom sheet with Replace/Dismiss
     - On error: show floating SnackBar with `AppColors.dangerText`
     - Set `_aiLoading = false` in finally block

## Verification

1. **Backend only**: `curl -X POST http://localhost:8000/api/ai/suggest -H "Content-Type: application/json" -d '{"title":"Broken AC in Room 101","location":"Building A","type":"HVAC"}'`
2. **Error case**: Stop Ollama, repeat curl → expect 503
3. **Frontend**: Create new work order, fill title, tap Suggest → description populates
4. **Replace flow**: Open existing work order with description, tap Suggest → bottom sheet appears
