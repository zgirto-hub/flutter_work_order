# Phase 0 Research: Phase 2 Cleanups

**Feature**: 065-fix-provider-display-audit
**Date**: 2026-04-15

## Scope

No `NEEDS CLARIFICATION` markers. All ambiguities resolved in the Clarifications session (2026-04-15): field name, chip format, audit taxonomy.

---

## R1 — Where to compute `provider_display_name`

**Decision**: Compute in the resolver (`backend/services/ai_providers/resolver.py`) at the moment the answer is returned, and thread it alongside the existing `(answer, provider_used, fallback_used)` tuple. Change the tuple to `(answer, provider_used, provider_display_name, fallback_used)`. The `manual_rag_service` response builder then stamps both `provider_display_name` and legacy `model` with the same value.

**Rationale**:
- The resolver already holds the concrete provider instance at the moment of generation; its `display_name` property is the authoritative string.
- Putting the lookup in `manual_rag_service` would require re-importing the PROVIDERS registry and a redundant `PROVIDERS[key]()` instantiation — waste.

**Alternatives considered**:
- Let the router look it up post-hoc from `provider_used` — rejected: introduces a second source of truth and a time-of-check/time-of-use gap if an Admin renames a provider between resolve and stamp.

---

## R2 — Audit write placement

**Decision**: Inside `resolver.py`, in the fallback branch (after Local Ollama successfully returns), call `utils.activity.log_activity(...)` directly. Plumb `user_email` down from the `/manuals/ask` handler through `manual_rag_service.*_answer(...)` into the resolver via a new parameter.

**Rationale**:
- Constitution principle VI mandates fire-and-forget audit writes. `log_activity()` is the existing helper and does not block.
- Writing in the resolver keeps the spec 063 FR-010 requirement close to the failure/fallback logic rather than scattered across the router layer.

**Alternatives considered**:
- Write in the router after the resolver returns (based on `fallback_used`) — rejected: the router would lose the specific failure reason classification; the resolver already knows it.
- New dedicated audit table — rejected: spec 063 and this spec both explicitly reuse `user_activity_log`.

---

## R3 — Failure reason classification (closed taxonomy)

**Decision**: A helper in `resolver.py` maps exceptions → one of `{quota_exceeded, timeout_30s, empty_response, missing_credentials, unknown}`. Order of checks:

1. `asyncio.TimeoutError` → `timeout_30s`
2. `GeneratorModelError` with reason string containing `"quota"` or `"429"` → `quota_exceeded`
3. `GeneratorModelError` with reason `"missing_credentials"` → `missing_credentials`
4. `GeneratorModelError` with reason `"empty_response"` → `empty_response`
5. Anything else → `unknown`

Raw exception text still goes to `logger.error(...)` for server-side diagnostics, but never to `detail`.

**Rationale**:
- Matches Q3 clarification. Prevents API-key leakage or verbose SDK error bodies from landing in persistent audit storage.
- The taxonomy is closed; if future providers add a new failure mode, it maps to `unknown` by default and can be promoted in a later spec.

**Alternatives considered**:
- Open free-form scrubbed string (Option B) — rejected: relies on scrubbing perfection.
- Hybrid `code:message` — rejected: defers the same risk to `message`.

---

## R4 — Flutter chip state propagation

**Decision**: `manual_rag_screen.dart` holds the last-response state (last `provider_display_name`, last `fallback_used`) and passes both to `AiProviderChip` as parameters. The chip widget accepts an optional `fallbackUsed: bool` and `displayNameOverride: String?` that, when non-null, override the screen-open active-provider lookup.

When `fallbackUsed: true`: render warning variant with text `⚠ <displayNameOverride> (fallback)`.
When `fallbackUsed: false`: render healthy variant with the active provider's display name (same as today's behavior).
When both are null (initial load before any response): keep today's screen-open behavior.

**Rationale**:
- Minimally invasive: no new state-management package needed. Chip stays a stateless/simple widget, driven by parent state.
- Survives hot reload and screen reopens — state is attached to the response data, not to chip-local state.

**Alternatives considered**:
- `InheritedWidget` / provider package — rejected: overkill for one value local to one screen.
- Chip polls backend after each response — rejected: ignores the per-response truth already in the response body and introduces race conditions.

---

## R5 — Backwards compatibility of `model` field

**Decision**: Response builder sets both `model` and `provider_display_name` to the same string. FR-009 mandates one release of overlap, with removal scheduled for a subsequent spec. A TODO comment with spec number is added near the `model` stamp to mark it for deletion.

**Rationale**:
- Zero risk of breaking third-party consumers (there are none known, but the project has a "don't break working things" posture — spec 063 FR-018).
- Removal is a one-line change when it comes.

**Alternatives considered**:
- Drop `model` immediately — rejected: violates FR-009.
- Keep `model` forever as an alias — rejected: long-term cruft.

---

## Summary

All five research decisions align with the spec clarifications and constitution. No open items. Proceed to Phase 1.
