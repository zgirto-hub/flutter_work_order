# Research: Dashboard AI Work Order Card with Draft Preview

**Branch**: `025-dashboard-ai-wo-card` | **Date**: 2026-04-06

## R1: Shared NL Input Widget Design

**Decision**: Extract a `NlInputCard` widget with a callback-driven design: `onGenerate(String text, String language)`.

**Rationale**: The NL input UI (text field, language chips, mic button, Generate button) is identical on Dashboard and AddWorkOrderScreen. A shared widget avoids duplication. The widget manages its own internal state (dictation language, expanded/collapsed) but delegates generation logic to the parent via callback. The callback passes both the text and selected language, so the parent can use them for the AI service call.

**Alternatives considered**:
- **Keep duplicated code**: Faster to implement initially but leads to divergence. Two bugs to fix for every UI change.
- **Stateless widget with all state hoisted**: Over-engineered. The widget can own simple UI state (language selection, collapse toggle) internally.

## R2: Draft Bottom Sheet Pattern

**Decision**: Use existing `showAppBottomSheet` + `BottomSheetContainer` from `frontend/lib/widgets/bottom_sheet_widgets.dart`. Return an `AiDraftAction` enum (create/edit) via `Navigator.pop`.

**Rationale**: The codebase already has a well-styled bottom sheet helper (`showAppBottomSheet`) that provides consistent styling (rounded corners, drag handle, max height). The draft sheet is a simple read-only preview with two action buttons — no need for `StatefulBuilder` since no local state is needed (fields are read-only). Returns the user's choice to the caller.

**Alternatives considered**:
- **Custom dialog**: Not the app's pattern. Bottom sheets are the standard for contextual actions.
- **Full-page preview**: Over-engineered for a simple preview with two actions.
- **StatefulBuilder in sheet**: Only needed if fields were editable inline. They're read-only per clarification.

## R3: Job Number Generation for Direct Create

**Decision**: Generate job number client-side using the same timestamp pattern from `work_order_home.dart` line 758: `WO${YY}${MM}${DD}-${HH}${mm}${ss}`.

**Rationale**: The existing "New Work Order" flow in `WorkOrderHome._openAdd()` generates the job number client-side before creating the work order. The Dashboard's direct Create path must follow the same pattern. This is a simple timestamp string — no server call needed.

**Alternatives considered**:
- **Server-generated job number**: Would require a new endpoint. The existing pattern is client-side and works well.
- **Empty job number (let server assign)**: Risky — the backend may reject empty job numbers. Safer to follow the existing pattern.

## R4: Department Fetching Strategy

**Decision**: Fetch departments on-demand when Generate is tapped. Cache in dashboard state for subsequent calls.

**Rationale**: The Dashboard doesn't currently load departments. Fetching on init would add unnecessary API calls for users who never use the AI card. On-demand fetching with caching provides the best balance: first Generate is slightly slower (department fetch + AI call), subsequent ones are instant (cached departments, AI call only).

**Alternatives considered**:
- **Fetch on Dashboard init**: Wastes a network call for every dashboard load, even when AI isn't used.
- **Pass departments from MainScreen**: MainScreen doesn't currently load departments either. Would push complexity upward.

## R5: AddWorkOrderScreen Prefill Expansion

**Decision**: Add optional constructor parameters: `prefillDescription`, `prefillLocation`, `prefillType`, `prefillStatus`, `prefillDepartment`, `prefillDepartmentId`. Apply in initState alongside existing `prefillTitle` handling.

**Rationale**: The screen already supports `prefillTitle` and `prefillLocation`. Extending the pattern to cover all AI-parseable fields is consistent and minimal. The existing init block (around line 219) already demonstrates the pattern: `if (widget.prefillTitle != null) clientController.text = widget.prefillTitle!`.

**Alternatives considered**:
- **Pass a Map instead of individual params**: Less type-safe. Individual params match the existing pattern.
- **Create a PrefillData class**: Over-engineered for 6 optional strings.
