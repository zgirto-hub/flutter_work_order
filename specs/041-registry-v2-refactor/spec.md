# Feature Specification: Document Registry V2 UI Refactor

**Feature Branch**: `041-registry-v2-refactor`  
**Created**: 2026-04-12  
**Status**: Draft  
**Input**: Refactor Document Registry screen UI/UX to match the Letters v2 design pattern (expandable card list, FAB-to-pushed-form, matching visual tokens). Preserve all existing backend integration and functionality.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Browse Registry Entries with Expandable Cards (Priority: P1)

A user opens the Document Registry screen and sees a clean list of all registry entries displayed as collapsed cards. Each card shows the document name (RTL), document number, date, and a replied status badge. The user taps any card to smoothly expand it, revealing full details including attachment info and action buttons (Attach, Edit, Delete). Tapping again collapses the card. A chevron icon animates to indicate expand/collapse state.

**Why this priority**: The browsing experience is the primary interaction users have with the registry. Replacing the current flat, always-visible action buttons with expandable cards dramatically improves visual hierarchy and reduces clutter, making it the highest-value change.

**Independent Test**: Can be fully tested by loading the screen with existing entries and verifying expand/collapse behavior, card content, and visual alignment with Letters v2 cards.

**Acceptance Scenarios**:

1. **Given** the user opens Document Registry with existing entries, **When** the screen loads, **Then** all entries appear as collapsed cards showing document name (RTL-aligned), document number, date, and replied badge — with no action buttons visible.
2. **Given** a collapsed card, **When** the user taps anywhere on the card, **Then** the card smoothly expands (240ms, easeInOutCubic) revealing full details and action buttons, and the chevron rotates 180 degrees.
3. **Given** an expanded card, **When** the user taps the card again, **Then** it collapses with the reverse animation and action buttons disappear.
4. **Given** an expanded card, **When** the user taps a different card, **Then** the previously expanded card collapses and the newly tapped card expands (only one card expanded at a time).
5. **Given** the entry list is displayed, **When** the user pulls down on the list, **Then** a RefreshIndicator triggers and the list reloads from the backend.
6. **Given** no entries exist (or search yields no results), **When** the screen renders, **Then** an EmptyState widget displays with an appropriate icon, title, and subtitle.

---

### User Story 2 - Create New Registry Entry via Pushed Form (Priority: P1)

A user wants to add a new document registry entry. They tap the floating action button (FAB) on the main list screen, which pushes a full-screen form view. The form contains fields for document name, document number, date picker, and replied checkbox, plus an "Extract from PDF" button. After filling in the form, the user taps "Add Entry" to save. The form dismisses and the list refreshes to show the new entry.

**Why this priority**: Separating the creation form from the browsing view is the core architectural change of this refactor, eliminating the current mixed form-and-list layout. This is equally critical to the card list for delivering the Letters v2 pattern.

**Independent Test**: Can be fully tested by tapping the FAB, filling in form fields, submitting, and verifying the new entry appears in the list after the form dismisses.

**Acceptance Scenarios**:

1. **Given** the user is on the main list view, **When** they tap the FAB, **Then** a full-screen form view is pushed onto the navigation stack with a header reading "Create Document Entry".
2. **Given** the form is open in create mode, **When** the user fills all required fields and taps "Add Entry", **Then** the entry is created via the existing backend service, the form dismisses, and the list refreshes to include the new entry.
3. **Given** the form is open, **When** the user taps the back button or navigates back, **Then** the form dismisses without saving and returns to the list view.
4. **Given** the form is open in create mode, **When** the user taps "Extract from PDF", **Then** a file picker opens for PDF selection, and on success the document name, number, and date fields are auto-populated, with a pending attachment chip displayed.
5. **Given** the user extracted fields from a PDF (with pending attachment), **When** they submit the form, **Then** the entry is created AND the pending PDF file is uploaded as an attachment.
6. **Given** required fields are empty, **When** the user taps submit, **Then** validation errors display on the relevant fields and submission is blocked.

---

### User Story 3 - Edit Existing Entry via Pushed Form (Priority: P2)

A user wants to modify an existing registry entry. From an expanded card's action buttons, they tap "Edit". A full-screen form view is pushed, pre-filled with the entry's current data. After making changes, they tap "Save Changes" to update. The form dismisses and the list refreshes.

**Why this priority**: Editing is a secondary but essential flow. It depends on both the expandable card (to access the Edit button) and the pushed form architecture, so it naturally follows P1 stories.

**Independent Test**: Can be tested by expanding an entry card, tapping Edit, modifying a field, saving, and verifying the updated data appears in the list.

**Acceptance Scenarios**:

1. **Given** a card is expanded, **When** the user taps the "Edit" action button, **Then** a full-screen form pushes with header "Edit Entry" and all fields pre-filled with the entry's current values.
2. **Given** the edit form is open, **When** the user changes a field and taps "Save Changes", **Then** the entry updates via the existing backend service, the form dismisses, and the list refreshes with updated data.
3. **Given** the edit form is open, **When** the user taps back without saving, **Then** no changes are persisted and the list remains unchanged.

---

### User Story 4 - Manage Attachments and Delete Entries from Expanded Cards (Priority: P2)

A user manages entry attachments and deletions through action buttons in the expanded card state. They can attach a file, view/download existing attachments, remove attachments, or delete an entry entirely with a confirmation dialog.

**Why this priority**: These are supporting actions that rely on the expandable card infrastructure. They preserve existing functionality in the new UI pattern.

**Independent Test**: Can be tested by expanding cards and using Attach, Delete actions, and interacting with attachment rows.

**Acceptance Scenarios**:

