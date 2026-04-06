# Quickstart: 027-ai-document-expert

## Prerequisites

- Ollama running locally with `gemma4:e2b` model loaded
- Backend server running (`uvicorn`)
- Frontend dev server running (`flutter run -d chrome`)

## Files to Modify

### Backend (1 file)
- `backend/routers/ai_assist.py` — add `POST /ai/document-expert` endpoint + `GET /ai/health` + request models + prompt builder

### Frontend (3 files)
- `frontend/lib/services/ai_assist_service.dart` — add `documentExpert()` and `checkAiHealth()` methods
- `frontend/lib/widgets/ai_document_expert_widget.dart` — **new file** — collapsible AI panel widget
- `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart` — embed `AiDocumentExpertWidget` below the editor

## Implementation Order

1. Backend endpoint + health check
2. Frontend service methods
3. AI panel widget
4. Integration into letter form

## Testing

- Verify Ollama is running: `curl http://localhost:11434/api/tags`
- Test endpoint: `curl -X POST http://localhost:8000/api/ai/document-expert -H "Content-Type: application/json" -d '{"action":"improve","html_content":"<p>نص تجريبي</p>","target_language":"ar"}'`
- Test health: `curl http://localhost:8000/api/ai/health`
