# Feature Specification: Persist Letter Header Field Formatting

**Feature Branch**: `031-persist-letter-header-formatting`
**Created**: 2026-04-07
**Status**: Draft
**Input**: User description: "reference num, subject, recipient and their font size/bold/underline are not saved whenever I load pre-existed letters, it should be saved"

## Clarifications

### Session 2026-04-07

- Q: Does header-field formatting (font size, bold, underline) apply to the whole field or to character ranges within it? → A: Whole-field — one font size, one bold flag, one underline flag per header field. Rich-text per-character runs are deferred to a future feature; this fix matches the existing UI which uses field-level toggles only.
- Q: Which header fields are in scope? → A: Reference Number, Date, Recipient, and Subject (four fields).

## User Scenarios & Testing

### User Story 1 - Header fields and their formatting persist across sessions (Priority: P1)

A user composes a letter, fills in the Reference Number, Subject, and Recipient fields, and applies formatting (font size, bold, underline) to each. They save the letter. Later, they (or another user) reopen the saved letter and see the same field values and the same formatting exactly as they were left.

**Why this priority**: This is a data-loss bug. Users currently lose formatting work every time they reload a letter, eroding trust in the letter generator and forcing manual rework on every edit.

**Independent Test**: Create a letter with non-default formatting on Reference Number, Subject, and Recipient (e.g., bold subject, underlined recipient, custom font size on reference number). Save. Close the editor. Reopen the letter from the letters list. Verify each field shows the original text AND the original formatting attributes.

**Acceptance Scenarios**:

1. **Given** a new letter with Reference Number set to bold and font size 16, **When** the user saves and reopens the letter, **Then** the Reference Number field displays the same text, in bold, at font size 16.
2. **Given** a saved letter with an underlined Subject, **When** the user reopens it, **Then** the Subject field is shown underlined with the original text intact.
3. **Given** a saved letter with a Recipient styled bold + underlined at font size 14, **When** the user reopens it, **Then** all three formatting attributes are restored together.
4. **Given** the user reopens a saved letter and changes only the body, **When** they save again, **Then** the previously-saved header field formatting remains unchanged.

### Edge Cases

- A letter saved before this fix exists (legacy record with no stored formatting): system loads the field text and falls back to default formatting without error.
- The user clears formatting (returns to default) and saves: the cleared/default state is preserved on reload, not the previously-bold version.
- The user edits a field's text but not its formatting: the existing formatting still applies to the new text after reload.
- Exporting the letter to PDF after reload reflects the restored formatting, not defaults.

## Requirements

### Functional Requirements

- **FR-001**: System MUST persist the Reference Number field's text content together with one font size, one bold flag, and one underline flag (whole-field) when a letter is saved.
- **FR-002**: System MUST persist the Subject field's text content together with one font size, one bold flag, and one underline flag when a letter is saved.
- **FR-003**: System MUST persist the Recipient field's text content together with one font size, one bold flag, and one underline flag when a letter is saved.
- **FR-008**: System MUST persist the Date field's value together with one font size, one bold flag, and one underline flag when a letter is saved.
- **FR-004**: System MUST restore all stored formatting attributes for Reference Number, Date, Recipient, and Subject when a previously-saved letter is loaded for viewing or editing.
- **FR-005**: System MUST apply sensible default formatting to legacy letters that were saved before formatting persistence existed, without errors or data loss to the field text.
- **FR-006**: System MUST include the restored formatting in any downstream output (PDF export, preview) so what the user sees in the editor matches what is generated.
- **FR-007**: Saving a reloaded letter MUST NOT silently revert formatting to defaults; only explicit user changes alter the stored formatting.

### Key Entities

- **Letter Header Field**: Represents one of {Reference Number, Date, Recipient, Subject}. Attributes: text/value, font size (number), bold (on/off), underline (on/off). Belongs to a Letter.
- **Letter**: The saved letter record. Owns four header fields plus body content. Reload must reconstruct each header field's full attribute set, not only its text.

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% of newly saved letters reload with Reference Number, Subject, and Recipient text and formatting matching the saved state, verified across bold, underline, and font-size variations.
- **SC-002**: Zero reports of "formatting lost on reload" for header fields after the fix ships.
- **SC-003**: Legacy letters (saved before the fix) continue to open successfully with default formatting in 100% of cases — no load errors.
- **SC-004**: Users can edit and re-save a previously-formatted letter without re-applying header formatting, eliminating the manual rework step entirely.

## Assumptions

- The letter editor already supports applying font size, bold, and underline to these three header fields in-session — the gap is purely persistence and restoration, not the formatting controls themselves.
- The same three formatting attributes (font size, bold, underline) are the complete set the user expects persisted for header fields. Other rich-text attributes (color, italic, font family) are out of scope unless they are already saved today.
- Body content formatting persistence is unchanged — this fix is scoped to the three header fields the user explicitly named.
- Legacy letters without stored formatting are acceptable to display with current default styling; no migration/backfill of old records is required.
- The letter storage layer can be extended to carry the new formatting attributes alongside existing field text without breaking existing consumers.
