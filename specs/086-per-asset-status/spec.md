# Feature Specification: Per-Asset System Status Reporting

**Feature Branch**: `086-per-asset-status`
**Created**: 2026-04-18
**Status**: Draft
**Input**: User description: "Asset-level System Status Reporting — add per-asset issue tracking alongside existing system-level flow so operators can record that a single asset (e.g., Damascus international circuit) is down without marking its whole parent system (e.g., AIDA NG) down."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Report and resolve an issue on a specific asset (Priority: P1)

An operator notices that a single piece of equipment linked to a system is malfunctioning while the rest of the system is fine. They open the Status screen, find the system's card, tap it to open a drill-in sheet that lists every asset linked to that system, pick the affected asset, and record an issue with a date and notes. When the issue is fixed, they return to the same sheet, tap the asset again, and mark it resolved — all without ever touching the parent system's status.

**Why this priority**: This is the core capability the feature exists to deliver. Without it, operators have to mark a whole system as "Issue" when only one asset is affected, which misrepresents operational state, corrupts uptime reporting, and creates noise for anyone else looking at the dashboard. Every other story builds on this one.

**Independent Test**: Create an asset linked to a system in Infrastructure, open the Status drill-in sheet for that system, report an issue on the asset, confirm the issue appears in the history labeled with "System → Asset", then resolve it and confirm it clears. No other stories need to ship for this to deliver value.

**Acceptance Scenarios**:

1. **Given** the AIDA NG system has three linked assets and none have open issues, **When** the operator opens the drill-in sheet and reports an issue on "Damascus international circuit" with today's date and notes "line degraded", **Then** a new asset-level report is created, the drill-in sheet re-renders showing that asset with an "Issue" dot, the history list shows a row labeled "AIDA NG → Damascus international circuit", and the parent system's system-level status remains "OK".
2. **Given** Damascus international circuit has an open issue, **When** the operator opens the same asset in the drill-in sheet and resolves the issue with a resolve date and resolution notes, **Then** the asset returns to "OK", the history row gains a "Resolved" pill, and the parent system's card no longer shows the asset-issue badge.
3. **Given** Damascus international circuit already has an unresolved issue for today, **When** the operator tries to report a second unresolved issue on the same asset for the same date, **Then** the system rejects the duplicate with a clear message explaining an unresolved issue already exists.
4. **Given** an operator picks an asset that is not linked to the system they chose, **When** they submit the report, **Then** the system rejects it with a clear message that the asset does not belong to that system.

---

### User Story 2 - At-a-glance awareness of asset issues on the grid (Priority: P2)

When an operator glances at the Status screen, they can immediately see which systems have asset-level problems without drilling into every card. A system whose own status is "OK" but which has one or more assets with open issues shows a small amber badge on its card indicating the count of asset issues, visually distinct from the red "system down" state.

**Why this priority**: Without the badge, operators would have to open every drill-in sheet to check for asset issues — a discovery regression compared to today's flat grid. The badge preserves the "dashboard at a glance" property of the screen. It depends on Story 1 (the asset-level issue has to exist to be counted) but is not part of the minimum viable slice.

**Independent Test**: With one asset-level issue open on AIDA NG (from Story 1), load the Status screen. The AIDA NG card shows a green "OK" dot for the system plus an amber badge showing "⚠ 1". The other system cards are unchanged. Clearing the issue removes the badge on the next load.

**Acceptance Scenarios**:

1. **Given** the AIDA NG system has one asset with an open issue and no system-level issue, **When** the operator loads the Status screen, **Then** the AIDA NG card shows green dot + "OK" label + amber "⚠ 1" badge.
2. **Given** the AIDA NG system has both a system-level issue and an asset-level issue, **When** the operator loads the Status screen, **Then** the AIDA NG card shows red dot + "Issue" label + amber "⚠ 1" badge.
3. **Given** a system has no open issues at any level, **When** the operator loads the Status screen, **Then** the card renders exactly as it does today — no badge is shown.

---

### User Story 3 - Uptime report reveals which assets caused a system's downtime (Priority: P3)

When the operator pulls an uptime report for a date range, each system card can now be expanded to reveal how each of its linked assets performed over that period. Assets are sorted worst-uptime-first so the biggest contributors to downtime surface at the top. This lets operators answer "which specific asset hurt us this month?" without running a separate report.

