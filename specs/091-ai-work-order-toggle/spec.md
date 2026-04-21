# Feature Specification: AI Work Order Toggle (Admin Control)

**Feature Branch**: `091-ai-work-order-toggle`
**Created**: 2026-04-21
**Status**: Draft
**Input**: User description: "Admin-controlled global toggle for AI-assisted work order creation. New 'AI Features' section in Admin settings with a switch labeled 'AI Work Order'. When enabled, Add Work Order screen shows an AI Assist entry that accepts a free-text description and auto-fills form fields. When disabled, the AI entry is hidden from all users. Flag persisted, enforced server-side on the autofill endpoint."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin disables AI Work Order globally (Priority: P1)

An administrator opens the Admin settings and navigates to the new "AI Features" section. The section lists an "AI Work Order" toggle with a subtitle explaining that it allows AI to auto-fill work order fields from a plain-text description. The admin switches it off. From that moment on, every user opening the Add Work Order screen — including the admin themselves — sees a standard form with no AI entry point anywhere.

**Why this priority**: This is the primary mechanism of control the feature exists to provide. Without it, the rest of the feature has no purpose. It also delivers immediate value on its own: even before the AI auto-fill flow is polished, an admin can already shut it off.

**Independent Test**: Set the toggle to OFF in Admin settings; confirm no AI element is visible to any role on the Add Work Order screen. Set it ON; confirm the AI Assist entry appears. The toggle can be validated end-to-end using the Admin UI plus one non-admin test account, no AI generation required.

**Acceptance Scenarios**:

1. **Given** the admin is signed in and the toggle is currently ON, **When** the admin switches "AI Work Order" to OFF, **Then** the toggle state is saved immediately and a visual confirmation is shown.
2. **Given** the toggle is OFF, **When** any user (any role) opens the Add Work Order screen, **Then** no AI Assist button, chip, banner, bottom sheet, or other AI-related element is visible anywhere on the screen.
3. **Given** the toggle is ON, **When** any authenticated user opens the Add Work Order screen, **Then** an AI Assist entry point is visible on the form.
4. **Given** a non-admin user is signed in, **When** they look at the admin navigation, **Then** the "AI Features" section is not listed and is not reachable by deep link.

---

### User Story 2 - Technician uses AI to draft a work order from a description (Priority: P2)

A technician taps "Add Work Order" and sees an "AI Assist" entry near the top of the form. They tap it, a bottom sheet opens, and they type a short free-text description of the problem (for example, "AC unit in tower 3 is leaking water onto the floor, been getting worse since yesterday"). They submit. The system calls AI, returns structured values for title, description, priority, category, and asset/equipment, and maps those values into the form fields. The technician reviews the draft, edits what they want, and saves.

**Why this priority**: This is the user-visible payoff of having the feature enabled. It only becomes reachable once P1 is in place (toggle ON) so it is P2 by dependency. The functionality itself is valuable but still requires a human review step before save.

**Independent Test**: With the toggle ON, any authenticated user can tap AI Assist, enter a description, receive a populated form within a reasonable wait, and complete save. The test exercises the full UI flow plus the autofill backend.

**Acceptance Scenarios**:

1. **Given** the toggle is ON and all form fields are empty, **When** the user submits a description via AI Assist, **Then** the form fields are populated with the returned values and no confirmation dialog is shown.
2. **Given** the toggle is ON and the user has already filled some form fields manually, **When** they submit a description via AI Assist and the AI response would overwrite one or more of those fields, **Then** a side-by-side preview dialog shows every conflicting field with its current value and the AI's proposed value; the user chooses "keep mine" or "use AI" per field via radio buttons and must confirm the selection before any overwrite happens.
3. **Given** the user opens the AI Assist bottom sheet, **When** they submit and the AI call fails (timeout, server error, all providers exhausted), **Then** an error message is shown, the bottom sheet is dismissed or remains with the input intact, and no form fields are modified.
4. **Given** the toggle is ON and the user submits a very short or empty description, **When** the system receives the request, **Then** the user is told the description is too short to process and no AI call is made.

---

### User Story 3 - Server refuses autofill when feature is disabled (Priority: P2)

Even if a client (an older app version, a reverse-engineered request, or a race between a just-toggled-off flag and a still-open screen) sends an autofill request while the feature is disabled, the server refuses the request with a clear "feature disabled" response. No AI provider is contacted, no resources are spent, and no structured values are returned.

**Why this priority**: Defense in depth. The admin toggle is a governance control; if it can be bypassed by client-side tampering, it isn't really a control. This story is P2 because it protects the P1 guarantee.

**Independent Test**: Disable the toggle, then issue an autofill request directly to the backend. Confirm the server returns a denial response and no AI call is logged.

**Acceptance Scenarios**:

1. **Given** the toggle is OFF, **When** any client sends an autofill request, **Then** the server responds with a "feature disabled" error and does not call any AI provider.
2. **Given** the toggle is ON and the user is not authenticated, **When** a request reaches the autofill endpoint, **Then** the server rejects it as unauthorized.
3. **Given** a non-admin user sends a request to change the toggle, **When** the server receives it, **Then** the request is rejected and the toggle state is unchanged.

