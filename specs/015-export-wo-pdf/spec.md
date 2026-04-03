# Feature Specification: Export PDF Report for Closed Work Orders

**Feature Branch**: `015-export-wo-pdf`  
**Created**: 2026-04-04  
**Status**: Draft  
**Input**: User description: "Export PDF report for closed work order with electronic signatures"

## Clarifications

### Session 2026-04-04

- Q: If multiple signatures exist per role (e.g., two technicians signed), which appears in the PDF? → A: Show only the first (oldest) signature per role.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Export PDF from Work Order Details (Priority: P1)

An admin or technician opens a closed work order's detail screen. They see an "Export PDF Report" button at the bottom of the Details tab. Tapping the button generates a professional PDF report containing all work order details, assigned technicians, and embedded electronic signatures. The PDF opens in a preview screen where it can be printed or saved.

**Why this priority**: This is the core feature — generating the PDF with all required content. Without this, nothing else matters.

**Independent Test**: Can be fully tested by opening any closed work order, tapping "Export PDF Report", and verifying the generated PDF contains correct header with logos, work order details, technician list, signature images, and footer.

**Acceptance Scenarios**:

1. **Given** a closed work order with both technician and admin signatures approved, **When** the user taps "Export PDF Report", **Then** a PDF is generated containing all work order fields, both embedded signature images, logos in the header, and a professional layout.
2. **Given** a closed work order with only one signature (e.g., technician signed but admin has not), **When** the user taps "Export PDF Report", **Then** a PDF is generated with the existing signature embedded and a "Pending Signature" placeholder for the missing one.
3. **Given** a closed work order with no signatures at all, **When** the user taps "Export PDF Report", **Then** a PDF is generated with two empty signature boxes labeled "Awaiting Signature".
4. **Given** the user taps "Export PDF Report", **When** the PDF is successfully generated, **Then** a preview screen opens displaying the PDF content with options to print or save.
5. **Given** the user taps "Export PDF Report", **When** an error occurs during generation, **Then** a user-friendly error message is displayed.

---

### User Story 2 - Export PDF from Work Order List (Priority: P2)

A user browsing the work order list sees a small "Export PDF" icon on expanded cards for closed work orders. Tapping the icon triggers the same PDF generation and preview flow without needing to open the work order detail screen first.

**Why this priority**: Convenience feature that reduces friction — users can export directly from the list without navigating into each work order. Lower priority because the core export functionality is already covered by Story 1.

**Independent Test**: Can be tested by expanding a closed work order card in the list view, tapping the Export PDF icon, and verifying the same PDF is generated and previewed.

**Acceptance Scenarios**:

1. **Given** a closed work order card is expanded in the work order list, **When** the user views the card actions, **Then** an "Export PDF" icon button is visible.
2. **Given** a work order that is not closed (e.g., Open, In Progress), **When** the user views the expanded card, **Then** no "Export PDF" icon is shown.
3. **Given** a closed work order card in the list, **When** the user taps the "Export PDF" icon, **Then** the same PDF generation and preview flow is triggered as in Story 1.

---

### User Story 3 - Role-Based Export Access (Priority: P1)

The system enforces role-based access when exporting PDFs. Reporters can only export their own work orders. Technicians can export work orders within their department. Admins can export any work order. Unauthorized export attempts are blocked.

**Why this priority**: Security and access control are critical — users must not be able to export work orders they don't have access to. This is tied to P1 because it's enforced alongside the core export.

**Independent Test**: Can be tested by attempting to export work orders with different user roles and verifying access is correctly granted or denied.

**Acceptance Scenarios**:

1. **Given** a user with Reporter role, **When** they attempt to export a work order they created, **Then** the export succeeds.
2. **Given** a user with Reporter role, **When** they attempt to export a work order created by someone else, **Then** the export is denied with an appropriate message.
3. **Given** a user with Technician role, **When** they attempt to export a work order in their department, **Then** the export succeeds.
4. **Given** a user with Technician role, **When** they attempt to export a work order in a different department, **Then** the export is denied.
5. **Given** a user with Admin role, **When** they attempt to export any work order, **Then** the export succeeds.

---

### Edge Cases

