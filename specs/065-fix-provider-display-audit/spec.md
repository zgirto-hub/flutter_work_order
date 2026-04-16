# Feature Specification: AI Provider Manager — Phase 2 Cleanups (Display Truth + Fallback Audit)

**Feature Branch**: `065-fix-provider-display-audit`
**Created**: 2026-04-15
**Status**: Draft
**Input**: User description: "Fix three small but visible defects discovered in production after spec 063 (AI Provider Manager) shipped: stale `model` field in /manuals/ask response, missing `ai_provider_fallback` audit log entry, and Ask-the-AI chip not switching to fallback warning state."

## Clarifications

### Session 2026-04-15

- Q: What should the new response field be called? → A: Add new field `provider_display_name` (string). Keep `model` populated with the same value for one release as backwards-compat. Chip + footer read `provider_display_name`.
- Q: What text should the chip show during a fallback response? → A: `⚠ <fallback_provider_display_name> (fallback)` — shows only the provider that actually answered, with a warning icon and the literal "(fallback)" tag. The failed provider is not named in the chip (available in the response JSON and audit log for diagnostics).
- Q: How should the audit `detail` string be filled? → A: Closed taxonomy. `detail` MUST be one of: `quota_exceeded`, `timeout_30s`, `empty_response`, `missing_credentials`, `unknown`. Any unrecognized failure maps to `unknown`; the full exception text is written to server logs only (never to the audit row). Prevents accidental leakage of SDK stack traces or API key fragments into persistent audit storage.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Truthful provider/model label under each answer (Priority: P1)

A user asks a question in Ask-the-AI while the active provider is anything other than Local Ollama (e.g., Groq). Today, the small footer line under the answer reads `gemma4:e2b · 00:36` — the local Ollama generation model name — even though Groq actually produced the answer. After this fix, the footer reads the actual provider's display name (e.g., `Groq (Llama 3.3 70B) · 00:36`), matching the chip at the top of the message.

**Why this priority**: The mismatch directly contradicts the chip and undermines user trust in the provider switch feature. Users have already asked "are you sure Groq answered?" because of this. P1 because it actively confuses the live demo of feature 063.

**Independent Test**: Switch active provider to Groq (or any non-Local provider). Ask a question. Confirm the chip and the footer line show the same provider name.

**Acceptance Scenarios**:

1. **Given** the active provider is Groq and Groq answers successfully, **When** the user views the answer, **Then** the footer line shows `Groq (Llama 3.3 70B)` (or the configured display name) — never `gemma4:e2b`.
2. **Given** the active provider is Local (Ollama) and it answers successfully, **When** the user views the answer, **Then** the footer line shows the local provider's display name.
3. **Given** the active provider was Gemini but the request fell back to Local, **When** the user views the answer, **Then** the footer line shows the fallback provider's display name (`Local (Ollama)`), matching what actually generated the text.

---

### User Story 2 - Fallback events appear in the activity log (Priority: P1)

When the active provider fails and the system falls back to Local Ollama, an Admin can later open the user activity log and see exactly which provider failed, why, who was affected, and when. Today, the response correctly carries `fallback_used: true` and the chip (after Story 3) reflects it, but no row is written to `user_activity_log`. This is a release-blocking gap against FR-010 of spec 063.

**Why this priority**: Without an audit row, an Admin investigating a complaint ("the answer was slow / different than usual") cannot reconstruct what happened. The audit trail is a documented requirement of feature 063 and shipping without it is a compliance regression. P1.

**Independent Test**: Force the active provider to fail (e.g., invalidate the API key for the active cloud provider). Submit a question as a known user. Verify a single new row appears in `user_activity_log` with action `ai_provider_fallback`, the failed provider's identifier, the fallback provider's identifier, the failure reason, and the user's email.

**Acceptance Scenarios**:

1. **Given** the active provider is non-Local and fails on a request, **When** the system falls back to Local and returns the answer, **Then** exactly one new row is written to `user_activity_log` with action `ai_provider_fallback`, attributing the event to the requesting user, naming the failed provider, the fallback provider, and a short reason string.
2. **Given** the active provider answers successfully (no fallback), **When** the user views the activity log, **Then** no `ai_provider_fallback` row is written for that request.
3. **Given** the active provider IS Local and Local fails (no fallback possible), **When** the request errors out, **Then** no `ai_provider_fallback` row is written (because no fallback occurred), but the user-facing error is still returned per existing behavior.

---

### User Story 3 - Chip reflects the actual outcome of the last response (Priority: P1)

When the chat receives a response with `fallback_used: true`, the provider chip at the top of that conversation must visibly switch to a warning state (e.g., `⚠ Local (fallback)` in amber/orange) so the user immediately sees that the cloud provider didn't serve them. Today, the chip continues to show the configured active provider in healthy green even when fallback fired.

**Why this priority**: Spec 063 FR-015 explicitly requires the visual distinction. Without it, users cannot tell when their answer came from the local backup vs. the cloud — defeating the trust/transparency rationale for the chip.

**Independent Test**: Force fallback (invalidate cloud key, ask question). Without reloading the page, verify the chip's color and text change to the warning variant naming the fallback provider. Then ask another question with the cloud key restored — chip returns to healthy state showing the active provider.

**Acceptance Scenarios**:

1. **Given** the active provider is Gemini and Gemini answers successfully, **When** the response renders, **Then** the chip shows `● Gemini 2.5 Flash` in healthy state.
2. **Given** the active provider is Gemini and a fallback to Local just fired, **When** the response renders, **Then** the chip shows `⚠ Local (fallback)` (or equivalent warning string) in warning visual state.
3. **Given** a fallback just rendered, **When** the user submits a new question that succeeds on the active provider, **Then** the chip transitions back to the healthy state showing the active provider.

