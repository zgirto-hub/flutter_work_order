# Feature Specification: Verified Tab Sort Toggle

**Feature Branch**: `081-verified-sort-toggle`
**Created**: 2026-04-18
**Status**: Draft
**Input**: User description: "Add a sort toggle to the Verified tab so admins can order cached answers by most-recent (current default), most-used (👍 count DESC), or most-problematic (👎 count DESC). Entries with zero votes are hidden when sorting by usage/problems."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Surface Greatest-Hits for Paraphrase Investment (Priority: P1)

An admin opens the Verified tab and changes the sort dropdown from "Most recent" to "Most used." The list re-orders to show the top thumbs-up entries first; entries with zero thumbs-up votes are hidden. The admin identifies the top 5 most-used answers and notes which ones deserve more paraphrase variants to capture more incoming question phrasings.

**Why this priority**: The existing Verified tab shows every cached answer ordered by update time. An admin has no way to distinguish an entry that served 50 technicians from one that was inserted once and never matched again. Surfacing high-use entries concentrates admin attention where it has the most leverage.

**Independent Test**: From a fresh Verified tab view, change sort to "Most used." Verify that (a) entries are ordered by `thumbs_up_count` descending, (b) no entry with `thumbs_up_count = 0` appears in the list, (c) the count badge at the top reflects only the filtered subset, and (d) pagination continues to work across the filtered list.

**Acceptance Scenarios**:

1. **Given** the admin is on the Verified tab with the default "Most recent" sort, **When** they change the dropdown to "Most used", **Then** the list re-fetches and shows entries with `thumbs_up_count > 0` ordered by `thumbs_up_count DESC`, then by `updated_at DESC` as tie-breaker.
2. **Given** the admin is viewing "Most used", **When** no verified entries have any thumbs-up votes yet, **Then** an empty-state message reads "No verified answers have thumbs-up votes yet."
3. **Given** the admin is viewing "Most used" and scrolls to the bottom, **When** more than one page of results exists, **Then** pagination fetches the next page with the same sort and filter applied.
4. **Given** the admin has typed a search term, **When** they change the sort, **Then** the search filter is preserved and ANDed with the sort's zero-vote filter.

---

### User Story 2 - Catch Problematic Answers Before Re-flag Threshold (Priority: P2)

An admin opens the Verified tab and changes the sort dropdown to "Most problematic." The list shows entries ordered by thumbs-down count descending, hiding any entry with zero thumbs-down votes. The admin spots entries trending toward the auto-reflag threshold (30% thumbs-down with ≥3 total votes) and proactively corrects them before they get auto-flagged back to the Review queue.

**Why this priority**: Re-flagging currently only fires after ≥3 total votes AND >30% thumbs-down ratio. An entry at 1👎/2👍 is sub-threshold but worth admin attention. "Most problematic" gives early visibility into degrading entries without waiting for auto-reflag.

**Independent Test**: Seed a few validated_qa rows with varying thumbs-down counts. Open "Most problematic" sort. Verify rows are ordered by `thumbs_down_count DESC` and that entries with `thumbs_down_count = 0` are absent from the list.

**Acceptance Scenarios**:

1. **Given** the admin is on the Verified tab, **When** they select "Most problematic", **Then** entries are ordered by `thumbs_down_count DESC, updated_at DESC`, with `thumbs_down_count = 0` entries hidden.
2. **Given** the admin is viewing "Most problematic", **When** no verified entries have thumbs-down votes, **Then** an empty-state message reads "No verified answers have thumbs-down votes yet."
3. **Given** an entry in the "Most problematic" list is already auto-reflagged (`is_reflagged = true`), **When** the admin views it, **Then** it renders with the same re-flagged visual treatment it has on the current Verified tab (no new styling required).

---

### User Story 3 - Preserve Current Default Behavior (Priority: P3)

An admin who does not touch the sort dropdown sees the exact same Verified tab list they see today — ordered by `updated_at DESC`, showing all entries regardless of vote counts. The default selection is "Most recent".

**Why this priority**: The existing screen is how admins currently browse the cache. The sort toggle is additive; no existing workflow should regress.