- What happens when a signature image file is missing from the server? The PDF shows a blank box with "Signature file not found" text.
- What happens when logo image files are missing from the server? The PDF skips the missing logo(s) gracefully without crashing.
- What happens when the work order description or tech notes are very long? The text wraps and the PDF overflows to additional pages as needed.
- What happens when tech notes are empty? The tech notes section is omitted from the PDF entirely.
- What happens when the work order contains Arabic text? The text is rendered as-is without special RTL enforcement.
- What happens when a non-closed work order is exported (if the button were somehow triggered)? The PDF still generates showing the current status but omits the signature section.
- What happens when the user has no network connectivity during export? An error message is shown to the user.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST generate a PDF report for any work order, containing all work order fields (job number, title, description, location, mobile number, type, status, department, creator, creation date, closure date, tech notes, assigned technicians).
- **FR-002**: System MUST embed electronic signature images into the PDF for each signer (technician and admin), reading the images directly from stored files on the server.
- **FR-003**: System MUST display three organizational logos side by side in the PDF header (emblem, civil aviation, new Kuwait).
- **FR-004**: System MUST show a "Pending Signature" placeholder when a signature is missing or not yet approved, and "Awaiting Signature" placeholders when no signatures exist at all.
- **FR-005**: System MUST display the signature section as two side-by-side columns: technician signature on the left, admin authorization on the right. When multiple signatures exist for a role, the first (oldest) approved signature is used.
- **FR-006**: System MUST include a footer on each page with the system name, export timestamp, and page number.
- **FR-007**: System MUST enforce role-based access control on PDF export matching existing work order viewing permissions (Reporter: own WOs only; Technician: department WOs; Admin: all WOs).
- **FR-008**: System MUST present the "Export PDF Report" button only on closed work orders in the detail screen.
- **FR-009**: System MUST present an "Export PDF" icon button on closed work order cards in the list view.
- **FR-010**: System MUST open a PDF preview screen after successful generation, allowing the user to view, print, or save the document.
- **FR-011**: System MUST set the PDF filename to "WO-{job_no}-report.pdf" where {job_no} is the work order's job number.
- **FR-012**: System MUST handle missing logo files, missing signature files, and empty optional fields gracefully without errors.
- **FR-013**: System MUST display a loading indicator while the PDF is being generated.
- **FR-014**: System MUST show an error message to the user if PDF generation fails.

### Key Entities

- **Work Order**: The primary entity containing all job details — job number, title, description, location, type, status, department, creator, dates, tech notes, and assigned technicians.
- **Work Order Signature**: A record linking a signer (by email and role) to a work order, including the signature image file path, approval status, and signing timestamp.
- **User**: System user with a name, email, role (Reporter/Technician/Admin), and department affiliation. Used to resolve signer names and enforce access control.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can generate and preview a PDF report for a closed work order in under 10 seconds from button tap to preview display.
- **SC-002**: 100% of work order fields specified in the layout are accurately rendered in the exported PDF.
- **SC-003**: Signature images are legible and correctly positioned in the PDF for all work orders that have approved signatures.
- **SC-004**: Partial reports (missing or pending signatures) export successfully with appropriate placeholder content — no errors or blank pages.
- **SC-005**: Unauthorized export attempts (wrong role/department) are blocked 100% of the time with a clear denial message.
- **SC-006**: The PDF export feature works identically on both web (PWA) and mobile platforms.
- **SC-007**: The exported PDF filename follows the "WO-{job_no}-report.pdf" naming convention for every export.

## Assumptions

- Existing role-based access control for viewing work orders is already implemented and will be reused for export authorization.
- The PDF preview screen (PdfPreviewScreen) already exists in the application and supports receiving raw PDF bytes for display.
- Signature image files (PNG format) are stored on the server filesystem and accessible to the PDF generation process.
- Logo image files exist in the server's assets directory; if any are missing, the PDF will still generate without them.
- The existing monthly task report PDF generation pattern provides a proven foundation for this feature's server-side approach.
- Users have network connectivity when triggering the export (the PDF is generated server-side and streamed to the client).
- Work orders typically fit on a single PDF page, but the system accommodates overflow to additional pages for work orders with long descriptions or notes.