---

### Edge Cases

- The active provider is changed by an Admin between two messages in the same chat session — the chip on the next response must reflect the new active provider (not the prior one).
- A response is missing `provider_used` or `fallback_used` (defensive parsing) — the chip falls back to the screen-open active provider value rather than crashing or showing an empty chip.
- Multiple sequential fallbacks within a single session — each one writes its own audit row; chip reflects the most recent response only.
- The `display_name` on a provider class changes between deployments (e.g., Groq's label is renamed) — the response carries the *current* display name at request time; previously-rendered messages keep whatever they originally received.
- A consumer of `/manuals/ask` other than the Flutter app still expects the `model` field — the response keeps `model` populated for one release as a backwards-compatibility alias mirroring the new field, then the field is removed in a subsequent spec.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `/manuals/ask` response payload MUST include a new string field named `provider_display_name` that names the provider that actually generated the answer using its human-readable display name (e.g., "Groq (Llama 3.3 70B)", "Local (Ollama)", "Gemini 2.5 Flash"). The field MUST reflect the *real* generator, including in the fallback case.
- **FR-002**: The Ask-the-AI chat footer line under each answer MUST render the provider display name from FR-001 — never a hardcoded model identifier.
- **FR-003**: When fallback fires (active provider fails and the system substitutes Local Ollama), the system MUST write exactly one row to `user_activity_log` with: `action='ai_provider_fallback'`, the failed provider's identifier in `target_label`, the fallback provider's identifier in `target_id`, a failure reason from the closed taxonomy `{quota_exceeded, timeout_30s, empty_response, missing_credentials, unknown}` in `detail`, and the requesting user's email as the actor. Raw exception text MUST NOT be written to `detail`; it MAY be written to server-side logs only (which are not client-visible).
- **FR-004**: When the active provider answers successfully (no fallback), the system MUST NOT write an `ai_provider_fallback` row.
- **FR-005**: When the active provider IS Local Ollama and Local fails (no fallback possible per spec 063 FR-008), the system MUST NOT write an `ai_provider_fallback` row.
- **FR-006**: The Ask-the-AI provider chip MUST update its display after every response based on the response's fallback indication and the provider that actually generated it. When fallback was used, the chip MUST display in a visually distinct warning state with the literal text pattern `⚠ <provider_display_name> (fallback)`, naming only the provider that ultimately produced the answer; the failed provider MUST NOT be named in the chip itself.
- **FR-007**: When the most recent response did NOT use fallback, the chip MUST display in the healthy visual state and MUST name the active provider as configured.
- **FR-008**: The chip's update behavior MUST be driven by the per-response signal, not by a periodic poll or by the screen-open active-provider value alone.
- **FR-009**: Existing consumers of the `/manuals/ask` response that read the legacy `model` field MUST continue to function for at least one release: the response MUST keep `model` populated with the same string value as `provider_display_name`, with removal of `model` scheduled for a future spec.
- **FR-010**: API keys, secrets, and any backend-only identifiers MUST NOT be added to the response payload as part of this fix (preserves spec 063 FR-016 / SC-006).
- **FR-011**: All other `/manuals/ask` response fields and behavior MUST remain unchanged (no regression to retrieval, conflict detection, source listing, or any other downstream consumer).
- **FR-012**: The change MUST work for both Arabic and English answer text without affecting rendering of either.

### Key Entities *(include if feature involves data)*

- **AI Request Outcome** (existing — extended): The result of an AI generation request. Already carries the answering provider's identifier (`provider_used`) and a fallback flag (`fallback_used`). This spec adds the provider's human-readable display name to the outcome.
- **Fallback Event** (existing per spec 063 — now actually written): A row in the user activity log capturing failed-provider identifier, fallback-provider identifier, failure reason, and the requesting user. Spec 063 defined this entity but the write was never implemented.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of answers display a footer label that matches the chip label for the same message — verified across at least 5 sample questions per provider (Local, Gemini, Groq, Mistral).
- **SC-002**: 100% of fallback events produce exactly one corresponding `user_activity_log` row within 5 seconds of the response being returned — verified by forcing 5 fallback events and counting the resulting log rows.
- **SC-003**: When fallback fires, the chip transitions to its warning visual state within the same render frame as the answer — verified by visual inspection and screen recording.
- **SC-004**: Zero existing AI feature regresses — verified by smoke-testing all `/manuals/ask` flows (single-manual, cross-manual synthesis, agentic) post-deploy.
- **SC-005**: No new fields containing API keys, raw error stack traces, or backend internals appear in any client-bound payload — verified by inspecting the response JSON.
- **SC-006**: The legacy `model` field continues to be present in the response for the duration of one release after this spec ships, ensuring no third-party consumer breaks during the transition.

## Assumptions

- The existing `display_name` property on each `AIProvider` subclass is the canonical human-readable name and is appropriate to expose to users.
- The existing `log_activity()` helper in the backend accepts the (`actor_email`, `category`, `action`, `target_label`, `target_id`, `detail`) shape used elsewhere in the codebase, and writing to `user_activity_log` is the established audit path.
- The Flutter chat screen already receives the full `/manuals/ask` response body and can introspect new fields without route or model changes beyond a Dart model update.
- The active-provider chip widget is the single source of truth for chip visual state; no other widget renders an independent chip on the same screen in phase 1.
- "One release" of backwards compatibility for the legacy `model` field is acceptable because no known third-party consumer depends on it; removal will be scheduled as a follow-up cleanup.
- Failure reason strings used in audit `detail` (`quota_exceeded`, `timeout_30s`, `empty_response`, etc.) come from the provider/resolver layer's existing classification and need no new taxonomy.
