# Phase 1 Data Model: Verbatim Verified Answers

**Feature**: 083-verbatim-verified-answers
**Date**: 2026-04-18

No database schema changes. This document describes in-memory shapes, helper signatures, and the JSON response-contract diff.

---

## 1. In-memory entities (backend)

### 1.1 Verified-answer match row (unchanged — from `check_validated_match`)

Returned list `matches: list[dict]` where each element has:

| Field | Type | Source |
|---|---|---|
| `id` | `str` | validated_qa row PK |
| `question_text` | `str` | curated question |
| `validated_answer` | `str` | curated answer body — **used verbatim on the verbatim path** |
| `validated_by` | `str` | admin email |
| `validated_at` | `str | datetime` | ISO timestamp |
| `similarity` | `float` (2 decimals) | cosine similarity, 0.00–1.00 |

Ordering: best-first (highest similarity). Length: 0–3.

### 1.2 Verbatim decision (new, internal)

Return type of `_should_return_verbatim(matches)` — a plain `bool`.

Domain rules (the single source of truth for FR-001/002/005):

| Case | Input | Result |
|---|---|---|
| Empty | `matches == []` | `False` |
| Single below floor | `len==1` and `top1 < 0.85` | `False` |
| Single at/above floor | `len==1` and `top1 >= 0.85` | `True` |
| Multi, top1 below floor | `top1 < 0.85` | `False` |
| Multi, top1 strong, gap too small | `top1 >= 0.85` and `top1 - top2 < 0.05` | `False` |
| Multi, top1 strong, dominant | `top1 >= 0.85` and `top1 - top2 >= 0.05` | `True` |

### 1.3 Verbatim response payload (new, internal)

Return type of `_build_verbatim_payload(matches, question_or_search_query, extras)` — a `dict` shaped like today's synthesized verified response, with these key fields set for verbatim:

| Field | Value on verbatim path |
|---|---|
| `answer` | `matches[0]["validated_answer"]` (byte-identical, no formatting or whitespace changes) |
| `grounded` | `True` |
| `sources` | `[{"id": m["id"], "question_text": m["question_text"], "score": m["similarity"]} for m in matches]` |
| `confidence` | `"high"` if `top1 >= RAG_HIGH_CONFIDENCE` else `"medium"` (same rule as today) |
| `score` | `top1` |
| `model` | `"Verbatim (no generation)"` — cosmetic marker for the existing provider-display line; does not affect routing |
| `provider_display_name` | `"Verbatim (no generation)"` |
| `duration_seconds` | `0.0` (no generation call) |
| `is_verified` | `True` |
| `verified_source` | `{validated_qa_id, validated_by, validated_at, similarity}` — same shape as today |
| `verification_mode` | `"verbatim"` — **new field** |
| `verified_source_count` | `1` — **new field** (always 1 on verbatim) |
| `retrieval_info` | pass-through from caller |
| `provider_used` | `"verbatim"` — **new value** for this field (previously `"local"`/`"groq"` etc.) |
| `fallback_used` | `False` |
| `session_summary` | `None` |
| `search_query` | pass-through |
| `latency_breakdown` | pass-through (with `generator_ms = 0`) |
| `source_type` | `"validated_qa"` (unchanged) |

### 1.4 Synthesized verified response (modified — pre-existing dict, two new fields)

Existing fields unchanged; adds:

| Field | Value on synthesis path |
|---|---|
| `verification_mode` | `"synthesized"` |
| `verified_source_count` | `len({m["validated_answer"] for m in matches})` — dedup-by-answer-text count per R2 |

### 1.5 Streaming `stream_meta` dict (modified — new keys)

The existing `stream_meta` dict mutated by `ask_stream` gains:

- `"verification_mode"`: `"verbatim"` | `"synthesized"`
- `"verified_source_count"`: `int` (computed once when the is_verified path fires)

Consumed by `backend/routers/manuals.py` in the terminal `event: metadata` emission (lines 470–489): the `result` dict must be extended to include both new fields via `stream_meta.get("verification_mode")` and `stream_meta.get("verified_source_count")`.

---

## 2. Helper signatures (module-private, `backend/services/manual_rag_service.py`)

### 2.1 `_should_return_verbatim`

```python
def _should_return_verbatim(matches: list[dict]) -> bool:
    """
    Return True iff the top-1 match is strong enough (>= VERBATIM_MIN_SIMILARITY)
    AND clearly dominates the top-2 (gap >= VERBATIM_DOMINANCE_GAP), OR is a lone
    match at/above the floor. Pure function of the similarity scores — no side
    effects, no I/O.

    Callers MUST have already confirmed the entry gate (max score >=
    RAG_CONFIDENCE_THRESHOLD) before consulting this helper.
    """
```

Covered by 6 parametrized unit tests (see [research.md](research.md) §R8).

### 2.2 `_build_verbatim_payload`

