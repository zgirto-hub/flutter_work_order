# Quickstart: Feedback Loop AI Assistant

**Branch**: `048-feedback-loop-ai-assistant` | **Date**: 2026-04-13

## Prerequisites

- Flutter 3.x + Dart 3.x
- Python 3.10 with FastAPI backend running
- Supabase (PostgreSQL) with pgvector extension enabled
- Ollama running with `nomic-embed-text` model loaded
- At least one manual uploaded to the manual assistant

## Setup

### 1. Apply Database Migration

```bash
# Apply the migration to create answer_ratings, validated_qa tables, and search RPC
supabase db push
# Or apply directly:
psql $DATABASE_URL -f supabase/migrations/20260413000000_create_feedback_loop.sql
```

### 2. Restart Backend

```bash
sudo systemctl restart document_server.service
```

### 3. Rebuild Frontend

```bash
cd frontend
flutter build web --release
# Deploy via existing deploy script
```

## Verification

### Test Rating Flow

1. Open Manual Assistant → Chat tab
2. Ask any question (e.g., "What is the engine oil change procedure?")
3. Wait for AI response
4. Tap the thumbs-down button beneath the answer
5. Verify the button shows selected state
6. Check database: `SELECT * FROM answer_ratings ORDER BY created_at DESC LIMIT 1;`

### Test Review Queue (Admin)

1. Log in as admin user
2. Open Manual Assistant
3. Verify 3 tabs visible: Chat, Knowledge, Review Queue
4. Open Review Queue tab
5. See the flagged answer from step above
6. Tap "Approve" or write a correction and tap "Save Correction"
7. Check database: `SELECT * FROM validated_qa ORDER BY created_at DESC LIMIT 1;`

### Test Validated Answer Reuse

1. After approving/correcting an answer in the review queue
2. Ask a semantically similar question in the Chat tab
3. If similarity >= 0.90: response should appear instantly with "Verified Answer" label
4. If similarity 0.75-0.90: response should be AI-generated but influenced by the validated answer

### Test Non-Admin Access

1. Log in as a non-admin user (technician/reporter)
2. Open Manual Assistant
3. Verify only 2 tabs visible: Chat, Knowledge (no Review Queue)

## Key Files

| File | Purpose |
|------|---------|
| `backend/services/validated_qa_service.py` | Rating CRUD, validated QA management, similarity search |
| `backend/routers/manuals.py` | New endpoints: rate-answer, flagged-answers, review-answer |
| `backend/services/manual_rag_service.py` | Validated QA check inserted before RAG pipeline |
| `frontend/lib/screens/manual_assistant/widgets/answer_card.dart` | Rating buttons UI |
| `frontend/lib/screens/manual_assistant/review_queue_tab.dart` | Admin review queue |
| `frontend/lib/services/manual_assistant_service.dart` | New API methods |
| `supabase/migrations/20260413000000_create_feedback_loop.sql` | Database schema |
