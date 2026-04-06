# Feature Specification: Civil Aviation Letter Generator

**Feature Branch**: `026-civil-aviation-letter-gen`  
**Created**: 2026-04-06  
**Status**: Draft  
**Input**: User description: "Build a screen that lets a user fill in fields and generate a formatted Arabic RTL PDF letter matching the official Kuwait Civil Aviation (DGCA) letter format."

## Clarifications

### Session 2026-04-06

- Q: What is persisted to Supabase after letter generation? → A: Only the form field data (not the PDF file). The PDF is generated on-demand and not stored persistently.
- Q: How is the signature stored for history regeneration? → A: Save signature as base64 string in the letter record in Supabase (matches existing project pattern).
- Q: How are letters and payment certificates related? → A: The letter is the parent (cover letter); payment certificates are children linked to it. A letter can have one or more payment certificates.
- Q: How does the user access letter history? → A: Tab/toggle within the letter generator screen (e.g., "New Letter" / "History" tabs), keeping the feature self-contained.
- Q: Is preview required before exporting? → A: Yes, the user must preview the letter before generating/exporting the PDF.
- Q: Can a letter span multiple pages? → A: No, the letter is strictly single-page. The payment certificate is also single-page.
- Q: How is الموضوع (subject) displayed in the PDF? → A: The subject field supports multi-line text and is rendered centered/middle of the page, bold, before the body text.
- Q: How is the body text (بالإشارة للموضوع أعلاه) formatted in the PDF? → A: Multi-line, RTL aligned, with a tab (indent) empty space at the beginning of the first line.
- Q: What does the actual DGCA UI look like? → A: Reference screenshots provided. Key differences from initial spec: (1) Three logos — Civil Aviation right, Emblem center, New Kuwait left. (2) السيد is a dropdown selector from officials list, not free text. (3) Signer is also a dropdown from officials list. (4) New fields: "مطلوب الرد" (Reply Required) checkbox and "قائمة النسخ" (CC List) dropdown. (5) Body text has a rich text editor toolbar. (6) Reference number format is YYYY-NNNNN. (7) Three action buttons: التالي (Next), حفظ (Save), الغاء (Cancel). (8) Footer is bilingual Arabic+English. (9) "المحترم" label appears after the recipient.
- Q: What level of rich text editing is needed for the body? → A: Full WYSIWYG rich text editor — user wants to write complex formatted documents (bold, underline, alignment, lists, tables) and generate them as PDF. Body content is stored as HTML.
- Q: Which PDF renderer for rich HTML content? → A: WeasyPrint (HTML/CSS → PDF). The backend builds an HTML template with the DGCA layout (header, footer, logos) and injects the rich HTML body from the editor, then renders to PDF via WeasyPrint.
- Q: Are recipient (السيد) and signer dropdowns or free text? → A: Free text fields. User types the recipient and signer name manually.


## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fill and Generate Official Letter (Priority: P1)

A staff member at Kuwait DGCA needs to produce an official Arabic letter. They open the letter generator screen, fill in the reference number, date, recipient title, subject line, body text, and signer name. They optionally upload a signature image. They tap "Generate PDF" and receive a professionally formatted PDF that matches the DGCA institutional letter layout — complete with header logos, red divider bar, and footer contact info.

**Why this priority**: This is the core value proposition — producing correctly formatted official letters without manual layout work. Without this, the feature has no purpose.

**Independent Test**: Can be fully tested by filling all form fields, generating a PDF, and verifying the output contains all user-entered content within the correct DGCA layout (header, body, footer).

**Acceptance Scenarios**:

1. **Given** a user is on the letter generator screen, **When** they fill all required fields and tap "Generate PDF", **Then** a PDF is downloaded/displayed that contains the user's input within the standard DGCA letter layout.
2. **Given** a user fills all fields and uploads a signature image, **When** they generate the PDF, **Then** the signature image appears in the sign-off block of the letter.
3. **Given** a user leaves a required field empty, **When** they tap "Generate PDF", **Then** validation errors highlight the missing fields and generation is blocked.
4. **Given** a user enters Arabic text with mixed punctuation, **When** the PDF is generated, **Then** all text renders correctly in RTL direction with proper Arabic shaping.

