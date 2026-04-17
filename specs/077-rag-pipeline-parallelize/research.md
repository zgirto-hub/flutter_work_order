# Research: RAG Pipeline Latency Optimization

**Date**: 2026-04-17  
**Feature**: 077-rag-pipeline-parallelize

## Research Task 1: asyncio.gather() for Concurrent Ollama Calls

**Decision**: Use `asyncio.gather(return_exceptions=True)` to run `_rewrite_query()` and `_generate_hypothetical_answer()` concurrently.

**Rationale**: Both functions are independent — rewrite uses conversation history to expand the query, HyDE generates a hypothetical passage from the original question. Neither depends on the other's output. `asyncio.gather(return_exceptions=True)` allows both to proceed and captures failures without cancelling the other task.

**Alternatives considered**:
- `asyncio.create_task()` + `await` — equivalent but more verbose; `gather` is cleaner for exactly two tasks.
- `asyncio.TaskGroup` (Python 3.11+) — project uses Python 3.10, not available.
- Sequential with reduced timeouts — doesn't solve the fundamental problem.

**Key finding**: Ollama uses a single GPU and may serialize concurrent inference requests internally. If so, parallelization won't reduce wall-clock time but also won't cause errors. The `_StageTimer` context manager writes to distinct keys (`rewrite_ms`, `hyde_ms`) in the shared breakdown dict, so concurrent writes are safe (no key collision).

## Research Task 2: Direct-Lookup Heuristic Design

**Decision**: Use a pure regex/pattern-matching function `_is_direct_lookup(query)` that returns `True` if the query contains identifiable technical terms that make HyDE unnecessary.

**Rationale**: HyDE generates a hypothetical manual passage to improve embedding quality. For queries containing exact technical identifiers (hostnames, IPs, component names), the original query already contains the exact terms that would appear in the relevant chunks. HyDE adds ~5-15s of Ollama inference time with no retrieval benefit for these queries.

**Patterns to match**:
1. **IP addresses**: `\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b` — any dotted-quad IPv4
2. **Hostnames**: `\b[a-z]{2,5}\d?-(ops|cont|mux)\b` — matches the `{prefix}{digit}-{suffix}` pattern used across all server hostnames (as1-ops, cs2-cont, efg-mux, eaip1-ops, cims1-cont, proxy1-ops, etc.)
3. **Component names with numbers**: `\b(AIDA|ATS|CISECA|IMS|eAIP|Mux|EFG)\s*\d*\b` — case-insensitive, matches "AIDA 1", "ATS 2", "CISECA", "Mux 1", etc.

**Alternatives considered**:
- LLM-based classification — adds latency, defeats the purpose.
- Database lookup of known terms — adds I/O and complexity; the domain is small and stable.
- Configurable pattern list in `app_settings` — YAGNI; the aviation department's naming conventions don't change. Can be added later if needed.

**Edge case handling**: Short ambiguous queries like "ip?" or single words ("aida") should NOT trigger the skip — require the query to contain a sufficiently specific identifier. The hostname regex requires the full `prefix-suffix` pattern; bare "as1" won't match. Component names require the full word boundary match.

## Research Task 3: _StageTimer Concurrency Safety

**Decision**: Safe to use concurrently — each `_StageTimer` instance writes to a different key in the `breakdown` dict.

**Rationale**: Python's GIL ensures dict writes are atomic. `_StageTimer("rewrite_ms")` and `_StageTimer("hyde_ms")` write to different keys and never read each other's values. In `asyncio.gather()` context, only one coroutine executes at a time between await points, so even without the GIL guarantee, there's no race condition.

**Adaptation needed**: The current code uses `_StageTimer` as a context manager (`with _StageTimer(...)`). For parallel execution, each stage needs its own timer. Since `asyncio.gather()` runs two separate coroutines, each can independently use `with _StageTimer(breakdown, key)` inside its own coroutine wrapper — no changes to `_StageTimer` itself.

## Research Task 4: Post-Parallel Pipeline Flow

**Decision**: After `asyncio.gather()` completes, the pipeline continues exactly as before: use rewritten query for system detection and validated QA, use HyDE text (or rewritten query if HyDE failed/skipped) for embedding.

**Rationale**: The only change is the timing of when rewrite and HyDE results become available (simultaneously instead of sequentially). The downstream flow is unchanged:
1. `search_query` = result of rewrite (or original if no history)
2. `_layer2_hyde_text` = result of HyDE (or `None` if skipped/failed)
3. `embed_input` = `_layer2_hyde_text if _layer2_hyde_text else search_query`
4. Everything after embedding is unchanged.

**Note on HyDE input**: In the current sequential flow, HyDE runs on `search_query` (the rewritten query). In the parallel flow, HyDE runs on the original `question` since rewrite hasn't completed yet. This is acceptable because HyDE's purpose is to generate a hypothetical passage — the original question contains the same core intent. The rewritten query mainly adds context for follow-ups, which HyDE doesn't need.
