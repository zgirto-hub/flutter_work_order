# Feature Specification: Editor Image Insertion

**Feature Branch**: `034-editor-image-insert`  
**Created**: 2026-04-08  
**Status**: Draft  
**Input**: User description: "Add image insertion capability to the letter body WYSIWYG editor"

## Clarifications

### Session 2026-04-08

- Q: How should the existing "Add Attachment" feature relate to the new inline image insertion? → A: Keep them fully separate — attachments remain as independent supporting documents; inline images are a new editor-only capability embedded in the letter body content.
- Q: How should users delete an inserted image from the editor? → A: Standard editor behavior only — select image and press Delete/Backspace to remove it. No special overlay or controls needed.
- Q: Should the server apply compression when resizing images? → A: Yes — resize + compress to 80% quality for optimal balance of file size and visual quality.
- Q: Where should the 5MB file size limit be enforced? → A: Both client-side (instant feedback) and server-side (security). Defense-in-depth approach.
- Q: Should there be a maximum number of images per letter? → A: Soft limit of 10 images — warn the user but allow proceeding.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Insert Image into Letter Body (Priority: P1)

A letter author is composing a letter in the WYSIWYG editor and needs to include a photograph, diagram, or visual reference inline within the letter body. They click the "Insert Image" button on the toolbar, select an image file from their device, and the image appears at the cursor position in the editor. The image is saved on the server and referenced by URL so it persists across sessions.

**Why this priority**: This is the core capability. Without image upload and inline insertion, the feature has no value.

**Independent Test**: Can be fully tested by opening the letter editor, placing the cursor in the body, clicking the image button, selecting a valid image file, and verifying the image appears inline at the cursor position and persists after saving/reopening the letter.

**Acceptance Scenarios**:

1. **Given** the editor is open with the cursor placed in the body text, **When** the user clicks the "Insert Image" toolbar button and selects a PNG file under 5MB, **Then** the image is uploaded to the server, a loading indicator is shown during upload, and the image appears inline at the cursor position with responsive sizing.
2. **Given** the editor contains existing text and images, **When** the user saves the letter and reopens it for editing, **Then** all previously inserted images load correctly and remain in their original positions.
3. **Given** the user selects an image file larger than 1920px in width, **When** the upload completes, **Then** the server automatically resizes the image to a maximum width of 1920px while preserving aspect ratio, and the resulting image is stored and displayed.

---

### User Story 2 - Image Validation and Error Handling (Priority: P2)

A user attempts to insert an invalid file (wrong format, too large, or corrupt). The system provides clear feedback explaining why the file was rejected and what formats/sizes are acceptable, without disrupting the editor state.

**Why this priority**: Proper validation prevents server errors, storage abuse, and user confusion. Essential for a production-ready feature but not the core insertion flow.

**Independent Test**: Can be tested by attempting to upload files that violate each constraint (oversized file, unsupported format) and verifying that clear, specific error messages appear without losing editor content.

**Acceptance Scenarios**:

1. **Given** the user selects a file exceeding 5MB, **When** the upload is attempted, **Then** the system rejects the file before uploading and displays an error message indicating the maximum allowed size.
2. **Given** the user selects a non-image file (e.g., .pdf, .exe, .txt), **When** the file picker returns, **Then** the system rejects the file and displays an error message listing accepted formats (PNG, JPG, JPEG, GIF, WebP).
3. **Given** an upload is in progress, **When** a network error occurs, **Then** the user sees an error message and the editor content remains unchanged.

---

### User Story 3 - Images in Generated PDF (Priority: P1)

When a letter containing inline images is generated as a PDF, all images are rendered correctly in the output document. The images appear at the same positions as in the editor, properly sized within the page margins.

**Why this priority**: Letters are ultimately distributed as PDFs. If images do not appear in the PDF output, the feature fails its primary business purpose.

**Independent Test**: Can be tested by inserting one or more images into a letter body, generating the PDF, and verifying that each image appears in the correct position with appropriate sizing within the PDF page layout.

**Acceptance Scenarios**:

1. **Given** a letter body contains one or more inline images referenced by server URL, **When** the PDF is generated, **Then** all images are fetched from the server filesystem and rendered in the PDF at their corresponding positions.
2. **Given** a letter body contains a wide image, **When** the PDF is generated, **Then** the image is scaled to fit within the page content area without exceeding margins or distorting the aspect ratio.
3. **Given** a letter body contains multiple images interspersed with text, **When** the PDF is generated, **Then** the text and images maintain their relative ordering and layout from the editor.

