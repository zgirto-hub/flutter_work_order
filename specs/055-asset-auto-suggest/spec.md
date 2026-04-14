# Feature Specification: Auto-Suggest Asset Registry Additions

**Feature Branch**: `055-asset-auto-suggest`  
**Created**: 2026-04-14  
**Status**: Draft  
**Input**: User description: "When the pattern engine detects recurring alerts for an equipment_id that is NOT in the asset registry, the system should automatically suggest adding it as a new asset. This closes a gap where technicians reference equipment in work orders that hasn't been registered yet, making the registry self-improving over time."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin Reviews Suggested Assets (Priority: P1)

An Admin opens the Asset Registry screen and sees a "Suggestions" section at the top showing unregistered equipment that has appeared in 2 or more pattern alerts. Each suggestion shows the equipment name, the number of alerts it has triggered, and the most recent fault types. The Admin can quickly scan these to decide which equipment should be formally added to the registry.

**Why this priority**: This is the core value — surfacing unregistered equipment that the system already knows about from real work orders, so the Admin doesn't have to manually cross-reference alerts and the registry.

**Independent Test**: Can be tested by ensuring pattern alerts exist for equipment_ids not in the asset registry (e.g., "MUX system", "CADAS-ATS mailbox"). Open the Asset Registry screen and verify the suggestions section appears with correct alert counts.

**Acceptance Scenarios**:

1. **Given** pattern alerts exist for "MUX system" (3 alerts) and "MUX system" is not in the asset registry, **When** the Admin opens the Asset Registry screen, **Then** "MUX system" appears in the Suggestions section with alert count 3 and the relevant fault types.
2. **Given** pattern alerts exist for "WS-001" (2 alerts) and "WS-001" IS in the asset registry, **When** the Admin opens the Asset Registry screen, **Then** "WS-001" does NOT appear in the Suggestions section.
3. **Given** pattern alerts exist for "Room KCMC-S-65" (1 alert only), **When** the Admin opens the Asset Registry screen, **Then** "Room KCMC-S-65" does NOT appear in suggestions (below the 2-alert threshold).
4. **Given** no unregistered equipment has 2+ alerts, **When** the Admin opens the Asset Registry screen, **Then** the Suggestions section is hidden or shows "No suggestions".

---

### User Story 2 - Admin Accepts a Suggestion (Priority: P1)

When the Admin sees a suggestion they want to act on, they tap "Add" on that suggestion. This navigates to the Add Asset form with the equipment name pre-filled, and any inferrable metadata (equipment type, location) pre-populated from the extraction data. The Admin reviews, adjusts if needed, and saves. The suggestion disappears from the list because the equipment is now registered.

**Why this priority**: Accepting suggestions is the primary action that makes the registry self-improving — it reduces the manual effort of adding assets by pre-filling known data.

**Independent Test**: Can be tested by tapping "Add" on a suggestion, verifying the form is pre-filled, saving the asset, and confirming the suggestion disappears on return.

**Acceptance Scenarios**:

1. **Given** "CADAS-ATS mailbox" appears as a suggestion with extracted type "server", **When** the Admin taps "Add", **Then** the Add Asset form opens with name "CADAS-ATS mailbox" and type "server" pre-filled.
2. **Given** the Admin saves the pre-filled asset, **When** they return to the Asset Registry screen, **Then** "CADAS-ATS mailbox" no longer appears in suggestions and instead appears in the main asset list.
3. **Given** a suggestion has no inferrable type or location from extraction data, **When** the Admin taps "Add", **Then** the form opens with only the name pre-filled and type/location left for the Admin to choose.

---

### User Story 3 - Admin Dismisses a Suggestion (Priority: P2)

Some suggested equipment names are noise — overly verbose descriptions, one-off references, or equipment that doesn't warrant tracking. The Admin can dismiss a suggestion so it no longer appears. Dismissed suggestions don't come back even if more alerts arrive for that equipment.

**Why this priority**: Without dismiss, the suggestions list would accumulate irrelevant entries over time, making the feature less useful.

**Independent Test**: Can be tested by dismissing a suggestion, verifying it disappears, and confirming it doesn't reappear after new alerts are created for the same equipment.

**Acceptance Scenarios**:

