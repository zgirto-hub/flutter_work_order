# Tasks: Google Docs–Style Toolbar for Letter Editor

**Input**: Design documents from `/specs/033-gdocs-editor-toolbar/`
**Prerequisites**: plan.md, spec.md, research.md, quickstart.md

**Tests**: Not requested — manual testing only per plan.md.

**Organization**: All tasks operate on a single file (`frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`) inside the `_editorHtml` string constant. Tasks are grouped by user story so each story can be shipped independently.

---

## Phase 1: Setup

_(No setup — single-file change, target file already exists, no dependencies to install)_

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared `wrapSelectionWithStyle()` helper that US2 (font family) and US3 (highlight) depend on. Also unblocks CSS polish. Must complete before any user story work begins.

- [x] T001 Extract `wrapSelectionWithStyle(styleProp, styleVal)` helper and refactor `applyFontSize()` / `applyFontColor()` to use it in [frontend/lib/screens/letters_v2/letter_form_tab_v2.dart](frontend/lib/screens/letters_v2/letter_form_tab_v2.dart) (inside `_editorHtml` JS block around lines 1423-1560)
- [x] T002 Add `.tb-select` CSS class and rename existing `.fontsize-select` references in [frontend/lib/screens/letters_v2/letter_form_tab_v2.dart](frontend/lib/screens/letters_v2/letter_form_tab_v2.dart) (inside `_editorHtml` CSS block around lines 1280-1290)

**Checkpoint**: Font Size and Font Color still work exactly as before. New helper available for other tasks.

---

## Phase 3: User Story 1 - Apply Heading Styles (Priority: P1) 🎯 MVP

**Goal**: Users can apply Heading 1/2/3 and revert to Normal text via a dropdown in the toolbar.

**Independent Test**: Select a line → pick "Heading 1" from Style dropdown → line becomes `<h1>`. Pick "Normal text" → reverts to `<p>`.

### Implementation for User Story 1

- [x] T003 [US1] Add Paragraph Style dropdown HTML + `applyParaStyle(tag)` JS function in [frontend/lib/screens/letters_v2/letter_form_tab_v2.dart](frontend/lib/screens/letters_v2/letter_form_tab_v2.dart) (toolbar HTML around line 1321, JS after refactored `applyFontColor`)

**Checkpoint**: Style dropdown renders with Normal/Heading 1/2/3 options. Picking a heading wraps the block in the corresponding tag; Normal reverts to `<p>`. Dropdown resets to "Style" after each pick.

---

## Phase 4: User Story 2 - Change Font Family (Priority: P1)

**Goal**: Users can change font family of selected text via a Font dropdown, with multi-paragraph selections handled correctly.

**Independent Test**: Select multi-paragraph text → pick Times New Roman → all selected text uses new font. No selection → pick font → start typing → new text in picked font.

### Implementation for User Story 2

- [x] T004 [US2] Add Font Family dropdown HTML + `applyFontFamily(f)` JS function (delegates to `wrapSelectionWithStyle`) in [frontend/lib/screens/letters_v2/letter_form_tab_v2.dart](frontend/lib/screens/letters_v2/letter_form_tab_v2.dart) (toolbar HTML near Paragraph Style dropdown, JS near `applyParaStyle`)

**Depends on**: T001 (shared helper)

**Checkpoint**: Font dropdown shows 7 fonts. Picking a font applies it to selection (multi-paragraph-safe) or sets pending font at cursor.

---

## Phase 5: User Story 3 - Highlight Important Passages (Priority: P2)

**Goal**: Users can highlight text with a background color via a native color picker button.

**Independent Test**: Select text → click highlight button → pick yellow → text gets yellow background. Verify highlight persists in saved letter and appears in exported PDF.

### Implementation for User Story 3

- [x] T005 [US3] Add Highlight Color button HTML + `applyHighlight(c)` JS function (delegates to `wrapSelectionWithStyle`) in [frontend/lib/screens/letters_v2/letter_form_tab_v2.dart](frontend/lib/screens/letters_v2/letter_form_tab_v2.dart) (toolbar HTML next to font color button, JS near `applyFontColor`)

**Depends on**: T001 (shared helper)

**Checkpoint**: Highlight button opens native color picker. Selected text gets the chosen background color. Multi-paragraph selections work. Highlight renders correctly in PDF export.

---

## Phase 6: User Story 4 - Adjust Line Spacing (Priority: P2)

**Goal**: Users can apply Single/1.15/1.5/Double line spacing to selected paragraphs.

