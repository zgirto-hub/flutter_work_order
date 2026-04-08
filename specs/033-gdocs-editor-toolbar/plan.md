# Implementation Plan: Google Docs–Style Toolbar for Letter Editor

**Branch**: `033-gdocs-editor-toolbar` | **Date**: 2026-04-08 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/033-gdocs-editor-toolbar/spec.md`

## Summary

Enrich the existing iframe-based WYSIWYG letter editor with 7 new toolbar controls (paragraph style, font family, line spacing, highlight color, clear formatting, indent/outdent, zoom) while refactoring the existing font-size/font-color logic into a shared `wrapSelectionWithStyle()` helper. All changes live inside a single Dart string constant (`_editorHtml`) in [frontend/lib/screens/letters_v2/letter_form_tab_v2.dart](frontend/lib/screens/letters_v2/letter_form_tab_v2.dart). No backend, database, or new dependency changes.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x (embedded HTML5 / JS ES5 inside string constant)
**Primary Dependencies**: Flutter Material (existing), browser-native `document.execCommand`, `Range`, `TreeWalker`, CSS `zoom`
**Storage**: N/A — all state lives in editor DOM; persists as inline HTML via existing letters_v2 save pipeline
**Testing**: Manual end-to-end testing in Chromium (PWA target)
**Target Platform**: Web (PWA) — Chromium-based browsers only (Chrome, Edge)
**Project Type**: Web application (frontend-only change)
**Performance Goals**: Toolbar actions feel instant (<50ms perceived). No impact on letter save/load latency.
**Constraints**: Chromium-only (CSS `zoom`, `execCommand` deprecation tolerated since app targets modern Chromium). Must not regress existing editor functionality.
**Scale/Scope**: Single-file edit to one Dart file. ~250 lines of HTML/CSS/JS added inside `_editorHtml`, ~120 lines removed (refactor duplication).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS (frontend-only justified) | Feature adds zero persistent state, no API surface, no schema. All changes are inline CSS/HTML emitted by the existing save pipeline. Backend and DB layers are intentionally untouched — no ghost endpoints or orphaned UI risk. |
| II. Explicit Over Automatic | PASS | All formatting is user-triggered (click button / pick dropdown). Zoom is view-only. No silent auto-formatting. |
| III. Role-Based Access Control | PASS | Inherits existing letter-form role gates. No new permissions needed. |
| IV. Server-First File Storage | N/A | No files involved. |
| V. Client-Side Computation | PASS | Entirely client-side — no API calls added. |
| VI. Audit Everything | N/A | Pure editor UI change. The letter save itself is already audited. |
| VII. Simplicity & YAGNI | PASS | Refactor reduces duplication (~60 lines per existing function → shared helper). New controls reuse the helper for consistency. No speculative abstractions. |

**Post-Phase 1 Re-check**: All gates still pass. No new storage, no new roles, no new dependencies.

## Project Structure

### Documentation (this feature)

```text
specs/033-gdocs-editor-toolbar/
├── plan.md              # This file
├── spec.md              # Feature spec
├── research.md          # Phase 0 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
frontend/
└── lib/
    └── screens/
        └── letters_v2/
            └── letter_form_tab_v2.dart    # SINGLE FILE — modify _editorHtml constant
```

**Structure Decision**: Single-file change. The `_editorHtml` constant (around lines 1255–1470) contains the entire toolbar HTML, CSS, and JS. All 9 phases operate on different regions of this constant.

No `data-model.md` or `contracts/` — this feature has no entities and no API surface.

## Complexity Tracking

No constitution violations. Table intentionally empty.
