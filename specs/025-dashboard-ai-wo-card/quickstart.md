# Quickstart: Dashboard AI Work Order Card with Draft Preview

**Branch**: `025-dashboard-ai-wo-card` | **Date**: 2026-04-06

## Prerequisites

- Flutter SDK 3.x installed
- Backend running with Ollama and `gemma4:e2b` model (for AI parse endpoint)
- Chrome browser for PWA testing
- Network connectivity

## Setup

No new dependencies needed. Run the existing app:

```bash
cd frontend
flutter run -d chrome
```

## Testing the Feature

### Test 1: Generate and Quick-Create from Dashboard
1. Open the app → land on **Dashboard**
2. Find the **"AI Work Order"** card (below stats, above Quick Actions)
3. Type: `broken AC unit in room 205, urgent`
4. Tap **Generate**
5. Verify a bottom sheet slides up with draft fields:
   - Title: "Broken AC Unit" (or similar)
   - Description: expanded professional text
   - Location: "Room 205"
   - Type: "Technical"
6. Tap **Create**
7. Verify: sheet closes, input clears, success SnackBar appears, dashboard stats refresh

### Test 2: Edit Flow
1. Type a description and tap **Generate**
2. In the draft bottom sheet, tap **Edit**
3. Verify: Add Work Order screen opens with all fields pre-filled
4. Modify any field, submit
5. Verify work order is created with modifications

### Test 3: Voice Dictation on Dashboard
1. Tap the **mic button** on the Dashboard AI card
2. Speak: "make a work order for clearing CADAS-IMS operator queue"
3. Verify transcribed text appears in input
4. Tap **Generate**
5. Verify draft bottom sheet appears

### Test 4: Arabic Support
1. Select **AR** language chip
2. Type Arabic text
3. Tap **Generate**
4. Verify draft shows Arabic content

### Test 5: Error Handling
1. Stop the backend/Ollama service
2. Type a description and tap **Generate**
3. Verify error SnackBar appears
4. Verify the form is still usable

### Test 6: Shared Widget Parity
1. Open Dashboard → verify NL card looks correct
2. Navigate to Add Work Order → verify NL card looks identical
3. Generate from Add Work Order → verify auto-fill still works as before

### Test 7: Empty Title Prevention
1. Generate a draft where AI returns no title
2. Verify the "Create" button is disabled in the bottom sheet

## Key Files

| File | Purpose |
|------|---------|
| `frontend/lib/widgets/nl_input_card.dart` | NEW: shared NL input widget |
| `frontend/lib/widgets/ai_draft_bottom_sheet.dart` | NEW: draft preview bottom sheet |
| `frontend/lib/screens/dashboard_screen.dart` | Modified: AI card + generation logic |
| `frontend/lib/screens/Work_Orders/add_work_order.dart` | Modified: prefill params + use shared widget |
