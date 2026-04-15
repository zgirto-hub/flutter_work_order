# Phase 0 — Research: System Status Infra Compatibility

## Scope

This research phase confirms the exact code removal targets in `frontend/lib/screens/system_status_screen.dart` and verifies that the surrounding behavior (Report Issue, Issue Details, Recent Issues, uptime report) can remain intact when the grouping layer is removed. No external research needed — all unknowns are internal to one file.

## Unknowns: none

Technical Context has no `NEEDS CLARIFICATION` markers. The spec's pre-answered clarifications resolve everything we need: name-based identity stays, uptime logic stays, SAT badge goes, grouping goes, grid stays 3-column.

## Findings

### Decision 1 — Remove grouping logic in `_loadData`

- **Decision**: Delete the `_mainSystems`/`_groupedSystems` split inside `setState` at lines ~65–74. Assign the full `_systems` list directly to the grid.
- **Rationale**: Post-061 there are no names containing `" - "`, so the split always lands 100% in `_mainSystems`. The split code is dead weight. With 7 flat rows, grouping has no meaning anyway.
- **Alternatives considered**:
  - *Leave the split in for defense-in-depth*: rejected — FR-001 and FR-002 explicitly require removal; YAGNI.
  - *Replace the name split with a real parent/child lookup via `asset_system_links`*: rejected — out of scope (per-asset status is explicitly out of scope).

### Decision 2 — Remove `_ExpandableGroup` widget + state set

- **Decision**: Delete the `_ExpandableGroup` widget class (lines ~1143–1287) and the `_expandedGroups` field (line 22). Delete the `for (final entry in _groupedSystems.entries)` block in `build` (lines ~1096–1112).
- **Rationale**: FR-002, FR-005. No callers remain once the grouping step is gone.
- **Alternatives considered**: keep the widget as a library-internal helper — rejected, no future use is planned (SAT badge replacement is out of scope).

### Decision 3 — Simplify `_SystemCard`

- **Decision**: Remove the optional `displayName` parameter (line 1295), the `_satSystems` static set (line 1292), `_isSat` getter (line 1301), and the SAT badge `Container` (lines ~1332–1348). Render `system.systemName` directly (FR-003, FR-004).
- **Rationale**: No caller will pass `displayName` once grouping is removed, and SAT badge targets are stale/data-less post-061.
- **Alternatives considered**:
  - *Keep `displayName` for safety*: rejected — unused parameter triggers `flutter analyze` warnings and violates YAGNI.
  - *Data-drive the SAT badge via a new `systems` column*: rejected — spec explicitly defers this.

### Decision 4 — Preserve grid layout constants

- **Decision**: Keep `crossAxisCount: 3`, `crossAxisSpacing: 8`, `mainAxisSpacing: 8`, `childAspectRatio: 3.0` exactly as at lines 1082–1086.
- **Rationale**: FR-008. No visual regression intended for unaffected cards.

### Decision 5 — Leave `_HistoryCard`, uptime report, and service layer untouched

- **Decision**: Do not modify `_HistoryCard` (line 1376+), do not modify any `_show*Sheet` helpers, do not modify `SystemStatusService`, `SystemStatus` model, or backend routes.
- **Rationale**: FR-006, FR-007. Recent Issues section simply renders whatever `system_name` string is on each `SystemStatusReport` row — which is exactly how it works today. Repointed rows already display the repointed canonical name because the backend writes the current `system_name` at report time.
- **Alternatives considered**: normalize history names to the current canonical — rejected, risks rewriting history; spec calls this accepted existing behavior.

### Decision 6 — Verification strategy

- **Decision**: Rely on `flutter analyze` (SC-005) plus manual verification following `quickstart.md` for each SC-00x.
- **Rationale**: The change is pure deletion of unreachable-post-migration code plus a small reshape of the grid's data source. Behavior that's *kept* is already covered by existing manual test practice; behavior that's *removed* has no production equivalent to regress against.
- **Alternatives considered**: Add a widget test asserting "no SAT badge, flat grid" — rejected per YAGNI and SC-005's analyze-only gate; the removal is mechanical.

## Risk register

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| A sibling screen imports `_ExpandableGroup` | Very low — it's file-private (`_` prefix) | Dart private symbols cannot cross files; guaranteed safe. |
| A dependent widget passes `displayName` | None — only the internal grouped-subsystem block passes it | Both callsites are deleted together in one task. |
| Pre-migration env still has `" - "` names | Tolerated | Without grouping, the full name simply renders in a card (FR-003). Behavior is strictly better than today's truncated names. |
| Analyzer complains about an unused import after deletion | Low | Final task runs `flutter analyze` and fixes any fallout. |

## Outcome

All questions resolved. Proceed to Phase 1.
