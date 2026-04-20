# Contracts — Routes Being RETAINED

**Feature**: Spec 090, Delete Legacy `manuals` Table & Dead Code
**Scope**: Every FastAPI route under `/manuals/*` that remains live after this spec ships. These routes share the URL prefix with the removed CRUD routes but are semantically part of the AI-assistant surface (Ask-the-AI) — none of them read or write the `manuals` / `manual_chunks` / `manual_corpus_stats` tables.

Line numbers refer to `backend/routers/manuals.py` on `main` as of this spec's creation.

---

## AI provider / settings (unchanged)

| HTTP verb | Path | Handler | Line |
|---|---|---|---:|
| GET | `/manuals/models` | `get_models` | 104 |
| GET | `/manuals/active-provider` | `get_active_provider` | 112 |
| GET | `/manuals/settings` | `get_ai_settings` | 147 |
| POST | `/manuals/settings` | `update_ai_settings` | 167 |

These read/write `app_settings` and `manual_assistant_settings`, neither of which is touched by this spec.

---

## Ask / streaming ask (RAG pipeline) (unchanged)

| HTTP verb | Path | Handler | Line |
|---|---|---|---:|
| POST | `/manuals/ask` | `ask_question` | 745 |
| POST | `/manuals/ask/stream` | `ask_question_stream` | 389 |

Both call through to `manual_rag_service` helpers that search `document_chunks` (not `manual_chunks`). The trim of `manual_rag_service.py` in Story 2 preserves every helper on this path.

---

## Rating / feedback (unchanged)

| HTTP verb | Path | Handler | Line |
|---|---|---|---:|
| POST | `/manuals/rate-answer` | `rate_answer` | 1021 |
| PATCH | `/manuals/ratings/{rating_id}/feedback` | `patch_rating_feedback` | 1075 |
| DELETE | `/manuals/ratings/{rating_id}` | `delete_rating` | 1108 |
| GET | `/manuals/flagged-answers` | `get_flagged_answers` | 1156 |
| POST | `/manuals/review-answer` | `review_answer` | 1180 |
| POST | `/manuals/review-answer-with-variants` | `review_answer_with_variants` | 1320 |
| POST | `/manuals/paraphrase-variants` | `generate_paraphrase_variants` | 1231 |
| POST | `/manuals/ratings/bulk-delete` | `bulk_delete_ratings` | 1873 |

After Story 3, the `answer_ratings.manual_id` column disappears. Any reader of that column in these handlers must be removed in Story 2 — **audit finding**: grep confirms none of the retained handlers read or write `answer_ratings.manual_id` today, so no code edit is required beyond Story 2's general trim.

---

## Verified answers CRUD (unchanged)

| HTTP verb | Path | Handler | Line |
|---|---|---|---:|
| GET | `/manuals/verified-answers` | `get_verified_answers` | 1384 |
| PUT | `/manuals/verified-answers/{qa_id}` | `update_verified_answer` | 1409 |
| POST | `/manuals/verified-answers` | `create_verified_answer` | 1451 |
| DELETE | `/manuals/verified-answers/{qa_id}` | `delete_verified_answer` | 1494 |
| GET | `/manuals/verified-answers/{qa_id}/variants` | `get_verified_answer_variants` | 1519 |
| PUT | `/manuals/verified-answers/{qa_id}/variants` | `update_verified_answer_variants` | 1540 |
| POST | `/manuals/generate-qa-candidates` | `generate_qa_candidates` | 1591 |

These operate on `validated_qa`. The `manual_ids[]` and `source_manual_id` columns on that table are retained (see data-model.md). No handler change.

---

## Training / cache management (unchanged)

| HTTP verb | Path | Handler | Line |
|---|---|---|---:|
| GET | `/manuals/real-usage-suggestions` | `real_usage_suggestions` | 1791 |
| GET | `/manuals/stale-cache-entries` | `stale_cache_entries` | 1905 |
| POST | `/manuals/mark-cache-reviewed` | `mark_cache_reviewed` | 1982 |

---

## URL prefix note

The `/manuals/*` prefix is retained as-is. See research.md Decision 2 for the rationale. A future spec can alias or rename the prefix without touching any of the database or feature work done here.

---

## Backend services being retained in full

| File | Reason |
|---|---|
| `backend/services/system_registry.py` | Already redirected to `knowledge_documents` in commit `f0cf05c`. Unchanged by this spec. |
| `backend/services/validated_qa_service.py` | Reads/writes `validated_qa` only. |
| `backend/services/ai_providers/*` | AI provider resolver layer; orthogonal to the manuals feature. |
| `backend/services/ollama_embedder.py`, `ollama_generator.py` | Generation and embedding helpers used by the retained ask path. |
| `backend/services/document_service.py`, `document_chunks` pipeline | The live corpus pipeline — spec 072. |

---

## Frontend service methods being retained

Every method in `frontend/lib/services/manual_assistant_service.dart` other than those in [removed-api.md](./removed-api.md) stays. Concretely:

- Settings: `getAiSettings`, `updateAiSettings`, `getModels`, `getActiveProvider`
- Ask: `ask`, `askStream`
- Rating: `rateAnswer`, `patchRatingFeedback`, `deleteRating`, `getFlaggedAnswers`, `reviewAnswer`, `reviewAnswerWithVariants`, `generateParaphraseVariants`, `bulkDeleteRatings`
- Verified answers: `getVerifiedAnswers`, `updateVerifiedAnswer`, `createVerifiedAnswer`, `deleteVerifiedAnswer`, `getVerifiedAnswerVariants`, `updateVerifiedAnswerVariants`, `generateQaCandidates`
- Training/cache: `realUsageSuggestions`, `staleCacheEntries`, `markCacheReviewed`
