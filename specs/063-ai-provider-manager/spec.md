# Feature Specification: AI Provider Manager — Extensible Multi-Provider System

**Feature Branch**: `063-ai-provider-manager`
**Created**: 2026-04-15
**Status**: Draft
**Input**: User description: "AI Provider Manager - extensible multi-provider system to switch AI backend between Local Ollama and Gemini 2.5 Flash via Admin settings, with provider abstraction layer for future providers."

## Clarifications

### Session 2026-04-15

- Q: Which AI features must route through the new provider abstraction in phase 1? → A: Only the user-facing Ask-the-AI answer generation (`/manuals/ask`) routes through the abstraction in phase 1; all other AI features (WO description, analytics insights, NL search, query rewrite, HyDE, reranking, session summary, cross-manual synthesis, agentic tool use, WO entity extraction) remain on their current Ollama-direct path and may migrate in later specs.
- Q: Does the phase 1 provider abstraction include the embedding step, or only generation? → A: Generation only is routed in phase 1. Embeddings continue to use Ollama `nomic-embed-text` for `manual_chunks` and query embedding. The provider interface reserves an `embed()` capability (stub/not-implemented by default) so a future spec can fill it per provider without breaking the interface contract.
- Q: What upper-bound wall-clock timeout on the active provider triggers automatic fallback to Ollama? → A: 30 seconds. If the active provider has not returned a complete response within 30 seconds, abort the call and retry with Ollama as fallback.
- Q: What should happen when the active provider is Local (Ollama) and it fails? → A: No fallback attempt. The system returns a clear user-facing error (e.g., "The AI service is temporarily unavailable. Please try again."), records the failure, and does NOT silently retry on another provider. Fallback to Ollama only applies when a *different* provider (e.g., Gemini) was active and failed — consistent with the Admin's explicit choice to use Local.
- Q: Where should the provider indicator chip be displayed in phase 1? → A: Only on the Ask-the-AI / `/manuals/ask` chat screen (the single surface routed through the provider abstraction in phase 1). Other AI-powered UIs (dashboard AI WO card, analytics insights, NL search, etc.) do NOT show the chip in phase 1 because they are not routed through the abstraction. When those features migrate in later specs, each can add its own chip.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin switches active AI provider (Priority: P1)

An Admin opens Settings, navigates to the "AI Assistant" section, sees the list of available AI providers loaded dynamically from the backend, selects a different provider (e.g., from "Local" to "Gemini"), and saves. Within one minute, the user-facing Ask-the-AI answer generation flow routes new requests through the newly selected provider. (Other AI features remain on their current paths in phase 1 — see Clarifications.)

**Why this priority**: This is the core value of the feature — giving an Admin the ability to pivot between a private local model and a faster cloud model without a redeploy. Without it, the rest of the feature has no purpose.

**Independent Test**: Log in as Admin, change the provider in Settings, then submit any AI request (e.g., ask a question in the AI Assistant) and verify the response metadata reports the newly-selected provider within 60 seconds.

**Acceptance Scenarios**:

1. **Given** the Admin is logged in and the current provider is "Local", **When** the Admin selects "Gemini" and saves, **Then** the settings screen shows "Gemini" as active with a healthy status indicator and a confirmation toast appears.
2. **Given** the provider was just changed to "Gemini", **When** any user submits an AI request within 60 seconds, **Then** the response metadata reports the active provider as "Gemini" (cache refresh is bounded by a 60-second TTL).
3. **Given** a non-Admin user opens Settings, **When** they navigate to the AI Assistant section, **Then** they do not see provider-switching controls (read-only or hidden).

---

### User Story 2 - Automatic fallback when active provider fails (Priority: P1)

When the active provider (e.g., Gemini) is unreachable, quota-exceeded, or errors out on a user's AI request, the system automatically retries the same request with the local Ollama provider, returns the answer with a warning flag, and records the fallback event in the activity log. The user still gets an answer; the Admin can review fallback events later.

**Why this priority**: Without fallback, a cloud provider outage would break every AI feature in the app. Falling back to the always-available local model preserves core functionality and is a release-blocking reliability requirement.

**Independent Test**: Temporarily invalidate the Gemini API key (or block outbound traffic to Google AI), submit an AI request, and verify (a) the user receives a valid answer from Ollama, (b) the response indicates a fallback occurred, (c) the activity log contains a fallback entry with a reason.

**Acceptance Scenarios**:

1. **Given** the active provider is "Gemini" and Gemini is unreachable, **When** a user submits an AI request, **Then** the system returns an answer generated by the local provider, the response includes a fallback flag and reports the actual answering provider, and a fallback event is recorded in the activity log.
2. **Given** a fallback just occurred, **When** any user (including non-Admins) views the AI Assistant chat screen, **Then** the provider indicator visibly signals that the last response was served via fallback.
3. **Given** the local Ollama provider is also unreachable after an active provider failure, **When** a user submits an AI request, **Then** the system returns a clear, user-friendly error rather than a silent failure.

