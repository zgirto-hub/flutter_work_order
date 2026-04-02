# Feature Specification: HTML/CSS Template Rendered to PDF for Payment Certificate

**Feature Branch**: `002-use-html-css`  
**Created**: 2026-04-02  
**Status**: Draft  
**Input**: User description: "I want to use an HTML/CSS template rendered to PDF for the payment certificate, instead of direct PDF generation"

## Clarifications

### Session 2026-04-02

- Q: Should the HTML template be fully self-contained (inline CSS, base64 fonts) to avoid iOS PWA resource loading failures? → A: Yes — fully self-contained with all CSS inline and Calibri fonts base64-embedded in the HTML.
- Q: Should the system fall back to direct PDF generation if HTML-to-PDF conversion fails? → A: No — clean replacement with no fallback. Show error on failure.
- Q: How should PDF delivery work on iOS PWA? → A: Preserve current blob URL download via Printing.sharePdf() on web/PWA (proven working after recent fix).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Export Payment Certificate as PDF via HTML Template (Priority: P1)

A user fills in all payment certificate details (invoice info, contract info, payment rows, attachments, signatures) and taps the export/download button. The system renders an HTML/CSS template with the certificate data, converts it to a PDF document, and delivers it to the user for download or sharing — producing the same visual layout as the current direct-PDF approach.

**Why this priority**: This is the core feature — replacing the existing direct PDF generation with HTML/CSS-based rendering while preserving the exact same output for users.

**Independent Test**: Can be tested by creating a payment certificate with sample data, exporting it, and verifying the PDF output matches the expected layout (title block, subject row, invoice table, contract table, payment table with merged headers, attachments list, signature blocks).

**Acceptance Scenarios**:

1. **Given** a complete payment certificate record exists, **When** the user taps "Export PDF", **Then** a PDF file is generated from the HTML/CSS template containing all certificate sections with correct Arabic RTL text, Calibri font, and table formatting.
2. **Given** a payment certificate with extension periods, **When** the PDF is exported, **Then** the title block shows the extension label and date range, and the contract table includes extension rows.
3. **Given** a payment certificate with multiple payment rows, **When** the PDF is exported, **Then** the payment table renders all rows plus a totals row with the correct sums, using the merged-header layout (الدفعة المستحقة, الخصم, الصافي spanning دينار/فلس sub-columns).

---

### User Story 2 - Consistent Layout Across Platforms (Priority: P1)

A user exports a payment certificate from the app on any supported platform (Android, iOS, iOS PWA, web). The generated PDF looks identical regardless of platform, because the HTML/CSS template defines the layout independent of platform-specific rendering.

**Why this priority**: The current direct-PDF approach had issues on iOS PWA. HTML/CSS templates provide a single source of truth for layout, reducing platform-specific bugs.

**Independent Test**: Export the same certificate on two different platforms and visually compare the resulting PDFs for layout consistency.

**Acceptance Scenarios**:

