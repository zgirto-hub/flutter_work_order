# Quickstart — Delete Review/Rating from Ask-the-AI

A short, manual end-to-end verification for all three surfaces. Use after `/speckit.implement` completes to validate the feature in a running local or staging environment.

## Prerequisites

- Backend is running (systemd `document_server.service` or `uvicorn backend.main:app`).
- Frontend is running (`flutter run -d chrome` or deployed PWA).
- Two test accounts exist in `users`:
  - `tech@example.com` with `user_type = 'technician'` (or `reporter`).
  - `admin@example.com` with `user_type = 'admin'`.
- At least one manual is indexed so the AI assistant returns answers.

## Flow 1 — Technician undo (chat)

1. Sign in as `tech@example.com`.
2. Open **Ask the AI** → **Chat**.
3. Ask a question. Wait for the streamed answer.
4. Tap **thumbs-down** on the answer.
   - Expected: the thumb turns red. The first time (for this account) a snackbar reads "Tap the thumb again to remove your rating." — it auto-dismisses.
5. Tap the same **thumbs-down** again.
   - Expected: the thumb de-selects (grey). Snackbar: "Rating removed."
6. Sign in as `admin@example.com` in another tab/incognito session, open **Ask the AI** → **Review**.
   - Expected: the answer from step 3 is NOT in the review list.
7. Back as `tech@example.com`, rate a different answer **thumbs-up**.
   - Expected: no hint snackbar (one-time hint already consumed). Thumb turns blue.
8. Tap the **thumbs-up** again.
   - Expected: thumb de-selects. Snackbar: "Rating removed."
9. As admin, open **Train AI** → **From Real Usage**.
   - Expected: the Q&A from step 7 is not present (if it was the only positive rating for that Q&A).

## Flow 2 — Admin single-rating delete (Review tab)

1. As `tech@example.com`, rate a fresh AI answer **thumbs-down** and do NOT undo it.
2. Sign in as `admin@example.com`, open **Ask the AI** → **Review**.
   - Expected: the flagged answer is in the list. Note the "Needs Review" badge count.
3. On the flagged card, tap **Delete** (red).
   - Expected: confirmation dialog appears: "Delete rating? This thumbs-down will be removed and the answer will leave the review queue. The verified-answer cache (if any) is unaffected."
4. Tap **Delete** on the dialog.
   - Expected: card disappears from the list; "Needs Review" badge decrements by 1.
5. Reload the tab.
   - Expected: the answer does not reappear.

## Flow 3 — Admin permanent delete (Train AI → From Real Usage)

1. As two different tech accounts (or the same account with a small script inserting `answer_ratings`), produce at least 2 positive ratings on the same `(question_text, answer_text)` pair so a From-Real-Usage suggestion appears.
2. Sign in as `admin@example.com`, open **Ask the AI** → **Train AI** → **From Real Usage**.
   - Expected: the suggestion card is listed with its rating count (N ≥ 2).
3. Tap the card's **overflow menu** (three-dot icon), choose **Delete permanently**.
   - Expected: dialog: "Delete permanently? Permanently delete N positive ratings for this question? It will stop appearing here. Cannot be undone."
4. Tap **Delete permanently** on the dialog.
   - Expected: card disappears from the list.
5. Reload the tab.
   - Expected: the suggestion does not reappear.
6. Still as admin, open **Verified Answers** and search for the question.
   - Expected: if the Q&A was previously promoted to verified, it is STILL present (confirming the verified-answer cache survived).

## Verification — verified-cache preservation

To directly confirm the critical data rule in a database console (or via a read-only script):

```sql
-- Before: a rating that has a linked verified entry.
SELECT ar.id AS rating_id, vq.id AS validated_qa_id, vq.rating_id
FROM answer_ratings ar
JOIN validated_qa vq ON vq.rating_id = ar.id
LIMIT 5;

-- Run Flow 2 or Flow 3 against one of those rating_ids.

-- After:
SELECT id, rating_id FROM validated_qa WHERE id = '<validated_qa_id>';
-- rating_id column should be NULL (orphaned, but row present)
SELECT id FROM answer_ratings WHERE id = '<rating_id>';
-- zero rows
```

## Verification — audit trail

```sql
SELECT user_email, category, action, target_label, detail, created_at
FROM user_activity_log
WHERE category = 'manual'
  AND action IN ('unrated_answer', 'admin_deleted_rating', 'admin_bulk_deleted_ratings')
ORDER BY created_at DESC
LIMIT 20;
```

Expected rows:
- `unrated_answer` from `tech@example.com` after Flow 1 steps 5 / 8.
- `admin_deleted_rating` from `admin@example.com` after Flow 2 step 4.
- `admin_bulk_deleted_ratings` from `admin@example.com` with `detail` matching `count=<N>` after Flow 3 step 4.

## Failure-path check (optional)

With the backend stopped (to force a network failure):

1. Rate an answer thumbs-up, then tap it again to trigger undo.
   - Expected: error snackbar ("Could not remove rating — please try again.") and the thumb reappears as selected (rollback).
2. Start the backend back up; re-tap to undo.
   - Expected: normal success flow resumes.

## Expected acceptance

All nine functional requirements groups are covered. If any step deviates from the expectations above, flag it in `/speckit.analyze` before shipping.
