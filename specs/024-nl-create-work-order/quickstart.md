# Quickstart: Natural Language Work Order Creation

**Branch**: `024-nl-create-work-order` | **Date**: 2026-04-06

## Prerequisites

- Flutter SDK 3.x installed
- Python 3 with FastAPI backend running
- Ollama running locally on the server (`http://localhost:11434`) with `gemma4:e2b` model
- Chrome browser (for PWA testing)
- Network connectivity between frontend and backend

## Setup

1. **Backend** — no new dependencies needed (httpx already in requirements.txt):
   ```bash
   cd backend
   # Verify Ollama is running
   curl http://localhost:11434/api/tags
   # Restart backend if needed
   uvicorn main:app --reload
   ```

2. **Frontend** — no new dependencies needed:
   ```bash
   cd frontend
   flutter run -d chrome
   ```

## Testing the Feature

### Test 1: Basic English Input
1. Navigate to **Add Work Order** screen
2. At the top, find the **"Describe your work order..."** input card
3. Type: `broken AC unit in room 205, urgent`
4. Select **EN** language chip
5. Tap **Generate**
6. Verify form fields are auto-filled:
   - Title: something like "Broken AC Unit"
   - Description: expanded professional text
   - Location: "Room 205"
   - Type: "Technical"
7. Verify auto-filled fields are briefly highlighted
8. Edit any field if needed, then submit

### Test 2: Arabic Input
1. Type an Arabic description: `تسريب مياه في الحمام الطابق الثاني`
2. Select **AR** language chip
3. Tap **Generate**
4. Verify fields are filled with Arabic text

### Test 3: Voice Input
1. Tap the **mic button** on the NL input area
2. Speak: "make a new work order regarding clearing CADAS-IMS operator queue"
3. Wait for transcription to appear
4. Tap **Generate**
5. Verify form fields are auto-filled

### Test 4: Abbreviation Expansion
1. Type: `fix elev stuck 3rd flr bldg B asap`
2. Tap **Generate**
3. Verify description is expanded to professional language

### Test 5: Error Handling
1. Stop the Ollama service
2. Type any description and tap **Generate**
3. Verify a user-friendly error message appears
4. Verify the form is still usable for manual entry

### Test 6: Edit Screen Exclusion
1. Open an existing work order (Edit mode)
2. Verify the NL input card is NOT shown

## Key Files

| File | Purpose |
|------|---------|
| `backend/routers/ai_assist.py` | New `POST /ai/parse-work-order` endpoint |
| `frontend/lib/services/ai_assist_service.dart` | New `parseWorkOrder()` method |
| `frontend/lib/screens/Work_Orders/add_work_order.dart` | NL input card, Generate button, auto-fill logic |

## Backend Endpoint Test (curl)

```bash
curl -X POST http://localhost:8000/ai/parse-work-order \
  -H "Content-Type: application/json" \
  -d '{
    "text": "broken AC unit in room 205, urgent",
    "language": "en",
    "departments": ["General", "IT", "Maintenance"],
    "types": ["Technical", "Inspection", "Other"],
    "statuses": ["Pending", "In Progress"]
  }'
```

Expected response:
```json
{
  "title": "Broken AC Unit",
  "description": "Air conditioning unit is malfunctioning in Room 205...",
  "location": "Room 205",
  "type": "Technical",
  "department": "Maintenance",
  "status": "Pending"
}
```