1. **Given** the app is running on iOS PWA, **When** the user exports a payment certificate, **Then** the PDF is generated successfully and matches the layout produced on Android/web.
2. **Given** the app is running on any supported platform, **When** the user exports, **Then** Arabic RTL text, merged table cells, color-coded headers (#DCE6F1 blue, #FDE9D9 orange for totals), and signature blocks all render correctly.

---

### User Story 3 - Maintainable Template (Priority: P2)

A developer needs to adjust the payment certificate layout (e.g., add a new section, change colors, modify column widths). They edit the HTML/CSS template file directly rather than modifying Dart widget-tree code, making layout changes faster and more intuitive.

**Why this priority**: A key motivation for this change is easier maintainability — HTML/CSS is a more natural format for document layout than programmatic widget trees.

**Independent Test**: Make a cosmetic change (e.g., header color) in the HTML/CSS template and verify the change appears in the exported PDF without modifying any Dart logic code.

**Acceptance Scenarios**:

1. **Given** the HTML/CSS template exists as a separate asset, **When** a developer edits the CSS (e.g., changes a background color), **Then** the next PDF export reflects the change without touching Dart logic.
2. **Given** the template uses placeholder tokens for dynamic data, **When** the template is populated with certificate data, **Then** all placeholders are replaced with actual values.

---

### Edge Cases

- What happens when a text field contains very long Arabic text that could overflow a table cell?
- How does the system handle a certificate with zero payment rows (empty payment table)?
- What happens when optional fields (extension dates, renewal info) are null or empty?
- How does the template handle a certificate with no attachments checked?
- What happens if the Calibri font asset fails to load?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST render the payment certificate using an HTML/CSS template instead of the current `pdf` package widget tree.
- **FR-002**: System MUST populate the HTML template with all PaymentCertificate model fields (title, subject, contract number, invoice details, contract info, payment rows, attachments, signature blocks).
- **FR-003**: System MUST support full Arabic RTL text direction throughout the document.
- **FR-004**: System MUST render the payment table with merged header cells (الدفعة المستحقة, الخصم, الصافي spanning دينار/فلس sub-columns) using standard HTML colspan.
- **FR-005**: System MUST calculate and display payment row totals in a highlighted totals row.
- **FR-006**: System MUST apply the existing color scheme: #DCE6F1 for header backgrounds, #FDE9D9 for the totals row.
- **FR-007**: System MUST use the Calibri font family (regular and bold) loaded from app assets.
- **FR-008**: System MUST produce A4-sized PDF output with consistent margins.
- **FR-009**: System MUST conditionally show extension period rows in the contract table only when extension dates exist.
- **FR-010**: System MUST conditionally format the title block to include extension period label and date range when applicable.
- **FR-011**: System MUST render the attachments checklist and four signature blocks (dept head, controller, director, auditor).
- **FR-012**: System MUST convert the rendered HTML to PDF and return it as a byte array (Uint8List) compatible with the existing export/share workflow.
- **FR-013**: The HTML/CSS template MUST be stored as a separate asset file, not embedded as a string in Dart code. Note: the complex payment table with merged headers (colspan) is built programmatically using `pdf` widgets, as no pure-Dart HTML-to-PDF library reliably supports colspan on all platforms.
- **FR-014**: The HTML template sections MUST be fully self-contained — all CSS inline and Calibri fonts base64-embedded — to avoid resource loading failures in restricted environments such as iOS PWA (WKWebView).
- **FR-015**: The PDF delivery mechanism on web/PWA MUST use the existing blob URL download approach (Printing.sharePdf) that is proven to work on iOS PWA; on native platforms, the existing native layout/share behavior MUST be preserved.

### Key Entities

- **PaymentCertificate**: The main data model containing all certificate fields — identity, contract details, invoice info, extension periods, payment rows, attachments, and signatories.
- **PaymentRow**: Individual line item in the payment table with due payment, deduction, and net amounts (each split into dinar and fils).
- **HTML Template**: The asset file containing the HTML/CSS layout with placeholder tokens for dynamic data injection.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Exported PDF is visually identical to the current direct-PDF output (same sections, layout, colors, fonts, RTL alignment).
- **SC-002**: PDF export completes within the same perceived time as the current approach (no noticeable delay increase for users).
- **SC-003**: PDF exports work on all currently supported platforms (Android, iOS, iOS PWA, web) without platform-specific workarounds.
- **SC-004**: Layout changes (colors, spacing, text) can be made by editing only the HTML/CSS template file, without touching Dart logic.
- **SC-005**: All dynamic data from the PaymentCertificate model appears correctly in the exported PDF with no missing or misplaced fields.

## Assumptions

- The existing PaymentCertificate data model and export/share workflow remain unchanged — only the PDF generation step is replaced.
- The Calibri font assets (calibri.ttf, calibrib.ttf) already bundled with the app will be reused.
- The HTML-to-PDF conversion will happen client-side within the Flutter app (no server-side dependency required).
- The HTML/CSS template will be bundled as a Flutter asset (e.g., in `assets/templates/`).
- The current `pdf` package direct-PDF approach will be fully replaced — no fallback or dual-engine coexistence. The `pdf` package dependency may be removed if no other features use it.
- The `build()` method signature (`Future<Uint8List>`) will remain the same so callers are unaffected.
