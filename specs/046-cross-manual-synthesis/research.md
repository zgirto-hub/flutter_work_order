# Research: Cross-Manual Synthesis (Layer 4)

**Date**: 2026-04-13 | **Branch**: `046-cross-manual-synthesis`

## R1: Ollama Concurrency Model

**Decision**: Sub-answer generation is sequential (one call at a time)

**Rationale**: Ollama gemma4:e2b on a 15GB RAM server processes inference requests sequentially on the GPU. Sending parallel requests would just queue them internally. Sequential calls with `asyncio` are cleaner and avoid hidden queuing behavior. If the server is later upgraded to multiple Ollama instances or a model-serving backend that supports batching, the sequential loop can be replaced with `asyncio.gather`.

**Alternatives considered**:
- `asyncio.gather` for all sub-answers simultaneously — rejected because Ollama serializes anyway; adds complexity without benefit
- Batch API (Ollama doesn't support multi-prompt batching in a single request) — not available

## R2: Per-Manual Retrieval Strategy

**Decision**: Call existing `search_manual_chunks` RPC once per manual with `manual_id_filter` set

**Rationale**: The existing RPC already supports filtering by manual_id and returns distance-sorted results. Calling it N times (once per manual) is simpler than writing a new RPC that groups results. pgvector queries are fast (~5-20ms each), so even 15 calls add <300ms total — negligible compared to LLM generation time (~10-15s per sub-answer).

**Alternatives considered**:
- New SQL RPC `search_manual_chunks_grouped` that returns results partitioned by manual — rejected per YAGNI; existing RPC works, and a new migration adds unnecessary complexity
- Single call with `match_count=50` then group client-side — rejected because distance-based ranking across manuals creates bias toward manuals with many chunks

## R3: Sub-Answer Cap

**Decision**: Cap at 8 manuals maximum for sub-answer generation

**Rationale**: With ~15s per sub-answer (sequential Ollama), 8 manuals = ~2 minutes worst case. The 3x latency target from the spec (SC-004) allows ~45s, so in practice 3-4 manuals is the sweet spot. The cap of 8 is a safety valve for large corpora. Manuals are ranked by average chunk distance (most relevant first) when exceeding the cap.

**Alternatives considered**:
- No cap (process all) — rejected; 20+ manuals would mean 5+ minutes
- Cap at 5 — considered too restrictive for a corpus with many specialized manuals
- Cap at 3 — too aggressive; misses relevant manuals

## R4: Conflict Detection Strategy

**Decision**: Instruct the synthesis prompt to use a "⚠ CONFLICT:" marker, then detect it in the response text

**Rationale**: Simple string detection is reliable and doesn't require a separate LLM call or structured output parsing. The marker is distinctive enough to avoid false positives in aviation maintenance text. The frontend checks `has_conflicts` boolean (set server-side) rather than parsing the answer text.

**Alternatives considered**:
- Separate "conflict detection" LLM call after synthesis — rejected; doubles latency for a secondary concern
- Structured JSON output from Ollama — rejected; gemma4:e2b is unreliable for strict JSON adherence
- Semantic similarity comparison between sub-answers — too complex, unreliable

## R5: Sources Aggregation for Synthesized Answers

**Decision**: Collect all qualifying chunks from all contributing manuals into a single `sources` list

**Rationale**: The existing `sources` array format already includes `manual_id` and `manual_title` per source, so cross-manual sources work without format changes. Highlight computation (Jaccard overlap) runs against the final synthesized answer, which references content from multiple manuals — this may reduce highlight precision slightly but maintains backward compatibility.

**Alternatives considered**:
- Separate sources per manual (nested structure) — rejected; breaks existing frontend contract
- Only include sources from the "most relevant" manual — rejected; loses attribution for synthesized content
