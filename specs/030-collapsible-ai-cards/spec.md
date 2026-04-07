# Feature Specification: Collapsible AI Cards on Dashboard

**Feature Branch**: `030-collapsible-ai-cards`
**Created**: 2026-04-07
**Status**: Draft
**Input**: User description: "Make the AI Insights card and AI Work Order card on the dashboard collapsible. Default collapsed; tap header to expand; independent per card; animated; no persistence."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reduce dashboard clutter by collapsing AI cards (Priority: P1)

A dashboard user opens the app and sees the AI Insights and AI Work Order cards in a compact, collapsed state by default. This keeps the dashboard focused on stats, quick actions, and recent activity, while still making AI features discoverable.

**Why this priority**: This is the core of the request — without collapsed-by-default headers, the feature does not exist. It immediately reduces visual noise on the dashboard.

**Independent Test**: Open the dashboard. Verify both AI Insights and AI Work Order appear as single-row headers (icon + title + expand affordance) and that none of their inner controls (filter chips, text field, Generate button, etc.) are visible.

**Acceptance Scenarios**:

1. **Given** the user opens the dashboard, **When** the dashboard finishes loading, **Then** both AI Insights and AI Work Order cards are rendered in a collapsed state showing only their header.
2. **Given** a card is collapsed, **When** the user looks at the header, **Then** an expand affordance (e.g., a chevron) is visible indicating the card can be opened.

---

### User Story 2 - Expand a card to use it (Priority: P1)

When the user wants to use AI Insights or generate an AI Work Order, they tap the card's header and the card smoothly expands to reveal its full existing content.

**Why this priority**: Users must be able to access the underlying functionality; collapsing is only useful if expansion is easy and obvious.

**Independent Test**: Tap the AI Insights header — verify the filters and insights area appears with a smooth animation. Tap the AI Work Order header — verify the text input, language toggle, mic button, and Generate button appear.

**Acceptance Scenarios**:

1. **Given** the AI Insights card is collapsed, **When** the user taps its header, **Then** the card animates open and shows its full controls and content.
2. **Given** the AI Work Order card is collapsed, **When** the user taps its header, **Then** the card animates open and shows its description input, language toggle, mic, and Generate button.
3. **Given** an expanded card, **When** the user taps the header again, **Then** the card animates closed back to header-only.
4. **Given** the AI Insights card is expanded, **When** the user expands the AI Work Order card, **Then** AI Insights remains expanded (state is independent per card).

---

### User Story 3 - Fresh state on each app launch (Priority: P3)

Each time the app is launched or the dashboard is reopened, both cards return to their default collapsed state, regardless of what the user did in the previous session.

**Why this priority**: Explicitly requested. Simple, predictable default; no storage needed.

**Independent Test**: Expand both cards, close and reopen the app, return to the dashboard, and verify both cards are collapsed again.

**Acceptance Scenarios**:

1. **Given** the user expanded one or both cards, **When** the app is restarted, **Then** both cards are collapsed again on the next dashboard view.

---

### Edge Cases

- Tapping the header rapidly should not leave the card in a broken or half-animated state.
- Expanding/collapsing must not interrupt or reset in-progress operations (e.g., an AI Work Order generation that is currently running, or AI Insights that are loading).
- If the user has typed text into the AI Work Order field and collapses the card, the typed text must be preserved when re-expanded.
- The collapse/expand interaction must remain accessible to assistive technologies (the header is announced as a button with an expanded/collapsed state).
- Pull-to-refresh on the dashboard must continue to work regardless of expansion state.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The dashboard MUST render the AI Insights card in a collapsed state by default whenever the dashboard is shown.
- **FR-002**: The dashboard MUST render the AI Work Order card in a collapsed state by default whenever the dashboard is shown.
- **FR-003**: A collapsed card MUST display only a header consisting of the card's icon, its title, and a visible expand/collapse affordance.
- **FR-004**: Tapping anywhere on a collapsed card's header MUST expand that card to reveal its full existing content.
- **FR-005**: Tapping anywhere on an expanded card's header MUST collapse that card back to header-only.
- **FR-006**: The expand and collapse transitions MUST be visually animated (smooth size/opacity change), not instantaneous snaps.
- **FR-007**: The expansion state of each AI card MUST be independent — toggling one card MUST NOT affect the other.
- **FR-008**: The expand affordance (e.g., chevron) MUST visually reflect the current state (pointing down/right when collapsed, up/open when expanded).
- **FR-009**: The expansion state MUST NOT be persisted across app restarts or navigation away from and back to the dashboard; both cards always re-appear collapsed.
- **FR-010**: In-progress operations inside a card (AI generation, insight loading) MUST continue uninterrupted if the user collapses or re-expands the card.
- **FR-011**: User-entered text in the AI Work Order input MUST be preserved when the card is collapsed and re-expanded within the same dashboard session.
- **FR-012**: All existing functionality of both cards (filters, language toggle, dictation, Generate, insights generation/refresh) MUST remain unchanged when expanded.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a fresh dashboard load, the vertical space occupied by the AI Insights and AI Work Order cards combined is reduced by at least 60% compared to the current always-expanded layout.
- **SC-002**: A user can expand a collapsed AI card and begin interacting with its controls in a single tap.
- **SC-003**: Expand/collapse animations complete in under 300 ms and feel smooth (no visible jank) on supported devices.
- **SC-004**: 100% of dashboard sessions begin with both AI cards collapsed.
- **SC-005**: No regression in existing AI Insights or AI Work Order functionality — every action available today remains available once the card is expanded.

## Assumptions

- The visual style of the collapsed header reuses the existing card chrome (background, border, padding) so no new design system tokens are required.
- A chevron icon is acceptable as the expand/collapse affordance.
- "Independent per card" means local UI state on the dashboard screen; no cross-device sync is required.
- Non-persistence is intentional and desirable; no setting is needed to change the default.
- The feature is scoped to the dashboard screen only; AI Insights and AI Work Order usages elsewhere (if any) are unaffected.
