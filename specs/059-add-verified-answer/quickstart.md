# Quickstart: Add Verified Answer — Manual Entry

## Prerequisites

- Supabase database accessible
- Ollama running with `nomic-embed-text` model loaded
- Backend server running (`document_server.service`)
- Admin user account

## Implementation Order

```
1. Migration     → make rating_id nullable
2. Backend       → service function + router endpoint (can verify with curl)
3. Flutter svc   → createVerifiedAnswer() method
4. Flutter UI    → FAB + dialog in verified_answers_tab.dart
```

## Quick Verification

### After Step 1 (Migration)
```sql
-- Should succeed:
INSERT INTO validated_qa (question_text, validated_answer, question_embedding, validated_by)
VALUES ('test', 'test', '[' || array_to_string(array_fill(0::float, ARRAY[768]), ',') || ']', 'test@test.com');
-- Clean up:
DELETE FROM validated_qa WHERE question_text = 'test' AND validated_by = 'test@test.com';
```

### After Step 2 (Backend)
```bash
curl -X POST http://localhost:8000/api/manuals/verified-answers \
  -H "Content-Type: application/json" \
  -d '{"question_text":"What is the ILS frequency?","validated_answer":"The ILS frequency is 110.3 MHz.","editor_email":"admin@example.com"}'
```
Expected: 200 with JSON containing `id`, `question_text`, `validated_answer`.

### After Step 4 (Flutter UI)
1. Open Manual Assistant → Verified Answers tab
2. Tap FAB (bottom-right)
3. Fill in question and answer
4. Tap "Add"
5. Verify entry appears at top of list
