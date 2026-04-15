# Phase 1 Data Model: Per-Stage RAG Latency

**Feature**: 066-stage-latency-breakdown
**Date**: 2026-04-15
**Scope**: Transient in-memory / in-response shapes only. **No database tables, no migrations, no persisted state.**

---

## Entity: `LatencyBreakdown` (transient, per-response)

Represents the per-stage millisecond measurements for one `/manuals/ask` invocation. Lives only for the duration of a single request; attached to the response; never stored.

### Fields

| Field | Type | Nullable | Description |
|-------|------|----------|-------------|
| `embed_ms` | integer (ms) | yes | Elapsed wall-clock for query-embedding stage. `null` if stage was skipped (greeting bypass) or raised an exception. |
| `hyde_ms` | integer (ms) | yes | Elapsed wall-clock for HyDE hypothetical-answer generation. `null` if HyDE disabled, greeting bypass, or stage raised. |
| `rewrite_ms` | integer (ms) | yes | Elapsed wall-clock for query rewrite. `null` if rewrite disabled, greeting bypass, or stage raised. |
| `retrieval_ms` | integer (ms) | yes | Elapsed wall-clock for pgvector retrieval RPC. `null` if greeting bypass or stage raised. |
| `rerank_ms` | integer (ms) | yes | Elapsed wall-clock for rerank pass. `null` if fewer than two candidates, greeting bypass, or stage raised. |
| `generator_ms` | integer (ms) | yes | Elapsed wall-clock for final LLM generation, measured at the resolver level so it reflects the provider that actually answered (post-fallback). `null` for greeting bypass (canned reply) or if the call raised. |
| `total_ms` | integer (ms) | **no** | Full request wall-clock from `/ask` handler entry to just-before-response-serialization. Never `null`, always ≥ 0. |

### Validation rules

- Every key is always present in the emitted JSON object (FR-002).
- Nullable keys are either a non-negative integer or `null`. **No zero-placeholder, no negative values, no floats.**
- `total_ms` is authoritative for wall-clock; frontend MUST display `total_ms` directly rather than summing stage values (FR-003). Stage values may not sum to total because stages can overlap (future), be skipped (now), or include sub-measurements absorbed into the gap.
- Values represent integer milliseconds obtained via `round((end - start) * 1000)` using `time.perf_counter()`.

### State transitions

None — the object is built once per request and discarded after response serialization. It has no lifecycle beyond the HTTP response.

### Python representation (Pydantic)

```python
# backend/services/manual_rag_service.py  (or a nearby types module)
from typing import Optional
from pydantic import BaseModel, Field

class LatencyBreakdown(BaseModel):
    embed_ms: Optional[int] = Field(default=None, ge=0)
    hyde_ms: Optional[int] = Field(default=None, ge=0)
    rewrite_ms: Optional[int] = Field(default=None, ge=0)
    retrieval_ms: Optional[int] = Field(default=None, ge=0)
    rerank_ms: Optional[int] = Field(default=None, ge=0)
    generator_ms: Optional[int] = Field(default=None, ge=0)
    total_ms: int = Field(ge=0)

    class Config:
        # Always emit all seven keys, including nulls. Pydantic v1: default.
        # Pydantic v2: ensure model_dump(exclude_none=False) at serialization.
        pass
```

### Dart representation

```dart
// frontend/lib/models/latency_breakdown.dart
class LatencyBreakdown {
  final int? embedMs;
  final int? hydeMs;
  final int? rewriteMs;
  final int? retrievalMs;
  final int? rerankMs;
  final int? generatorMs;
  final int totalMs;

  const LatencyBreakdown({
    this.embedMs,
    this.hydeMs,
    this.rewriteMs,
    this.retrievalMs,
    this.rerankMs,
    this.generatorMs,
    required this.totalMs,
  });

  factory LatencyBreakdown.fromJson(Map<String, dynamic> json) => LatencyBreakdown(
        embedMs: json['embed_ms'] as int?,
        hydeMs: json['hyde_ms'] as int?,
        rewriteMs: json['rewrite_ms'] as int?,
        retrievalMs: json['retrieval_ms'] as int?,
        rerankMs: json['rerank_ms'] as int?,
        generatorMs: json['generator_ms'] as int?,
        totalMs: json['total_ms'] as int,
      );
}
```

---

## Entity: `ManualQaAnswer` (existing, modified)

Unchanged existing fields. One additive field:

| Field | Type | Nullable | Notes |
|-------|------|----------|-------|
| `latencyBreakdown` | `LatencyBreakdown` | **yes** | Present when the backend is running the new instrumentation; `null` when parsing a response from an older backend (graceful degradation — the field is strictly additive per FR-009). |

The Dart model's `fromJson` sets `latencyBreakdown = json['latency_breakdown'] == null ? null : LatencyBreakdown.fromJson(...)`.

---

## Persistence

**None.** The feature is observability-only (FR-010, clarification Q2). No rows are written to `user_activity_log`, `answer_ratings`, or any other table. No file is written to disk.

## Relationships

`LatencyBreakdown` is composed into `ManualQaAnswer` via JSON response only. It has no relationships to any persisted entity.
