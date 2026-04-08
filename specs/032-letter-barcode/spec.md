# Feature Specification: Letter Reference Barcode

**Feature Branch**: `032-letter-barcode`
**Created**: 2026-04-08
**Status**: Draft
**Input**: Add a Code 128 barcode above the reference number in generated letter PDFs.

## User Scenarios & Testing

### User Story 1 - Scannable Reference on Generated Letters (Priority: P1)

A clerk archiving outgoing correspondence needs to look up a letter quickly. When they receive a printed letter, they scan the barcode at the top with a phone or handheld scanner and instantly retrieve the reference number, instead of typing it manually.

**Why this priority**: This is the entire feature. Without it, archival lookup remains manual and error-prone.

**Independent Test**: Generate a letter with a non-empty reference number, open the resulting PDF, and confirm a barcode appears directly above the reference text. Scan the barcode with any standard barcode reader and confirm the decoded value matches the reference number exactly.

**Acceptance Scenarios**:

1. **Given** a letter with reference number `2026-56634`, **When** the PDF is generated, **Then** a barcode appears above the reference text on the same column and decodes to `2026-56634`.
2. **Given** a letter with no reference number, **When** the PDF is generated, **Then** no barcode image is rendered and no broken-image placeholder appears.
3. **Given** an existing letter is re-exported or previewed, **When** the PDF is rendered, **Then** the barcode appears without changing any other layout (date column, signatures, body, header).

### Edge Cases

- Reference number is empty or whitespace → no barcode rendered.
- Reference number contains characters outside Code 128's supported set → letter still generates; barcode is omitted gracefully if it cannot be encoded.
- Very long reference numbers must still fit within the reference column width without breaking page layout.

## Requirements

### Functional Requirements

- **FR-001**: The system MUST render a Code 128 barcode encoding the letter's reference number in every generated letter PDF when the reference number is non-empty.
- **FR-002**: The barcode MUST appear directly above the existing reference-number text, in the same visual column, without displacing the date column or other letter elements.
- **FR-003**: The barcode image MUST display the reference number as human-readable text underneath the bars.
- **FR-004**: When the reference number is empty, the system MUST omit the barcode entirely (no placeholder, no broken image).
- **FR-005**: The barcode MUST be scannable by standard consumer barcode-reading apps and decode to exactly the reference number string.
- **FR-006**: Existing letter generation, preview, PDF export, and history flows MUST continue to work unchanged aside from the added barcode.

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% of newly generated letters with a non-empty reference number contain a scannable barcode that decodes to the exact reference number.
- **SC-002**: Letters with empty reference numbers render with zero broken-image artifacts.
- **SC-003**: No regression in letter generation success rate compared to the prior release.
- **SC-004**: Clerks can retrieve a letter's reference number by scanning rather than typing, eliminating manual transcription errors for archived letters.

## Assumptions

- The reference number (`ishara`) is the only value that needs encoding; no composite identifier is required.
- Code 128 (1D barcode) is sufficient; a 2D format (QR) is explicitly out of scope.
- The existing letter template's reference column has enough vertical space to accept a small (~38px tall) barcode without breaking pagination.
- Only the v2 letter generator is in scope; the legacy generator is not modified.
- No frontend, database, or API contract changes are required.
