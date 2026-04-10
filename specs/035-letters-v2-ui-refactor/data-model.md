# Data Model: Letters V2 UI/UX Refactor

**Date**: 2026-04-10  
**Feature**: 035-letters-v2-ui-refactor

## No Data Model Changes

This feature is a purely visual/UX refactor. No database tables, columns, relationships, or data entities are created, modified, or removed.

### Existing Entities (unchanged)

- **GeneratedLetter**: Existing model used by the letter form and history list. No field additions or changes required.
- **PaymentCertificate**: Linked to letters via `letter_id` FK. No changes.

### State Management (in-memory only)

The refactor introduces no new persistent state. The following transient UI state is added or modified:

- **Tab active index**: Already exists as `_tabIndex` integer; interaction model changes from segmented-tap to bottom-border-tap (no data impact).
- **Focus node tracking**: New `FocusNode` instances for form fields to support iOS PWA keyboard scroll handling. Disposed on widget dispose. No persistence.
- **Loading button state**: Boolean flags per action button (e.g., `_isGenerating`, `_isSaving`). Already partially exist; will be standardized.
