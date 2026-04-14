# Quickstart: Verified Answers Admin Tab

## What this feature does

Adds a "Verified" admin tab to the AI Assistant screen showing all validated Q&A pairs with search, edit, and delete capabilities.

## Implementation order

1. **Backend service** — `validated_qa_service.py`: add `get_all_verified_answers()`, `update_verified_answer()`, `delete_verified_answer()`
2. **Backend router** — `manuals.py`: add GET, PUT, DELETE `/manuals/verified-answers` endpoints
3. **Frontend service** — `manual_assistant_service.dart`: add `getVerifiedAnswers()`, `updateVerifiedAnswer()`, `deleteVerifiedAnswer()`
4. **Frontend tab** — new `verified_answers_tab.dart`: list + search + edit dialog + delete confirmation
5. **Wire tab** — `manual_assistant_screen.dart`: TabController length 5→6, add tab + child

## Key patterns to follow

- **Admin check**: `_admin_check(user_email)` at `manuals.py:517`
- **Error handling**: Catch specific exceptions → HTTPException with detail dicts
- **Audit logging**: `log_activity(email, "manual", "action_verb", ...)` fire-and-forget
- **Embedding**: `await embed_single(text)` → format as `"[" + ",".join(...) + "]"`
- **Tab widget**: Follow `review_queue_tab.dart` — StatefulWidget + AutomaticKeepAliveClientMixin

## Test manually

```bash
# 1. List verified answers
curl "http://localhost:8000/manuals/verified-answers?user_email=admin@example.com"

# 2. Edit a verified answer
curl -X PUT "http://localhost:8000/manuals/verified-answers/<uuid>" \
  -H "Content-Type: application/json" \
  -d '{"validated_answer": "Updated answer text", "editor_email": "admin@example.com"}'

# 3. Delete a verified answer
curl -X DELETE "http://localhost:8000/manuals/verified-answers/<uuid>?editor_email=admin@example.com"
```

## Flutter: verify in browser

1. Log in as admin
2. Navigate to "Ask the AI" screen
3. Confirm 6 tabs visible (Chat, Knowledge, Review, Rules, Alerts, Verified)
4. Tap "Verified" → list loads
5. Search → filters by question text
6. Tap entry → edit dialog → save → list updates
7. Delete entry → confirmation → removed from list
8. Log in as non-admin → confirm only 2 tabs visible