**Independent Test**: Select multiple paragraphs → pick "1.5" from Line Spacing dropdown → all selected blocks get `line-height: 1.5`.

### Implementation for User Story 4

- [x] T006 [US4] Add Line Spacing dropdown HTML + `applyLineSpacing(v)` JS function (walks block-level elements in selection) in [frontend/lib/screens/letters_v2/letter_form_tab_v2.dart](frontend/lib/screens/letters_v2/letter_form_tab_v2.dart) (toolbar HTML after Indent/Outdent, JS standalone function)

**Checkpoint**: Line Spacing dropdown renders. Picking a value applies `line-height` to every block intersecting the selection. Works for single-paragraph and multi-paragraph selections.

---

## Phase 7: User Story 5 - Clear Accidental Formatting (Priority: P2)

**Goal**: Users can strip all formatting from selected text with one click.

**Independent Test**: Apply bold + color + font family + highlight to text → select it → click Clear Formatting → all styles removed and block reverts to `<p>`.

### Implementation for User Story 5

- [x] T007 [US5] Add Clear Formatting button HTML + `clearFormatting()` JS function (runs `removeFormat` + `formatBlock → p`) in [frontend/lib/screens/letters_v2/letter_form_tab_v2.dart](frontend/lib/screens/letters_v2/letter_form_tab_v2.dart) (toolbar HTML after Highlight, JS standalone function)

**Checkpoint**: Clear Formatting button removes all inline styles from selection AND converts heading blocks back to `<p>`.

---

## Phase 8: User Story 6 - Indent/Outdent Paragraphs (Priority: P3)

**Goal**: Users can nest/unnest paragraphs with dedicated toolbar buttons.

**Independent Test**: Click in a paragraph → click Indent → paragraph indents. Click Outdent → reverts.

### Implementation for User Story 6

- [x] T008 [US6] Add Indent and Outdent buttons HTML (direct `fmt('indent')` / `fmt('outdent')` calls, no new JS) in [frontend/lib/screens/letters_v2/letter_form_tab_v2.dart](frontend/lib/screens/letters_v2/letter_form_tab_v2.dart) (toolbar HTML after lists)

**Checkpoint**: Indent/Outdent buttons visible and functional. Indentation persists through save/reload.

---

## Phase 9: User Story 7 - Zoom Editor View (Priority: P3)

**Goal**: Users can visually zoom the editor 50%–150% without affecting saved content.

**Independent Test**: Pick 150% from Zoom dropdown → editor view enlarges. Save letter → saved HTML has no scaling.

### Implementation for User Story 7

- [x] T009 [US7] Add Zoom dropdown HTML + `applyZoom(z)` JS function (sets `#editor.style.zoom`) in [frontend/lib/screens/letters_v2/letter_form_tab_v2.dart](frontend/lib/screens/letters_v2/letter_form_tab_v2.dart) (toolbar HTML at end, JS standalone function)

**Checkpoint**: Zoom dropdown visible and functional. Saved HTML is identical regardless of zoom level.

---

## Phase 10: Polish & Cross-Cutting Concerns

- [ ] T010 Manual end-to-end verification against [quickstart.md](quickstart.md) testing checklist (all 7 stories + regression + round-trip persistence + PDF export)

---

## Dependencies & Execution Order

```
T001 (shared helper) ──┬── T003 (US1 heading)
                       ├── T004 (US2 font family)      [depends on T001]
                       ├── T005 (US3 highlight)        [depends on T001]
                       ├── T006 (US4 line spacing)
                       ├── T007 (US5 clear formatting)
                       ├── T008 (US6 indent/outdent)
                       └── T009 (US7 zoom)

T002 (CSS .tb-select) ── can run in parallel with T001

T010 (verification) ── runs after all user stories complete
```

### Phase Dependencies

- **Phase 2 (Foundational)**: T001 and T002 can run in parallel (different regions of same file, but different concerns — JS vs CSS)
- **User Stories 1–7**: Each depends only on Phase 2. US1 (T003), US4 (T006), US5 (T007), US6 (T008), US7 (T009) don't use the shared helper and could even run without T001 if needed. US2 (T004) and US3 (T005) require T001.
- **Polish**: Runs after everything

### Parallel Opportunities