**Why this priority**: Enhances existing reporting for post-hoc analysis. Not required for day-to-day operations — the P1/P2 stories already keep real-time state accurate. Valuable for monthly reviews and capacity planning.

**Independent Test**: Over a 30-day window where "Damascus international circuit" had 3 days of open issues and AIDA NG itself had no system-level issues, generate the uptime report. The AIDA NG system card shows 100% system uptime. Expanding it reveals Damascus at 90% uptime with a red indicator; any other AIDA NG assets with zero issues show at 100% with a green indicator.

**Acceptance Scenarios**:

1. **Given** a system has linked assets and one of them had days with issues in the report period, **When** the operator expands the system's card, **Then** the expanded body shows one row per linked asset (sorted worst uptime first), each with a colored indicator (green/amber/red by threshold) and an uptime percentage.
2. **Given** a system and all its linked assets had zero days with issues in the report period, **When** the operator expands the system's card, **Then** the expanded body shows a single line "All assets operational for the period" and no per-asset rows.
3. **Given** a system has no linked assets, **When** the operator expands the system's card, **Then** the expanded body shows "No linked assets" and no per-asset rows.

---

### Edge Cases

- **Linked asset is deleted or unlinked while an asset-level report is open**: the open report is removed along with the asset (cascading removal tied to the asset record). On next Status screen load, the badge count drops accordingly. No orphaned reports remain.
- **Retired system has open asset reports**: consistent with today's behavior for system-level reports on retired systems — the retired system is hidden from the Status grid, so its reports become invisible. No special handling.
- **Operator edits a report's date to a day on which another unresolved issue already exists for the same (system, asset) pair**: same duplicate rule kicks in — the edit is rejected with a clear message.
- **System-level report and asset-level report both open for the same system, same date**: both are allowed. They are distinct records and are displayed/edited/resolved independently. The grid card shows both signals (red dot for system + amber badge for asset).
- **Asset appears under multiple systems via the linking table**: if the same asset is linked to two systems, an asset-level issue is scoped to the `(system, asset, date)` triple — reporting the asset down on System A does not automatically down it on System B. Each relationship is tracked independently.
- **Drill-in sheet network failure while fetching the asset list**: the sheet header and system-level section still render (from grid data already in memory); the asset list area shows an inline error with a retry action. The operator can still report or resolve system-level issues without leaving the sheet.
- **Tapping a fully healthy system (no issues, no assets)**: the sheet opens with a prominent "Report System Issue" primary action at the top and an empty-state message below. The tap is never a dead-end.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Operators MUST be able to record an issue against a specific asset that is linked to a system, providing a report date, free-text notes, and their identity.
- **FR-002**: The system MUST reject an asset-level issue if the asset is not linked (via the existing asset-to-system linking relationship) to the chosen system.
- **FR-003**: The system MUST enforce at most one unresolved issue per `(system, asset, date)` triple. An existing system-level unresolved issue MUST NOT block a new asset-level unresolved issue on the same system and date, and vice versa.
- **FR-004**: Operators MUST be able to edit, resolve, and delete asset-level issues through the same flows they use today for system-level issues, with edits subject to the same duplicate rule.
- **FR-005**: The Status screen grid MUST indicate, on each system's card, when one or more of that system's linked assets has an open issue — without changing the existing system-level status indicator.
- **FR-006**: Tapping any system card on the Status screen MUST open a drill-in view that presents (a) the system's own current status with actions to report or manage the system-level issue, and (b) the list of the system's linked assets with each asset's own current status and actions.
- **FR-007**: The drill-in view MUST always present a clear primary action to the operator, even when the system and all its assets are operational (i.e., a system whose grid card is all green must not result in a dead-end tap).
- **FR-008**: The drill-in view MUST fetch the asset list and statuses lazily when opened, and reflect changes from any subsequent report/resolve/edit/delete operation both inside the sheet and on the parent Status screen.
- **FR-009**: The Recent Issues history MUST include asset-level issues interleaved with system-level issues, with asset-level rows labeled in the form "System Name → Asset Name" so operators can distinguish them at a glance.
- **FR-010**: An asset's current status MUST be computed from whether any of its reports are unresolved at all, independent of the report's date — matching the existing rule for system-level status.
- **FR-011**: The Uptime Report MUST, on request, include a per-asset breakdown within each system, providing each linked asset's total days, days with issues, uptime percentage, and downtime percentage over the report period.
- **FR-012**: Each per-asset row in the Uptime Report MUST carry a visual severity indicator driven by deterministic integer-based thresholds: "green" when the asset had zero days with issues; "amber" when days with issues is greater than zero and uptime percentage is at least 95.0; "red" when uptime percentage is below 95.0.
- **FR-013**: When every asset linked to a system has zero days with issues AND the system itself has zero days with issues, the expanded uptime view for that system MUST display a single summary line (no per-asset rows).
- **FR-014**: Existing system-level issue records (created before this feature) MUST continue to function as system-level issues after the change, without migration or reinterpretation as asset-level.
- **FR-015**: All reporting and management of asset-level issues MUST happen on the Status screen; the Infrastructure screen MUST remain unchanged — it continues to show structural relationships only, with no status indicators and no reporting actions.
- **FR-016**: When a linked asset is deleted or unlinked from a system, any open asset-level reports tied to that (system, asset) pair MUST be removed along with the asset link (cascading removal), so that the badge count and drill-in list stay consistent without manual cleanup.