---

### User Story 2 - Preview Letter Before Generating (Priority: P2)

Before committing to PDF generation, the user wants to preview how the letter will look. They tap "Preview" and see a rendered preview of the letter with their current field values, allowing them to review and correct any mistakes before generating the final PDF.

**Why this priority**: Preview is a mandatory step before PDF export — users must review the letter layout before generating. This catches errors and enforces the single-page constraint visually.

**Independent Test**: Can be tested by filling form fields, tapping "Preview", and verifying the preview displays all entered content in the correct DGCA layout.

**Acceptance Scenarios**:

1. **Given** a user has filled form fields, **When** they tap "Preview", **Then** a preview dialog or view shows the letter with current field values in the DGCA format.
2. **Given** a user sees the preview, **When** they close it and edit a field, **Then** tapping "Preview" again reflects the updated values.

---

### User Story 3 - View Letter History (Priority: P3)

A user wants to find a letter they generated previously. They navigate to a history view that lists all past generated letters with key metadata (date, recipient, subject). They can tap an entry to view or re-download the PDF.

**Why this priority**: History provides audit trail and retrieval convenience, but is not required for the primary letter generation workflow.

**Independent Test**: Can be tested by generating one or more letters, navigating to the history view, and verifying all generated letters appear with correct metadata and are accessible.

**Acceptance Scenarios**:

1. **Given** a user has generated letters previously, **When** they navigate to the history view, **Then** they see a list of generated letters with date, recipient, and subject.
2. **Given** a user taps on a history entry, **When** the action completes, **Then** the system regenerates the PDF from the saved field data and allows the user to view or download it.

---

### Edge Cases

- What happens when the user uploads an extremely large signature image (e.g., 10MB+)? The system should reject images above 5MB with a clear error message.
- What happens when the body text is too long to fit on one page? The system must warn the user that the text exceeds the single-page limit and prevent generation until the text is shortened.
- What happens if the backend PDF generation fails (e.g., server error)? The user sees a clear error message and can retry.
- What happens when the user has no internet connection? The form remains accessible but PDF generation fails gracefully with an offline error message.
- What happens if the user enters Latin/English text mixed with Arabic? The text should render with correct bidirectional layout.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a form screen with the following fields (matching the DGCA reference UI): reference number (رقم الإشارة — format YYYY-NNNNN), recipient (السيد — free text field, followed by static "المحترم" label), subject (الموضوع — multi-line text area), body text (WYSIWYG rich text editor with toolbar: font color, table, alignment, bold, underline, bulleted/numbered lists, paste from Word, link, undo), signer (الاسم — free text field), "مطلوب الرد" (Reply Required — checkbox), and "قائمة النسخ" (CC List — free text field for carbon copy recipients).
- **FR-002**: System MUST provide three action buttons at the bottom: "التالي" (Next/Preview), "حفظ" (Save as draft), "الغاء" (Cancel).
- **FR-003**: System MUST allow users to upload a PNG or JPG signature image and display a thumbnail preview of the uploaded image.
- **FR-004**: System MUST validate that required fields (reference number, recipient, subject, body text, signer) are filled before allowing PDF generation. Checkbox and CC list are optional.
- **FR-005**: System MUST generate a PDF that includes a fixed header with three logos arranged in a row: Civil Aviation logo with Arabic+English text (right), Kuwait state emblem (center), New Kuwait logo (left), followed by a red horizontal divider bar.
- **FR-006**: System MUST generate a PDF where the body content is rendered from rich HTML (produced by the WYSIWYG editor). The PDF must faithfully reproduce all formatting: bold, underline, text alignment, bulleted/numbered lists, tables, and font styling. The first paragraph should have a tab indent. All content is RTL Arabic direction.
- **FR-007**: System MUST generate a PDF with a fixed bilingual footer: Arabic line (ص.ب: 17 الصفاة - الرمز البريدي: 13001 دولة الكويت - البدالة: 24336699 (965+) - الرد الآلي: 161 (965+) - فاكس: 24713504 (965+)) and English line (P.O.Box: 17 Safat - P.Code: 13001 - State of Kuwait - Operator: (+965) 24336699 - IVR: (+965) 161 - Fax (+965) 24713504), plus E-mail: info@dgca.gov.kw and www.dgca.gov.kw.
- **FR-008**: System MUST include a fixed "المرفقات" (attachments) section label below the letter body in the generated PDF.
- **FR-009**: System MUST embed the uploaded signature image in the sign-off block of the generated PDF when provided.
- **FR-010**: System MUST require the user to preview the letter before allowing PDF generation/export. The preview shows the letter layout with current field values.
- **FR-011**: System MUST save letter form field data (reference number, recipient, subject, body text, signer, reply required flag, CC list) to Supabase after successful PDF generation. No PDF file is persisted.
- **FR-012**: System MUST be able to regenerate a PDF on-demand from saved letter field data when a user requests it from the history view.
- **FR-013**: System MUST provide a history tab within the letter generator screen listing previously generated letters with key metadata (date, recipient, subject).
- **FR-014**: System MUST allow users to regenerate and download a PDF from any saved letter record in the history view.
- **FR-015**: System MUST render the subject (الموضوع) in bold styling, centered horizontally on the page, supporting multi-line text. It appears between the recipient line and the body text.
- **FR-016**: System MUST include a document reference block in the PDF header area showing the reference number and date.
- **FR-017**: System MUST constrain the generated letter to exactly one page. If body text exceeds available space, the system must warn the user before generation.
- **FR-018**: System MUST allow linking one or more payment certificates to a letter (letter is the parent/cover letter, payment certificates are children).
- **FR-019**: System MUST display linked payment certificates when viewing a letter in the history view.

