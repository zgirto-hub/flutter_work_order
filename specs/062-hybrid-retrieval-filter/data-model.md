# Phase 1 Data Model — Hybrid Retrieval System Pre-filter

**Feature**: 062-hybrid-retrieval-filter
**Date**: 2026-04-14

This feature introduces **no database tables, columns, or migrations**. All new entities are in-memory (Python module constants) or response-level DTOs. This document describes them for clarity and so the contracts in `contracts/` are self-contained.

---

## Persistent entities

**None.** Existing tables (`manuals`, `manual_chunks`) are read unchanged. No inserts, no updates, no schema changes.

---

## In-memory (module-level) entities

### KnownSystem registry

Lives in `backend/services/system_registry.py` as module-level constants.

```python
# Ordered by specificity — longest/most-specific first.
KNOWN_SYSTEMS: list[str] = [
    "CADAS-ATS",
    "CADAS-IMS",
    "AIDA-NG",
    "INDRA CCTV",
    "Billing System",
    "International Circuits",
    "AFTN",
    "IRTOS",
    "UPS",
    "Permissions",
]

# Aliases map every variant token → canonical name from KNOWN_SYSTEMS.
SYSTEM_ALIASES: dict[str, str] = {
    "CADAS ATS": "CADAS-ATS",
    "CADAS-ATS": "CADAS-ATS",
    "CADAS IMS": "CADAS-IMS",
    "CADAS-IMS": "CADAS-IMS",
    "AIDA NG":   "AIDA-NG",
    "AIDA-NG":   "AIDA-NG",
    # ... one entry per canonical name plus spacing/hyphenation variants
}
```

**Invariants**:
- Every value in `SYSTEM_ALIASES` MUST appear in `KNOWN_SYSTEMS`.
- Detection sort key is `len(alias)` descending; ties broken by insertion order.
- Bare/ambiguous tokens (e.g. `"CADAS"`) MUST NOT appear in either list — their absence is what makes "CADAS backup procedure" return `None`.

**Lifecycle**: module constants, loaded at import time. No refresh mechanism. Edits require code change + deploy.

---

## Response-level DTOs

### RetrievalInfo (backend response payload, nested under `ask()` return dict)

```jsonc
{
  "retrieval_info": {
    "detected_system":     "CADAS-ATS",            // string | null
    "filtered_manual_ids": ["<uuid>", "<uuid>"],   // string[] (UUIDs); [] when no narrowing
    "filter_applied":      true,                    // bool
    "fallback_reason":     null                     // "no_manuals_for_system" | null
  }
}
```

**Field semantics**:

| Field | Type | When set | Meaning |
|---|---|---|---|
| `detected_system` | string or null | Always present | Canonical system name from `KNOWN_SYSTEMS` if the question matched an entry, else `null`. |
| `filtered_manual_ids` | string[] | Always present | IDs of manuals the retrieval was narrowed to. Empty array when `filter_applied=false`. |
| `filter_applied` | bool | Always present | `true` only when the actual set of manuals searched was reduced by detection. `false` on: validated-QA hit, user-selected-manual, no detection, detection-but-no-matches. |
| `fallback_reason` | string or null | Present when narrowing was attempted but not applied | `"no_manuals_for_system"` when `detected_system != null` AND the title/filename query returned zero manuals. Future codes reserved. |

**Validation rules**:
- `filter_applied=true` IMPLIES `detected_system != null` AND `filtered_manual_ids` non-empty.
- `fallback_reason="no_manuals_for_system"` IMPLIES `detected_system != null` AND `filter_applied=false` AND `filtered_manual_ids=[]`.
- `retrieval_info` is OPTIONAL in the response contract (clients parsing older responses continue to work — FR-009).

### RetrievalInfo (Flutter model — frontend mirror)

```dart
class RetrievalInfo {
  final String? detectedSystem;
  final List<String> filteredManualIds; // default []
  final bool filterApplied;             // default false
  final String? fallbackReason;
}
```

Parsed defensively from `retrieval_info` JSON; the whole field is nullable on `ManualQaAnswer` to handle absent payloads.

---

## State transitions

None. All entities are request-scoped; no stateful lifecycle.

---

## Scale notes

- Registry size: ~20 entries typical, ~50 upper bound. O(n) scan per question = single-digit microseconds.
- `filtered_manual_ids` cardinality: typically 1–3 UUIDs per detected system. Upper bound ~10 (clarification assumption).
- Response payload overhead: ~150 bytes JSON per question — negligible.
