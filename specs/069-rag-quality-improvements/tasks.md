# Tasks: RAG Quality Improvements

**Input**: Design documents from `/specs/069-rag-quality-improvements/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Manual curl tests only (no automated test tasks).

**Organization**: Tasks grouped by user story. Backend-only changes in 2-3 Python files.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1, US2, US3, US4)

## Important Context for the Implementer

**READ BEFORE STARTING**: This feature modifies the validated_qa lookup path in the "Ask the AI" knowledge base. Here's what you need to know:

### Architecture Overview
- **Endpoint**: `POST /api/manuals/ask` in `backend/routers/manuals.py` (line ~331)
- **RAG orchestration**: `ask()` in `backend/services/manual_rag_service.py` (line ~748)
- **Validated QA lookup**: `check_validated_match()` in `backend/services/validated_qa_service.py` (line ~267)
- **SQL RPC**: `search_validated_qa` in `supabase/migrations/20260413000000_create_feedback_loop.sql` (line ~74) — DO NOT modify this file

### Current Flow (what you're changing)
1. User asks question → `manual_rag_service.ask()` is called
2. **Pre-rewrite check** (~line 799): calls `check_validated_match(question)` with `match_count: 1`
   - If `distance <= 0.10` ("direct"): returns cached `validated_answer` directly — **NO LLM call**
   - If `distance <= 0.25` ("context"): stores answer as `validated_context` for manual-chunks LLM prompt
   - Otherwise: `"none"` — falls through to manual-chunks RAG pipeline
3. **Post-rewrite check** (~line 867): same logic on rewritten query
4. If no validated_qa match, continues to manual-chunks RAG pipeline (HyDE → embed → search → rerank → LLM)

### New Flow (what you're building)
1. `check_validated_match()` fetches **top 3** entries (not 1) and returns all with similarity scores
2. If **max similarity < 0.70**: return fallback message immediately, skip LLM
3. If **max similarity >= 0.70**: combine all 3 entries as labeled context → call LLM with **strict system prompt**
4. Response includes `answer`, `confidence`, `score`, `sources` array

### Distance vs Similarity
The `search_validated_qa` RPC returns `distance` (cosine distance via `<=>` operator):
- distance 0.0 = identical, distance 1.0 = orthogonal
- **similarity = 1.0 - distance**
- Threshold 0.70 similarity = distance 0.30
- Current "direct" match: distance <= 0.10 (similarity >= 0.90)
- Current "context" match: distance <= 0.25 (similarity >= 0.75)

### What NOT to Change
- `backend/services/ai_providers/resolver.py` — provider resolver is off limits
- `supabase/migrations/` — no schema changes
- `frontend/` — no Dart/Flutter changes
- `.env` files
- The manual-chunks RAG pipeline (HyDE, reranking, cross-manual synthesis) — only touch the validated_qa path
- The greeting bypass at the top of `ask_question()` in manuals.py — leave it as-is

---

## Phase 1: Setup (Constants & Configuration)

**Purpose**: Define constants used by all subsequent tasks

- [x] T001 [US1] Add RAG confidence constants at module level in `backend/services/manual_rag_service.py`

  **What to do**: Add these constants near the top of the file (after existing constants like `MAX_PROMPT_CHUNKS`, `MAX_CHUNK_DISTANCE`, etc. around line ~70-80):

  ```python
  # --- Validated QA confidence thresholds (spec 069) ---
  RAG_CONFIDENCE_THRESHOLD = 0.70   # Minimum similarity to proceed to LLM
  RAG_HIGH_CONFIDENCE = 0.85        # Score >= this → confidence: "high"
  ```

  **Why**: Named constants make threshold tuning easy. These are used in Phases 3-5.

**Checkpoint**: Constants defined. No behavior change yet.

---

## Phase 2: Foundational (Multi-Match Retrieval)

**Purpose**: Modify `check_validated_match()` to return top 3 results with similarity scores. This is the data layer that all subsequent user stories depend on.

**CRITICAL**: No user story work can begin until this phase is complete.

- [x] T002 Modify `check_validated_match()` in `backend/services/validated_qa_service.py` to fetch top 3 and return all matches with similarity scores

  **Current code** (line ~267-320): The function calls `search_validated_qa` with `match_count: 1`, gets one result, and returns `{"match_type": "direct"/"context"/"none", "validated_qa": match}`.

  **What to change**:
  1. Change `match_count: 1` to `match_count: 3` (line ~274)
  2. Instead of returning a single match with match_type logic, return ALL matches with their similarity scores
  3. Convert distance to similarity: `similarity = round(1.0 - distance, 2)`

  **New return shape**:
  ```python
  {
      "matches": [
          {
              "id": str(match["id"]),
              "question_text": match["question_text"],
              "validated_answer": match["validated_answer"],
              "validated_by": match["validated_by"],
              "validated_at": match["validated_at"],
              "similarity": round(1.0 - match.get("distance", 1.0), 2),
          }
          for match in rpc_resp.data
      ]
  }
  ```

  If `rpc_resp.data` is empty, return `{"matches": []}`.

  **IMPORTANT — Topic guard**: The existing topic guard logic (lines ~286-311) checks if the matched entry's `manual_ids` overlap with the detected system's manuals. This currently works on a single match. For the multi-match version:
  - Apply the topic guard to the **best match** (first result, lowest distance)
  - If the best match fails the topic guard, return `{"matches": []}` (reject all — if the best match is off-topic, the others likely are too)
  - If the best match passes, keep all 3 matches as-is

  **Keep backward compatibility**: The old `match_type` field is consumed in `manual_rag_service.py`. Rather than changing the return shape AND the consumer simultaneously, **add** the new `matches` field alongside the existing return. But it's simpler to change both together in T002 + T003. Choose whichever approach is cleaner — just make sure `manual_rag_service.py` is updated to consume the new shape in T003.

**Checkpoint**: `check_validated_match()` now returns top 3 matches with similarity scores. The consumer in `manual_rag_service.py` is broken until T003.

---

## Phase 3: User Story 1+2 — Multi-Chunk Context + Confidence Threshold (Priority: P1) MVP

**Goal**: Replace the pre-rewrite and post-rewrite validated_qa shortcut blocks in `manual_rag_service.ask()` with the new multi-match + threshold + LLM flow.

**Independent Test**: 
- Ask a well-matched question → get LLM answer from 3 sources
- Ask an off-topic question → get fallback message without LLM call

- [x] T003 [US1] [US2] Rewrite the pre-rewrite validated_qa block in `backend/services/manual_rag_service.py` (~lines 792-838)

  **Current code**: Calls `check_validated_match(question)`, checks `match_type == "direct"` to return cached answer, `match_type == "context"` to set `validated_context`.

  **Replace with**:
  1. Call `check_validated_match(question, detected_system=detected_system)` (same as before)
  2. Extract `matches` from the result
  3. If `matches` is empty or `max(m["similarity"] for m in matches) < RAG_CONFIDENCE_THRESHOLD`:
     - Set a flag like `vqa_below_threshold = True` and store `max_score` for the fallback response
     - Do NOT return yet — let the flow continue to the post-rewrite check (the rewritten query might match better)
  4. If max similarity >= threshold:
     - Build combined context string:
       ```python
       context_parts = []
       for i, m in enumerate(matches):
           context_parts.append(f"[Source {i+1}]\n{m['validated_answer']}")
       combined_context = "\n\n".join(context_parts)
       ```
     - Call the LLM with the strict system prompt (see T005) and this combined context
     - Build and return the response with `confidence`, `score`, `sources` (see T006)

  **CRITICAL**: Do NOT remove the pre-rewrite/post-rewrite two-pass structure. Keep both passes. The pre-rewrite pass checks the raw question; the post-rewrite pass checks the context-resolved query. If the pre-rewrite pass gets a strong match, use it. If not, let the post-rewrite pass try.

- [x] T004 [US1] [US2] Rewrite the post-rewrite validated_qa block in `backend/services/manual_rag_service.py` (~lines 865-905)

  **Same logic as T003** but for the post-rewrite check. This block currently calls `check_validated_match(search_query, detected_system=detected_system)`.

  **What to change**:
  1. If the pre-rewrite pass already returned a validated_qa answer (T003), this block is skipped (the function already returned).
  2. If the pre-rewrite pass didn't match (or was below threshold), this block runs with `search_query` (the rewritten query).
  3. Same threshold + multi-match + LLM logic as T003.
  4. If this pass also fails the threshold, let the flow continue to the manual-chunks RAG pipeline as before. Do NOT return the fallback message here — the manual-chunks pipeline is the fallback for validated_qa misses.

  **Wait — design decision**: The user's spec says if max_score < 0.70, return a fixed fallback message. But currently, if validated_qa doesn't match, the system falls through to the manual-chunks pipeline (which searches actual PDF manual content). Returning a fallback message would prevent the manual-chunks pipeline from running.

  **Resolution**: Apply the threshold + fallback **only to the validated_qa path**. If validated_qa has matches but all below threshold, proceed to the manual-chunks pipeline. The fallback message ("I don't have reliable information...") should only be returned if we specifically want to gate on validated_qa quality. Given the user's explicit instructions, implement it as: if the pre-rewrite OR post-rewrite validated_qa check finds matches above threshold → use them with LLM. If BOTH checks fail (no matches or all below threshold) → fall through to the existing manual-chunks pipeline (not the fallback message). The fallback message from Fix 2 should be returned ONLY if the entire pipeline (validated_qa + manual-chunks) fails to produce a grounded answer. This preserves the existing fallback behavior while adding the threshold to validated_qa.

  **ACTUALLY — follow the user's spec literally**: Re-reading the user's description: "If the highest similarity score among the top 3 is below 0.70, do NOT call the LLM. Instead return a fixed response immediately." The user wants the threshold to gate the validated_qa → LLM path. If below threshold on validated_qa, the manual-chunks pipeline still runs. The fallback is only for when validated_qa is the ONLY path being used. Since validated_qa is a shortcut that runs BEFORE the manual-chunks pipeline, if it doesn't match well, we just fall through. The threshold prevents a low-quality validated_qa match from being sent to the LLM — it does NOT prevent the manual-chunks pipeline from running.

  **Final approach**:
  - Pre-rewrite validated_qa: if matches exist and max_score >= 0.70 → LLM with validated_qa context → return
  - Pre-rewrite validated_qa: if no matches or max_score < 0.70 → continue to rewrite + post-rewrite check
  - Post-rewrite validated_qa: same logic
  - If both validated_qa checks miss → continue to manual-chunks pipeline (existing behavior, unchanged)

**Checkpoint**: The validated_qa path now fetches top 3, applies threshold, and either calls LLM with combined context or falls through to manual-chunks. The strict system prompt (T005) and response shape (T006) are still needed.

---

## Phase 4: User Story 3 — Strict System Prompt (Priority: P2)

**Goal**: Add a strict context-only system prompt for validated_qa RAG calls.

**Independent Test**: Ask a question where context is tangentially related. The LLM should say "I don't have that information" rather than guessing.

- [x] T005 [US3] Add the strict validated_qa system prompt constant in `backend/services/manual_rag_service.py`

  **What to do**: Add a module-level constant (near the constants from T001):

  ```python
  # --- Strict system prompt for validated QA RAG (spec 069) ---
  VALIDATED_QA_SYSTEM_PROMPT = (
      "You are a technical assistant for a civil aviation maintenance management system (CMMS).\n\n"
      "Your job is to answer maintenance and operations questions using ONLY the context provided below.\n\n"
      "Rules:\n"
      "- Answer ONLY from the provided context. Do not use outside knowledge.\n"
      "- If the answer is not clearly stated in the context, respond with exactly: "
      "\"I don't have that information in the knowledge base.\"\n"
      "- Never guess, infer, or make up technical specifications, procedures, or values.\n"
      "- Be concise and direct. Use bullet points for procedures.\n"
      "- Always refer to the source when answering (e.g. \"According to source 1...\").\n"
      "- If multiple sources are relevant, synthesize them into one clear answer."
  )
  ```

  **How it's used**: In the validated_qa → LLM call (T003/T004), build the prompt like:

  ```python
  prompt = (
      f"{VALIDATED_QA_SYSTEM_PROMPT}\n\n"
      f"CONTEXT:\n{combined_context}\n\n"
      f"QUESTION: {question}\n\nANSWER:"
  )
  ```

  Then call `provider_generate(prompt, [], user_email, latency_breakdown=breakdown)` — the same resolver used by the manual-chunks path.

  **NOTE**: This prompt is SEPARATE from the existing `_build_prompt()` function (line ~106), which is used for the manual-chunks path. Do NOT modify `_build_prompt()`. The validated_qa path builds its own prompt with the strict system prompt + combined validated_qa context.

**Checkpoint**: Strict system prompt defined and used in the validated_qa → LLM flow.

---

## Phase 5: User Story 4 — Source References in Response (Priority: P2)

**Goal**: Every validated_qa response includes `confidence`, `score`, and `sources` array.

**Independent Test**: Curl the endpoint and verify the response JSON contains the new fields.

- [x] T006 [US4] Build the enriched response dict for validated_qa hits in `backend/services/manual_rag_service.py`

  **What to do**: In the blocks modified by T003/T004, after the LLM call succeeds, build the response:

  ```python
  max_score = max(m["similarity"] for m in matches)
  
  # Confidence band
  if max_score >= RAG_HIGH_CONFIDENCE:
      confidence = "high"
  elif max_score >= RAG_CONFIDENCE_THRESHOLD:
      confidence = "medium"
  else:
      confidence = "low"
  
  sources = [
      {
          "id": m["id"],
          "question_text": m["question_text"],
          "score": m["similarity"],  # already rounded to 2dp in T002
      }
      for m in matches
  ]
  
  return {
      "answer": answer,  # from LLM
      "grounded": True,
      "sources": sources,
      "confidence": confidence,
      "score": max_score,
      "model": provider_display_name,
      "provider_display_name": provider_display_name,
      "duration_seconds": round(gen_elapsed, 1),
      "is_verified": True,
      "verified_source": {
          "validated_qa_id": str(matches[0]["id"]),
          "validated_by": matches[0]["validated_by"],
          "validated_at": matches[0]["validated_at"].isoformat()
          if hasattr(matches[0]["validated_at"], "isoformat")
          else str(matches[0]["validated_at"]),
          "similarity": max_score,
      },
      "retrieval_info": retrieval_info,
      "provider_used": provider_used,
      "fallback_used": fallback_used,
      "session_summary": memory if needs_compression else None,
      "latency_breakdown": breakdown,
  }
  ```

  **IMPORTANT**: Keep `is_verified` and `verified_source` for backward compatibility with the frontend. The `sources` array is the new field. The frontend currently ignores unknown fields, so `confidence` and `score` are safe to add.

- [x] T007 [US4] Verify the router in `backend/routers/manuals.py` passes through the new fields

  **What to check**: The `ask_question()` function in `manuals.py` (line ~331) calls `rag_service.ask()` and returns its result. Since `ask()` returns a dict and the router returns it directly, the new fields (`confidence`, `score`, enriched `sources`) should pass through automatically.

  **Verify**: Read the router code and confirm there's no response model or field filtering that would strip the new fields. If there IS a Pydantic response model, add the new fields to it. If it's a plain dict return, no changes needed.

**Checkpoint**: Full response shape with `confidence`, `score`, `sources` is returned. All 4 fixes are complete.

---

## Phase 6: Polish & Verification

**Purpose**: End-to-end validation

- [ ] T008 Run curl test for a well-matched question against `POST /api/manuals/ask`

  ```bash
  curl -X POST http://localhost:8000/api/manuals/ask \
    -H "Content-Type: application/json" \
    -d '{"question": "how do I retrieve incoming messages"}'
  ```

  **Expected**: Response contains `answer` (LLM-generated), `confidence` ("high" or "medium"), `score` (>= 0.70), `sources` (array of up to 3 entries with `id`, `question_text`, `score`).

- [ ] T009 Run curl test for an off-topic question against `POST /api/manuals/ask`

  ```bash
  curl -X POST http://localhost:8000/api/manuals/ask \
    -H "Content-Type: application/json" \
    -d '{"question": "what is the weather in Kuwait today"}'
  ```

  **Expected**: If validated_qa has no matches above 0.70, the system falls through to the manual-chunks pipeline. If manual-chunks also finds nothing, the existing "This information is not in the available manuals" response is returned. The key verification: no validated_qa → LLM call was made for this off-topic query.

- [ ] T010 Verify backward compatibility — existing fields unchanged

  Check that the response still contains `answer`, `grounded`, `sources` (now enriched), `is_verified`, `verified_source`, `retrieval_info`, `latency_breakdown`. No existing field removed or renamed.

- [ ] T011 Show diff of all changed files

  ```bash
  git diff
  ```

  **Expected changed files**:
  - `backend/services/validated_qa_service.py` — `check_validated_match()` modified
  - `backend/services/manual_rag_service.py` — constants, prompt, response handling modified
  - `backend/routers/manuals.py` — possibly unchanged (if dict passthrough)

  **Must NOT appear in diff**:
  - Any `frontend/` files
  - Any `supabase/migrations/` files
  - `backend/services/ai_providers/resolver.py`
  - Any `.env` files

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1. BLOCKS all user stories.
- **Phase 3 (US1+US2)**: Depends on Phase 2. This is the MVP.
- **Phase 4 (US3)**: Depends on Phase 3 (needs the LLM call point to exist)
- **Phase 5 (US4)**: Depends on Phase 3 (needs the response building point to exist)
- **Phase 4 and Phase 5 can run in parallel** — US3 touches the prompt, US4 touches the response dict. Different parts of the code.
- **Phase 6 (Polish)**: Depends on all previous phases

### Task Execution Order

```
T001 → T002 → T003 → T004 → T005 + T006 (parallel) → T007 → T008 → T009 → T010 → T011
```

### Parallel Opportunities

- **T005 and T006** can be implemented in parallel (prompt constant vs response dict — different concerns)
- **T008, T009, T010** can be run in parallel (independent curl tests)

---

## Implementation Strategy

### MVP First (Phase 1-3)

1. T001: Add constants
2. T002: Modify `check_validated_match()` for top 3
3. T003 + T004: Rewrite the validated_qa blocks in `ask()`
4. **STOP and VALIDATE**: The core multi-chunk + threshold flow works

### Incremental Delivery

1. Phases 1-3 → Multi-chunk + threshold working → Test
2. Phase 4 → Strict prompt added → Test (answers should be more grounded)
3. Phase 5 → Source references in response → Test (verify JSON shape)
4. Phase 6 → Full verification

---

## Notes

- All changes are in 2-3 Python files under `backend/`
- The `search_validated_qa` RPC already supports `match_count` parameter — just pass 3 instead of 1
- Distance (from RPC) must be converted to similarity: `similarity = 1.0 - distance`
- The manual-chunks RAG pipeline is untouched — only the validated_qa shortcut path changes
- Keep existing logging patterns — add `logger.info()` for the new threshold decisions
- Commit after each phase for clean history