### Key Entities *(include if feature involves data)*

- **System Status Report**: an operator-submitted record that a system or a specific asset under that system was in a failed state starting on a given date. Existing attributes are preserved (system reference, report date, notes, reporter identity, optional resolution date/notes/resolver). New attribute: an optional link to a specific asset. When the asset link is absent, the report is system-level; when present, the report is asset-level and scoped to that particular (system, asset) pair.
- **Asset**: an individual piece of equipment already tracked by the Asset Registry and linked to one or more systems via the existing asset-to-system linking relationship. Referenced by asset-level reports; deletion of an asset cascades to its asset-level reports.
- **Asset-System Link**: the existing relationship record that attaches an asset to a system with a role (primary/standby/client) and a site (production/contingency). Used to (a) enumerate a system's assets in the drill-in view and the uptime per-asset breakdown, and (b) validate that an asset-level report's asset actually belongs to its chosen system.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can report an asset-level issue in three or fewer taps from the Status screen home (tap system card → tap asset row → submit).
- **SC-002**: From a cold load of the Status screen, an operator can identify every system that has any open issue (system-level OR asset-level) within two seconds, without drilling into any card.
- **SC-003**: In a test range where one asset had 3 days of issues and its parent system had 0 system-level days of issues, the operator reaches the responsible asset name within two actions on the Uptime Report screen (expand system card → read top-sorted asset row).
- **SC-004**: Zero existing system-level reports are lost, silently converted, or altered by the rollout of this feature; the Recent Issues history on launch day shows the same system-level rows it showed the day before (with the new "System → Asset" label applying only to newly created asset-level rows).
- **SC-005**: The duplicate-prevention rule catches 100% of attempts to create a second unresolved report for the same (system, asset-or-system, date) triple — verified by the acceptance scenarios returning a clear error in manual testing.
- **SC-006**: A tap on any system card — including fully healthy systems — always results in an actionable screen; zero operator-reachable dead-ends exist in the new drill-in flow.

## Assumptions

- Assets and their system links already exist as first-class entities via the Asset Registry (spec 053) and Infrastructure screen (spec 061); this feature does not introduce new asset concepts, only new reporting semantics on top of them.
- Existing system-level reports stay as system-level and are never retroactively migrated to specific assets. Operators accept that historical reports predating this feature represent the whole system, not individual assets.
- The Status screen remains the single operational surface for reporting and managing availability issues. The Infrastructure screen stays structural (what is linked to what) and does not gain status visualization or reporting actions.
- The existing rule that an issue is "open" when its resolution date is unset (independent of its report date) remains unchanged and is applied identically to asset-level issues.
- The small set of canonical systems (24 today) and their typical asset counts per system (single-digit in most cases) are small enough that the extra drill-in fetch per opened sheet is negligible to operators; no caching or offline story is required in this spec.
- Approval chains, notifications, and activity-log formats used elsewhere in the app are not changed by this feature beyond the natural appearance of an asset identifier alongside the existing system identifier in records the user already sees today.
