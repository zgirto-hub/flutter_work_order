# Quickstart: 033-gdocs-editor-toolbar

## Prerequisites

- Flutter dev environment set up
- Letter generator screen accessible in the running app
- Chromium-based browser for testing

## File to Modify

- `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart` — modify the `_editorHtml` string constant only (no other code changes)

## Implementation Order

1. **Refactor**: Extract `wrapSelectionWithStyle()` helper, migrate `applyFontSize()` and `applyFontColor()` to use it.
2. **Paragraph Style dropdown** — headings
3. **Font Family dropdown** — uses shared helper
4. **Highlight Color button** — uses shared helper
5. **Line Spacing dropdown** — block-level line-height
6. **Clear Formatting button**
7. **Indent / Outdent buttons**
8. **Zoom dropdown**
9. **CSS polish** — unify `.tb-select`

## Testing Checklist

### Structural
- [ ] Toolbar shows all 7 new controls plus existing ones
- [ ] Toolbar order: Style → Font → Size → B/U → Color → Highlight → Clear → Align → Lists → Indent/Outdent → Spacing → Table → Undo/Redo → Zoom
- [ ] All dropdowns (except Zoom) reset to placeholder after selection

### Paragraph Style
- [ ] Select a line, pick Heading 1 → line becomes `<h1>`
- [ ] Select a heading, pick Normal text → reverts to `<p>`
- [ ] Heading 2 and Heading 3 work identically

### Font Family
- [ ] Select multi-paragraph text, pick Times New Roman → all selected text uses Times New Roman
- [ ] No selection, pick Arial, start typing → new text is Arial (pending-style)
- [ ] Block structure preserved (no `<span>` around `<p>`)

### Highlight
- [ ] Select text, pick yellow → text gets yellow background
- [ ] Multi-paragraph selection → highlight applies to all
- [ ] Saved letter + exported PDF → highlights visible
- [ ] Pending-style at cursor works

### Line Spacing
- [ ] Select single paragraph, pick 1.5 → line-height: 1.5 on that block only
- [ ] Select multiple paragraphs, pick Double → all blocks get line-height: 2
- [ ] Cursor in a paragraph (no selection), pick 1.15 → applies to current block

### Clear Formatting
- [ ] Apply bold + color + font family + highlight → click Clear → all styles removed
- [ ] Text inside heading → Clear reverts to `<p>`

### Indent/Outdent
- [ ] Click in paragraph, click Indent → paragraph indents
- [ ] Click Outdent → reverts
- [ ] Persists through save/reload

### Zoom
- [ ] Pick 150% → editor view zooms in
- [ ] Pick 100% → reverts
- [ ] Save letter → saved HTML has no scaling (view-only)
- [ ] Zoom state does NOT persist across sessions (acceptable — view-only)

### Regression
- [ ] Bold, Underline still work
- [ ] Alignment (left/center/right/justify) still works
- [ ] Bullets and Numbered Lists still work
- [ ] Table insert still works
- [ ] Undo/Redo still work
- [ ] Font Size (existing) still works
- [ ] Font Color (existing) still works

### Round-Trip Persistence
- [ ] Apply all new formatting, save letter, reopen from History → all formatting visible
- [ ] Export to PDF → headings, line spacing, highlights all render correctly
