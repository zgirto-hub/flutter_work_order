# Research: HyDE Retrieval for Manual Assistant

**Date**: 2026-04-12 | **Branch**: `043-hyde-retrieval`

## R1: HyDE Prompt Design

**Decision**: Use a short, domain-specific system prompt that instructs the model to write a 1-2 paragraph excerpt from a civil aviation technical manual answering the question. The prompt must specify: match the language of the question, write in technical manual style, do not add disclaimers or preamble.

**Rationale**: HyDE works by generating a text in the same "document space" as the corpus. A domain-specific prompt (civil aviation maintenance manual) produces embeddings closer to the actual manual chunks than a generic answer. Short output (1-2 paragraphs) keeps generation fast and embedding focused.

**Alternatives considered**:
- Generic "answer this question" prompt — produces conversational text whose embeddings are farther from technical manual style
- Multiple hypothetical documents (multi-HyDE) — more accurate but doubles/triples latency; not viable on 15 GB RAM server

## R2: HyDE Timeout

**Decision**: Use 15-second timeout for HyDE generation (same `generate()` function with `timeout=15.0`).

**Rationale**: Query rewrite uses 10s. HyDE output is slightly longer (1-2 paragraphs vs. one sentence) so 15s provides margin. The final answer generation uses 180s default, so 15s is well within user tolerance. On timeout, fallback to direct query embedding is immediate.

**Alternatives considered**:
- 10s (same as query rewrite) — too tight for 1-2 paragraph generation on a loaded server
- 30s — too long; if HyDE takes 30s, total pipeline time becomes unacceptable
- Separate lighter model for HyDE — avoids RAM doubling but requires model management; rejected per YAGNI

## R3: Pipeline Integration Point

**Decision**: Insert HyDE between `_rewrite_query()` and `embed_single()` in the `ask()` function. The flow becomes:
1. `_rewrite_query(question, history)` → `search_query`
2. `_generate_hypothetical_answer(search_query)` → `hyde_text` (or fallback to `search_query`)
3. `embed_single(hyde_text)` → `question_embedding`
4. pgvector RPC search
5. `_build_prompt(chunks, question, history)` (uses original question, not hyde_text)
6. `generate(prompt)` → final answer

**Rationale**: This placement ensures query rewriting resolves pronouns first, then HyDE operates on a clean self-contained query. The original question is preserved for the final prompt (FR-008).

**Alternatives considered**:
- HyDE before query rewrite — would generate hypothetical from ambiguous follow-up text; worse results
- HyDE in the embedder service — wrong layer; HyDE is a RAG concern, not an embedding concern
- Parallel HyDE + direct embedding — could use both vectors for retrieval but adds complexity; rejected per YAGNI

## R4: Fallback Strategy

**Decision**: On any failure (timeout, empty response, exception), log a warning and fall back to embedding the `search_query` directly (current behavior). No retry.

**Rationale**: HyDE is an optimization. The fallback path is the existing proven behavior. Retrying doubles latency for a probabilistic improvement. Fire-and-forget logging keeps the request path clean per constitution principle VI.

**Alternatives considered**:
- Retry once — adds up to 30s worst case; not worth it
- Return error to user — violates FR-004; HyDE failure should be invisible to the user

## R5: Observability

**Decision**: Log at `logger.info` level on successful HyDE generation (include length of hypothetical text). Log at `logger.warning` on fallback (include reason: timeout/empty/exception). No new metrics endpoint.

**Rationale**: Consistent with existing `_rewrite_query()` logging pattern. Info-level for success keeps logs useful without flooding. Warning-level for fallback makes failures visible in log monitoring.

**Alternatives considered**:
- Debug-level for success — too easy to miss when tuning
- New metrics/stats endpoint — YAGNI; log-based monitoring is sufficient for this team size
