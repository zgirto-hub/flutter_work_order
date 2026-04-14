# Feature Specification: Verified Answers Admin Tab

**Feature Branch**: `057-verified-answers-tab`  
**Created**: 2026-04-14  
**Status**: Draft  
**Input**: User description: "Add a 6th admin-only tab ('Verified') to the AI Assistant screen (manual_assistant_screen.dart) that lets admins browse, search, and edit the full validated_qa library — not just flagged items."

## Clarifications

### Session 2026-04-14

- Q: When deleting a validated_qa entry, should the linked answer_ratings row be cleaned up? → A: Reset linked `answer_ratings.review_status` to `'pending'` so it re-enters the Review Queue for potential re-approval. This preserves the original user feedback.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Browse all verified answers (Priority: P1)

An administrator opens the AI Assistant screen and sees a new "Verified" tab after the existing five tabs. Tapping it loads a paginated list of all validated Q&A pairs from the `validated_qa` table, ordered by most recently updated. Each card shows the question (bold, truncated), the answer (truncated), and thumbs-up/thumbs-down counts. The admin can pull to refresh or tap a refresh button to reload the list.

**Why this priority**: This is the foundation — without the ability to see the full verified library, editing is impossible. Currently admins can only see flagged items in the Review Queue, leaving the bulk of validated Q&A invisible.

**Independent Test**: Can be fully tested by logging in as an admin, navigating to the AI Assistant screen, tapping the "Verified" tab, and verifying that all validated_qa entries appear in a scrollable list ordered by updated_at descending.

**Acceptance Scenarios**:

1. **Given** an admin is on the AI Assistant screen, **When** they tap the "Verified" tab, **Then** a paginated list of validated_qa entries loads (first 50 items) ordered by updated_at descending.
2. **Given** the list has loaded, **When** the admin scrolls to the bottom, **Then** a "Load More" button appears that fetches the next page of 50 items and appends them to the list.
3. **Given** the list is displayed, **When** the admin pulls to refresh, **Then** the list reloads from the first page with fresh data.
4. **Given** a non-admin user is on the AI Assistant screen, **When** they view the tabs, **Then** the "Verified" tab is not visible and the screen shows only 2 tabs (Chat, Knowledge).

---

### User Story 2 - Search verified answers by question text (Priority: P1)

An administrator types a search term into the search bar at the top of the Verified tab. After a brief debounce (300ms), the list filters to show only entries whose question text matches the search. Each new keystroke cancels any in-flight request before firing the next one, preventing stale results from overwriting fresher ones.

**Why this priority**: Same priority as browsing — with potentially hundreds of verified answers, search is essential for admins to find the specific Q&A they need to review or edit.

**Independent Test**: Can be tested by typing a known question keyword into the search bar and verifying the list filters to matching entries within ~300ms of the last keystroke.

**Acceptance Scenarios**:

1. **Given** the admin is on the Verified tab with entries loaded, **When** they type "hydraulic" in the search bar, **Then** after 300ms debounce the list shows only entries whose question contains "hydraulic" (case-insensitive).
2. **Given** the admin is typing quickly, **When** they type "hyd" then immediately "hydraulic pump", **Then** only the final search fires and the intermediate "hyd" request is cancelled.
3. **Given** a search is active, **When** the admin clears the search bar, **Then** the full unfiltered list reloads.
4. **Given** a search returns no results, **When** the list is empty, **Then** an appropriate empty-state message is shown.

---

### User Story 3 - Edit a verified answer's question and answer text (Priority: P1)

An administrator taps a verified answer card to open an edit dialog. The dialog shows two pre-populated text fields: one for the question, one for the validated answer. The admin edits either or both fields and taps Save. The backend updates the record — if the question text changed, it re-generates the embedding and re-extracts equipment_type/fault_code. The list item refreshes with the server-returned data (not a local patch).

**Why this priority**: This is the core purpose of the feature — allowing admins to correct or refine verified answers that are actively used by the RAG pipeline, without having to wait for the answer to be re-flagged by users.