**Independent Test**: Load the Verified tab without interacting with the sort dropdown. Confirm the list is identical (same rows, same order, same total count) to the current production behavior.

**Acceptance Scenarios**:

1. **Given** the admin opens the Verified tab, **When** they do not change the sort, **Then** the list is ordered by `updated_at DESC` and includes all entries (no vote filter applied).
2. **Given** the sort is set to "Most recent", **When** the admin changes a search term or paginates, **Then** the behavior matches today's Verified tab exactly.

---

### Edge Cases

- Sort change while a page of results is loading: pending request should be ignored; only the latest sort's results render.
- Sort change resets pagination offset to 0 (changing sort implicitly changes the result set).
- Invalid `sort` value sent from a tampered client: backend rejects with 400.
- Search + sort combined: both filters are ANDed. Example: search "backup" + "Most problematic" returns entries containing "backup" AND `thumbs_down_count > 0` ordered by `thumbs_down_count DESC`.
- Count badge at top ("36 verified answers") always reflects the filtered-and-searched total, not the total in the table.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Verified tab MUST present a sort dropdown with three options: "Most recent" (default), "Most used", "Most problematic".
- **FR-002**: "Most recent" MUST order entries by `updated_at DESC` with no vote-count filter.
- **FR-003**: "Most used" MUST order entries by `thumbs_up_count DESC, updated_at DESC` and MUST hide entries where `thumbs_up_count = 0`.
- **FR-004**: "Most problematic" MUST order entries by `thumbs_down_count DESC, updated_at DESC` and MUST hide entries where `thumbs_down_count = 0`.
- **FR-005**: Sort and search filters MUST be combinable (ANDed).
- **FR-006**: Changing the sort dropdown MUST reset pagination offset to 0.
- **FR-007**: The result count shown above the list MUST reflect the filtered+searched total, not the unfiltered table total.
- **FR-008**: Empty-state messages MUST be sort-specific: "Most used" → "No verified answers have thumbs-up votes yet."; "Most problematic" → "No verified answers have thumbs-down votes yet."; "Most recent" keeps the current empty state.
- **FR-009**: The backend endpoint MUST validate the `sort` query parameter against the allowed set `{recent, most_used, most_problematic}` and reject unrecognized values with HTTP 400.
- **FR-010**: The existing card rendering MUST NOT change; the `👍 N 👎 M` counters are already the signal the admin needs when sorting by those axes.

### Non-functional Requirements

- **NFR-001**: No schema changes, no migrations, no new tables.
- **NFR-002**: No new backend endpoints; extend the existing `/manuals/verified-answers` endpoint with a `sort` query parameter.
- **NFR-003**: The sort filter MUST apply at the database layer (Supabase query), not client-side, to keep pagination math correct.
- **NFR-004**: The count query MUST apply the same WHERE filter as the data query so "N verified answers" matches the list.

### Out of Scope

- No re-flag logic changes.
- No new tabs or sub-sections; this is a one-control addition to the existing Verified tab.
- No export, bulk edit, or bulk delete on the sorted view.
- No time-windowed stats (e.g., "most used this week"). Only lifetime counts.
- No card visual changes; the existing `👍 N 👎 M` rendering is sufficient.
- No change to how votes are cast or counted (that logic lives in `update_validated_rating` and is untouched).
- No change to the Train AI tab or its "From Real Usage" suggestions.

## Key Entities *(include if feature involves data)*

- **validated_qa** (existing, unchanged): Columns `thumbs_up_count`, `thumbs_down_count`, `updated_at` are the sort/filter axes. No new columns.

## Success Criteria *(mandatory)*

- **SC-001**: An admin can switch between the three sorts on the Verified tab and the list re-orders within one request round-trip.
- **SC-002**: "Most used" and "Most problematic" lists never show rows with zero on their respective axis.
- **SC-003**: Default view (no sort change) is byte-identical to the current Verified tab list for the same dataset.
- **SC-004**: Pagination continues to work correctly across all three sort modes.
- **SC-005**: Search + sort combinations return the correct intersection.
