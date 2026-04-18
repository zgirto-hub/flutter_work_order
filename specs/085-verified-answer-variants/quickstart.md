# Quickstart: Verified Answer Variants

Manual verification flow for the three user stories in [spec.md](./spec.md). Run after implementation to confirm the feature works end-to-end. All steps happen in the admin surface of "Ask the AI" in the Flutter web PWA, with the FastAPI backend + Ollama embedder running.

## Prerequisites

- Admin account signed into the PWA.
- At least one existing verified answer in the Verified tab.
  - If none exists, create one via the tab's "+" FAB (question + answer).
- Ollama embedder reachable on `localhost:11434`.
- Generator provider (Ollama or Gemini) available for paraphrase generation.

## User Story 1 — Broaden with AI paraphrases (P1)

1. Open "Ask the AI" → **Verified** tab.
2. Click any verified answer row → the existing Edit dialog opens.
3. Click **Generate variants** (new button).
   - **Expected**: Modal opens within ~5 s.
   - **Expected**: The row's own question appears as a **saved chip** (with the verified/checkmark badge).
   - **Expected**: 3–4 additional chips appear below, marked as **new** (no badge, dashed border).
4. Edit one of the new chips (e.g. shorten it). Keep a couple of AI chips, remove one.
5. Click **Save all**.
   - **Expected**: Modal closes. Snack-bar reads "Verified answer variants updated".
   - **Expected**: Edit dialog may refresh or stay open — either is acceptable, as long as no data is lost.
6. Close the dialog. Re-open the same entry and click **Generate variants** again.
   - **Expected**: The variants you saved now appear as **saved chips** (including your edited text).
7. In the **Chat** tab, ask a question that matches one of the newly-saved phrasings.
   - **Expected**: The chat returns the same verified answer (verbatim, with the green "Verified Answer" banner).

## User Story 2 — Remove a stale variant (P2)

1. On an entry with ≥ 3 stored variants, open **Generate variants**.
2. Click the × on one of the saved chips. Leave the remaining chips unchanged.
3. Click **Save all**.
   - **Expected**: Backend returns 200; snack-bar reads updated.
4. Re-open the modal; the removed variant is gone.
5. Ask (in chat) a question that only the removed variant matched.
   - **Expected**: The assistant no longer short-circuits to the verified answer (or matches via a broader similarity, but the specific verbatim trigger is gone).

## User Story 3 — Paraphrase service unavailable (P3)

1. Stop the generator service or block it (`sudo systemctl stop ollama.service`, or point AI provider to a dead URL temporarily).
2. Click a row → **Generate variants**.
   - **Expected**: Modal opens showing only the saved chips.
   - **Expected**: Orange notice banner at the top reads "AI paraphrases are unavailable right now. You can still edit, add, or remove variants and save."
3. Click **Add variant**, type a new phrasing, click **Save all**.
   - **Expected**: Backend 200 (embeddings for manually-added variants still work — the generator is a different service).
4. Restart the generator service.

## Edge-case spot checks

- **Legacy entry (rating_id = NULL)**:
  - In Supabase SQL editor: `SELECT id, rating_id FROM validated_qa WHERE rating_id IS NULL LIMIT 1;`
  - Open that entry in the Verified tab → Generate variants → add a variant → Save all.
  - Re-query: the original row now has a non-null `rating_id`, and the new variant shares it.
- **500-char ceiling**: Open Generate variants, paste a 501+ char variant, try to Save.
  - **Expected**: Save button disabled (modal-side enforcement) or 400 from backend.
- **Empty final set**: Open Generate variants, remove all chips, try Save.
  - **Expected**: Save button disabled.
- **Atomic embedding failure**:
  - Stop Ollama embedder (`sudo systemctl stop ollama.service`).
  - Open Generate variants, add a new variant (manual), Save.
  - **Expected**: 503 surfaced via snack-bar; refreshing shows no change to the stored set.

## Audit log check

After any successful save:

```sql
SELECT user_email, category, action, target_id, detail, created_at
FROM user_activity_log
WHERE action = 'updated_verified_answer_variants'
ORDER BY created_at DESC
LIMIT 5;
```

**Expected**: one row per save, with `detail` reading `added=X, removed=Y, final=Z`.