**Independent Test**: Can be tested by tapping a verified answer, editing the question and/or answer in the dialog, saving, and verifying the list item updates with the server-returned data including any re-extracted metadata.

**Acceptance Scenarios**:

1. **Given** an admin taps a verified answer card, **When** the edit dialog opens, **Then** both the question and answer text fields are pre-populated with the current values.
2. **Given** the admin changes only the answer text, **When** they tap Save, **Then** the answer is updated but the embedding and equipment_type/fault_code are not re-generated (no unnecessary work).
3. **Given** the admin changes the question text, **When** they tap Save, **Then** the backend re-embeds the question and re-extracts equipment_type/fault_code, and the list item reflects the server-returned values.
4. **Given** the embedder service is unreachable (timeout), **When** the admin saves a question edit, **Then** a distinct SnackBar is shown: "Embedding timed out — please try again" and the edit is not persisted.
5. **Given** an edit is saved successfully, **When** the dialog closes, **Then** a success SnackBar appears and the specific list item is updated in place without reloading the entire list.

---

### User Story 4 - Delete a verified answer (Priority: P2)

An administrator decides a verified answer is no longer accurate or relevant. From the edit dialog (or via a delete button on the card), they tap Delete. A confirmation dialog appears warning that this action is permanent and the Q&A will no longer be used by the RAG pipeline. Upon confirmation, the entry is hard-deleted from the `validated_qa` table and removed from the list.

**Why this priority**: P2 because browse/search/edit are needed first, but delete is essential for maintaining a clean, accurate knowledge base. Stale or incorrect verified answers that slip past re-flagging thresholds can actively harm RAG quality.

**Independent Test**: Can be tested by tapping Delete on a verified answer, confirming the dialog, and verifying the entry disappears from the list and is no longer returned by the GET endpoint.

**Acceptance Scenarios**:

1. **Given** an admin is viewing a verified answer, **When** they tap Delete, **Then** a confirmation dialog appears with the question text and a warning that this is permanent.
2. **Given** the confirmation dialog is shown, **When** the admin confirms deletion, **Then** the entry is hard-deleted from the database, removed from the local list, and a success SnackBar is shown.
3. **Given** the confirmation dialog is shown, **When** the admin cancels, **Then** nothing happens and the entry remains.
4. **Given** a verified answer is deleted, **When** a user later asks the same question, **Then** the RAG pipeline no longer returns the deleted Q&A as a validated match.

---

### Edge Cases