Since all tasks modify the same file, **sequential execution is safer** to avoid merge conflicts. The only true parallel opportunity is T001 and T002 since they operate on different regions (JS functions vs CSS block).

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete T001 + T002 (Foundational)
2. Complete T003 (US1 — heading dropdown)
3. **STOP and VALIDATE**: Verify headings work, font size/color still work (regression check)
4. Deploy if ready

### Incremental Delivery

Each user story is independent after Phase 2. Recommended order:
1. T001, T002 (foundation)
2. T003 (US1 headings) → test → commit
3. T004 (US2 font family) → test → commit
4. T005 (US3 highlight) → test → commit
5. T006 (US4 line spacing) → test → commit
6. T007 (US5 clear formatting) → test → commit
7. T008 (US6 indent/outdent) → test → commit
8. T009 (US7 zoom) → test → commit
9. T010 (full regression sweep) → deploy

---

## Task Details

### T001: Extract `wrapSelectionWithStyle()` Helper

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**Region**: `_editorHtml` JS block, around lines 1423–1560
**What to do**:
- Add a new function `wrapSelectionWithStyle(styleProp, styleVal)` that contains the logic currently duplicated in `applyFontSize` and `applyFontColor`:
  - If selection is collapsed: insert a `<span>` with the given style and a zero-width space, place caret inside.
  - If selection has range: walk via `TreeWalker` (SHOW_TEXT), filter by `range.intersectsNode`, split each text node at selection boundaries, wrap each slice in a `<span>` with the given style. If parent is already a sole-child span with the same style property set, update it in place.
- Refactor `applyFontSize(s)` to a single-line wrapper: `if (s) { document.getElementById("editor").focus(); wrapSelectionWithStyle("fontSize", s + "pt"); }`
- Refactor `applyFontColor(c)` to:
  ```js
  function applyFontColor(c) {
    if (!c) return;
    var swatch = document.getElementById("colorSwatch");
    if (swatch) swatch.style.color = c;
    document.getElementById("editor").focus();
    wrapSelectionWithStyle("color", c);
  }
  ```
**Signatures**:
```javascript
function wrapSelectionWithStyle(styleProp, styleVal) { ... }
function applyFontSize(s) { ... }
function applyFontColor(c) { ... }
```
**Acceptance**:
- Existing Font Size dropdown behavior is unchanged (tested: select multi-paragraph text, change size, verify it applies correctly).
- Existing Font Color picker behavior is unchanged (tested: same as above with color).
- Pending-style at cursor still works for both.
- `applyFontSize` and `applyFontColor` bodies are now ≤10 lines each.
- Line count of the JS block reduced by ~80 lines.

### T002: Add `.tb-select` CSS Class

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**Region**: `_editorHtml` CSS block, around lines 1280–1290
**What to do**:
- Rename `.fontsize-select` selector to `.tb-select` (two occurrences, both inside the toolbar style rules).
- Update the existing Font Size dropdown HTML (around line 1338) to use `class="tb-select"` instead of `class="fontsize-select"`.
**Signatures**: N/A (CSS only)
**Acceptance**:
- Font Size dropdown renders identically to before.
- No orphan `.fontsize-select` references remain.
- The class is ready to be reused by all new dropdowns (Style, Font, Spacing, Zoom).

### T003: Paragraph Style Dropdown

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**What to do**:
- Add an HTML `<select>` in the toolbar with options: "Style" (placeholder), "Normal text" (`p`), "Heading 1" (`h1`), "Heading 2" (`h2`), "Heading 3" (`h3`). Use `class="tb-select"`. Place it before the existing Font Size dropdown.
- Add `onchange="applyParaStyle(this.value); this.value=''"`.
- Add a new JS function `applyParaStyle(tag)` that focuses the editor and calls `document.execCommand("formatBlock", false, tag)` when `tag` is non-empty.
**Signatures**:
```javascript
function applyParaStyle(tag) {
  if (!tag) return;
  document.getElementById("editor").focus();
  document.execCommand("formatBlock", false, tag);
}
```
**Acceptance**:
- Dropdown renders with 4 options plus "Style" placeholder.
- Picking "Heading 1" wraps the block containing the cursor in `<h1>`.
- Picking "Normal text" reverts to `<p>`.
- Dropdown resets to "Style" after each pick.

### T004: Font Family Dropdown

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**Depends on**: T001
**What to do**:
- Add an HTML `<select>` with options: "Font" (placeholder), Calibri, Arial, Times New Roman, Tahoma, Georgia, Courier New, Verdana. Each option's `value` is the appropriate CSS `font-family` string (e.g., `'Times New Roman', serif`). Use `class="tb-select"`. Place it after the Paragraph Style dropdown.
- Add `onchange="applyFontFamily(this.value); this.value=''"`.
- Add a new JS function:
  ```javascript
  function applyFontFamily(f) {
    if (!f) return;
    document.getElementById("editor").focus();
    wrapSelectionWithStyle("fontFamily", f);
  }
  ```