---

### User Story 3 - Provider status visibility for all users (Priority: P2)

Every user of the AI Assistant sees a small, read-only indicator showing which provider is currently serving their requests. This builds trust (users know whether responses came from the private local model or a cloud model) and makes it obvious when fallback occurs.

**Why this priority**: Useful for transparency and supports debugging, but the app remains functional without it. It can ship slightly after the core switch + fallback logic.

**Independent Test**: As any role, open the AI Assistant chat screen and confirm a provider indicator is visible and matches the currently active provider reported by the backend.

**Acceptance Scenarios**:

1. **Given** the active provider is "Local", **When** any user opens the AI Assistant screen, **Then** the provider indicator displays "Local" with a healthy status.
2. **Given** the active provider is "Gemini" and a fallback just occurred on the most recent response, **When** the user views the chat, **Then** the indicator shows a warning visual state labelled to indicate fallback to Local.

---

### User Story 4 - Extensibility for future providers (Priority: P2)

The system is designed so that adding a third provider (e.g., Mistral, Groq) in a future release requires only (a) adding one new provider module on the backend, (b) updating the central list of available providers, and (c) supplying credentials — with no changes to the Flutter UI, to the AI request routing, or to the database schema. The available-providers list is read dynamically by the frontend.

**Why this priority**: Protects the long-term investment. The architecture must be proven by verifying that adding a stub "future provider" surfaces in the Admin UI with no frontend code changes.

**Independent Test**: Add a stub provider module and include its key in the available-providers list; reload the Flutter Settings screen and verify the new provider appears as an option without any Flutter code deployment.

**Acceptance Scenarios**:

1. **Given** a new provider key is added to the backend's list of available providers, **When** an Admin opens the Settings screen, **Then** the new provider appears in the selector without requiring a new app build.
2. **Given** a new provider module is registered on the backend, **When** the Admin selects it and submits an AI request, **Then** the system routes the request through the new provider with no code changes to the AI request router or the Flutter request path.

---

### Edge Cases

- The Admin selects a provider key present in the "available" list but whose module or credentials are not configured — the save is rejected with a clear error, or it is accepted but the provider reports unhealthy and refuses to serve traffic (behavior must be deterministic).
- Two Admins change the provider within the same 60-second cache TTL window — last write wins; every server instance converges to the latest value within at most one TTL cycle.
- Health-check reflects the last known state and refreshes only when the health endpoint is explicitly called or the cache expires.
- A user submits an AI request while an Admin is saving a new provider — the request is served by whichever provider is resolved from the cache at that moment; no request is dropped.
- The cloud provider returns a partially garbled or empty response (not an exception) — treated as a failure and fallback is triggered.
- The API key for the active cloud provider is missing at backend startup — the provider is reported as unhealthy; Admin attempts to route traffic to it fail safe with a clear error.
- Arabic and English prompts must produce comparable-quality answers through every provider; a provider that silently corrupts non-Latin text must be reported as unhealthy.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST expose a centralized, server-side setting identifying the currently active AI provider, persisted such that all backend instances read the same value.
- **FR-002**: System MUST expose a centralized, server-side list of available AI provider keys and display names that the frontend reads dynamically; the client MUST NOT hard-code the provider list.
- **FR-003**: System MUST provide an endpoint that returns the list of available providers (keys plus human-readable display names) to the frontend.
- **FR-004**: System MUST provide an endpoint that allows only users with the Admin role to change the active provider. Non-Admins MUST receive an authorization error.
- **FR-005**: System MUST provide an endpoint that reports the health of the currently active provider on demand.
- **FR-006**: System MUST resolve the active provider on each AI request using an in-memory cache with a TTL no greater than 60 seconds, so that provider changes take effect within 60 seconds across all running backend instances without restart.
- **FR-007**: System MUST route Ask-the-AI answer generation requests (prompt plus retrieved knowledge chunks for the `/manuals/ask` flow) through the resolved active provider's generate function. Other AI features are out of scope for phase 1 routing.
- **FR-008**: When the active provider fails — defined as any of: raised exception, wall-clock time exceeding 30 seconds without a completed response, explicit quota/rate-limit error, or empty/invalid response payload — and the active provider is NOT the local Ollama provider, the system MUST automatically retry the same request against the local Ollama provider as a fallback. If the active provider IS the local Ollama provider and fails, the system MUST NOT fall back (Ollama is already the designated fallback target) and instead return a clear user-facing error per FR-011.
- **FR-009**: When a fallback occurs, the system MUST include in the response a flag indicating fallback happened and the identifier of the provider that ultimately produced the answer.
- **FR-010**: When a fallback occurs, the system MUST record the event to the existing user activity log with enough information to diagnose which provider failed and why.
- **FR-011**: If the active provider fails and no fallback is available (either the active provider IS Local, or the fallback attempt against Local also failed), the system MUST return a clear, user-facing error rather than an empty or silent failure.
- **FR-012**: The Settings screen MUST, for Admin users only, present a selector built dynamically from the available-providers response, allowing the Admin to choose an active provider and save the change.
- **FR-013**: The Settings screen MUST display the health status of the currently active provider with a clear visual indicator (healthy / unhealthy).
- **FR-014**: The Ask-the-AI chat screen (the `/manuals/ask` UI) MUST display a small, read-only indicator showing the currently active provider to all user roles. Other AI-powered UI surfaces (dashboard AI WO card, analytics insights, NL search, etc.) MUST NOT display a provider indicator in phase 1.
- **FR-015**: The Ask-the-AI chat screen MUST visually distinguish a response that was served via fallback from one served by the active provider.
- **FR-016**: Provider API keys and other credentials MUST be configured server-side via environment configuration and MUST NEVER be delivered to the client.
- **FR-017**: Adding a new provider MUST NOT require changes to Flutter UI code, to the AI request routing layer, or to the database schema — only a new provider module, a registry entry, and an update to the available-providers list.
- **FR-018**: Existing AI endpoints MUST continue to function during and after migration; no in-flight AI feature may regress as part of this rollout.
- **FR-019**: The system MUST support Arabic and English prompts/responses through every shipped provider with comparable quality (no provider may silently strip or corrupt non-Latin text).
- **FR-020**: Phase 1 explicitly excludes: per-user provider preferences, streaming responses, load balancing or rotation across providers, cost tracking per provider, rate-limit retry logic, and shipped UI for not-yet-released providers (Mistral, Groq, etc.).
- **FR-021**: The provider interface MUST reserve a capability for embedding generation (`embed()`) so that a future spec can implement provider-specific embeddings without altering the interface contract. In phase 1, embeddings are NOT routed through the provider abstraction — the system continues to use the existing Ollama `nomic-embed-text` path for both chunk and query embedding. An unimplemented `embed()` on a provider MUST raise a clear "not implemented" error if called.

