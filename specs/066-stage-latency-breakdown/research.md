# Phase 0 Research: Per-Stage RAG Latency Instrumentation

**Feature**: 066-stage-latency-breakdown
**Date**: 2026-04-15
**Status**: Complete — no open NEEDS CLARIFICATION items

All Technical Context fields resolved; no unknowns. Research below documents the key design decisions that shape Phase 1 contracts.

---

## Decision 1: Timing primitive

**Decision**: Use Python `time.perf_counter()` (monotonic, nanosecond-resolution) captured on entry/exit of each stage, converted to integer milliseconds via `round((end - start) * 1000)`.

**Rationale**:
- Monotonic — not affected by wall-clock adjustments (NTP, DST).
- Higher resolution than `time.time()`; overhead is sub-microsecond per call.
- Integer milliseconds match the spec's response contract (`embed_ms`, `generator_ms`, etc.) and avoid float serialization edge cases.

**Alternatives considered**:
- `time.monotonic_ns()` — equivalent semantics, but requires `// 1_000_000` conversion; no practical advantage.
- `datetime.utcnow()` — wall-clock, non-monotonic, unsuitable.
- `asyncio.get_event_loop().time()` — valid but couples timing to event loop; `perf_counter` works uniformly in sync and async paths already used by `manual_rag_service.py`.

---

## Decision 2: Timing hook pattern

**Decision**: A tiny async-safe context manager `_StageTimer(breakdown: dict, key: str)` that records `perf_counter()` on `__aenter__`/`__enter__` and writes the delta on `__aexit__`/`__exit__`. If an exception escapes the block, the key is set to `None` (stage failed) rather than the partial measurement.

```python
class _StageTimer:
    def __init__(self, breakdown: dict, key: str):
        self.breakdown = breakdown
        self.key = key
    def __enter__(self):
        self._start = time.perf_counter()
        return self
    def __exit__(self, exc_type, exc, tb):
        if exc_type is not None:
            self.breakdown[self.key] = None
        else:
            self.breakdown[self.key] = round((time.perf_counter() - self._start) * 1000)
        return False  # never suppress
```

**Rationale**:
- Keeps call sites trivial (`with _StageTimer(lb, "embed_ms"): embed_query(...)`).
- Never swallows exceptions (FR-012: MUST NOT change pipeline behavior).
- Guarantees the key is present even when the stage raises — required by FR-002 (all seven keys always present).

**Alternatives considered**:
- Decorator on stage functions — less explicit at the orchestration site; harder to handle conditional stages (HyDE may not run).
- Manual `start = perf_counter()` / `lb["x"] = ...` pairs — more boilerplate, easier to forget on an exception branch.

---

## Decision 3: Where to measure generator latency

**Decision**: Measure generator latency inside `backend/services/ai_providers/resolver.py` at the innermost provider-call boundary, after fallback resolution has picked the actual provider, and write the result directly into the shared `latency_breakdown` dict passed in by the caller.

**Rationale**:
- FR-013 requires the reported `generator_ms` to reflect the provider that actually answered. If we timed around the resolver entry (before fallback), the value would include retry latency for the failed primary provider, which misleads the user.
- Keeps the service layer ignorant of provider identity; the resolver already owns fallback orchestration.

**Alternatives considered**:
- Time around the resolver entrypoint — rejected: sweeps failed-primary retry time into the displayed generator number.
- Have the resolver return a `(text, generator_ms)` tuple — rejected: more invasive signature change; passing the breakdown dict keeps the shape change local.

---

## Decision 4: Stage boundaries

**Decision**: Seven measured boundaries, each corresponding to an existing function-call site in `manual_rag_service.py`:

| Key | What it measures | Skip conditions |
|-----|------------------|-----------------|
| `embed_ms` | Query embedding (Ollama `nomic-embed-text`) | Greeting bypass |
| `hyde_ms` | HyDE hypothetical-answer generation | HyDE disabled in settings, greeting bypass |
| `rewrite_ms` | Query rewrite call | Rewrite disabled, greeting bypass |
| `retrieval_ms` | Supabase vector search (RPC) | Greeting bypass |
| `rerank_ms` | Cross-encoder / score-based rerank | Fewer than 2 candidates, greeting bypass |
| `generator_ms` | Final LLM call via active provider (post-fallback) | Greeting bypass (canned reply) |
| `total_ms` | Wall-clock from `/ask` handler entry to just-before-response-serialization | Never skipped |

**Rationale**: These boundaries correspond to distinct, independently slow operations users may want to attribute. Finer granularity (e.g., splitting retrieval into "RPC call" vs "row marshal") is not user-actionable.

**Alternatives considered**:
- Merging `rewrite_ms` + `hyde_ms` into a single `preprocess_ms` — rejected: users want to see which preprocessing step dominates; HyDE is typically 3-5× slower than rewrite.
- Adding a `network_ms` to capture HTTP round-trips to Ollama — rejected: these are already subsumed by the respective stage timings; separating would mislead.