1. **Given** an expanded card without an attachment, **When** the user taps "Attach", **Then** a file picker opens and on selection the file uploads via the existing service, and the card updates to show the attachment.
2. **Given** an expanded card with an attachment, **When** the user taps the attachment name, **Then** the file opens in an external application via its download URL.
3. **Given** an expanded card, **When** the user taps "Delete", **Then** a styled confirmation dialog appears matching the Letters v2 delete dialog pattern.
4. **Given** the delete confirmation dialog is shown, **When** the user confirms, **Then** the entry is deleted via the backend service and removed from the list.
5. **Given** the delete confirmation dialog is shown, **When** the user cancels, **Then** the dialog closes and no action is taken.

---

### User Story 5 - Search and Filter Registry Entries (Priority: P3)

A user searches for specific registry entries using the search bar at the top of the list view. The search filters entries by document name or document number in real-time as the user types.

**Why this priority**: Search is an existing feature that simply moves position (from above the form to the list header). Its functionality is preserved unchanged.

**Independent Test**: Can be tested by typing in the search bar and verifying the list filters correctly by name and number.

**Acceptance Scenarios**:

1. **Given** the list view is displayed, **When** the user types in the search bar, **Then** entries filter in real-time by document name or document number.
2. **Given** search is active with results, **When** the user clears the search field, **Then** all entries reappear.
3. **Given** search yields no results, **When** the list is empty, **Then** the EmptyState widget shows with a "No matching entries" message.

---

### Edge Cases

- What happens when the user submits the form while the backend is slow or unreachable? A loading indicator displays on the submit button and an error snackbar appears on failure.
- What happens when the user navigates back from the form while a submission is in progress? The save operation completes in the background; if it fails, the error is silently discarded since the user left the form.
- What happens when an attachment upload fails after entry creation? The entry is still created but without an attachment; an error snackbar informs the user.
- What happens when the app resumes from background? The entry list reloads automatically via the existing lifecycle observer.
- What happens when the user rapidly taps multiple cards? Only the most recently tapped card expands; previous expansion collapses via the single-expanded-index pattern.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The main screen MUST display only a list of registry entries and a floating action button — no inline form.
- **FR-002**: The FAB MUST use the ClaudeFAB widget and push a full-screen form view when tapped.
- **FR-003**: Each entry MUST render as an expandable card with collapse/expand animation (240ms, easeInOutCubic curve).
- **FR-004**: Collapsed cards MUST show: document name (RTL text direction), document number, date, and replied badge.
- **FR-005**: Expanded cards MUST reveal: full entry details, attachment info (if present), and action buttons (Attach, Edit, Delete).
- **FR-006**: Only one card MUST be expanded at a time; expanding a new card collapses the previous one.
- **FR-007**: The chevron icon MUST animate rotation (0-180 degrees) synchronized with expand/collapse.
- **FR-008**: Action buttons MUST only be visible in the expanded state.
- **FR-009**: The "Edit" action MUST push a full-screen form pre-filled with the entry's data; header reads "Edit Entry".
- **FR-010**: The form screen MUST include fields for document name, document number, date picker, replied checkbox, and a submit button.
- **FR-011**: The create form MUST include an "Extract from PDF" button that auto-populates fields and stores a pending attachment.
- **FR-012**: After successful form submission (create or edit), the form MUST dismiss and the list MUST refresh using the UniqueKey pattern.
- **FR-013**: The "Delete" action MUST show a styled confirmation dialog before proceeding with deletion.
- **FR-014**: The list MUST support pull-to-refresh via RefreshIndicator.
- **FR-015**: An EmptyState widget MUST display when there are no entries or when search yields no results.
- **FR-016**: Search filtering MUST remain in the list view header (not in the form).
- **FR-017**: The screen MUST refresh entries on app lifecycle resume (existing behavior preserved).
- **FR-018**: All existing backend service methods (create, read, update, delete, extract, attach, remove attachment) MUST be preserved without modification.
- **FR-019**: Visual styling MUST match Letters v2 design tokens: 14px border radius, 0.5px border width, 14px card padding, consistent color scheme, 13px card titles (weight 500), 11px metadata (weight 500).

### Key Entities

- **Registry Entry**: A document record with document name, document number, date, replied status, and optional file attachment (name + URL). Identified by a unique ID, tracks creator and creation timestamp.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can create a new registry entry end-to-end (FAB tap to saved entry visible in list) in under 30 seconds with no navigational confusion.
- **SC-002**: Users can locate and expand a specific entry from a list of 50+ entries in under 5 seconds using search and expand interaction.
- **SC-003**: Card expand/collapse animations complete smoothly with no visible frame drops or jitter on target devices.
- **SC-004**: 100% of existing functionality (create, edit, delete, attach, detach, PDF extraction, search, lifecycle refresh) remains operational after the refactor.
- **SC-005**: The Document Registry screen is visually indistinguishable in design language (colors, spacing, typography, animation style) from the Letters v2 screen when compared side-by-side.
- **SC-006**: Users experience zero data loss — all existing registry entries and attachments remain accessible and unmodified after deployment.

## Assumptions

- The existing DocumentRegistryService methods and return types will remain unchanged and require no modifications.
- The existing RegistryEntry model has all fields needed for the new card display (documentName, documentNumber, date, replied, fileName, fileUrl, hasAttachment).
- The ClaudeFAB and EmptyState widgets are available from existing shared widget libraries already used in Letters v2.
- Backend endpoints for document registry operations remain stable and require no changes.
- The refactor is frontend-only; no database schema changes are needed.
- The app's theme system (AppColors, AppTheme) already includes all color tokens referenced in the Letters v2 pattern.
- The ValidatedTextField widget used in the current form will continue to be used in the new pushed form screen.
- RTL text direction for document names is a display-only concern (the stored data is unchanged).