---

### Edge Cases

- **Toggle flipped while a user has the AI bottom sheet open**: if the admin turns the feature off after a user has already opened the AI Assist bottom sheet, submitting the description must fail cleanly with the "feature disabled" message from the server. Form contents are preserved.
- **Toggle flipped between screens**: the flag is re-fetched each time the Add Work Order screen opens, so a freshly-off state takes effect the next time the screen is opened, without requiring a full app restart.
- **Admin role revocation mid-session**: a user who was admin and is no longer admin must not be able to flip the toggle; the server rejects the request based on the current role, not the cached role the client holds.
- **AI response that omits fields**: the AI may legitimately leave optional fields blank. Missing fields in the response mean "no suggestion"; existing form values are preserved, no overwrite confirmation is needed for them.
- **AI response returning a value for a field that does not exist in this deployment** (for example, a category name that was removed): the system must not write a value that fails form validation; unknown values are dropped with a soft note in the confirmation dialog.
- **Very long description**: descriptions longer than 500 characters are rejected (not silently truncated) before any AI provider is contacted, so the user can shorten their input deliberately and latency/cost stay predictable.
- **Description language**: a description written in Arabic or any other language is accepted; field values returned match the language of the input, while the internal prompt to the AI is in English.
- **All AI providers unavailable**: when every provider in the fallback chain fails, the failure path of AS-3 above applies. No partial fill is performed.
- **Rate limit reached**: when a user exceeds 10 requests/min or 100 requests/day, the autofill request is refused with a "please try again later" style message indicating the retry window; no AI provider is contacted, form contents are preserved.
- **Toggle state load fails at screen open**: if the flag can't be read, the system defaults to OFF (hide the AI entry) rather than risking an ungoverned ON state.

## Clarifications

### Session 2026-04-21

- Q: Description length policy for AI autofill input (min / max / over-max behavior)? → A: Min 20 chars, Max 500 chars, reject over-max with error
- Q: Overwrite confirmation granularity when AI would change user-entered fields? → A: Side-by-side preview with per-field "keep mine" vs "use AI" radios
- Q: Rate limiting on the autofill endpoint? → A: Per-user cap — 10 requests/min AND 100 requests/day, 429 response beyond either
- Q: Loading-state UX during the AI call (up to 30s per SC-003)? → A: Blocking spinner inside the AI Assist surface + Cancel action + timing hint ("usually a few seconds")
- Q: Atomicity when the user cancels the conflict-preview dialog? → A: Empty fields fill immediately; the dialog governs only conflicting fields; cancelling the dialog preserves the empty-field fills

## Requirements *(mandatory)*

### Functional Requirements

**Admin settings surface**

- **FR-001**: System MUST expose an "AI Features" section in the Admin settings navigation.
- **FR-002**: The "AI Features" section MUST be visible and reachable ONLY to users whose role is Admin; for all other roles the navigation entry MUST be hidden and direct navigation attempts MUST NOT render the section.
- **FR-003**: The "AI Features" section MUST contain a toggle tile labeled "AI Work Order" with the subtitle "Allow AI to auto-fill work order fields from a plain-text description".
- **FR-004**: The toggle tile MUST follow the same visual pattern used by other settings toggles in the application.
- **FR-005**: Changing the toggle MUST persist immediately on release, with an optimistic UI update and a rollback if the save fails.

**Persistence**

- **FR-006**: The system MUST persist the "AI Work Order" feature state as a global boolean setting accessible to the backend.
- **FR-007**: The default state for the setting, on a fresh installation or after migration, MUST be OFF.
- **FR-008**: Only users with the Admin role MUST be able to change the setting's value.

**Add Work Order screen behavior**

- **FR-009**: On every open of the Add Work Order screen, the system MUST fetch the current value of the "AI Work Order" setting fresh, not from an app-startup cache that may be stale.
- **FR-010**: When the setting is OFF, the Add Work Order screen MUST NOT render any AI-related control, entry point, hint text, or other element, for any user role.
- **FR-011**: When the setting is ON, the Add Work Order screen MUST render an "AI Assist" entry point at a prominent location at the top of the form.
- **FR-012**: Tapping the AI Assist entry point MUST open a dedicated input surface where the user can type a free-text description of the work needed.
- **FR-013**: Submitting the free-text description MUST call the AI autofill service and receive a structured result containing title, description, priority, category, and optionally an asset/equipment reference.
- **FR-014**: Before writing AI results into form fields that the user has already manually filled with a non-empty value, the system MUST show a side-by-side preview dialog listing every conflicting field with its current value and the AI's proposed value, each row offering a "keep mine" vs "use AI" radio choice (default selection: "keep mine"), and MUST apply the overwrite only for fields the user selected "use AI" on after explicit confirmation.
- **FR-015**: For fields the user has not yet filled, the system MUST populate them from the AI result immediately and without a confirmation dialog, before the per-field conflict-preview dialog (FR-014) is shown for any conflicting fields. If the user cancels or dismisses the conflict-preview dialog, the already-applied empty-field fills MUST be preserved (not rolled back); only the conflicting fields remain untouched.
- **FR-016**: If the AI call fails, the system MUST surface the failure to the user in a non-intrusive way, leave all form fields unchanged, and allow the user to retry or continue filling the form manually.