---

## Decision 5: Null vs. missing keys

**Decision**: Always emit all seven keys; use explicit JSON `null` for skipped or failed stages. The Pydantic response model declares each stage key as `Optional[int]` and `total_ms` as `int`.

**Rationale**: Clarification Q4 settled this — stable shape is friendlier to clients than key absence. A single rule on the frontend (`if value is null, render '—'`) covers all skip paths.

**Alternatives considered**: Omitting keys (rejected in clarify). Sentinel values like `-1` or `0` (rejected: confusable with real measurements <1ms).

---

## Decision 6: Frontend formatter

**Decision**: A pure Dart function `formatStageLatency(int? ms)` returning a display `String`:

```dart
String formatStageLatency(int? ms) {
  if (ms == null) return '—';
  if (ms < 100) return '<1s';
  if (ms < 60000) {
    final seconds = ms / 1000.0;
    return '${seconds.toStringAsFixed(1)}s';
  }
  final totalSeconds = ms ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final remSeconds = totalSeconds % 60;
  return '${minutes}m ${remSeconds}s';
}
```

**Rationale**:
- Locks in FR-007 format rules as a single function; every display site calls it.
- Pure function → trivially unit-testable at boundary values (0, 99, 100, 999, 1000, 59999, 60000, 75000).
- Returns the same string in English and Arabic contexts — no locale branching needed (FR-008). Units `s`, `m` are language-neutral in this app's existing practice.

**Alternatives considered**:
- `intl` `NumberFormat` — overkill for a three-branch formatter; adds locale complexity that conflicts with FR-008's "render identically".
- Returning a `Duration` and formatting at call site — multiplies display logic, risks drift between call sites.

---

## Decision 7: Expansion UI pattern

**Decision**: Reuse the footer `Row` with a trailing `IconButton` using `Icons.expand_more` / `Icons.expand_less`, toggling a `StatefulWidget` flag. When expanded, a `Column` of `Row`s renders below the footer, each row: `[stage label] [formatted value]`. Skipped stages show `—`.

**Rationale**:
- `ExpansionTile` is available but forces its own header styling and feels heavy for a footer accessory.
- A stateful toggle with a visible chevron satisfies clarify Q3 (always-on, discoverable, keyboard-focusable via `IconButton`).
- `Semantics(label: 'Show pipeline timing breakdown')` on the button satisfies FR-006's assistive-technology requirement without any extra accessibility package.

**Alternatives considered**:
- Tooltip/popover on hover — rejected: hover doesn't exist on touch devices (primary PWA platform); clarify Q3 chose always-visible chevron.
- Modal bottom sheet — rejected: breaks context ("where did my answer go?"), overkill for 7 rows.

---

## Decision 8: Greeting-bypass code path

**Decision**: The greeting-bypass short-circuit (see project memory `project_ai_greeting_bypass.md`) already returns a canned response without invoking any pipeline stage. It MUST construct a `latency_breakdown` dict with all seven keys set to `null` except `total_ms`, populated with the measured handler wall-clock (typically 1-3 ms).

**Rationale**: FR-014 guarantees every answer has a displayable total; FR-002 guarantees all keys are present. The bypass path is the edge case where six of seven are `null`, and this is the correct representation — the breakdown tells the user "no stages ran; this was an instant canned reply".

**Alternatives considered**:
- Omit `latency_breakdown` entirely for bypass responses — rejected: violates FR-002/FR-009 stable-shape guarantee and forces the frontend to branch.

---

## Decision 9: Testing strategy

**Decision**:
- **Backend**: pytest `test_manual_rag_latency.py` with (a) a contract test that asserts the response JSON has all seven keys for a normal query, (b) a contract test asserting five of six stage keys are `null` on the greeting bypass path, (c) a unit test on `_StageTimer` for the exception path (key set to `None`, exception propagates), (d) a fallback-timing test using monkeypatched provider resolver to assert the measured generator latency matches the successful fallback provider, not the failed primary.
- **Frontend**: Dart unit tests on `formatStageLatency` covering boundary transitions (99→100 ms, 999→1000 ms, 59999→60000 ms, null input). One widget test on `AnswerCard` that renders with a fabricated `LatencyBreakdown` fixture and asserts the footer shows both generator and total; tapping the chevron reveals all seven rows.

**Rationale**: Matches the project's existing pytest + `flutter test` setup (no new runners). Boundary tests lock in the formatting rules identified as non-negotiable.

**Alternatives considered**: End-to-end test against a live Ollama — rejected: brittle, adds CI coupling; contract tests with a real request payload suffice for this additive observability change.

---

## Open items

None. All NEEDS CLARIFICATION resolved; all design choices tied back to a spec clause.
