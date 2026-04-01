# Feature Specification: System Status Cards Redesign

**Feature Branch**: `001-status-cards-redesign`
**Created**: 2026-04-02
**Status**: Draft
**Input**: User description: "at system status page: I want to make a better UI system cards are very big, study the screen, make it better"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Compact System Status Overview (Priority: P1)

An admin or technician opens the System Status page and sees all system
status cards at a glance without excessive scrolling. Each card conveys
the system name, its current status (OK or Issue), and any relevant
tags (e.g., SAT) in a visually dense but readable layout. The user can
quickly scan dozens of systems and immediately spot which ones have
issues.

**Why this priority**: The primary pain point is that the current cards
are too large, forcing users to scroll extensively to get a full
picture of system health. A compact card layout directly addresses
this.

**Independent Test**: Open the System Status page with 15+ systems and
verify all cards are visible with minimal scrolling, each card is
readable, and status is immediately distinguishable.

**Acceptance Scenarios**:

1. **Given** a system status page with 12 systems, **When** the user
   opens the page on a standard desktop viewport (1280x800), **Then**
   all 12 system cards are visible without scrolling.
2. **Given** a system has an active issue, **When** the user views the
   card grid, **Then** the issue state is distinguishable from OK
   within 1 second (color, icon, or badge difference).
3. **Given** the current 3-column grid, **When** the redesigned cards
   are rendered, **Then** each card takes up noticeably less vertical
   space than before while retaining all existing information.

---

### User Story 2 - Compact Expandable Group Sections (Priority: P2)

When the user expands a group section (e.g., a department's
sub-systems), the contained cards use the same compact layout. The
group header remains clear and the expand/collapse interaction is
unchanged, but the expanded content takes up less vertical space.

**Why this priority**: Groups reuse the same card widget, so once P1 is
done this follows naturally, but it must be verified as a separate
user journey.

**Independent Test**: Expand any group section and verify the cards
inside match the compact layout and the section does not push content
excessively downward.

**Acceptance Scenarios**:

1. **Given** a collapsed expandable group with 6 sub-systems, **When**
   the user expands it, **Then** all 6 sub-system cards are visible
   within the expanded area without the page jumping excessively.
2. **Given** multiple expandable groups, **When** two groups are
   expanded simultaneously, **Then** the user can see both groups'
   cards without scrolling more than one viewport height.

---

### User Story 3 - Compact Recent Issues List (Priority: P3)

The "Recent Issues" section at the bottom of the page uses a more
compact card design so users can scan recent issue history faster. Each
history card still shows the system name, date, resolution status, and
notes, but in a tighter layout.

**Why this priority**: The history cards are secondary to the live
status overview but also contribute to page bloat.

**Independent Test**: View the Recent Issues section with 10+ entries
and verify more entries are visible per viewport compared to the
current design.

**Acceptance Scenarios**:

1. **Given** 10 recent issues exist, **When** the user scrolls to the
   Recent Issues section on desktop, **Then** at least 6 issue entries
   are visible without further scrolling.
2. **Given** a recent issue with notes, **When** the user views the
   history card, **Then** the system name, date, status, and truncated
   notes are all visible and readable.

---

### Edge Cases

- What happens when a system name is very long (30+ characters)? It
  MUST truncate with ellipsis rather than expanding the card.
- How does the compact layout behave on narrow viewports (mobile/tablet
  below 600px width)? The grid MUST gracefully reduce to fewer columns
  without breaking the layout.
- What happens when there are zero systems or zero recent issues? Empty
  states MUST remain properly styled and not collapse awkwardly.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System status cards MUST display the system name, status
  indicator (OK/Issue), and optional SAT tag in a more compact layout
  than the current design.
- **FR-002**: The redesigned cards MUST retain all existing information
  currently shown on each card (name, status dot, status badge, SAT
  tag when applicable).
- **FR-003**: Long system names MUST truncate with ellipsis rather than
  wrapping to multiple lines or expanding the card height.
- **FR-004**: The card grid MUST remain responsive, supporting at least
  3 columns on desktop and reducing gracefully on narrower viewports.
- **FR-005**: The expandable group sections MUST use the same compact
  card layout for their contained sub-system cards.
- **FR-006**: Recent Issues (history) cards MUST use a more compact
  layout with reduced vertical padding and tighter spacing while
  retaining all existing fields (status dot, name, date, notes, status
  label, action menu).
- **FR-007**: All existing interactions MUST be preserved: card tap
  behavior, expandable group toggle animation, history card context
  menu (Edit/Delete), and pull-to-refresh.
- **FR-008**: The color scheme and status differentiation (green for OK,
  red for Issue, amber for SAT) MUST remain unchanged.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a standard desktop viewport (1280x800), at least 50%
  more system cards are visible above the fold compared to the current
  design.
- **SC-002**: Users can identify all systems with active issues within
  3 seconds of opening the page (visual scan test).
- **SC-003**: The redesigned page retains 100% of the information shown
  in the current design — no data is removed or hidden behind
  additional clicks.
- **SC-004**: The vertical space consumed by each individual system card
  is reduced by at least 30% compared to the current card height.

## Assumptions

- The existing 3-column grid structure is a reasonable default and does
  not need to change to a 4+ column layout — the improvement comes
  from reducing card height, not adding columns.
- The screen is primarily used on desktop/web viewports; mobile
  optimization is secondary but MUST NOT break.
- All existing bottom-sheet modals (report issue, resolve issue, edit
  issue, uptime report) are out of scope — only the main page cards
  and layout are being redesigned.
- The uptime report charts and per-system uptime cards are out of scope
  for this redesign.
