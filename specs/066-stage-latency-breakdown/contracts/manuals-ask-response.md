# Contract: `POST /manuals/ask` Response Delta

**Feature**: 066-stage-latency-breakdown
**Status**: Additive — existing consumers unaffected
**Baseline**: Spec 065 (`065-fix-provider-display-audit`) response shape

---

## Change summary

Add one top-level field `latency_breakdown` to the `/manuals/ask` success response. No fields are removed, renamed, or restructured.

## Response delta (added field)

```jsonc
{
  // ... all existing fields from spec 065 baseline (answer, sources, provider, ...) unchanged ...

  "latency_breakdown": {
    "embed_ms":     123,   // non-negative int | null
    "hyde_ms":      null,  // non-negative int | null (null when HyDE disabled)
    "rewrite_ms":   89,    // non-negative int | null
    "retrieval_ms": 412,   // non-negative int | null
    "rerank_ms":    207,   // non-negative int | null
    "generator_ms": 1180,  // non-negative int | null (the provider that ACTUALLY answered, post-fallback)
    "total_ms":     2135   // non-negative int, NEVER null
  }
}
```

### Field rules

1. **All seven keys are always present** in the object. Consumers may rely on this.
2. `total_ms` is never `null`; all other keys MAY be `null`.
3. Values are integer milliseconds, ≥ 0. No floats, no negatives, no zero-as-sentinel.
4. `total_ms` is the full request wall-clock and is authoritative. Consumers MUST NOT sum the six stage values to compute total.
5. When the greeting bypass short-circuits (trivial inputs like "hi", "thanks", "salam", "شكرا"), `total_ms` is populated and all other keys are `null`.
6. When a stage raises an exception but the request still returns successfully (via fallback), that stage's key is `null`.
7. `generator_ms` reflects the provider that actually produced the answer. If the primary provider failed and a fallback succeeded, `generator_ms` measures only the successful fallback call (not the failed primary retry window).

### Backward compatibility (FR-009)

- Old clients that do not know about `latency_breakdown` MUST continue to work. The field is ignorable.
- New clients seeing a response from an old backend (missing the field) MUST render the answer normally and omit latency display — treated as if the entire breakdown were unavailable.

---

## Example: normal (all stages ran)

```json
{
  "answer": "...",
  "sources": [ ... ],
  "provider": { "name": "groq", "model": "llama-3.3-70b-versatile", "display_label": "Groq (Llama 3.3 70B)" },
  "latency_breakdown": {
    "embed_ms": 98, "hyde_ms": 3412, "rewrite_ms": 201,
    "retrieval_ms": 387, "rerank_ms": 176, "generator_ms": 1243,
    "total_ms": 5571
  }
}
```

## Example: HyDE disabled

```json
{
  "latency_breakdown": {
    "embed_ms": 102, "hyde_ms": null, "rewrite_ms": 198,
    "retrieval_ms": 412, "rerank_ms": 181, "generator_ms": 1198,
    "total_ms": 2110
  }
}
```

## Example: Greeting bypass

```json
{
  "answer": "Hi! Ask me anything about your manuals.",
  "latency_breakdown": {
    "embed_ms": null, "hyde_ms": null, "rewrite_ms": null,
    "retrieval_ms": null, "rerank_ms": null, "generator_ms": null,
    "total_ms": 2
  }
}
```

## Example: Fallback (primary Groq failed, secondary Mistral succeeded)

```json
{
  "provider": { "name": "mistral", "model": "mistral-large-latest", "display_label": "Mistral (Large)" },
  "latency_breakdown": {
    "embed_ms": 101, "hyde_ms": 3390, "rewrite_ms": 195,
    "retrieval_ms": 398, "rerank_ms": 170,
    "generator_ms": 1402,   // measures only the Mistral call, not the failed Groq attempt
    "total_ms": 8105        // includes the failed Groq attempt in wall-clock
  }
}
```

## Example: Stage failure (rerank raised but pipeline continued)

```json
{
  "latency_breakdown": {
    "embed_ms": 99, "hyde_ms": 3401, "rewrite_ms": 203,
    "retrieval_ms": 395,
    "rerank_ms": null,       // stage raised; other values unaffected
    "generator_ms": 1211,
    "total_ms": 5412
  }
}
```

---

## Consumer impact

- **Existing frontend (pre-066)**: no change; ignores the new field.
- **New frontend (066)**: parses `latency_breakdown` into `LatencyBreakdown` (see [data-model.md](../data-model.md)); when the field is absent, renders as pre-066 (no breakdown UI).
- **Activity log**: no change — this feature is observation-only, not persisted (FR-010).

## Out of contract scope

- Other AI endpoints (`/api/ai/analytics-insights`, `/api/work-orders/ai-description`, `/api/work-orders/nl-search`, session summary, cross-manual synthesis) are **not** modified by this contract. Phase 2 may extend the pattern.
