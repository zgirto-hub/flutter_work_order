# Feature Specification: Structured Work Order Description Fields

**Feature Branch**: `054-structured-wo-description`  
**Created**: 2026-04-14  
**Status**: Draft  
**Input**: User description: "In add_work_order.dart, replace the single free-text description field with 4 structured sub-fields: Asset Name (autocomplete from Asset Registry), Fault Description (free text), Action Taken (free text), and Outcome (dropdown: Resolved / Pending Parts / Escalated / Monitoring). Add an optional Notes field for free text in Arabic or English. The backend stitches the 4 fields into a single description string before saving, so no changes are needed to the database schema or extraction pipeline. The Asset Name autocomplete calls the asset registry API and suggests registered asset names as the technician types."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fill Out Structured Description When Creating a Work Order (Priority: P1)

A technician creates a new work order and sees four distinct fields instead of a single free-text description box. They begin typing an asset name and see suggestions from the Asset Registry, select the correct asset, describe the fault, note the action taken, and choose an outcome from a dropdown. They optionally add notes in Arabic or English. The system saves the work order with all sub-fields combined into a single description string, ensuring full backward compatibility.

**Why this priority**: This is the core feature. Without the structured form, no other story is meaningful. It replaces the existing description field, so it must work end-to-end before anything else matters.

**Independent Test**: Can be tested by opening the "Add Work Order" screen, filling in all four required sub-fields plus optional notes, submitting, and verifying the saved description contains all sub-field values in a readable format.

**Acceptance Scenarios**:

1. **Given** a technician is on the Add Work Order screen, **When** the screen loads, **Then** four sub-fields are displayed: Asset Name, Fault Description, Action Taken, and Outcome, plus an optional Notes field.
2. **Given** the technician fills in all four sub-fields and submits, **When** the work order is saved, **Then** the stored description contains all four values stitched into a single formatted string.
3. **Given** the technician leaves any of the four required sub-fields empty, **When** they attempt to submit, **Then** a validation error highlights the missing field(s).

---

### User Story 2 - Find the Correct Asset via Autocomplete (Priority: P1)

A technician starts typing an asset name in the Asset Name field and sees a dropdown of matching registered assets from the Asset Registry. They select the correct one, and the field is populated with the official asset name. If the desired asset is not found, the technician can still type a custom name.

**Why this priority**: The asset autocomplete is a key differentiator over free text. It reduces errors and links work orders to known assets, which is critical for the entity extraction pipeline and pattern detection downstream.

**Independent Test**: Can be tested by typing partial asset names and verifying that matching suggestions appear, that selecting a suggestion populates the field, and that custom text entry is still allowed when no match exists.

**Acceptance Scenarios**:

1. **Given** the technician types 2 or more characters in the Asset Name field, **When** matching assets exist in the registry, **Then** a suggestion list appears with matching asset names.
2. **Given** the suggestion list is visible, **When** the technician selects an asset, **Then** the field is populated with the selected asset name.
3. **Given** no matching assets exist for the typed text, **When** the technician continues typing, **Then** the field accepts the free-text entry without error.
4. **Given** the Asset Registry is unreachable, **When** the technician types in the Asset Name field, **Then** the field gracefully falls back to free-text input without blocking the form.

---

### User Story 3 - Select an Outcome from Predefined Options (Priority: P2)

A technician selects one of the four predefined outcomes (Resolved, Pending Parts, Escalated, Monitoring) from a dropdown. This ensures consistent outcome reporting across all work orders.

**Why this priority**: Standardized outcomes enable reliable reporting and analytics. It is lower priority than P1 stories because the form can technically function with a text field as a fallback.

**Independent Test**: Can be tested by opening the Outcome dropdown, verifying all four options are present, selecting each one, and confirming it persists through form submission.

**Acceptance Scenarios**:

1. **Given** the technician taps the Outcome field, **When** the dropdown opens, **Then** exactly four options are shown: Resolved, Pending Parts, Escalated, Monitoring.
2. **Given** the technician selects an outcome, **When** they submit the form, **Then** the selected outcome appears in the stitched description string.

---

### User Story 4 - Add Optional Notes in Arabic or English (Priority: P3)

A technician adds free-text notes in either Arabic or English. The notes field is optional and supports bidirectional text. If left empty, the stitched description omits the notes section entirely.

**Why this priority**: Notes are supplementary. The core structured fields carry the essential information. Notes add context but are not required for a valid work order.

**Independent Test**: Can be tested by submitting a work order with notes filled in (both Arabic and English), and separately with notes left empty, verifying the stitched description includes or omits notes accordingly.

**Acceptance Scenarios**:

1. **Given** the technician types notes in Arabic, **When** they submit the form, **Then** the notes appear correctly in the stitched description with proper right-to-left rendering.
2. **Given** the technician types notes in English, **When** they submit the form, **Then** the notes appear correctly in the stitched description.
3. **Given** the technician leaves the Notes field empty, **When** they submit the form, **Then** the stitched description does not include a notes section.

---

### User Story 5 - View Structured Description on Work Order Detail Screen (Priority: P2)

A technician or supervisor opens a work order that was created with the structured form and sees the description displayed as visually separated, labeled sub-fields (Asset Name, Fault Description, Action Taken, Outcome, and Notes if present) rather than a single block of text. Work orders created before this feature continue to display their description as plain text.

