# Research: RAG Quality Improvements

**Branch**: `069-rag-quality-improvements` | **Date**: 2026-04-16

## R1: Current validated_qa Flow Architecture

**Decision**: Modify the existing `check_validated_match()` → `manual_rag_service.ask()` pipeline, not create a parallel path.

**Rationale**: The validated_qa lookup currently runs twice in `manual_rag_service.ask()`:
1. **Pre-rewrite** (line ~799): checks raw question against validated_qa. If `distance <= 0.10` ("direct"), returns cached answer immediately (is_verified=true). If `distance <= 0.25` ("context"), stores as `validated_context` for the LLM prompt.
2. **Post-rewrite** (line ~867): same logic on the rewritten query.

The user wants to change this flow so that instead of returning cached answers directly on "direct" match, the top 3 validated_qa entries are used as LLM context with a confidence threshold gate. This changes the meaning of the pre-rewrite/post-rewrite checks.

**Key insight**: The `search_validated_qa` RPC already supports `match_count` parameter (default 5). Currently called with `match_count: 1`. Simply changing to `match_count: 3` gives us multi-chunk retrieval. The RPC returns `distance` (cosine distance, 0=identical, 1=orthogonal), so similarity = `1 - distance`. Threshold 0.70 similarity = distance <= 0.30.

**Alternatives considered**:
- Creating a new RPC: Unnecessary — existing RPC already supports match_count parameter.
- Modifying the manual_chunks path: Out of scope — user explicitly targets validated_qa flow only.

## R2: Confidence Threshold Mapping

**Decision**: Use `RAG_CONFIDENCE_THRESHOLD = 0.70` expressed as similarity (1 - distance). Internally compare `max_similarity >= 0.70` which means `min_distance <= 0.30`.

**Rationale**: The RPC returns `distance` (cosine distance via `<=>` operator). The user specified the threshold in similarity terms (0.70). Converting: similarity 0.70 = distance 0.30. We'll convert distances to similarities in the service layer for cleaner API.

**Confidence bands**:
- `high`: similarity >= 0.85 (distance <= 0.15)
- `medium`: similarity >= 0.70 (distance <= 0.30)
- `low`: similarity < 0.70 (distance > 0.30)

## R3: System Prompt Strategy

**Decision**: Add a dedicated strict system prompt for the validated_qa RAG path, separate from the existing `_build_prompt()` used for the manual-chunks path.

**Rationale**: The existing `_build_prompt()` (line 106-155 in manual_rag_service.py) is designed for manual chunk context with specific rules about "MANUAL SECTIONS". The validated_qa flow needs a different prompt that references "sources" from the knowledge base, not manual sections. The new prompt will be a module-level constant in `validated_qa_service.py` or `manual_rag_service.py`.

**Alternatives considered**:
- Reusing `_build_prompt()` with validated_qa context: Would conflate two different context types. The manual-chunks prompt says "MANUAL SECTIONS" which is misleading for validated_qa answers.
- Modifying the provider resolver: Explicitly excluded by spec (FR-013).

## R4: Response Shape Backward Compatibility

**Decision**: Add new fields (`confidence`, `score`, `sources` with qa metadata) to the validated_qa response dict. Keep existing `answer`, `grounded`, `is_verified`, `verified_source` fields.

**Rationale**: The frontend currently reads `answer` and `is_verified`. New fields are purely additive. The `sources` field already exists in the response shape (currently `[]` for validated_qa hits) — we'll populate it with validated_qa source entries instead.

**Key consideration**: The existing `sources` array contains manual-chunk objects (`manual_id`, `manual_title`, `chunk_index`, `source_page`, `content_preview`). The new validated_qa sources have different fields (`id`, `question_text`, `score`). Since these are different paths (validated_qa vs manual-chunks), the frontend will need to handle both shapes — but that's a separate spec per FR-012.

## R5: Where to Place the LLM Call for Validated QA Context

**Decision**: When validated_qa entries pass the threshold, call `provider_generate()` (the same resolver used by the manual-chunks path) with the combined validated_qa context and the strict system prompt.

**Rationale**: The user wants the validated_qa matches to be used as LLM context (not returned raw). This means:
1. Fetch top 3 from validated_qa
2. If max_similarity >= 0.70: build prompt with [Source 1], [Source 2], [Source 3] format → call provider_generate()
3. If max_similarity < 0.70: return fallback without LLM call

This replaces the current "direct" match shortcut that returns `validated_answer` raw. The "context" match type (used to supplement manual chunks) will also be affected — now all validated_qa matches go through the LLM.

**Integration point**: In `manual_rag_service.ask()`, replace the pre-rewrite and post-rewrite direct-return blocks with the new multi-match + threshold + LLM flow.
