# Feature Specification: Google Docs–Style Toolbar for Letter Editor

**Feature Branch**: `033-gdocs-editor-toolbar`
**Created**: 2026-04-08
**Status**: Draft
**Input**: User description: "Enrich the rich text editor in the letter form with Google Docs–style toolbar controls: paragraph style (headings), font family, line spacing, highlight color, clear formatting, indent/outdent, and zoom."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Apply Heading Styles to Section Titles (Priority: P1)

A user drafting a long formal letter wants to structure it with section titles. They select a line of text, open the Paragraph Style dropdown, and pick "Heading 1". The line becomes larger and bolder, visually distinguishing the section from the body text.

**Why this priority**: Structure is the most commonly requested typographic feature for formal documents. Headings make long letters readable and persist correctly through save/load/PDF export.

**Independent Test**: Select a line → pick Heading 1 → verify the text becomes a heading and the saved HTML contains `<h1>`.

**Acceptance Scenarios**:

1. **Given** a user has typed a line of text, **When** they select the line and pick "Heading 1", **Then** the line is wrapped in `<h1>` and rendered as a heading
2. **Given** a line is currently a heading, **When** the user picks "Normal text", **Then** the line reverts to a regular `<p>` paragraph
3. **Given** the letter contains headings, **When** the user saves and reopens it from History, **Then** the heading structure is preserved

---

### User Story 2 - Change Font Family Across Selection (Priority: P1)

A user wants to change the font of a multi-paragraph selection. They select the text, open the Font dropdown, pick "Times New Roman", and the whole selection changes font without breaking paragraph structure.

**Why this priority**: Font family is the second most requested typographic feature and must behave identically to the existing font size/color controls which already handle multi-paragraph selections correctly.

**Independent Test**: Select multiple paragraphs → pick a font → verify all selected text uses the new font and block structure is preserved.

**Acceptance Scenarios**:

1. **Given** text spanning multiple paragraphs is selected, **When** user picks a font family, **Then** all selected text renders in the new font
2. **Given** no selection (cursor only), **When** user picks a font and types, **Then** the new text is rendered in the picked font
3. **Given** selected text has existing styles, **When** a new font is applied, **Then** only the font family changes and other styles are preserved

---

### User Story 3 - Highlight Important Passages (Priority: P2)

A reviewer highlights a sentence in yellow to flag it. They select text, click the highlight button, pick a color, and the text gets a yellow background that persists in the PDF export.

**Why this priority**: Drafting/review feature that delivers real value but is less frequent than headings/fonts.

**Independent Test**: Select text → pick highlight color → verify background applied and visible in exported PDF.

**Acceptance Scenarios**:

1. **Given** text is selected, **When** user clicks highlight and picks a color, **Then** the text gets that background color
2. **Given** a letter with highlights, **When** exported to PDF, **Then** the highlights appear in the exported document
3. **Given** no selection, **When** user picks a highlight color and types, **Then** the new text has that background

---

### User Story 4 - Adjust Line Spacing (Priority: P2)

Official correspondence requires 1.5 or Double line spacing. The user selects paragraphs and picks from the Line Spacing dropdown.

**Why this priority**: Compliance requirement for certain formal documents. Needed but not used on every letter.

**Independent Test**: Select multiple paragraphs → pick 1.5 → verify visible spacing increase.

**Acceptance Scenarios**:

1. **Given** one or more paragraphs are selected, **When** user picks "1.5" from Line Spacing, **Then** all selected blocks get 1.5 line-height
2. **Given** a letter with custom line spacing, **When** saved and reopened, **Then** spacing persists

---

### User Story 5 - Clear Accidental Formatting (Priority: P2)

A user pastes text from an external source with unwanted styles. They select the pasted text and click Clear Formatting; all inline styles and block type reset to normal paragraph text.

**Why this priority**: Recovery feature. Essential for users pasting from Word/web pages.

**Independent Test**: Apply bold, color, font, highlight → select → click Clear Formatting → verify all styles removed.

**Acceptance Scenarios**:

1. **Given** text has multiple inline styles, **When** user clicks Clear Formatting, **Then** all inline styles are removed
2. **Given** text is inside a heading, **When** user clicks Clear Formatting, **Then** it reverts to `<p>`

---

### User Story 6 - Indent and Outdent Paragraphs (Priority: P3)

User clicks in a paragraph, clicks Indent, paragraph shifts inward. Clicks Outdent to reverse.

**Why this priority**: Nice-to-have. Used occasionally for structured correspondence.

**Independent Test**: Click in paragraph → Indent → verify indent. Outdent → verify reversal.

**Acceptance Scenarios**:

1. **Given** cursor in a paragraph, **When** user clicks Indent, **Then** the paragraph gets additional indentation
2. **Given** indented content, **When** letter is saved and reopened, **Then** indentation persists

