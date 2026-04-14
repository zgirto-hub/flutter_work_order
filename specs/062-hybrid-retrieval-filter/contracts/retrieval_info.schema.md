# Contract — `retrieval_info` response field

**Feature**: 062-hybrid-retrieval-filter
**Applies to**: All responses from `POST /manual-assistant/ask` (and the in-process `services.manual_rag_service.ask()` return dict).

---

## Position

`retrieval_info` is a top-level OPTIONAL object on the response. Example (full response truncated):

```jsonc
{
  "answer": "…",
  "grounded": true,
  "sources": [ … ],
  "manuals_consulted": [ … ],
  "model": "gemma:4e2b",
  "duration_seconds": 2.1,
  "retrieval_info": {
    "detected_system": "CADAS-ATS",
    "filtered_manual_ids": ["5e3…"],
    "filter_applied": true,
    "fallback_reason": null
  }
}
```

Absence of `retrieval_info` MUST be treated as equivalent to `{detected_system: null, filtered_manual_ids: [], filter_applied: false, fallback_reason: null}` by all clients.

---

## Schema

```yaml
retrieval_info:
  type: object
  required: [detected_system, filtered_manual_ids, filter_applied]
  properties:
    detected_system:
      type: [string, "null"]
      description: |
        Canonical system name if the question text matched a known-system
        keyword or alias (case-insensitive, longest-match-first). null when
        no known system was detected.
    filtered_manual_ids:
      type: array
      items: { type: string, format: uuid }
      description: |
        Manual UUIDs that retrieval was narrowed to. Empty array when no
        narrowing occurred.
    filter_applied:
      type: boolean
      description: |
        true only when the actual set of manuals queried was reduced by
        system detection. false on validated-QA hits, user-selected-manual,
        no-detection, and detection-but-no-matches fallback.
    fallback_reason:
      type: [string, "null"]
      enum: [null, "no_manuals_for_system"]
      description: |
        When detection triggered but filtering was not applied, explains why.
        Currently only "no_manuals_for_system" is defined. Other values are
        reserved for future use.
```

---

## Invariants

1. `filter_applied=true` ⇒ `detected_system != null` AND `filtered_manual_ids` non-empty.
2. `fallback_reason="no_manuals_for_system"` ⇒ `detected_system != null` AND `filter_applied=false` AND `filtered_manual_ids=[]`.
3. `detected_system=null` ⇒ `filter_applied=false` AND `fallback_reason=null` AND `filtered_manual_ids=[]`.
4. The response is backward-compatible: older clients that do not read `retrieval_info` MUST continue to render valid answers.

---

## Generator prompt side-channel

When `fallback_reason="no_manuals_for_system"` is set on the response, the backend MUST also have prepended the following directive to the generator prompt (no client-visible effect beyond the answer text itself):

```text
IMPORTANT: The user asked specifically about <detected_system>. No manuals for <detected_system> are currently uploaded to the system. Do NOT substitute content from other similar-sounding systems. Respond that specific information about <detected_system> is not available in the uploaded manuals.
```

Where `<detected_system>` is the canonical name from `detected_system`. This is a backend-internal contract; it is documented here so verification tests for SC-004 can assert the prompt shape.

---

## Flutter consumer contract

- When `retrieval_info.filter_applied` is `true`, the answer card SHOULD display a small info chip reading `Filtered to: <detected_system>`.
- When `filter_applied` is `false` OR `retrieval_info` is absent, the answer card MUST render unchanged from pre-feature behavior (no chip, no empty gap).
- Clients MUST tolerate unknown future values of `fallback_reason` (treat as opaque).

---

## Test vectors

| Scenario | Expected `retrieval_info` |
|---|---|
| "what is the backup for CADAS-ATS?" with CADAS-ATS manual uploaded | `{detected_system:"CADAS-ATS", filtered_manual_ids:["<id>"], filter_applied:true, fallback_reason:null}` |
| "what is the backup for CADAS-ATS?" with no CADAS-ATS manual uploaded | `{detected_system:"CADAS-ATS", filtered_manual_ids:[], filter_applied:false, fallback_reason:"no_manuals_for_system"}` |
| "backup procedure" (no system name) | `{detected_system:null, filtered_manual_ids:[], filter_applied:false, fallback_reason:null}` |
| User selected CADAS-IMS manual in UI, asked "backup for CADAS-ATS?" | `{detected_system:"CADAS-ATS", filtered_manual_ids:[], filter_applied:false, fallback_reason:null}` |
| Validated-QA hit for "restart AIDA-NG" | `{detected_system:"AIDA-NG", filtered_manual_ids:[], filter_applied:false, fallback_reason:null}` |
