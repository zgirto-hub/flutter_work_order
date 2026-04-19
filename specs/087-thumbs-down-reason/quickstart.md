# Quickstart — Thumbs-Down Reason & Comment

A step-by-step walkthrough to stand up the feature locally and verify the acceptance scenarios end-to-end. Assumes a working dev setup of the existing repo (Supabase project linked, FastAPI venv, Flutter toolchain).

---

## 1. Apply the migration

```bash
# From repo root
cat supabase/migrations/20260419000000_add_rating_feedback.sql
# Expect: ALTER TABLE answer_ratings ADD COLUMN feedback_reason ..., feedback_comment ...

# Apply (any of: Supabase CLI, SQL editor, or remote push)
supabase db push        # if using Supabase CLI locally
# — OR —
# paste the file into the Supabase Studio SQL editor and run
```

Verify:

```sql
\d answer_ratings
-- feedback_reason | text    | with CHECK constraint
-- feedback_comment | text   | nullable
```

## 2. Update backend dependencies (none)

No new Python packages. If the backend isn't already running:

```bash
cd backend
source venv/bin/activate       # or your activation path
pip install -r requirements.txt  # idempotent, for safety
uvicorn main:app --reload
```

## 3. Smoke-test the PATCH endpoint

```bash
# 1. Create a thumbs-down rating using the existing endpoint
curl -X POST http://localhost:8000/manuals/rate-answer \
  -H 'Content-Type: application/json' \
  -d '{
    "question_text": "how to reset the fire alarm panel?",
    "answer_text": "Hold RESET for 3s on the main panel keypad.",
    "source_chunks": [],
    "rating": "negative",
    "rater_email": "tech1@example.com"
  }'
# → Response: { "id": "<UUID>", "status": "saved" }
export RATING_ID=<the UUID from above>

# 2. Attach reason + comment via the new endpoint
curl -X PATCH http://localhost:8000/manuals/ratings/$RATING_ID/feedback \
  -H 'Content-Type: application/json' \
  -d '{
    "feedback_reason": "outdated",
    "feedback_comment": "The 2022 revision was superseded in 2024.",
    "user_email": "tech1@example.com"
  }'
# → 200 OK { "status": "saved", "rating_id": "<UUID>", ... }

# 3. Ownership rejection
curl -X PATCH http://localhost:8000/manuals/ratings/$RATING_ID/feedback \
  -H 'Content-Type: application/json' \
  -d '{
    "feedback_reason": "inaccurate",
    "user_email": "attacker@example.com"
  }'
# → 403 { "detail": { "error": "not_owner" } }

# 4. Invalid reason
curl -X PATCH http://localhost:8000/manuals/ratings/$RATING_ID/feedback \
  -H 'Content-Type: application/json' \
  -d '{"feedback_reason": "wharrgarbl", "user_email": "tech1@example.com"}'
# → 422 (Pydantic enum validation)

# 5. Over-cap comment
curl -X PATCH http://localhost:8000/manuals/ratings/$RATING_ID/feedback \
  -H 'Content-Type: application/json' \
  -d "{
    \"feedback_reason\": \"unclear\",
    \"feedback_comment\": \"$(python -c 'print("a"*2001)')\",
    \"user_email\": \"tech1@example.com\"
  }"
# → 422 (max_length)
```

Verify activity log:

```sql
SELECT user_email, category, action, target_label, detail, created_at
FROM user_activity_log
WHERE action = 'rated_answer_feedback'
ORDER BY created_at DESC
LIMIT 5;
```

## 4. Smoke-test the Review-tab query

```bash
curl 'http://localhost:8000/manuals/flagged-answers?user_email=admin@example.com'
```

Each returned item should now include `feedback_reason` and `feedback_comment` fields (null for legacy/skipped rows).

## 5. Run the Flutter frontend

```bash
cd frontend
flutter run -d chrome
```

### Scenario A — Happy path (US1)

1. Open the AI assistant, ask any question.
2. When an answer arrives, click the thumbs-down icon.
   - ✅ Thumbs-down icon fills immediately (< 2 s). Rating saved.
   - ✅ Bottom sheet titled "What went wrong?" slides up.
3. Tap the "Outdated" chip, type a short note in the comment field, tap **Save**.
   - ✅ Sheet dismisses, "Saved" toast appears.
4. Sign in as admin → Open Train AI → Review tab.
5. Locate the row.
   - ✅ Amber "Outdated" chip visible next to the question.
   - ✅ First ~100 chars of comment shown as muted italic preview below the question.
6. Expand the card.
   - ✅ Full comment visible.

### Scenario B — Skip path (US2)

1. Thumbs-down a different answer.
2. Swipe the bottom sheet down, or tap **Skip**.
   - ✅ Sheet closes. No toast. Rating remains saved.
3. Admin side → Review tab.
   - ✅ Row appears with muted grey **"No reason given"** chip.

### Scenario C — Un-rate cleanup (US3)

1. On an answer you previously thumbs-downed with a reason/comment, tap the filled thumbs-down icon again.
   - ✅ Rating removed; thumb returns to unrated state.
2. Admin side → Review tab.
   - ✅ That row is gone entirely (no orphan reason/comment).

### Scenario D — Admin triage at list level (US4)

1. Seed three ratings with different reasons (e.g., via curl as in step 3 above, or via repeated UI).
2. Admin Review tab.
   - ✅ Each card shows its respective colored chip inline.
   - ✅ Admin can quickly skim the list by chip color and pick which to tackle first.

### Scenario E — One-shot dismissal (clarification Q2)

1. Thumbs-down an answer, dismiss the sheet without saving.
2. Without un-rating first, look for any way to reopen the sheet (long-press, inline link, etc.).
   - ✅ There is no such affordance. The only recovery path is un-rate + re-rate.

## 6. Run backend tests

```bash
cd backend
pytest tests/routers/test_manuals_rating_feedback.py -v
```

Expected coverage:

- Happy-path 200
- Ownership mismatch → 403
- Invalid reason → 422
- Over-cap comment → 422
- Rating does not exist → 404
- Positive rating ID → 400 (`not_negative_rating`)
- Activity log event emitted
- Idempotency (two back-to-back PATCHes produce consistent state)

## 7. Pre-commit checks

```bash
# Backend
cd backend && ruff check . && pytest

# Frontend
cd ../frontend && flutter analyze && flutter test
```

## 8. Deploy

Per project memory:

```bash
# On the server (Zorin OS), after deploying code changes that touch routes:
sudo systemctl restart document_server.service
```

Apply the migration on the remote Supabase project (same SQL as step 1, targeting production URL).

---

## Success check (maps to spec §Success Criteria)

| SC | Verified by |
|---|---|
| SC-001 | Scenario A step 2 timing (sub-2 s) |
| SC-002 | Scenario A step 5 (chip + preview visible after refresh) |
| SC-003 | Scenario D (list-level triage after >= 3 ratings) |
| SC-004 | curl step 3 (403 on non-owner attempt) |
| SC-005 | Any pre-spec rating row, rendered in the Review tab, shows "No reason given" without layout break |
| SC-006 | Approve/correct a row in the Review tab — same number of clicks, no regression |
