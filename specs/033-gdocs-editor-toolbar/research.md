# Research: 033-gdocs-editor-toolbar

**Date**: 2026-04-08

## Decision 1: Shared Style-Wrapping Helper

**Decision**: Extract a new JS function `wrapSelectionWithStyle(styleProp, styleVal)` that:
- Handles collapsed selection → inserts zero-width-space marker span (pending-style pattern)
- Handles range selection → walks text nodes via `TreeWalker`, splits at boundaries, wraps each slice in a `<span style="...">`.
- Reuses the existing text-node-walker logic already proven in `applyFontSize()` and `applyFontColor()`.

Refactor `applyFontSize(s)` → `wrapSelectionWithStyle("fontSize", s + "pt")`.
Refactor `applyFontColor(c)` → update swatch, then `wrapSelectionWithStyle("color", c)`.

**Rationale**: The existing `applyFontSize` and `applyFontColor` duplicate ~60 lines of identical logic. Adding Font Family and Highlight without consolidation would create four copies of the same code, guaranteeing divergence. Extracting the helper now is a small refactor that enables the new features with zero duplication.

**Alternatives considered**:
- Keep the duplication, add two more duplicates for font family and highlight: rejected (4× maintenance burden).
- Use `document.execCommand("fontName")` / `execCommand("backColor")`: rejected — these produce inconsistent output across browsers, don't handle block-spanning selections reliably, and can't do pending-style at cursor.

## Decision 2: Paragraph Style (Headings) via `formatBlock`

**Decision**: Use `document.execCommand("formatBlock", false, tag)` where `tag` ∈ `{p, h1, h2, h3}`.

**Rationale**: Native Chromium support, handles block replacement correctly (wraps the current block in the target tag), and works naturally with the undo stack. No custom DOM manipulation needed.

**Alternatives considered**:
- Manual DOM walking to wrap blocks: rejected — duplicates what `execCommand` already does well.

## Decision 3: Line Spacing via Block-Level `line-height`

**Decision**: New function `applyLineSpacing(v)` walks via `TreeWalker` with `SHOW_ELEMENT` filter, accepts only block-level tags (`P`, `DIV`, `H1–H6`, `LI`, `BLOCKQUOTE`) that intersect the selection range, and sets `element.style.lineHeight = v` on each.

**Rationale**: `line-height` is a block-level property. Setting it on inline spans doesn't propagate. Walking blocks in the range gives the correct result for both single-paragraph and multi-paragraph selections. Fallback: if the walker finds no blocks (e.g., cursor in a bare text node), climb the ancestor chain until the first block-level element is found.

**Alternatives considered**:
- Apply to the whole editor: rejected — too broad; users expect it to apply to the selection.
- Apply via inline span with display:block: rejected — corrupts HTML structure.

## Decision 4: Clear Formatting Scope

**Decision**: `clearFormatting()` runs two commands in sequence:
1. `document.execCommand("removeFormat")` — strips inline styles (bold, italic, underline, color, background, fontSize, fontFamily).
2. `document.execCommand("formatBlock", false, "p")` — converts the selected block(s) back to `<p>`.

**Rationale**: `removeFormat` alone doesn't touch block-level elements (a heading stays a heading). The second call ensures Clear Formatting fully resets the selection to plain body text, matching Google Docs behavior.

**Alternatives considered**:
- Only `removeFormat`: rejected — leaves headings intact, confusing for users.
- Custom DOM walker that strips everything: rejected — more code for the same result.

## Decision 5: Zoom Implementation

**Decision**: Set `document.getElementById("editor").style.zoom = value` directly.

**Rationale**: CSS `zoom` is a Chromium-supported property that scales visually without affecting the DOM or the serialized HTML. Exactly what's needed for view-only zoom. The editor target is a PWA running in Chromium browsers, so cross-browser concerns are moot.

**Alternatives considered**:
- `transform: scale()`: rejected — shrinks/grows the container's reserved space in the layout, causing scroll issues and hit-testing bugs.
- Flutter-level zoom wrapper: rejected — adds Dart code for a purely visual tweak that belongs in the editor iframe.

## Decision 6: Dropdown Reset After Selection

**Decision**: All new dropdowns use `onchange="applyFoo(this.value); this.value=''"` pattern so the visible text returns to the placeholder after each pick. Zoom is the exception — it's stateful, so the picked value stays visible.

**Rationale**: Already proven in the existing Font Size dropdown. Allows users to reapply the same value multiple times (otherwise re-selecting the current value would not trigger `onchange`).

## Decision 7: Shared CSS Class `.tb-select`

**Decision**: Add a new CSS class `.tb-select` for all dropdown selects. Update the existing `.fontsize-select` selector to `.tb-select` (rename).

**Rationale**: Unifies styling across Style, Font, Size, Spacing, Zoom dropdowns. Avoids drift.

**Alternatives considered**:
- Keep `.fontsize-select` and add a second class: rejected — two CSS classes for the same visual result is noise.

## Decision 8: Highlight Color Default Value

**Decision**: Yellow `#FFFF00` as the initial highlight color, matching Google Docs.

**Rationale**: Universally recognized highlighter color. Users expect yellow for highlights.