**Signatures**: `function applyFontFamily(f)`
**Acceptance**:
- Dropdown shows 7 fonts.
- Selecting a font applies it to the current selection (single- or multi-paragraph).
- With no selection, picking a font and then typing produces text in that font.
- Dropdown resets to "Font" after each pick.
- Block structure (e.g., `<p>` wrapping) is preserved.

### T005: Highlight Color Button

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**Depends on**: T001
**What to do**:
- Add a `<label class="color-btn">` containing a `<span id="hlSwatch">` showing a yellow block, and a nested `<input type="color" value="#FFFF00">` with `onchange="applyHighlight(this.value); document.getElementById('hlSwatch').style.color=this.value"`. Place it right after the existing Font Color button.
- Add a new JS function:
  ```javascript
  function applyHighlight(c) {
    if (!c) return;
    document.getElementById("editor").focus();
    wrapSelectionWithStyle("backgroundColor", c);
  }
  ```
**Signatures**: `function applyHighlight(c)`
**Acceptance**:
- Highlight button visible next to Font Color, with a small yellow swatch.
- Clicking it opens the native color picker.
- Picked color is applied as `background-color` to selected text (multi-paragraph safe).
- Swatch color updates to match last pick.
- Highlight renders in both editor and PDF export.

### T006: Line Spacing Dropdown

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**What to do**:
- Add an HTML `<select>` with options: "Spacing" (placeholder), Single (1), 1.15, 1.5, Double (2). Use `class="tb-select"`. Place it after the Indent/Outdent buttons (or after Lists if Indent/Outdent not yet present).
- Add `onchange="applyLineSpacing(this.value); this.value=''"`.
- Add a new JS function that:
  1. Focuses the editor, gets the selection range.
  2. Walks block-level elements (`P`, `DIV`, `H1–H6`, `LI`, `BLOCKQUOTE`) via `TreeWalker` with `SHOW_ELEMENT`, filtered by `range.intersectsNode`.
  3. Sets `element.style.lineHeight = v` on each.
  4. Fallback: if no blocks found in range, climb the ancestor chain from `range.commonAncestorContainer` to the nearest block-level element and apply there.
**Signatures**:
```javascript
function applyLineSpacing(v) { ... }
```
**Acceptance**:
- Dropdown visible with 4 spacing options.
- Picking "1.5" sets `line-height: 1.5` on every block in the selection.
- Multi-paragraph selections work.
- Cursor-only (no selection) applies to the current block.
- Dropdown resets to "Spacing" after pick.

### T007: Clear Formatting Button

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**What to do**:
- Add a `<button onclick="clearFormatting()" title="Clear formatting">⌫</button>` (or similar icon) after the Highlight button.
- Add a new JS function:
  ```javascript
  function clearFormatting() {
    document.getElementById("editor").focus();
    document.execCommand("removeFormat");
    var sel = window.getSelection();
    if (sel.rangeCount && !sel.isCollapsed) {
      document.execCommand("formatBlock", false, "p");
    }
  }
  ```
**Signatures**: `function clearFormatting()`
**Acceptance**:
- Button removes bold, underline, color, font family, font size, highlight from selection.
- Headings in selection are reverted to `<p>`.
- Works on partial selections without affecting unselected text.

### T008: Indent / Outdent Buttons

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**What to do**:
- Add two `<button>` elements after the list buttons (bullets/numbered):
  - `<button onclick="fmt('indent')" title="Increase indent">→|</button>`
  - `<button onclick="fmt('outdent')" title="Decrease indent">|←</button>`
- No new JS — reuses existing `fmt()` helper.
**Signatures**: N/A (uses existing `fmt`)
**Acceptance**:
- Both buttons visible.
- Clicking Indent increases the current paragraph's indent level.
- Clicking Outdent reduces it.
- Indent level persists through save/reload.

### T009: Zoom Dropdown

