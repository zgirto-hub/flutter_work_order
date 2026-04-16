# Research: Auto-Paraphrase on Admin Approve

**Feature**: 068-auto-paraphrase-approve
**Date**: 2026-04-16

All technical unknowns were resolved against the existing codebase. No NEEDS CLARIFICATION remains. Summary below.

## R1 — Paraphrase generation via existing provider resolver

- **Decision**: Call `services.ai_providers.resolver.generate(prompt, system=None)` from spec 063. No new provider, no new SDK.
- **Rationale**: Spec 063 already implements the cloud-primary → Ollama-fallback chain. Reusing it satisfies the user's "reuse existing infrastructure" mandate and automatically inherits INV-3 behavior — if the whole chain fails, the resolver returns an error that we translate into "zero variants."
- **Prompt (fixed, English-only)**:

  ```text
  Generate exactly 4 alternative phrasings of the following technical question. Keep the same meaning and language. Do not add explanations. Return one phrasing per line, no numbering, no bullets.

  Question: {q}
  ```

- **Parser**: split on newline, strip, drop empties, drop any line that starts with a digit+delim or bullet (defensive against providers that add numbering despite instructions), drop lines identical (case-insensitive, whitespace-normalised) to the original question, cap at 5.
- **Alternatives considered**: structured JSON prompt (rejected — adds parser complexity for no benefit at this prompt simplicity); multiple targeted prompts (rejected — higher latency, violates SC-001 3s budget).

## R2 — Embedding strategy for variants

- **Decision**: For each admin-accepted variant, call `ollama_embedder.embed_single(variant_text)` to produce a fresh 768-dim vector. Embedding model stays `nomic-embed-text` via Ollama.
- **Rationale**: Existing `validated_qa` rows use this model and the `search_validated_qa` RPC assumes 768 dims. Mixing generator providers (Mistral/Gemini for paraphrase) with the embedder model is fine — they are independent concerns. Switching embedders would invalidate every existing entry's IVFFlat index entry and cross-similarity semantics.
- **Alternatives considered**: Having the cloud provider produce embeddings (rejected — would split the embedding space). Reusing the original question's embedding across variants (rejected — would make variants look identical to the fast-path read, defeating the purpose of having separate rows).

## R3 — Multi-row insert that preserves shared metadata

- **Decision**: Add `validated_qa_service.review_answer_multi(rating_id, action, corrected_answer, reviewer_email, variant_texts)`. Internally:
  1. Perform the same answer_ratings → validated_answer resolution as `review_answer` once (shared across variants).
  2. Build a base row dict identical to the existing `review_answer` (shared: validated_answer, validated_by, rating_id, manual_ids, source_chunks, equipment_type, fault_code).
  3. For each variant_text (including the original question as the first variant): compute its own embedding, clone the base row, override `question_text` and `question_embedding`, bulk insert.
  4. Mark `answer_ratings.review_status` once, at the end.
  5. Log one activity row per variant? → **No: log one activity for the batch** with `detail = "approved -> approved (N variants)"` to avoid audit-log spam.
- **Rationale**: Schema permits it — `rating_id` is nullable and has no unique constraint (confirmed in `supabase/migrations/20260415000000_make_rating_id_nullable.sql` and the original `20260413000000_create_feedback_loop.sql`). All variants therefore share one `rating_id` → thumbs aggregate through `update_validated_rating` → `search_validated_qa` RPC already sums rating counts across the matched row, not across rating_id, **so we additionally need**: when applying rating updates, update every row sharing the `rating_id` (reuse existing `update_validated_rating` signature but extend implementation to update all rows with that rating_id). This change is in-scope because it is a direct consequence of INV-8 (shared rating across variants).
- **Alternatives considered**: Per-variant rating_ids (rejected — explicitly out of scope in user input; would require new thumbs UI). Store only the original's embedding and compute variants' embeddings lazily at match time (rejected — breaks read path, violates INV-4).

## R4 — Modal UX and widget reuse

- **Decision**: New widget `frontend/lib/screens/manual_assistant/widgets/variants_modal.dart`, built on `BottomSheetContainer` from `frontend/lib/widgets/bottom_sheet_widgets.dart`. Chip list uses Flutter Material `InputChip` in edit mode wrapping a `TextField`; a trailing `FilledButton.tonal("Add variant")` appends an empty chip.
- **Rationale**: `BottomSheetContainer` is the canonical pattern for admin modals in this codebase (used in multiple spec 048 tabs). `InputChip` is Material's native editable+deletable chip — no custom widget needed.
- **Alternatives considered**: Full-screen dialog (rejected — overkill for 3–6 chips). Inline expansion inside the card (rejected — too cramped and doesn't match the "modal review" contract in the spec).

## R5 — Retro-expansion entry point (P2)

- **Decision**: Add two controls to `verified_answers_tab.dart`:
  1. Per-row: a "Generate variants" icon button on each `answer_card` → opens the same modal pre-seeded with the row's `question_text`.
  2. Tab-level: a "Generate variants for all" button that iterates the list client-side, opening the modal for each entry in sequence. User can Cancel any one to skip it; Save All on one modal advances to the next entry.
- **Rationale**: Per-row covers targeted retro work; tab-level covers the ~16-entry batch. Iterating one-at-a-time keeps the admin in the review loop per P2 and per user input ("NOT a bulk-all-at-once silent insert").
- **Alternatives considered**: Backend-driven batch that auto-saves all generated variants without review (rejected — out of scope per user input).

## R6 — Failure handling on the paraphrase endpoint

- **Decision**: The generate endpoint returns 200 with `{"variants": [...]}` on success, and **still 200 with `{"variants": []}`** when all providers fail. Frontend uses the empty list as the signal to show the "no variants generated" notice. Never 5xx from a provider failure — that would surface as a hard error in the modal and violate INV-3.
- **Rationale**: Keeps INV-3 (graceful degradation) simple and server-authoritative. Exceptions within the resolver are caught, logged, and converted to empty variants.
- **Alternatives considered**: 503 with a retry header (rejected — modal would need to special-case it to avoid blocking; simpler to let the empty-list path be the single fallback signal).

## R7 — Transaction boundary on Save All (atomicity — FR-013)

- **Decision**: Server performs all inserts in a single Supabase client `.insert([row1, row2, ...])` batch (Supabase client supports list payloads → single INSERT statement → atomic at the statement level). Update to `answer_ratings.review_status` happens after a successful insert; the activity log write happens fire-and-forget per constitution principle VI.
- **Rationale**: Supabase's REST layer maps `client.table().insert(list)` to a single Postgres INSERT, which is atomic. Full distributed transactions are not required because everything lives in one Postgres database accessed through one client.
- **Alternatives considered**: Explicit RPC wrapping INSERT + UPDATE in a function (rejected — YAGNI; single-statement atomicity is already sufficient for our correctness requirement).
