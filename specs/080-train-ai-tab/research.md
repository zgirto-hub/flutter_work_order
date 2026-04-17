# Research: 080 — Train the AI Tab

**Date**: 2026-04-17  
**Branch**: `080-train-ai-tab`

## Key Decisions

### 1. manuals table lacks `updated_at` column

**Decision**: Add `updated_at TIMESTAMPTZ DEFAULT now()` to `manuals` table in the staleness migration.

**Rationale**: The spec assumes `manuals.updated_at` exists for staleness detection (`manuals.updated_at > validated_qa.verified_at`), but the current schema only has `created_at`. Without this column, staleness detection cannot work. The re-embed endpoint already re-processes chunks but does not record when — adding `updated_at` and setting it during re-embed solves this.

**Alternatives considered**:
- Use `manual_chunks.created_at` as proxy for manual freshness — rejected because chunks are replaced (deleted + re-inserted) on re-embed, so the newest chunk `created_at` reflects re-embed time but requires a subquery per manual, complicating the staleness query.
- Track re-embed events in a separate log table — rejected as overengineered for this use case.

### 2. `validated_qa` already has `validated_at` — add separate `verified_at`

**Decision**: Add `verified_at` as a new column, distinct from the existing `validated_at`.

**Rationale**: `validated_at` records when the entry was first created/validated. `verified_at` records when an admin last confirmed the entry is still current after a manual update. These are semantically different timestamps. Reusing `validated_at` would lose the original validation date.

**Alternatives considered**:
- Reuse `validated_at` for both purposes — rejected because it loses provenance (when was this first validated vs. last checked).

### 3. provider_generate function binding

**Decision**: Import and use the existing `generate()` function from `services.ai_providers.resolver` (called `provider_generate` in manuals.py via import alias).

**Rationale**: The function signature is `async def generate(prompt, context_chunks, user_email=None, latency_breakdown=None) -> Tuple[str, str, str, bool, dict|None]`. The manuals router already imports and uses this function for paraphrase generation. We pass `context_chunks=[]` when generating Q&A candidates (the chunks are embedded in the prompt text itself).

### 4. Positive rating definition for real-usage suggestions

**Decision**: Filter `answer_ratings WHERE rating = 'positive'`.

**Rationale**: The `answer_ratings.rating` column is a CHECK constraint with values `'positive'` or `'negative'`. Positive ratings have `review_status IS NULL` (auto-set on save). The query groups by `question_text + answer_text`, counts positive ratings, filters `count >= 2`.

### 5. Frontend tab count change: 6 → 7

**Decision**: Increase admin tab count from 6 to 7. The new "Train the AI" tab is added as index 6 (last admin tab).

**Rationale**: Current tabs are: Chat(0), Review(1), Rules(2), Alerts(3), Verified(4), Documents(5). Adding Train the AI as tab 6 keeps logical ordering — training is adjacent to verified answers and documents.

### 6. Paraphrase endpoint extension (lang param)

**Decision**: Add optional `lang: str = "en"` field to `ParaphraseVariantsRequest`. When `lang="ar"`, use an Arabic-specific prompt. When `lang="en"`, existing behavior is unchanged.

**Rationale**: The existing endpoint uses `PARAPHRASE_PROMPT_TEMPLATE` for English. Arabic paraphrases need a different prompt that generates natural Arabic variants (not literal translations). Adding `lang` as an optional field with default `"en"` ensures zero breaking changes.

### 7. source_manual_id tracking for bootstrap entries

**Decision**: When saving approved candidates from Section A (From Manuals), pass the `source_manual_id` to `create_verified_answer()` and store it on the `validated_qa` row. Entries from Section B (From Real Usage) get `source_manual_id = NULL`.

**Rationale**: Staleness detection only applies to entries derived from a specific manual. Real-usage entries have no single source manual and should not be flagged as stale.

### 8. Re-embed flow must set manuals.updated_at

**Decision**: In the existing `re-embed all chunks` endpoint (`/manuals/{manual_id}/chunks/re-embed`), add an UPDATE to set `manuals.updated_at = now()` after successful re-embedding.

**Rationale**: This is the trigger for staleness detection. If an admin re-processes a manual's chunks, any cached Q&A derived from that manual should be reviewed. The upload flow creates a new manual row (new UUID), so it inherently gets a fresh `created_at`/`updated_at`.

## Existing Code Patterns to Reuse

### Backend (manuals.py)

| Pattern | Location | How to reuse |
|---------|----------|--------------|
| Admin check | `_admin_check(user_email)` at line 1113 | Call on all 5 new/modified endpoints |
| Pydantic request model | `ParaphraseVariantsRequest`, `CreateVerifiedAnswerRequest` | Follow same pattern for new request models |
| Activity logging | `background_tasks.add_task(log_activity, ...)` | Log training actions (generate, save, review) |
| Error handling | HTTPException with `{"error": "code"}` dict | Same pattern for new endpoints |

### Backend (validated_qa_service.py)

| Method | Signature | Reuse for |
|--------|-----------|-----------|
| `create_verified_answer()` | `async (question_text, validated_answer, editor_email) -> dict` | Step 1 of 4-step save — extend to accept `source_manual_id` |
| `review_answer_multi()` | `async (rating_id, action, ..., variant_texts, existing_validated_qa_id) -> dict` | Step 4 (retro_expand) — already supports this action |
| `get_all_verified_answers()` | `(search, limit, offset) -> dict` | Not directly needed but shows query pattern |
| `delete_verified_answer()` | `(qa_id) -> str` | For "Remove from Cache" — extend to cascade variants |

### Backend (ollama_embedder.py)

| Function | Signature | Reuse for |
|----------|-----------|-----------|
| `embed_single()` | `async (text, priority) -> List[float]` | Embedding generated questions for dedup check |
| `embed_many()` | `async (texts, priority) -> List[List[float]]` | Batch embedding if needed |

### Frontend (manual_assistant_service.dart)

| Method | Signature | Reuse for |
|--------|-----------|-----------|
| `generateParaphraseVariants()` | `({questionText, ratingId}) -> List<String>` | Extend with `lang` param |
| `createVerifiedAnswer()` | `({questionText, validatedAnswer, editorEmail}) -> Map` | Step 1 of save flow |
| `reviewAnswerWithVariants()` | `({ratingId, action, ..., existingValidatedQaId, variants}) -> Map` | Step 4 (retro_expand) |
| `listManuals()` | `() -> Map` | Populate manual dropdown in Section A |

### Frontend (manual_assistant_screen.dart)

| Pattern | Details | Reuse for |
|---------|---------|-----------|
| Tab structure | `TabController(length: _isAdmin ? 6 : 1)` | Change to 7, add Train the AI tab |
| Badge on tab | Review tab badge with `_flaggedCount` | Stale count badge on Needs Review segment |
| Admin guard | `if (_isAdmin)` wrapping tab rendering | Same pattern for new tab |

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Q&A generation produces low-quality candidates | Wasted admin review time | Admin can reject; skip-if-cached reduces duplicates |
| Embedding dedup check is slow for large validated_qa tables | Slow generation endpoint | Limit to 20 candidates; use existing IVFFlat index |
| Re-embed endpoint not setting updated_at (currently missing) | Staleness detection won't trigger | Migration adds column + code sets it on re-embed |
| Arabic paraphrase generation quality | Poor variants reduce cache hit rate | Admin reviews all variants before save |