### Key Entities *(include if feature involves data)*

- **Application Setting**: A centrally stored configuration entry identified by a key (e.g., active provider key, available providers list). Records the current value, who last changed it, and when it was last changed.
- **AI Provider**: A named backend capability that takes a prompt plus retrieved context chunks and returns an answer. Each provider has a stable identifier, a human-readable display name, and a health state. Initial providers: "Local" (Ollama) and "Gemini". Future: Mistral, Groq, Cloudflare Workers AI.
- **AI Request Outcome**: The result of an AI generation request, carrying the answer, the identifier of the provider that produced it, and a flag indicating whether fallback was used.
- **Fallback Event**: An activity log entry capturing that the active provider failed for a specific request, the reason, and which provider ultimately served the answer.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An Admin can switch the active AI provider in under 30 seconds from opening Settings to confirmation, and the change takes effect for all users within 60 seconds.
- **SC-002**: When the active cloud provider is unreachable, at least 99% of AI requests still return a usable answer via fallback within the normal request timeout budget, without manual intervention.
- **SC-003**: Every AI response visible to the user indicates which provider produced it; 100% of fallback responses are visually distinguishable from non-fallback responses.
- **SC-004**: Adding a hypothetical third provider in a future iteration requires zero changes to Flutter UI code and zero database schema changes — verified by demonstrating a stub provider appearing in the Admin selector via backend-only changes.
- **SC-005**: No existing AI feature regresses during rollout: every AI endpoint that worked before the change continues to work, verified by existing smoke checks.
- **SC-006**: No AI provider credentials are ever transmitted to the client, verified by inspection of all client-bound API responses.
- **SC-007**: Arabic and English prompts produce non-empty, coherent answers on both initial providers (Local and Gemini) in 100% of a representative sample (minimum 20 prompts per language per provider).

## Assumptions

- The existing pgvector-based retrieval layer continues to run unchanged; this feature only swaps out the generation step downstream of retrieval.
- The existing Admin role and authentication mechanism are reused to gate the provider-switch endpoint — no new role or permission model is introduced.
- The local Ollama instance on the backend host is considered the always-available fallback; if it and the active provider are down simultaneously, the feature degrades to a clear user-facing error (not a crash).
- The Gemini provider is accessed via a cloud API requiring an API key configured in backend environment variables; outbound internet access from the backend host is assumed available for cloud providers.
- A 60-second cache TTL on the active-provider setting is an acceptable propagation delay for Admin-driven changes; real-time propagation is not required.
- The existing user activity log is reused for fallback audit events; no new audit table is introduced.
- Phase 1 does not require new user-visible Admin tooling for listing or filtering fallback events beyond what already exists in the activity log.
- "Comparable quality" for Arabic vs English across providers is a spot-check acceptance bar, not a formal evaluation suite, for phase 1.
