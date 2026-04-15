# Feature Specification: System Status — Infrastructure Compatibility (post-spec-061 cleanup)

**Feature Branch**: `064-update-status-screen`
**Created**: 2026-04-15
**Status**: Draft
**Input**: Align the System Status screen with the post-061 data model (7 canonical systems, no sub-system rows) by removing obsolete grouping, display-name truncation, and SAT badge logic — without altering how outage reporting works for users.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Clean, flat system grid (Priority: P1)

An operations technician opens System Status and sees one card per real system. All cards are peers — no expandable group rows, no sub-system rows, no orphaned entries. Each card shows the full system name and its current status (OK or Issue). Tapping a card opens the Report Issue sheet (when OK) or the Issue Details sheet (when Issue) exactly as before.

**Why this priority**: The current screen exploits a naming convention (`" - "` split) that no longer exists. Without this fix, the grid is visually inconsistent with the real infrastructure model and can confuse users about what the systems actually are.

**Independent Test**: Open the System Status screen on a database where spec 061 has run. Verify exactly the canonical system count is rendered as peer cards, with no group expansion affordances and no nested rows.

**Acceptance Scenarios**:

1. **Given** spec 061 migration has run, **When** a user opens System Status, **Then** exactly 7 system cards are displayed as peers and no expandable group rows appear.
2. **Given** a system has an active unresolved issue, **When** its card is displayed, **Then** the card shows "Issue" with the red indicator.
3. **Given** a system has no active issue, **When** its card is displayed, **Then** the card shows "OK" with the green indicator.
4. **Given** a system card with no active issue, **When** the user taps it, **Then** the Report Issue sheet opens pre-filled with that system's name.
5. **Given** a system card with an active issue, **When** the user taps it, **Then** the Issue Details sheet opens with edit, delete, and resolve actions available.

---

### User Story 2 - No truncated display names, no stale SAT badge (Priority: P1)

None of the system cards show a truncated display name. Previously the screen stripped a prefix off sub-system names (e.g., `"AIDA-NG - Sector A"` → `"Sector A"`). Every card displays the canonical system name exactly as it exists in the data. The SAT badge, previously hard-coded to appear on specific system names (VAS, DRP), no longer appears on any card.

**Why this priority**: Truncated names and a stale SAT badge are actively misleading. Fixing them is necessary for the grid to be correct, not merely tidy.

**Independent Test**: Inspect every card's rendered label and verify it matches the full system name from the API. Inspect every card for the SAT badge and verify none appear.

**Acceptance Scenarios**:

1. **Given** any system card is rendered, **When** the screen loads, **Then** the card displays the full system name with no prefix stripping or truncation.
2. **Given** any system card is rendered, **When** the screen loads, **Then** no SAT badge appears.

---

### User Story 3 - Recent Issues history unaffected (Priority: P2)

The Recent Issues section at the bottom of the screen continues to display recent reports using the system name stored on the report. Reports that were repointed by the 061 migration display the repointed canonical name (e.g., "AIDA-NG"). Edit, delete, and resolve actions on history entries continue to function.

**Why this priority**: This is a regression-guard user story — no behaviour should change here, but the change to card rendering must not accidentally break history interactions.

**Independent Test**: Open the screen, scroll to Recent Issues, verify items render with their stored system names, and exercise Edit / Delete / Resolve from the overflow menu.

**Acceptance Scenarios**:

1. **Given** history reports exist, **When** the screen loads, **Then** Recent Issues renders with each report's stored system name (which may read "AIDA-NG" for repointed records).
2. **Given** a history card's overflow menu, **When** the user taps Edit or Delete, **Then** the corresponding sheet or dialog opens and completes successfully.
3. **Given** a history card with an active issue, **When** the user taps Resolve, **Then** the issue resolves successfully.

---

### Edge Cases

- **Spec 061 not yet run**: If the migration has not executed in a given environment, the screen still renders correctly — it will simply show more system cards (pre-migration rows), all as peers, with no grouping logic to break.
- **System named with " - "**: If any canonical system name legitimately contains `" - "`, it is displayed verbatim; no splitting occurs.
- **Zero systems returned**: If the API returns an empty systems list, the grid renders empty (same empty-state behaviour as today).
- **History references a system name no longer in the systems table**: The history card still displays the stored name; no lookup or repair is attempted.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The screen MUST render all systems returned by the API as a flat peer grid. No grouping by naming convention.
- **FR-002**: The expandable-group UI construct MUST be removed from the screen.
- **FR-003**: System cards MUST display the system name exactly as returned by the API, without any prefix stripping or truncation.
- **FR-004**: The SAT badge MUST NOT appear on any system card. The hard-coded SAT system set MUST be removed.
- **FR-005**: The expanded-group state (tracking which groups are open) MUST be removed.
- **FR-006**: Report, resolve, edit, delete, and uptime-report flows MUST continue to function without user-visible change.
- **FR-007**: No backend or service-layer changes are permitted. The System Status service contract is unchanged.
- **FR-008**: The grid layout (3-column, existing card aspect ratio) MUST be preserved for the flat system list.

### Key Entities

- **System**: A canonical infrastructure unit returned by the System Status API. Has a name and a current status (OK or Issue). Post-061, there are 7 canonical systems.
- **System Status Report**: A historical record of an issue reported against a system name. Repointed records retain their new canonical name. Used to render the Recent Issues section.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With 7 systems present in the data, the System Status grid renders exactly 7 cards and zero expandable group rows.
- **SC-002**: No card displays a name that is a substring of a canonical system name (e.g., no card reads "Sector A" when the canonical name is "AIDA-NG - Sector A").
- **SC-003**: No card displays a SAT badge.
- **SC-004**: Reporting, resolving, editing, and deleting issues (both via cards and via history overflow menu) each succeed end-to-end with no regression compared to current behaviour.
- **SC-005**: Static analysis reports zero new warnings introduced by the change on the affected screen.

## Assumptions

- Spec 061 migration has run in production before users interact with the updated screen. If it has not, the screen still renders correctly with more peer cards.
- The 7 canonical system names are stable after migration. If a name later changes, history records retain the name at the time of report (accepted existing behaviour).
- No role-based visibility change is required; the screen's existing access rules are preserved.
- The uptime report behaviour and UI are unchanged by this spec.

## Out of Scope

- Switching `system_status_reports` from name-based to id-based identity.
- Per-asset (sub-system) status reporting.
- Any change to uptime report calculation or UI.
- Reintroducing the SAT badge via a data-driven mechanism.
- Role-based visibility changes for the System Status screen.

## Affected Surface

- Single frontend screen responsible for System Status rendering. No other UI surfaces, no service layer, no backend, no database, no migrations.
