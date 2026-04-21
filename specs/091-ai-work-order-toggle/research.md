# Research: AI Work Order Toggle (091)

## R1: Where to persist the AI Work Order toggle setting

**Decision**: Add a new key `ai_work_order_enabled` to the existing `app_settings` table.

**Rationale**: The `app_settings` table already exists with `key` (PK), `value` (TEXT), `updated_at`, `updated_by` columns. Two similar features already use it: `smart_preprocessing_enabled` and `ai_provider`. The CRUD pattern is well-established via `backend/utils/app_settings.py` (`get_setting`/`set_setting`). The `system_settings` table is used by a different admin UI path (`SettingsService` → `/settings/{key}`); using `app_settings` keeps this feature consistent with the other AI toggles (`SmartPreprocessingSection` in `settings_page.dart`) which use `AiProviderService` → `/settings/smart-preprocessing`. The `app_settings` table also tracks `updated_by` (UUID FK to users), satisfying the audit requirement for who changed the setting.

**Alternatives considered**:
- New dedicated table: Rejected — one boolean row doesn't justify a new table.
- `system_settings` table: Rejected — that table is used by a different service layer (`SettingsService`) and doesn't track `updated_by`. The AI feature toggles all live in `app_settings`.

## R2: How to expose the toggle in Admin settings

**Decision**: Follow the `SmartPreprocessingSection` pattern — a `SurfaceCard` with a `Switch` widget inside a dedicated "AI Features" section on the main `SettingsPage`, gated behind admin role. Add GET/PUT endpoints at `/settings/ai-work-order` following the exact pattern of `/settings/smart-preprocessing` in `ai_providers.py`. Use `AiProviderService` on the frontend for consistency.

**Rationale**: The `SmartPreprocessingSection` (lines 1365-1499 in `settings_page.dart`) is the closest existing pattern for an AI feature toggle in admin settings. It uses `SurfaceCard`, a `Switch` widget, optimistic local state with loading indicator, and routes through `AiProviderService`. The new "AI Features" section will group this toggle alongside the existing Smart Preprocessing toggle, providing a natural home for future AI feature toggles.

**Alternatives considered**:
- `SwitchListTile` in `SettingsScreen` (separate screen): Rejected — that screen uses `SettingsService` → `system_settings`, which is a different service layer. The `SurfaceCard` + `Switch` pattern on the main `SettingsPage` is more visually consistent with the existing AI toggles.
- Separate "AI Features" screen: Rejected — YAGNI; two toggles don't require a dedicated screen. A section on the existing settings page is sufficient.

## R3: How to gate AI features on the Add Work Order screen

**Decision**: Fetch the `ai_work_order_enabled` setting on every open of `AddWorkOrderScreen.initState()`. Store the result in a `bool _aiWorkOrderEnabled` field (default `false`). Conditionally render `NlInputCard` only when `_aiWorkOrderEnabled` is `true`. On fetch failure, default to `false` (hide AI entry — per FR-010 fallback).

**Rationale**: The spec requires FR-009 (fresh fetch, not cached) and FR-010 (hide on failure). The `NlInputCard` is already conditionally rendered (`if (widget.workOrder == null)` at line 1510 of `add_work_order.dart`). Adding a second condition (`&& _aiWorkOrderEnabled`) is minimal. The fetch can use `AiProviderService.getAiWorkOrderEnabled()` — a simple GET that returns `bool`.

**Alternatives considered**:
- Real-time push (WebSocket): Rejected — spec explicitly says "fresh fetch on screen open" is sufficient (Assumption: "aggressive real-time push is not required").
- Cache with TTL: Rejected — spec says "not from an app-startup cache that may be stale". A per-screen fetch is cleaner and simpler.

## R4: How to implement server-side toggle enforcement on the autofill endpoint

**Decision**: Add a new `/ai/autofill-work-order` POST endpoint in `ai_assist.py`. Before any AI processing, check `app_settings.get_setting('ai_work_order_enabled')`. If the value is not `'true'`, return HTTP 403 with `{"detail": "AI Work Order feature is disabled"}`. Also require authentication (user email from request), reject if not authenticated (401). Validate input length (20–500 chars) before any AI call.

**Rationale**: The spec requires FR-018 (server-side toggle check), FR-019 (authentication required), and FR-022 (input validation). A dedicated endpoint is cleaner than modifying `/ai/parse-work-order` because: (1) it separates concerns (the old endpoint may still be used elsewhere), (2) it allows different rate limiting rules, and (3) it returns a structured response tailored to work order form field mapping. The toggle check happens first (cheapest check), then auth, then rate limiting, then input validation, then AI generation — a short-circuit chain that minimizes cost.

**Alternatives considered**:
- Modify existing `/ai/parse-work-order`: Rejected — that endpoint is also called from the Dashboard NL card and might be used for other purposes. Better to create a focused endpoint with the exact response shape needed.
- Middleware-based gate: Rejected — only one endpoint needs this specific combination of checks. A decorator/middleware is over-engineering for a single endpoint.

## R5: Rate limiting implementation

**Decision**: In-memory rate limiter using `collections.defaultdict` + `asyncio.Lock` per user email. Two separate counters: rolling 60-second window (max 10) and rolling 24-hour window (max 100). Store as lists of timestamps; on each request, prune expired entries and check counts. Return 429 with `Retry-After` header and human-readable message.