1. **Given** "AN816-12 fitting, return line section (aluminum 6061-T6, 3/4 OD)" appears as a suggestion, **When** the Admin taps "Dismiss", **Then** the suggestion is removed from the list immediately.
2. **Given** "AN816-12 fitting..." has been dismissed, **When** a new pattern alert is created for this equipment_id, **Then** it still does not appear in suggestions.
3. **Given** the Admin has dismissed 5 suggestions over time, **When** they want to review what was dismissed, **Then** there is no requirement to show dismissed items (they are simply hidden).

---

### Edge Cases

- What happens when an equipment_id in alerts matches an asset name with different casing (e.g., "Indra CCTV workstation" vs "INDRA CCTV workstation")? The match should be case-insensitive — if any casing variant exists in the registry, the equipment is considered registered.
- What happens when an equipment_id is extremely long (e.g., "AN816-12 fitting, return line section (aluminum 6061-T6, 3/4 OD)")? The suggestion card should truncate long names with ellipsis but show the full name on tap or tooltip.
- What happens when an asset is deleted from the registry but alerts still reference it? The equipment_id should reappear in suggestions if it still meets the 2-alert threshold (unless previously dismissed).
- What happens when the dismissed list grows very large? No practical concern — dismissed equipment names are lightweight strings and the list is bounded by the number of distinct equipment_ids in alerts.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST identify equipment_ids from pattern alerts that do not match any asset name in the registry (case-insensitive comparison).
- **FR-002**: System MUST only suggest equipment_ids that appear in 2 or more pattern alerts.
- **FR-003**: Each suggestion MUST display the equipment name, total alert count, and the most common fault types from those alerts.
- **FR-004**: System MUST infer metadata from extraction data when available — specifically equipment_type from the most common `equipment_type` across the equipment's entity extractions.
- **FR-005**: When the Admin accepts a suggestion, the Add Asset form MUST open with the equipment name pre-filled and any inferrable metadata (type) pre-populated.
- **FR-006**: Once an asset is saved from a suggestion, that equipment MUST no longer appear in the suggestions list.
- **FR-007**: System MUST allow Admins to dismiss suggestions, permanently hiding them from the suggestions list.
- **FR-008**: Dismissed equipment_ids MUST remain hidden even if new alerts are created for them.
- **FR-009**: The Suggestions section MUST appear on the existing Asset Registry screen, above the main asset list.
- **FR-010**: The Suggestions section MUST be hidden when there are no suggestions to show.
- **FR-011**: Only Admin users can see and interact with suggestions (same access control as the Asset Registry screen).

### Key Entities

- **Asset Suggestion**: A computed result (not a stored entity) derived from pattern alerts — an equipment_id with 2+ alerts that is not in the asset registry and not dismissed. Includes alert count and inferred metadata.
- **Dismissed Suggestion**: An equipment_id string stored in a JSON array within `system_settings` (key: `dismissed_asset_suggestions`). Persisted so the suggestion does not reappear.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Admins can identify unregistered equipment from the suggestions list in under 10 seconds, without manually cross-referencing alerts and the registry.
- **SC-002**: Accepting a suggestion and saving the asset takes under 15 seconds (vs 30+ seconds for manual entry), thanks to pre-filled form data.
- **SC-003**: 100% of equipment_ids with 2+ alerts that are not in the registry and not dismissed appear in the suggestions list.
- **SC-004**: Dismissed suggestions never reappear, even after new alerts are created for the same equipment.
- **SC-005**: The suggestions list loads within the same time as the Asset Registry screen — no noticeable additional delay.

## Clarifications

### Session 2026-04-14

- Q: How should dismissed suggestions be stored? → A: JSON array in `system_settings` table (key: `dismissed_asset_suggestions`, value: array of equipment_id strings).

## Assumptions

- The feature builds on the existing Asset Registry (spec 053) and pattern alerts infrastructure. Both must be deployed and functional.
- The 2-alert threshold is a reasonable default that filters noise (1 alert) while catching recurring equipment (2+). This threshold is hardcoded, not configurable.
- Dismissed suggestions are stored as a simple list of equipment_id strings. No audit trail is needed for dismissals.
- The case-insensitive match between alert equipment_ids and asset names handles the most common mismatch scenario (e.g., "Indra" vs "INDRA").
- Metadata inference is best-effort — if extraction data doesn't have a consistent equipment_type for a given equipment_id, the type field is left blank for the Admin to fill.
- The suggestions section is part of the existing Asset Registry screen, not a separate screen or tab.
