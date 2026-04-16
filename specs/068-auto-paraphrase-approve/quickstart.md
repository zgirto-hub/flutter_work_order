# Quickstart: Auto-Paraphrase on Admin Approve

**Feature**: 068-auto-paraphrase-approve

Purpose: smoke-test the feature end-to-end after implementation. Assumes backend and frontend are running and the admin user is signed in.

## Prerequisites

- At least one `pending` entry in `answer_ratings` (a technician has flagged an AI answer for admin review).
- At least one AI provider is configured and reachable (per spec 063). Ollama is up locally as the fallback.
- `nomic-embed-text` is available in local Ollama (existing dependency).

## Scenario P1 — Approve with generated variants

1. Open the Ask-the-AI admin screen → **Review** tab.
2. Click **Approve** on a pending entry.
3. Expected: within ~3 s, a modal titled "Save verified answer" opens with:
   - The original question as the first chip.
   - 3–5 paraphrased variants as additional editable chips.
4. Edit any one chip inline; click ✕ on another to remove it; click **Add variant** and type a custom phrasing.
5. Click **Save all**.
6. Expected: modal closes, toast "N verified answers saved" appears, Review tab removes the entry.
7. Open the **Verified** tab → confirm N rows now exist with identical answer text but distinct question phrasings.
8. As a technician, open the Ask-the-AI chat and ask one of the custom variants from step 4.
9. Expected: instant response (under ~2 s), "Verified Answer" badge visible.

## Scenario P2 — Retro-expand one existing verified entry

1. Admin screen → **Verified** tab.
2. On any row, click the "Generate variants" icon.
3. Expected: same modal opens seeded with that row's question + generated paraphrases.
4. Adjust and **Save all**.
5. Expected: new rows inserted; the original row is unchanged and still present.

## Scenario P2b — Bulk retro-expansion

1. Admin screen → **Verified** tab → click **Generate variants for all**.
2. Expected: the modal opens for the first entry. After **Save all** or **Cancel**, the modal immediately re-opens for the next entry.
3. Close any single modal via **Cancel** → that one entry is skipped and the sequence continues.
4. A failure on one entry (e.g., all providers down for that call) MUST NOT abort the sequence; the modal opens with just that entry's original question plus a notice.

## Scenario P3 — Provider failure fallback

1. Temporarily disable outbound network to the cloud providers AND stop local Ollama.
2. Admin screen → Review tab → click **Approve** on a pending entry.
3. Expected: modal still opens, containing only the original question as a chip, plus a non-blocking notice "Automatic variants could not be generated."
4. Click **Save all**.
5. Expected: exactly one `validated_qa` row inserted — identical to pre-feature behaviour.

## Post-checks

- `validated_qa` rows inserted in the same Save All share: `validated_answer`, `validated_by`, `validated_at`, `rating_id`, `manual_ids`, `source_chunks`.
- Each row has its own distinct `id`, `question_text`, `question_embedding`.
- `answer_ratings.review_status` transitioned exactly once per approval session (approve/correct only; retro-expand leaves it untouched).
- `user_activity_log` contains one `reviewed_answer` activity per approval session, detail mentioning the variant count.
- Thumbs-up from a technician on one variant increments thumbs on every variant sharing that `rating_id` (shared-rating behaviour).