**Rationale**: The spec requires per-user rate limits of 10/min and 100/day (FR-025). No existing rate limiting infrastructure exists in the backend. An in-memory approach is simplest and sufficient for a single-server deployment (~50 concurrent users). Rate-limited requests must not contact any AI provider (FR-025), so checks must happen before AI generation. A `collections.defaultdict(list)` keyed by user email with timestamp pruning is straightforward and doesn't require Redis or external state.

**Alternatives considered**:
- Redis-based rate limiter: Rejected — adds an external dependency for a feature that serves ~50 users. YAGNI.
- Decorator on the endpoint: Considered but the rate limiter needs to be instantiated and shared — a module-level `RateLimiter` instance in a new `services/rate_limiter.py` is simpler and reusable for future endpoints.
- Database-backed rate limiting: Rejected — counting request timestamps in Supabase on every request adds unnecessary latency and DB load. In-memory is sufficient for single-server.

## R6: How to implement the overwrite confirmation dialog

**Decision**: Create a new `AiOverwriteDialog` widget that receives a map of `{fieldName: {current, proposed}}` for conflicting fields. Each row shows a label, current value, proposed value, and "Keep mine" (default, radio) / "Use AI" radio buttons. User must tap "Apply" to confirm. Only fields where "Use AI" is selected get overwritten; all others keep their original value. Non-conflicting (empty) fields are filled immediately before the dialog is shown.

**Rationale**: FR-014 requires per-field "keep mine" vs "use AI" radio selection. FR-015 says empty fields fill immediately without confirmation. This means the dialog is only shown when at least one pre-filled field conflicts with an AI suggestion. Flutter's `AlertDialog` or `showDialog` with a custom `StatefulWidget` content is the standard approach. The `SurfaceCard` pattern and `AppColors` theme are already established in the codebase.

**Alternatives considered**:
- Bottom sheet instead of dialog: Rejected — the spec says "confirmation dialog", and a dialog blocks interaction with the form behind it, which is the correct UX for overwrite confirmation.
- Full list of all fields (including empty ones): Rejected — FR-015 explicitly says empty fields fill without confirmation. Only show conflicts.

## R7: How to handle the autofill response field mapping

**Decision**: The `/ai/autofill-work-order` endpoint returns a JSON response with fields: `title`, `description`, `priority`, `category` (department), `asset_name`, `fault_description`, `action_taken`, `outcome`. The AI prompt instructs the model to return these fields as a JSON object. Unknown values (e.g., a category not in the dropdown) are dropped. The frontend maps each field to its corresponding controller/dropdown, validates against known options, and only applies values that pass validation.

**Rationale**: The existing `/ai/parse-work-order` endpoint already returns a similar structure (`title`, `description`, `location`, `department`, `type`, `status`). The new endpoint extends this with `asset_name`, `fault_description`, `action_taken`, `outcome` to match the Add Work Order form's structured fields. Unknown values are silently dropped (spec edge case: "the system must not write a value that fails form validation").

**Alternatives considered**:
- Reuse `/ai/parse-work-order` response format verbatim: Rejected — that endpoint doesn't return `asset_name`, `fault_description`, `action_taken`, or `outcome`, which are all form fields on the Add Work Order screen. A new response shape is needed.

## R8: Which AI generation path to use for autofill

**Decision**: Use `services.ai_providers.resolver.generate()` instead of calling `ollama_generator.generate()` directly. This provides multi-provider fallback (local Ollama → hosted Gemini → etc.) as required by FR-020. Pass `user_email` for activity logging and `latency_breakdown` dict for observability.

**Rationale**: FR-020 says "the autofill service MUST use the existing multi-provider generation fallback ordering." The `resolver` module already handles provider selection, fallback, and logging. The existing `/ai/parse-work-order` endpoint calls `ollama_generator.generate()` directly, which bypasses the fallback chain — this is a known limitation to avoid repeating.

**Alternatives considered**:
- Direct `ollama_generator.generate()` call: Rejected — violates FR-020 which requires the multi-provider fallback chain.
- Custom provider chain: Rejected — YAGNI; the resolver already handles this.

## R9: Audit logging for toggle changes

**Decision**: Use the existing `log_activity()` utility from `backend/utils/activity.py` with `category='admin'`, `action='ai_work_order_toggled'`, `target_label=str(enabled)`, `detail=f'enabled={enabled}'`. This follows the exact pattern used by the smart preprocessing toggle.

**Rationale**: Constitution Principle VI requires audit logging. The `log_activity()` function is the established fire-and-forget pattern. The smart preprocessing toggle already logs with `category='admin'` and `action='smart_preprocessing_toggled'`. Using the same pattern ensures consistency.

**Alternatives considered**:
- Dedicated audit table: Rejected — `user_activity_log` already exists and serves this purpose.
- Logging in Supabase trigger: Rejected — the admin toggle happens via the FastAPI endpoint, not directly in Supabase. The `app_settings.updated_by` field tracks who, but doesn't give us the "when" as reliably as `user_activity_log`.

## R10: Branch name and migration timestamp

**Decision**: Branch `091-ai-work-order-toggle`. Migration `20260421000000_ai_work_order_toggle.sql` seeding `ai_work_order_enabled = false` into `app_settings`.

**Rationale**: Follows existing project conventions (branch numbered after spec, migrations timestamped).