**File**: `frontend/lib/screens/letters_v2/letter_form_tab_v2.dart`
**What to do**:
- Add an HTML `<select id="zoomSelect" class="tb-select">` with options: 50% (`0.5`), 75% (`0.75`), 100% (`1`, selected), 125% (`1.25`), 150% (`1.5`). Place at the end of the toolbar.
- Add `onchange="applyZoom(this.value)"` (no reset — zoom is stateful).
- Add a new JS function:
  ```javascript
  function applyZoom(z) {
    document.getElementById("editor").style.zoom = z;
  }
  ```
**Signatures**: `function applyZoom(z)`
**Acceptance**:
- Dropdown visible at end of toolbar with 5 zoom levels.
- Picking 150% scales the editor visually.
- Picking 100% reverts.
- Selected value stays visible (doesn't reset).
- Saved HTML is identical regardless of zoom level (view-only).

### T010: Full Regression & Round-Trip Verification

**File**: N/A (manual testing)
**What to do**: Run every item in [quickstart.md](quickstart.md) Testing Checklist. Fix any regressions before merging.
**Acceptance**:
- All 7 stories pass their independent tests.
- No regression in existing toolbar features.
- Full round-trip (save → reopen → PDF export) works with all new formatting.

---

## Implementation Prompts

--- IMPLEMENTATION PROMPT T001 ---
You are an expert Dart/Flutter developer with strong JavaScript knowledge.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart (editing an embedded JavaScript block inside a Dart string constant)
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: Inside the `_editorHtml` string constant's JavaScript block (around lines 1423–1560), extract a new shared function `wrapSelectionWithStyle(styleProp, styleVal)` and refactor the existing `applyFontSize(s)` and `applyFontColor(c)` to use it.

The existing `applyFontSize` currently has two code paths: (1) collapsed-selection path that inserts a `<span>` with a zero-width space and moves the caret inside, and (2) range-selection path that uses a `TreeWalker` over text nodes, filters by `range.intersectsNode`, splits text nodes at selection boundaries, and wraps each slice in a `<span>` (reusing existing spans when the parent is already a sole-child span with the matching style property). The existing `applyFontColor` duplicates this exact logic, differing only in the style property name.

Your refactor:
1. Add a new function `wrapSelectionWithStyle(styleProp, styleVal)` that contains BOTH code paths. The `styleProp` is a camelCase CSS property name (e.g., `"fontSize"`, `"color"`). The `styleVal` is the value string (e.g., `"14pt"`, `"#CC0000"`).
2. Reduce `applyFontSize(s)` to:
   ```js
   function applyFontSize(s) {
     if (!s) return;
     document.getElementById("editor").focus();
     wrapSelectionWithStyle("fontSize", s + "pt");
   }
   ```
3. Reduce `applyFontColor(c)` to:
   ```js
   function applyFontColor(c) {
     if (!c) return;
     var swatch = document.getElementById("colorSwatch");
     if (swatch) swatch.style.color = c;
     document.getElementById("editor").focus();
     wrapSelectionWithStyle("color", c);
   }
   ```

Signatures required:
- `function wrapSelectionWithStyle(styleProp, styleVal) { ... }`
- `function applyFontSize(s) { ... }` (slimmed down)
- `function applyFontColor(c) { ... }` (slimmed down)

Constraints:
- Only modify the JavaScript block inside the `_editorHtml` string constant. Do not touch any Dart code, HTML, or CSS.
- Preserve the exact behavior of Font Size and Font Color: collapsed-selection pending style AND range-selection wrapping must still work identically.
- Use ES5 syntax only (no arrow functions, no `let`/`const`, no template literals — this is an embedded script inside a Dart raw string and must match existing style).
- Do not add new toolbar controls in this task — that's for later tasks.
- Do not rename the existing functions.

Acceptance criteria:
- `wrapSelectionWithStyle` exists and handles both collapsed and range selections.
- `applyFontSize` and `applyFontColor` bodies are each ≤10 lines and delegate to the helper.
- Manual test: select multi-paragraph text, change font size → all text changes size without breaking paragraphs. Same for font color.
- Manual test: place cursor in empty spot, pick a font size, start typing → new text is sized. Same for color.
- Total JS block line count is reduced (roughly 80 fewer lines).
--- END PROMPT T001 ---

--- IMPLEMENTATION PROMPT T002 ---
You are an expert Dart/Flutter developer with strong CSS knowledge.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart (editing embedded CSS inside a Dart string constant)
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: Inside the `_editorHtml` string constant's CSS block (around lines 1280–1290), rename the `.fontsize-select` CSS class to `.tb-select`. Also update the existing Font Size `<select>` HTML element (around line 1338) to use `class="tb-select"` instead of `class="fontsize-select"`.

Signatures required: N/A (CSS/HTML only)

Constraints:
- Do not change the CSS rules themselves — only the selector name.
- Do not add new styles.
- Do not touch Dart code or the JavaScript block.

Acceptance criteria:
- No occurrences of `.fontsize-select` remain in the file.
- At least one occurrence of `.tb-select` exists in the CSS block.
- Font Size `<select>` uses `class="tb-select"`.
- Font Size dropdown renders identically to before (visual test).
--- END PROMPT T002 ---

--- IMPLEMENTATION PROMPT T003 ---
You are an expert Dart/Flutter developer with strong JavaScript knowledge.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart (editing embedded HTML + JS inside a Dart string constant)
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: Add a Paragraph Style dropdown to the editor toolbar.

1. In the toolbar HTML inside the `_editorHtml` constant (around the existing Font Size dropdown, line ~1338), add a new `<select>` element BEFORE the Font Size dropdown:
   ```html
   <select onchange="applyParaStyle(this.value); this.value=''" title="Paragraph style" class="tb-select">
     <option value="" selected>Style</option>
     <option value="p">Normal text</option>
     <option value="h1">Heading 1</option>
     <option value="h2">Heading 2</option>
     <option value="h3">Heading 3</option>
   </select>
   ```

2. Add a new JavaScript function `applyParaStyle(tag)` to the JS block (place it after the refactored `applyFontColor` function):
   ```javascript
   function applyParaStyle(tag) {
     if (!tag) return;
     document.getElementById("editor").focus();
     document.execCommand("formatBlock", false, tag);
   }
   ```

Signatures required: `function applyParaStyle(tag)`

Constraints:
- Use ES5 syntax only.
- Use `class="tb-select"` to match the shared dropdown styling.
- Do not modify existing toolbar controls.
- Place the new dropdown BEFORE the existing Font Size dropdown.

Acceptance criteria:
- Dropdown visible in toolbar with 5 options (Style placeholder + 4 real options).
- Picking "Heading 1" wraps the current block in `<h1>`.
- Picking "Normal text" reverts the block to `<p>`.
- Dropdown resets to "Style" after each pick.
- Font Size dropdown still works.
--- END PROMPT T003 ---

--- IMPLEMENTATION PROMPT T004 ---
You are an expert Dart/Flutter developer with strong JavaScript knowledge.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart (editing embedded HTML + JS inside a Dart string constant)
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: Add a Font Family dropdown to the editor toolbar.

1. In the toolbar HTML, add a new `<select>` AFTER the Paragraph Style dropdown (created by T003) and BEFORE the Font Size dropdown:
   ```html
   <select onchange="applyFontFamily(this.value); this.value=''" title="Font" class="tb-select">
     <option value="" selected>Font</option>
     <option value="Calibri, 'Segoe UI', sans-serif">Calibri</option>
     <option value="Arial, sans-serif">Arial</option>
     <option value="'Times New Roman', serif">Times New Roman</option>
     <option value="Tahoma, sans-serif">Tahoma</option>
     <option value="Georgia, serif">Georgia</option>
     <option value="'Courier New', monospace">Courier New</option>
     <option value="Verdana, sans-serif">Verdana</option>
   </select>
   ```

2. Add a new JavaScript function `applyFontFamily(f)` that delegates to the shared `wrapSelectionWithStyle` helper from T001:
   ```javascript
   function applyFontFamily(f) {
     if (!f) return;
     document.getElementById("editor").focus();
     wrapSelectionWithStyle("fontFamily", f);
   }
   ```

Signatures required: `function applyFontFamily(f)`

Constraints:
- REQUIRES T001 to be complete (uses `wrapSelectionWithStyle`).
- Use ES5 syntax only.
- Use `class="tb-select"`.
- Do not modify existing toolbar controls beyond adding this new one.

Acceptance criteria:
- Dropdown visible with 7 fonts plus "Font" placeholder.
- Picking Times New Roman applies it to current selection, preserving paragraph structure.
- Works on multi-paragraph selections.
- With no selection, picking a font and typing produces text in that font (pending-style).
- Dropdown resets to "Font" after pick.
--- END PROMPT T004 ---

--- IMPLEMENTATION PROMPT T005 ---
You are an expert Dart/Flutter developer with strong JavaScript knowledge.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart (editing embedded HTML + JS inside a Dart string constant)
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: Add a Highlight Color button to the editor toolbar.

1. In the toolbar HTML, add a new `<label class="color-btn">` AFTER the existing Font Color button (which uses `id="colorSwatch"` and `id="fontColorInput"`). It should mirror the font color button structure:
   ```html
   <label class="color-btn" title="Highlight">🖍<span id="hlSwatch" style="color:#FFFF00">▇</span><input type="color" value="#FFFF00" onchange="applyHighlight(this.value); document.getElementById('hlSwatch').style.color=this.value" /></label>
   ```
   (Use a highlighter emoji or a short text label like "H" if the emoji doesn't render consistently; the swatch span shows the current highlight color.)

2. Add a new JavaScript function `applyHighlight(c)` that delegates to the shared helper from T001:
   ```javascript
   function applyHighlight(c) {
     if (!c) return;
     document.getElementById("editor").focus();
     wrapSelectionWithStyle("backgroundColor", c);
   }
   ```

Signatures required: `function applyHighlight(c)`

Constraints:
- REQUIRES T001 to be complete (uses `wrapSelectionWithStyle`).
- Use ES5 syntax only.
- Reuse the existing `.color-btn` CSS class — do not add new CSS.
- Default color is yellow `#FFFF00`.
- Do not modify the existing Font Color button.

Acceptance criteria:
- Highlight button visible next to Font Color button.
- Clicking it opens native color picker.
- Picked color is applied as `background-color` to selected text.
- Works on multi-paragraph selections.
- Swatch color updates after each pick.
- Highlights persist through save/reload and render in PDF export.
--- END PROMPT T005 ---

--- IMPLEMENTATION PROMPT T006 ---
You are an expert Dart/Flutter developer with strong JavaScript knowledge.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart (editing embedded HTML + JS inside a Dart string constant)
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: Add a Line Spacing dropdown to the editor toolbar.

1. In the toolbar HTML, add a new `<select>` after the alignment/list buttons (or after Indent/Outdent if T008 is already done):
   ```html
   <select onchange="applyLineSpacing(this.value); this.value=''" title="Line spacing" class="tb-select">
     <option value="" selected>Spacing</option>
     <option value="1">Single</option>
     <option value="1.15">1.15</option>
     <option value="1.5">1.5</option>
     <option value="2">Double</option>
   </select>
   ```

2. Add a new JavaScript function `applyLineSpacing(v)` that applies `line-height` to every block-level element intersecting the selection:
   ```javascript
   function applyLineSpacing(v) {
     if (!v) return;
     var editor = document.getElementById("editor");
     editor.focus();
     var sel = window.getSelection();
     if (!sel.rangeCount) return;
     var range = sel.getRangeAt(0);
     var blockTags = ["P", "DIV", "H1", "H2", "H3", "H4", "H5", "H6", "LI", "BLOCKQUOTE"];
     var blocks = [];
     var walker = document.createTreeWalker(editor, NodeFilter.SHOW_ELEMENT, {
       acceptNode: function(node) {
         if (blockTags.indexOf(node.nodeName) === -1) return NodeFilter.FILTER_SKIP;
         if (!range.intersectsNode(node)) return NodeFilter.FILTER_REJECT;
         return NodeFilter.FILTER_ACCEPT;
       }
     });
     var n;
     while ((n = walker.nextNode())) blocks.push(n);
     if (blocks.length === 0) {
       // Fallback: climb from common ancestor to nearest block
       var el = range.commonAncestorContainer;
       if (el.nodeType === Node.TEXT_NODE) el = el.parentNode;
       while (el && el !== editor && blockTags.indexOf(el.nodeName) === -1) el = el.parentNode;
       if (el && el !== editor) blocks.push(el);
     }
     blocks.forEach(function(b) { b.style.lineHeight = v; });
   }
   ```

Signatures required: `function applyLineSpacing(v)`

Constraints:
- Use ES5 syntax only.
- Use `class="tb-select"`.
- Do not touch existing toolbar controls.

Acceptance criteria:
- Dropdown visible with 5 options (Spacing placeholder + 4 values).
- Picking "1.5" sets `line-height: 1.5` on every block intersecting the selection.
- Multi-paragraph selections work — all blocks get the spacing.
- Cursor-only (no selection) applies to the current block.
- Dropdown resets to "Spacing" after pick.
--- END PROMPT T006 ---

--- IMPLEMENTATION PROMPT T007 ---
You are an expert Dart/Flutter developer with strong JavaScript knowledge.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart (editing embedded HTML + JS inside a Dart string constant)
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: Add a Clear Formatting button to the editor toolbar.

1. In the toolbar HTML, add a button after the Highlight button (from T005):
   ```html
   <button onclick="clearFormatting()" title="Clear formatting">⌫</button>
   ```

2. Add a new JavaScript function:
   ```javascript
   function clearFormatting() {
     document.getElementById("editor").focus();
     document.execCommand("removeFormat");
     var sel = window.getSelection();
     if (sel.rangeCount && !sel.isCollapsed) {
       document.execCommand("formatBlock", false, "p");
     }
   }
   ```

Signatures required: `function clearFormatting()`

Constraints:
- Use ES5 syntax only.
- Reuse existing `.toolbar button` CSS.
- Do not touch existing toolbar controls.

Acceptance criteria:
- Button visible in toolbar.
- Clicking it strips all inline styles (bold, underline, color, font family, font size, highlight) from selection.
- Headings in selection are reverted to `<p>`.
- Cursor-only clicks do nothing harmful (just focus the editor).
--- END PROMPT T007 ---

--- IMPLEMENTATION PROMPT T008 ---
You are an expert Dart/Flutter developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart (editing embedded HTML inside a Dart string constant)
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: Add Indent and Outdent buttons to the editor toolbar.

In the toolbar HTML, add two buttons after the list buttons (Bullets, Numbered):
```html
<button onclick="fmt('indent')" title="Increase indent">→|</button>
<button onclick="fmt('outdent')" title="Decrease indent">|←</button>
```

Signatures required: N/A (uses existing `fmt()` helper)

Constraints:
- Do not add new JS functions — use the existing `fmt()` helper.
- Reuse existing `.toolbar button` CSS.
- Place immediately after the numbered list button.

Acceptance criteria:
- Both buttons visible in toolbar.
- Clicking Indent increases paragraph indent.
- Clicking Outdent decreases it.
- Indent level persists through save/reload.
--- END PROMPT T008 ---

--- IMPLEMENTATION PROMPT T009 ---
You are an expert Dart/Flutter developer with strong JavaScript knowledge.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Dart (editing embedded HTML + JS inside a Dart string constant)
File: frontend/lib/screens/letters_v2/letter_form_tab_v2.dart
Task: Add a Zoom dropdown to the editor toolbar.

1. In the toolbar HTML, add at the END of the toolbar (last control):
   ```html
   <select id="zoomSelect" onchange="applyZoom(this.value)" title="Zoom" class="tb-select">
     <option value="0.5">50%</option>
     <option value="0.75">75%</option>
     <option value="1" selected>100%</option>
     <option value="1.25">125%</option>
     <option value="1.5">150%</option>
   </select>
   ```
   Note: unlike other dropdowns, this one does NOT reset to a placeholder — the selected zoom stays visible.

2. Add a new JavaScript function:
   ```javascript
   function applyZoom(z) {
     document.getElementById("editor").style.zoom = z;
   }
   ```

Signatures required: `function applyZoom(z)`

Constraints:
- Use ES5 syntax only.
- Use `class="tb-select"`.
- Zoom does NOT reset to placeholder — keep the picked value visible.
- Apply to `#editor` only — do NOT zoom the toolbar itself.

Acceptance criteria:
- Dropdown visible at end of toolbar with 5 zoom levels.
- 100% selected by default.
- Picking 150% scales the editor view visually.
- Picking 100% reverts.
- Saved HTML is IDENTICAL regardless of zoom level (the `zoom` CSS is applied to the DOM element's inline style but is not part of the editor's content — verify by saving and inspecting the persisted HTML).
--- END PROMPT T009 ---

--- IMPLEMENTATION PROMPT T010 ---
You are a QA engineer for a Flutter web app.
This task is manual testing only — do not modify any files.

Task: Run the full testing checklist from `specs/033-gdocs-editor-toolbar/quickstart.md`. Verify:
1. Every item in the Structural, Paragraph Style, Font Family, Highlight, Line Spacing, Clear Formatting, Indent/Outdent, Zoom, Regression, and Round-Trip Persistence sections passes.
2. Save a letter with all new formatting applied, close the browser, reopen from History → verify all formatting is preserved.
3. Export to PDF → verify headings, line spacing, highlights, and font families render correctly.

If any test fails, report the failing item and stop — do not attempt fixes blindly.

Acceptance criteria:
- All quickstart checklist items pass.
- No regressions to existing features.
- Full save/reload/PDF round-trip works.
--- END PROMPT T010 ---