---

### User Story 7 - Zoom Editor View (Priority: P3)

User picks 125% from the Zoom dropdown; editor view enlarges visually. Saved HTML is unchanged.

**Why this priority**: Comfort feature. Doesn't affect the document.

**Independent Test**: Pick 150% → verify zoom. Save → verify saved HTML is identical to unzoomed content.

**Acceptance Scenarios**:

1. **Given** editor is at 100%, **When** user picks 150%, **Then** the editor view visually enlarges
2. **Given** editor is zoomed, **When** letter is saved, **Then** persisted HTML has no scaling

---

### Edge Cases

- User picks a paragraph style with no selection → style applies to the block containing the cursor
- User selects text with mixed existing fonts → new font family overwrites all, other styles preserved
- Clear Formatting clicked in an empty paragraph → no visible change
- Indent clicked multiple times → accumulates indent levels
- Zoom set to 150% when pasting → pasted content goes in at normal scale, only display is zoomed
- Highlight + Clear Formatting → highlight is removed with other inline styles
- Headings in PDF export → render at browser-default heading sizes

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a Paragraph Style dropdown with options: Normal text, Heading 1, Heading 2, Heading 3
- **FR-002**: Paragraph Style MUST wrap the current block(s) in the corresponding HTML tag (`<p>`, `<h1>`, `<h2>`, `<h3>`)
- **FR-003**: System MUST provide a Font Family dropdown: Calibri, Arial, Times New Roman, Tahoma, Georgia, Courier New, Verdana
- **FR-004**: Font Family MUST apply to the selected text range, handling multi-paragraph selections without breaking block structure
- **FR-005**: Font Family MUST set a pending style at the cursor when no selection exists
- **FR-006**: System MUST provide a Line Spacing dropdown: Single (1.0), 1.15, 1.5, Double (2.0)
- **FR-007**: Line Spacing MUST apply to every block-level element intersecting the current selection
- **FR-008**: System MUST provide a Highlight Color picker using a native color input, defaulting to yellow
- **FR-009**: Highlight MUST apply a background color to the selected text range using the same multi-paragraph-safe mechanism as Font Family
- **FR-010**: System MUST provide a Clear Formatting button that strips all inline styles and converts the block back to normal paragraph text
- **FR-011**: System MUST provide Indent and Outdent buttons for paragraph indentation
- **FR-012**: System MUST provide a Zoom dropdown: 50%, 75%, 100%, 125%, 150%
- **FR-013**: Zoom MUST affect only the editor's visual display — saved HTML MUST NOT include any scaling transformation
- **FR-014**: All new dropdowns (except Zoom) MUST reset to their placeholder label after selection so the same value can be reapplied
- **FR-015**: All new controls MUST preserve their effects when the letter is saved and reopened from History
- **FR-016**: Headings, line spacing, and highlights MUST render correctly in the exported PDF
- **FR-017**: The feature MUST NOT cause regressions to existing toolbar features (bold, underline, alignment, lists, table, undo/redo, font size, font color)
- **FR-018**: The feature MUST share the underlying "wrap selection with inline style" logic between font family, font size, font color, and highlight to guarantee consistent behavior across all four

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can apply Heading 1/2/3 and revert to Normal text within one click per action
- **SC-002**: Users can change font family across multi-paragraph selections without losing other styles or breaking block structure
- **SC-003**: Users can set custom line spacing (Single/1.15/1.5/Double) on any selected paragraphs in one click
- **SC-004**: Users can highlight text with any color, visible in both the editor view and the exported PDF
- **SC-005**: Clear Formatting removes 100% of inline styles and block formatting from the selection in one click
- **SC-006**: Zoom changes the visual editor size without modifying the saved HTML
- **SC-007**: All new formatting survives round trip: save → close → reopen from History → still visible
- **SC-008**: No regression in existing toolbar functionality

## Assumptions

- The existing rich text editor is an HTML5 `contenteditable` area inside an iframe, with toolbar controls embedded in an HTML/JS/CSS string constant
- Browser target is Chromium-based (Chrome, Edge) — Chromium-specific APIs (CSS `zoom`, `document.execCommand`) are acceptable
- The existing font size and font color controls already correctly handle multi-paragraph selections using a text-node-walker pattern; this feature will reuse and share that logic
- The existing save/load pipeline already persists and restores arbitrary inline HTML attributes — no backend or database changes needed
- The PDF export pipeline already renders inline CSS (headings, line-height, background-color) — no backend changes needed
- Fonts don't need to be embedded; they fall back to system defaults when unavailable
- Heading sizes rely on browser defaults (no custom h1/h2/h3 CSS)
- Accessibility features (screen reader labels, custom keyboard shortcuts) are not in scope