```python
def _build_verbatim_payload(
    matches: list[dict],
    *,
    search_query: str,
    retrieval_info: dict | None,
    latency_breakdown: dict | None,
) -> dict:
    """
    Return a response dict identical in shape to the synthesized verified
    response but with `answer` set to matches[0]["validated_answer"] verbatim,
    verification_mode="verbatim", verified_source_count=1, and duration_seconds=0.
    Does NOT call any LLM.
    """
```

### 2.3 `_log_verified_served` (convenience helper — research R4)

```python
def _log_verified_served(
    user_email: str,
    question: str,
    verification_mode: str,
    top1: float,
    top2: float,
) -> None:
    """
    Fire-and-forget telemetry write per FR-014. Wraps log_activity so all four
    verified paths share one format string. Swallows all exceptions (FR-015).
    """
```

Called from each of the four is_verified=true paths immediately after verification_mode is determined.

### 2.4 Module-level constants

```python
VERBATIM_MIN_SIMILARITY = 0.85  # FR-001 floor
VERBATIM_DOMINANCE_GAP = 0.05   # FR-001 gap
```

Placed next to the existing `RAG_CONFIDENCE_THRESHOLD = 0.75` (line 103) for discoverability.

---

## 3. Frontend model (`frontend/lib/models/manual_qa_answer.dart`)

### 3.1 `ManualQaAnswer` — additive fields

```dart
class ManualQaAnswer {
  // ... existing fields ...
  final String? verificationMode;     // "verbatim" | "synthesized" | null
  final int? verifiedSourceCount;     // populated when isVerified && synthesized

  const ManualQaAnswer({
    // ... existing ...
    this.verificationMode,
    this.verifiedSourceCount,
  });

  factory ManualQaAnswer.fromJson(Map<String, dynamic> json) {
    return ManualQaAnswer(
      // ... existing ...
      verificationMode: json['verification_mode'] as String?,
      verifiedSourceCount: (json['verified_source_count'] as num?)?.toInt(),
    );
  }
}
```

Both new fields are nullable / optional so older server responses (pre-deploy) continue to parse cleanly during the deploy window.

### 3.2 `answer_card.dart` — conditional footer

Insert after the answer `Text` widget at [answer_card.dart:131-134](../../frontend/lib/screens/manual_assistant/widgets/answer_card.dart#L131-L134), guarded by both conditions:

```dart
if (isVerified && widget.answer.verificationMode == 'synthesized') ...[
  const SizedBox(height: 8),
  Text(
    'Synthesized from ${widget.answer.verifiedSourceCount ?? widget.answer.sources.length} verified sources',
    style: TextStyle(
      fontSize: 11,
      color: Colors.grey.shade600,
    ),
  ),
],
```

Fallback `?? widget.answer.sources.length`: handles the backwards-compatibility case where a legacy server omits `verified_source_count`. After the coupled deploy this branch is dead but harmless.

**No change** to the verbatim branch — absence of the footer on `verification_mode == "verbatim"` is the product behavior FR-012 requires.

---

## 4. Telemetry row (existing table, new event type)

Written via `log_activity(...)` to table `user_activity_log`. One row per is_verified=true response.

| Column | Value |
|---|---|
| `user_email` | authenticated user's email (already available in the ask path) |
| `user_name` | derived by helper from email prefix (existing behavior) |
| `category` | `"manual"` |
| `action` | `"verified_answer_served"` |
| `target_label` | `question[:80]` (original user question, truncated) |
| `target_id` | `""` (empty — there is no single logical target object) |
| `detail` | `f"mode={mode};top1={top1:.3f};top2={top2:.3f}"` (top2 = 0.000 when matches has 1 element) |

Post-deploy analyst query (per SC-006):

```sql
SELECT
  regexp_replace(detail, 'mode=(\w+);.*', '\1') AS mode,
  (regexp_replace(detail, '.*top1=([\d.]+);.*', '\1'))::numeric AS top1,
  (regexp_replace(detail, '.*top2=([\d.]+).*', '\1'))::numeric AS top2,
  COUNT(*) AS events
FROM user_activity_log
WHERE action = 'verified_answer_served'
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY 1, 2, 3
ORDER BY events DESC;
```

---

## 5. State transitions

None. This feature introduces no stateful entity. `verification_mode` is a per-response derived value, not a persisted attribute.

---

## 6. Validation rules

| Rule | Enforcement location |
|---|---|
| `VERBATIM_MIN_SIMILARITY` and `VERBATIM_DOMINANCE_GAP` defined in one location | `manual_rag_service.py` module scope (FR-006) |
| Verbatim decision applied identically across all four is_verified paths | All four paths MUST invoke `_should_return_verbatim` (FR-005) |
| No LLM call on verbatim path | `_build_verbatim_payload` contains no provider imports; streaming verbatim path uses `yield` + `return` with no `provider_generate_stream` call (FR-003) |
| `verification_mode` present on every is_verified=true response | Set at the same decision site as `is_verified=True` (FR-007) |
| Telemetry row written for every is_verified=true response | `_log_verified_served` call at each of the four paths (FR-014) |
| Telemetry failure non-blocking | Existing `log_activity` try/except + defence-in-depth wrapper (FR-015) |
| Pre-existing fields unchanged | Code review checklist (FR-008) |