**Autofill service**

- **FR-017**: The autofill service MUST accept a free-text description and return a structured set of suggested field values.
- **FR-018**: The autofill service MUST re-check the global feature setting on every request and refuse the request when the setting is OFF, regardless of what the caller sends.
- **FR-019**: The autofill service MUST require the caller to be authenticated.
- **FR-020**: The autofill service MUST use the existing multi-provider generation fallback ordering used elsewhere in the system.
- **FR-021**: The internal instruction sent to the AI MUST be in English, while the returned field values MUST match the language of the user's input description.
- **FR-022**: The autofill service MUST reject descriptions shorter than 20 characters or longer than 500 characters before any AI provider is contacted, returning a descriptive validation error.
- **FR-025**: The autofill service MUST enforce a per-user rate limit of 10 requests per rolling minute AND 100 requests per rolling 24-hour window, rejecting further requests within those windows with a 429-style response and a user-visible message indicating when the user may retry; rate-limited requests MUST NOT contact any AI provider.
- **FR-026**: While an autofill request is in flight, the AI Assist input surface MUST display a blocking spinner, a timing hint ("usually a few seconds"), and a Cancel action that aborts the pending request client-side, leaves all form fields unchanged, and returns the user to the input with their description preserved; the surrounding Add Work Order form outside the AI Assist surface MAY remain interactive.

**Audit and observability**

- **FR-023**: Changes to the "AI Work Order" setting MUST be recorded, including who made the change and when.
- **FR-024**: Failures of the autofill service MUST be observable without exposing personally identifiable content of user descriptions to ordinary logs.

### Key Entities

- **AI Feature Setting**: A globally shared configuration flag indicating whether AI-assisted work order drafting is enabled. Holds a boolean value and metadata about the last change (who changed it, when). Exactly one row exists per deployment.
- **Work Order Draft Suggestion**: A transient, in-memory structured result produced by the AI autofill service for a single user request. Contains suggested values for title, description, priority, category, and optional asset/equipment reference. Not persisted.
- **User Role**: Existing concept in the system; the feature distinguishes Admin from all other roles for the purpose of managing this setting.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When an admin toggles "AI Work Order" OFF, every Add Work Order screen opened afterwards (by any user, any role) shows zero AI-related UI elements, verified by visual inspection on at least one user per role.
- **SC-002**: When the toggle is OFF, a direct request to the autofill service returns a refusal in under one second without contacting any AI provider, verified against service logs showing zero provider calls during the test window.
- **SC-003**: When the toggle is ON, a user can go from tapping the AI Assist entry to seeing suggested values populated in the form in under thirty seconds for typical descriptions under two hundred characters, for at least 95% of attempts that reach the server.
- **SC-004**: 100% of confirmed AI-generated overwrites are preceded by an explicit confirmation dialog when the target field already contained user-entered text, verified by automated test covering the dirty-field scenario for each overwritable field.
- **SC-005**: Zero non-admin users can change the setting, verified by an end-to-end attempt with each non-admin role resulting in a refusal.
- **SC-006**: If the feature setting cannot be loaded, the system defaults to hiding the AI entry in 100% of observed cases, verified by forcing a setting-load failure in a test environment.
- **SC-007**: Toggle changes made by an admin are visible to the next Add Work Order screen open within 10 seconds, without requiring any user to log out or restart the app.

## Assumptions

- A settings-style storage table already exists and can carry one additional boolean row; the specific table name is determined at plan time.
- An existing AI multi-provider fallback stack (local Ollama, hosted Gemini, hosted Groq, plus any current fallback after Groq) is already wired and can be reused for autofill; this feature does not add a new provider.
- Existing user-role information is available on both the frontend and backend through the current authentication mechanism.
- The work order form's field set — title, description, priority, category, asset/equipment — is stable at the time of implementation; if the form changes, the AI field mapping is expected to be updated accordingly.
- "Admin role" means a user whose role in the existing user table is Admin; administrative privilege is not delegated via any other mechanism for the purposes of this feature.
- Audit logging infrastructure already exists and can record the toggle change; no new audit pipeline is introduced.
- The "fresh fetch on screen open" requirement is satisfied by a single lightweight request per screen open; aggressive real-time push is not required.
- The confirmation dialog for overwrite uses existing dialog patterns in the app; no new design system component is required.
- A description of at least 20 characters is required for the AI to produce a useful draft, and descriptions are capped at 500 characters; both bounds are enforced server-side before any AI provider is contacted (see FR-022).
