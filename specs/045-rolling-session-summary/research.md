# Research: Rolling Session Summary

**Feature**: 045-rolling-session-summary  
**Date**: 2026-04-13

## R1: Compression Prompt Design

**Decision**: Use a dedicated system prompt instructing the LLM to summarize conversation turns into 3-4 sentences, preserving all technical facts, part numbers, specifications, and procedures.

**Rationale**: The compression call is a simple summarization task — no RAG, no chunk retrieval. A focused prompt with explicit instructions to preserve technical details produces concise, fact-dense summaries. Using the same Ollama `generate()` function already in the codebase keeps the implementation minimal.

**Alternatives considered**:
- Extractive summarization (pull key sentences) — rejected because conversation turns are Q&A pairs, not narrative text; extractive methods would miss cross-turn context.
- Keyword extraction instead of summary — rejected because it loses relational context (e.g., "the pump pressure is 3000 psi" becomes just "pump, pressure, 3000 psi").

## R2: Summary Persistence Between Requests

**Decision**: Backend returns `session_summary` string in the ask response JSON. Flutter stores it in ChatTab state and sends it back as an optional field in each subsequent request. The backend only re-compresses when new turns have aged out beyond the last 4 window — otherwise it reuses the summary the frontend sent back.

**Rationale**: This eliminates the recompression cost after the first compression. A 20-turn conversation pays the compression cost once (at turn 9) and then only incrementally when new turns push older ones past the 4-turn raw window. The frontend change is minimal — one field added to the request model and one field stored in state. The compression logic still lives entirely on the backend; the frontend is just a pass-through cache.

**Alternatives considered**:
- Full recompression each request (backend recomputes summary from scratch every time) — rejected because it wastes LLM compute on identical input; a 20-turn conversation would re-summarize turns 1-16 on every request.
- Backend-side session cache (in-memory dict keyed by user) — rejected per YAGNI; adds statefulness to a stateless request handler and introduces cache invalidation complexity.

## R3: Prompt Assembly with Memory Field

**Decision**: Insert the summary as a `CONVERSATION MEMORY:` block between the manual sections and the raw conversation history in `_build_prompt()`.

**Rationale**: The LLM needs the summary for context but must distinguish it from verbatim recent turns. Placing it before recent history follows a temporal ordering (old context → recent context → current question) that helps the LLM understand what's established background vs. active discussion.

**Prompt structure** (when compression active):
```
[System instructions]
[MANUAL SECTIONS: ...]
[CONVERSATION MEMORY: <3-4 sentence summary>]
[CONVERSATION HISTORY: <last 4 raw turns>]
[QUESTION: ...]
[ANSWER:]
```

**Alternatives considered**:
- Merge summary into system instructions — rejected because system instructions are cached and shared across all requests.
- Place summary after recent history — rejected because it breaks temporal ordering.

## R4: Fallback Behavior on Compression Failure

**Decision**: On any exception during the compression LLM call (timeout, connection error, malformed response), fall back to the current behavior: pass the last 10 raw turns to `_build_prompt()` with no summary.

**Rationale**: The compression step is an enhancement, not a requirement. The system must degrade gracefully. Logging the failure is sufficient; no user-facing error is needed.

**Alternatives considered**:
- Retry the compression call once — rejected because it doubles latency on failure and the fallback is perfectly acceptable.
- Send all turns without compression — rejected because this could exceed context window limits for very long conversations.

## R5: Ollama Model for Compression

**Decision**: Use the same model as the main answer generation (gemma4:e2b, or whatever model is passed/configured). No separate model for compression.

**Rationale**: Using the same model avoids loading a second model into the 15 GB RAM-constrained server. The compression task is simple enough that the same model handles it well. The `generate()` function already supports model selection.

**Alternatives considered**:
- Use a smaller/faster model for compression — rejected because loading a second model would consume additional RAM on the 15 GB server, and Ollama may need to swap models.