**Why this priority**: Structured display improves readability and makes it easy to scan work order details at a glance. It complements the structured input form and delivers the full value of standardized data.

**Independent Test**: Can be tested by creating a work order with the structured form, opening the detail screen, and verifying each sub-field is displayed with its label in a visually distinct layout. Also test viewing a pre-existing work order to confirm it still renders as plain text.

**Acceptance Scenarios**:

1. **Given** a work order was created with the structured form, **When** a user opens its detail screen, **Then** the description is displayed as separate labeled sub-fields (Asset Name, Fault Description, Action Taken, Outcome, and Notes if present).
2. **Given** a work order was created before this feature (legacy format), **When** a user opens its detail screen, **Then** the description is displayed as plain text, unchanged from current behavior.
3. **Given** a structured work order has no Notes, **When** a user opens its detail screen, **Then** the Notes sub-field is not displayed.

---

### Edge Cases

- What happens when the Asset Registry returns hundreds of matches? The suggestion list should be limited to a reasonable number (e.g., 10-15 results) with the ability to refine by typing more characters.
- What happens when the technician pastes a very long string into Fault Description or Action Taken? Reasonable character limits should be enforced with visible counters.
- What happens when the network drops mid-autocomplete request? The Asset Name field should continue accepting free text without errors or spinners blocking the form.
- What happens when the technician navigates away from the form with partially filled fields? Standard unsaved-changes behavior should apply (confirmation dialog).
- What happens when editing an existing work order? The Edit Work Order screen is out of scope for this feature; it continues to show the existing single free-text description field.
- What happens when the detail view encounters a description that partially matches the structured format but is malformed? It should fall back to plain-text display rather than showing broken parsed fields.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Add Work Order screen (only) MUST display four structured sub-fields: Asset Name, Fault Description, Action Taken, and Outcome, replacing the single free-text description field. The Edit Work Order screen is out of scope.
- **FR-002**: The Asset Name field MUST provide autocomplete suggestions sourced from the Asset Registry as the user types.
- **FR-003**: The autocomplete MUST trigger after the user types at least 2 characters.
- **FR-004**: The Asset Name field MUST accept free-text entry when no matching asset is found or when the registry is unavailable.
- **FR-005**: The Outcome field MUST be a dropdown with exactly four options: Resolved, Pending Parts, Escalated, Monitoring.
- **FR-006**: An optional Notes field MUST be available for free-text input in Arabic or English with bidirectional text support.
- **FR-007**: All four structured sub-fields (Asset Name, Fault Description, Action Taken, Outcome) MUST be required for form submission.
- **FR-008**: The Notes field MUST be optional and may be left empty.
- **FR-009**: The system MUST combine all sub-fields into a single description string before saving, preserving backward compatibility with the existing data model.
- **FR-010**: The stitched description MUST omit the Notes section when notes are empty.
- **FR-011**: The autocomplete suggestion list MUST be limited to a maximum number of results to prevent overwhelming the user.
- **FR-012**: The form MUST validate all required fields before allowing submission and highlight any empty required fields.
- **FR-013**: The work order detail screen MUST parse structured descriptions and display each sub-field with its label in a visually separated layout.
- **FR-014**: The work order detail screen MUST fall back to displaying the description as plain text for work orders created before this feature (legacy format).

### Key Entities

- **Asset**: A registered piece of equipment or system from the Asset Registry, identified by name. Used for autocomplete suggestions in the Asset Name field.
- **Work Order**: The primary entity being created. Its description field stores the stitched combination of all structured sub-fields.
- **Outcome**: A constrained set of four possible work results (Resolved, Pending Parts, Escalated, Monitoring) that standardizes reporting.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Technicians can complete the structured description fields and submit a work order in under 2 minutes (comparable to the current free-text workflow).
- **SC-002**: 90% of work orders created with the new form include a recognized asset name from the registry (vs. free-text only).
- **SC-003**: 100% of submitted work orders contain all four structured data points (asset, fault, action, outcome) in the saved description.
- **SC-004**: Asset autocomplete suggestions appear within 1 second of the user typing 2 characters.
- **SC-005**: The feature works correctly when the Asset Registry is unavailable, with zero form submission failures due to autocomplete errors.

## Clarifications

### Session 2026-04-14

- Q: Does the structured form apply to the Edit Work Order screen as well, or only the Add screen? → A: Add-only. The Edit Work Order screen is out of scope and remains unchanged.
- Q: Should the work order detail view display the stitched string as-is or parse it into labeled sub-fields? → A: Enhanced detail view — parse the stitched string back into visually separated, labeled sub-fields.

## Assumptions

- The Asset Registry already has a searchable list of assets accessible via an existing endpoint.
- The existing work order creation flow (aside from the description field) remains unchanged.
- The stitched description format is a plain text concatenation with labeled sections (e.g., "Asset: X | Fault: Y | Action: Z | Outcome: W | Notes: N") — the exact format is an implementation detail decided during planning.
- Existing work orders created before this feature retain their current description format and are not migrated.
- The Edit Work Order screen is explicitly out of scope; it retains the existing single free-text description field unchanged.
- The backend stitching logic handles the concatenation — no database schema or extraction pipeline changes are needed.
- The four outcome options are fixed and do not need to be configurable by administrators at this time.