---

### Edge Cases

- What happens when the user inserts an image and then undoes the action? The image tag is removed from the editor via standard undo behavior; the uploaded file remains on the server (no automatic cleanup).
- What happens when an image file referenced in a letter body is deleted from the server? The PDF generation still completes; the missing image appears as a broken image placeholder or is omitted gracefully.
- What happens when multiple images are inserted in rapid succession? Each upload is handled independently; images appear in the order they were inserted once each upload completes.
- What happens when the user selects an inserted image and presses Delete/Backspace? The `<img>` tag is removed from the editor content via standard contenteditable behavior. No special UI controls are needed. The server file is not deleted (no automatic cleanup).
- What happens when the editor body HTML is pasted from an external source containing external image URLs? Only images hosted on the application server (matching the `/files/letters/` path) are guaranteed to render in the PDF. External URLs are not processed or re-uploaded.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide an "Insert Image" button in the editor toolbar that opens the device file picker when clicked.
- **FR-002**: System MUST accept image uploads in PNG, JPG, JPEG, GIF, and WebP formats only.
- **FR-003**: System MUST reject image files exceeding 5MB in size both on the client (before upload, for instant feedback) and on the server (for security), displaying a clear error message to the user.
- **FR-004**: System MUST auto-resize uploaded images that exceed 1920px in width down to 1920px width, preserving the original aspect ratio, and compress to 80% quality.
- **FR-005**: System MUST save uploaded images to the server's letter images directory with a unique filename using the pattern `letter_img_{timestamp}_{uuid}.{extension}`.
- **FR-006**: System MUST return the server URL path `/files/letters/{filename}` for each uploaded image.
- **FR-007**: System MUST insert an `<img>` tag at the current cursor position in the editor with the server URL as the `src` attribute and responsive max-width styling.
- **FR-008**: System MUST display a loading indicator in the editor while an image upload is in progress.
- **FR-012**: System SHOULD warn the user when inserting more than 10 images in a single letter, but allow them to proceed.
- **FR-009**: System MUST render inline images correctly when an existing letter containing images is opened for editing.
- **FR-010**: The PDF generation system MUST fetch and embed all server-hosted images referenced in the letter body HTML when producing the PDF output.
- **FR-011**: Images in the generated PDF MUST be scaled to fit within the page content area without exceeding margins.

### Key Entities

- **Letter Image**: An image file uploaded for inline use in a letter body. Attributes: unique filename, server file path, original format, stored dimensions. Stored as a file on the server filesystem, not in the database. Referenced in the letter body HTML via its server URL.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can insert an image into the letter editor body in under 10 seconds (from button click to image visible in editor) for files under 2MB on a standard connection.
- **SC-002**: 100% of accepted image formats (PNG, JPG, JPEG, GIF, WebP) upload and display correctly in both the editor and generated PDF.
- **SC-003**: All images inserted in the editor appear in the generated PDF at their corresponding positions with correct aspect ratios.
- **SC-004**: Files exceeding the 5MB limit are rejected before upload with a user-friendly error message 100% of the time.
- **SC-005**: Uploaded images wider than 1920px are automatically resized, resulting in stored files no wider than 1920px.

## Assumptions

- The existing server filesystem storage at `backend/uploaded_files/letters/` is available and has sufficient disk space for image storage.
- The server's static file serving configuration already serves files from the `uploaded_files/` directory at the `/files/` URL path (consistent with existing attachment and signature file serving).
- The browser's native file picker is used for image selection (no custom gallery or drag-and-drop required for the initial release).
- A soft limit of 10 images per letter is enforced via a warning; users may proceed past the limit at their discretion.
- Image cleanup (deleting orphaned images from deleted letters) is out of scope for this feature.
- The PDF renderer has filesystem access to the `uploaded_files/letters/` directory or can resolve the image URLs via localhost.
- Only the letter body HTML content supports inline images; other letter fields (subject, recipient, etc.) do not.
- The inline image feature is fully independent from the existing "Add Attachment" feature. Attachments remain as separate supporting documents linked to the letter record. Inline images are embedded in the letter body HTML and rendered in the PDF. No interaction or integration between the two features is required.
