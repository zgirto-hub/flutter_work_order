# Research: Feedback Loop AI Assistant

**Branch**: `048-feedback-loop-ai-assistant` | **Date**: 2026-04-13

## R1: Embedding Infrastructure for Validated QA

**Decision**: Reuse existing `ollama_embedder.embed_single()` with nomic-embed-text (768-dim) for question embeddings in `validated_qa`.

**Rationale**: The embedding model and pgvector infrastructure are already proven for manual chunk retrieval. Question text is short (typically <100 tokens), so `embed_single()` is fast (<200ms). The same cosine similarity metric used for manual search applies directly.

**Alternatives considered**:
- Separate embedding model for QA: Rejected — adds complexity, no accuracy benefit for short question texts.
- Store embeddings externally (e.g., FAISS): Rejected — pgvector is already used and supports cosine similarity natively.

## R2: Similarity Search RPC Pattern

**Decision**: Create a new Supabase RPC function `search_validated_qa` modeled after the existing `search_manual_chunks` RPC.

**Rationale**: The existing `search_manual_chunks` RPC demonstrates the proven pattern — accepts a query embedding vector, returns rows ordered by cosine distance. The new RPC will accept `q_embedding VECTOR(768)` and `match_count INT`, returning rows with `distance` (cosine), `question_text`, `validated_answer`, and metadata. This keeps similarity search in PostgreSQL where pgvector's IVFFlat index provides efficient approximate nearest neighbor lookup.

**Alternatives considered**:
- Client-side similarity computation: Rejected — requires loading all validated_qa embeddings into Python memory.
- Supabase SDK `.select()` with manual distance calculation: Rejected — no index utilization, full table scan.

## R3: Rating Storage Architecture

**Decision**: Dedicated `answer_ratings` table with one row per rating event. Thumbs-down rows additionally serve as the flag mechanism (query `WHERE rating = 'negative' AND review_status = 'pending'` to build the review queue).

**Rationale**: Clarified during spec clarification session — all ratings (positive and negative) are persisted. A single table with a `review_status` column (NULL for positive ratings, 'pending'/'approved'/'corrected' for negative) avoids a separate flagged_answers table while supporting the review queue query pattern.

**Alternatives considered**:
- Separate `flagged_answers` table: Rejected — introduces data duplication and sync complexity between rating and flag lifecycle.
- Fire-and-forget for positive ratings: Rejected — loses data needed for cumulative metrics on validated answers (SC-006).

## R4: Validated QA Check Insertion Point

**Decision**: Insert the validated_qa similarity check at the very beginning of `manual_rag_service.ask()`, before query rewriting and HyDE.

**Rationale**: The spec requires checking validated answers "before running query rewriting or hypothetical answer generation" (FR-010). If a >=0.90 match is found, the entire RAG pipeline is skipped, saving ~5-15 seconds of processing. If a 0.75-0.90 match is found, the validated answer is injected as a high-priority context chunk that the pipeline processes alongside retrieved manual chunks.

**Alternatives considered**:
- Check after query rewriting: Rejected — wastes an Ollama call for rewriting when the answer might be cached.
- Check in the router instead of the service: Rejected — the service owns the pipeline logic; router should stay thin.

## R5: Re-flagging Mechanism

**Decision**: When a validated answer is served and subsequently receives a thumbs-down, the system increments the `thumbs_down_count` on the `validated_qa` row. After each increment, check if `thumbs_down_count / (thumbs_up_count + thumbs_down_count) > 0.30` AND `total >= 3`. If true, set a `re_flagged` boolean on the validated_qa row.

**Rationale**: Clarified during spec clarification — 30% threshold with minimum 3 total ratings prevents premature re-flagging from a single bad rating while catching genuinely degraded answers.

**Alternatives considered**:
- Re-flag on any single thumbs-down: Rejected — too aggressive; would flood the review queue.
- Separate re-flagging service: Rejected — simple threshold check can be done inline during rating submission.

## R6: Admin Role Detection (Frontend)

**Decision**: Use the existing `userRole == 'admin'` string comparison pattern already used in `ManualAssistantScreen` for the system instructions icon.

**Rationale**: The pattern is already established in the exact screen where the Review Queue tab will be added. The `userRole` is passed as a constructor parameter through navigation. No new role or permission mechanism is needed (per spec assumptions).

**Alternatives considered**:
- Backend-enforced tab visibility: Rejected — the backend already enforces role checks on API endpoints; frontend gating is a UX concern only.

## R7: Embedding Generation Timing

**Decision**: Generate question embedding synchronously when the admin saves a validated answer (approve or correct action).

**Rationale**: Clarified during spec clarification — synchronous embedding ensures the validated answer is immediately searchable. `embed_single()` for a short question string takes <200ms, which is negligible in the context of an admin review action.

**Alternatives considered**:
- Asynchronous background job: Rejected — adds complexity (job queue) for negligible performance gain on a single short embedding.