### Key Entities

- **Letter**: Represents a generated official letter. Key attributes: reference number (YYYY-NNNNN), recipient (selected from officials list), subject (multi-line), body text (rich text), signer (selected from officials list), reply required flag, CC list, signature image (optional), creation timestamp, creator user identity.
- **Letter History Record**: A stored record of letter field data in Supabase for retrieval and on-demand PDF regeneration. Attributes: unique ID, creation timestamp, reference number, recipient, subject, body text (rich text HTML), signer, reply required, CC list, signature base64 (optional), creator user identity.
- **Letter–Payment Certificate Relationship**: A letter serves as a cover letter (parent) for one or more payment certificates (children). Each payment certificate references the parent letter's ID.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can fill out the letter form and generate a PDF in under 2 minutes for a typical single-page letter.
- **SC-002**: 100% of generated PDFs contain all three fixed zones (header with logos and red bar, attachments label, footer with contact info) regardless of user input length.
- **SC-003**: All Arabic text in the generated PDF renders correctly in RTL direction with proper character shaping — zero rendering artifacts for standard Arabic content.
- **SC-004**: Users can locate and re-download any previously generated letter from the history view within 30 seconds.
- **SC-005**: The letter generation workflow completes (from form submission to PDF available) within 10 seconds under normal network conditions.
- **SC-006**: 95% of users successfully generate a correctly formatted letter on their first attempt without needing to regenerate due to layout issues.

## Assumptions

- Users have stable internet connectivity to reach the backend for PDF generation.
- The DGCA header logos (Civil Aviation logo and Kuwait state emblem) are already available as image assets in the project.
- The institutional footer contact information (email, website, P.O. Box, phone, fax) will be hardcoded as static values matching the official DGCA template.
- The "المرفقات" (attachments) section is a static label in this version — no user-editable attachment list.
- The letter is strictly single-page; the payment certificate is also single-page. Multi-page output is not supported.
- Letter generation is available to all authenticated users (no special role restriction).
- An Arabic font suitable for formal documents will be used for PDF rendering.
- PDF generation happens server-side; the client sends form data and receives the completed PDF.
- Signature upload accepts PNG and JPG formats with a maximum file size of 5MB.
- The history view shows letters generated by the current user only (not all users' letters).