- What happens when an admin submits an edit with both fields empty? The Save button should be disabled if either field is empty (both are required).
- What happens when two admins edit the same entry simultaneously? Last-write-wins — the `updated_at` timestamp will reflect the most recent save. No optimistic locking for v1.
- What happens when the validated_qa table is empty? The tab shows an empty-state message: "No verified answers yet."
- What happens when the admin edits the question to match text very similar to another existing verified answer? No duplicate detection for v1 — the admin is trusted to manage the library. The embedding similarity will naturally handle query routing.
- What happens if a search and "Load More" are combined? Search resets pagination — "Load More" fetches the next page of the current search results, not the unfiltered list.
- What happens when deleting a verified answer that was the source for a recent RAG response? The deletion is immediate — any in-progress conversation that already received the answer is unaffected, but future queries will no longer match it. The linked `answer_ratings` row has its `review_status` reset to `'pending'`, making it available for re-review in the Review Queue.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a `GET /manuals/verified-answers` endpoint (admin-only) that returns paginated validated_qa entries ordered by `updated_at` desc, with optional `search` (ilike on question_text), `limit` (default 50), and `offset` query parameters.
- **FR-002**: System MUST provide a `PUT /manuals/verified-answers/{qa_id}` endpoint (admin-only) that updates `question_text` and/or `validated_answer` on a validated_qa record.
- **FR-003**: When `question_text` is updated via the PUT endpoint, the system MUST re-generate the `question_embedding` vector using the existing `embed_single()` function and re-extract `equipment_type` and `fault_code` using existing helper functions.
- **FR-004**: When only `validated_answer` is updated (question unchanged), the system MUST NOT re-generate the embedding or re-extract metadata.
- **FR-005**: The PUT endpoint MUST update the `updated_at` timestamp on every successful edit.
- **FR-006**: The PUT endpoint MUST return a 404 if the `qa_id` does not exist, and a 504 if the embedder times out during re-embedding.
- **FR-007**: The frontend MUST display a 6th admin-only tab ("Verified") in the AI Assistant screen's TabBar, after the existing Alerts tab.
- **FR-008**: The Verified tab MUST show a search bar with 300ms debounce that cancels in-flight requests on new keystrokes.
- **FR-009**: The Verified tab MUST use "Load More" pagination (append next page to list) rather than full page replacement.
- **FR-010**: After a successful edit, the frontend MUST replace the local list item with the server-returned data (not a local patch) to reflect any re-extracted metadata.
- **FR-011**: Both endpoints MUST enforce admin-only access using the existing `_admin_check()` pattern.
- **FR-012**: Non-admin users MUST NOT see the Verified tab — their tab count remains 2 (Chat, Knowledge).
- **FR-013**: System MUST provide a `DELETE /manuals/verified-answers/{qa_id}` endpoint (admin-only) that hard-deletes the validated_qa record and resets the linked `answer_ratings.review_status` to `'pending'` so the original feedback re-enters the Review Queue.
- **FR-014**: The DELETE endpoint MUST return a 404 if the `qa_id` does not exist.
- **FR-015**: The frontend MUST show a confirmation dialog before deleting, displaying the question text and a warning that the action is permanent.

### Key Entities

- **validated_qa** (existing table): Stores admin-approved Q&A pairs with vector embeddings for RAG retrieval. Key attributes: id, question_text, validated_answer, question_embedding (vector 768), equipment_type, fault_code, validated_by, validated_at, thumbs_up_count, thumbs_down_count, is_reflagged, updated_at.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Admin can browse the complete validated_qa library without relying on the Review Queue's flagged-only filter.
- **SC-002**: Search returns matching results within 500ms of the final keystroke for libraries up to 1000 entries.
- **SC-003**: Editing a verified answer's question text triggers re-embedding and metadata re-extraction; editing only the answer text does not.
- **SC-004**: Non-admin users are completely unaffected — they see 2 tabs, no new UI elements.
- **SC-005**: All existing tab indices (0-4) and their behaviors remain unchanged after adding the 6th tab.

## Assumptions

- The `validated_qa` table already exists with all required columns — no database migration is needed.
- The `embed_single()` function from `backend/services/ollama_embedder.py` is the correct embedding function to use for re-embedding question text.
- The existing `_extract_equipment_type()` and `_extract_fault_code()` helpers in `validated_qa_service.py` are sufficient for metadata re-extraction.
- The existing `_admin_check()` helper in `manuals.py` is the correct admin authorization check.
- Pagination with limit/offset is sufficient for v1 — cursor-based pagination is not needed at current data volumes.
- Deletion is a hard delete (not soft delete) — the row is permanently removed from `validated_qa` and will no longer appear in RAG search results.
- No optimistic locking or concurrent-edit detection is needed for v1.

## Files to Modify

| File | Change |
|------|--------|
| `backend/services/validated_qa_service.py` | Add `get_all_verified_answers()`, `update_verified_answer()`, and `delete_verified_answer()` |
| `backend/routers/manuals.py` | Add `GET`, `PUT`, and `DELETE /manuals/verified-answers` endpoints with Pydantic model |
| `frontend/lib/services/manual_assistant_service.dart` | Add `getVerifiedAnswers()`, `updateVerifiedAnswer()`, and `deleteVerifiedAnswer()` |
| `frontend/lib/screens/manual_assistant/verified_answers_tab.dart` | **New file** — Verified tab widget |
| `frontend/lib/screens/manual_assistant/manual_assistant_screen.dart` | Wire in 6th admin tab, update TabController length |
