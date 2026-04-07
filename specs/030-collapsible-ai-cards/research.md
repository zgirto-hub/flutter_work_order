# Phase 0 Research: Collapsible AI Cards

**Feature**: 030-collapsible-ai-cards
**Date**: 2026-04-07

No `NEEDS CLARIFICATION` markers existed in Technical Context. Research below documents the small set of Flutter-specific decisions for the implementation.

## Decision 1: Animation primitive

- **Decision**: Wrap the card body in `AnimatedSize` (with a short `Duration(milliseconds: 200)` and `Curves.easeInOut`), keeping the body widget mounted at all times. When collapsed, the body is replaced by `SizedBox.shrink()` *only* if state preservation is not needed; otherwise use `Visibility(maintainState: true, visible: expanded, child: body)` so internal `State` (typed text, in-flight futures) is preserved.
- **Rationale**: `AnimatedSize` gives a smooth height transition without manually animating constraints. Combined with `Visibility(maintainState: true)`, it satisfies FR-010 (in-flight ops continue) and FR-011 (typed text preserved) while still hiding the content visually.
- **Alternatives considered**:
  - `ExpansionTile` — uses Material list semantics and a fixed leading/trailing layout that does not match the existing card chrome; harder to style; rebuilds children on expand by default.
  - `AnimatedCrossFade` — cross-fades between two children; works but is heavier than needed for a single show/hide.
  - `AnimatedContainer` with manual height — requires measuring intrinsic height, fragile.

## Decision 2: State location

- **Decision**: Add two `bool` fields, `_aiInsightsExpanded = false` and `_aiWorkOrderExpanded = false`, to `DashboardScreenState`. Toggle via `setState` in the header `onTap`.
- **Rationale**: Smallest possible surface area; matches FR-007 (independent per card) and FR-009 (no persistence — reset on every `initState`).
- **Alternatives considered**: A `Map<String,bool>` keyed by card id (overkill for 2 entries); a separate `ChangeNotifier` (unnecessary, no other listeners).

## Decision 3: Header design

- **Decision**: Build a private `_CollapsibleHeader` row inside `dashboard_screen.dart` reusing existing `AppColors`, `AppTheme`, the same border radius and surface color as the existing cards. Layout: leading icon (sparkle for AI Insights, sparkle for AI Work Order — matching what each card uses today), title text, trailing `AnimatedRotation` chevron (`Icons.expand_more_rounded` rotated 180° when expanded). The whole row is wrapped in an `InkWell` for tap feedback and accessibility (`Semantics(button: true, expanded: …)`).
- **Rationale**: Keeps visual continuity with the existing dashboard cards (FR-003, Assumption: reuse existing chrome). `Semantics` covers the accessibility edge case.
- **Alternatives considered**: Using each card's own existing internal header — rejected because that would require modifying `AiInsightsCard` and `NlInputCard` themselves, expanding scope and risk.

## Decision 4: Where the wrapping happens

- **Decision**: Wrap each child card from the outside in `dashboard_screen.dart`. `AiInsightsCard` and `NlInputCard` are not modified.
- **Rationale**: Scope is dashboard-only (Assumption in spec). Keeps the change reversible and avoids touching widgets potentially used elsewhere.

## Decision 5: Reset on dashboard re-entry

- **Decision**: Because the state lives in `DashboardScreenState`, leaving and returning to the dashboard tab triggers a fresh `initState`, naturally giving collapsed defaults. No additional code needed.
- **Rationale**: Satisfies FR-009 / SC-004 with zero extra logic.

## Open Questions

None. All decisions above are local, low-risk, and require no new dependencies.
