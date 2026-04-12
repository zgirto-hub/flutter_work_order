# Research: RAG Query Rewrite

**Feature**: 042-rag-query-rewrite | **Date**: 2026-04-12

## R1: Query Rewrite Prompt Design

**Decision**: Use a simple system prompt with the Gemma model (same `ollama_generator.generate()`) that instructs the model to rewrite the user's question into a self-contained search query, given the last 3 conversation turns as context.

**Rationale**: The existing `generate()` function in `ollama_generator.py` already handles Ollama API calls, timeouts, and error handling. A dedicated prompt template is simpler and more maintainable than a separate API call or service. The Gemma e2b model (already loaded in memory on the server) is capable of this lightweight rewriting task.

**Alternatives considered**:
- Separate rewrite model (e.g., a smaller model): Rejected — loading a second model on a 15GB RAM server is not feasible alongside Gemma e2b.
- Rule-based rewriting (regex substitution): Rejected — cannot handle complex coreference resolution ("the second point", "that issue").
- Chat API `/api/chat` instead of `/api/generate`: Rejected — `generate()` is already battle-tested in this codebase; no benefit to switching.

## R2: Conversation History Format for Rewrite

**Decision**: Pass the last 3 `HistoryTurn` entries (each containing `question` and `answer` fields) as plain text context in the rewrite prompt. If fewer than 3 turns exist, use whatever is available.

**Rationale**: The `history` parameter is already passed from the frontend as a list of `{question, answer}` dicts. The router (`manuals.py`) already validates this via the `HistoryTurn` Pydantic model. No additional data fetching is needed.

**Alternatives considered**:
- Use all available history (up to 10 turns, the current prompt limit): Rejected — increases rewrite prompt size and latency without meaningful benefit. 3 turns captures sufficient context for reference resolution.
- Store history server-side and fetch from DB: Rejected — conversation memory is client-side by design (spec 040), and no DB table exists for it.

## R3: Fallback Strategy

**Decision**: Wrap the rewrite call in a try/except. On any failure (timeout, error, empty response), log a warning and return the original user question unmodified. The pipeline continues with the original query.

**Rationale**: The rewrite is an optimization, not a correctness requirement. The existing pipeline works without it (current production behavior). A failed rewrite should never block the user from getting an answer.

**Alternatives considered**:
- Retry once before fallback: Rejected — adds latency; if Ollama is struggling, a retry likely fails too. YAGNI.
- Return an error to the user: Rejected — contradicts graceful degradation principle.

## R4: Rewrite Timeout

**Decision**: Use a 10-second timeout for the rewrite call (separate from the 180s generation timeout). This keeps the total rewrite overhead well under the 2s target for typical cases while allowing headroom for cold-start scenarios.

**Rationale**: On this server, Gemma e2b typically responds to short prompts in 1-3 seconds. A 10s timeout is generous enough to avoid false timeouts but short enough to not stall the pipeline excessively. The 2s success criterion is a typical-case target, not a hard timeout.

**Alternatives considered**:
- 2s hard timeout: Rejected — would cause frequent fallbacks on a busy server or cold Ollama process.
- 30s timeout (same as embedder): Rejected — too long; user would wait 30s before fallback kicks in.

## R5: Integration Point

**Decision**: Add a `_rewrite_query()` async function in `manual_rag_service.py`. Call it immediately before `embed_single(question)` at line 269. The function receives the raw question and history, returns the rewritten query string. The rewritten query replaces the question for embedding only — the original question is still passed to `_build_prompt()` for answer generation.

**Rationale**: This is the minimal-touch integration. The `ask()` function already has both `question` and `history` in scope. The rewritten query only affects the embedding step (line 269) and vector search. The answer generation prompt (line 323) continues using the original question, which preserves natural conversation flow.

**Alternatives considered**:
- Use rewritten query for both retrieval and generation: Rejected — the generation prompt already includes conversation history (Layer 3), so the LLM already has context. Using the rewritten query there could produce awkward answers that don't match the user's actual phrasing.
- Add rewrite as a separate middleware/service: Rejected — overengineering for a single function call. Violates YAGNI.
