# Tasks: System Status Cards Redesign

**Input**: Design documents from `/specs/001-status-cards-redesign/`
**Prerequisites**: plan.md (required), spec.md (required), research.md
**Target file**: `frontend/lib/screens/system_status_screen.dart`

**Important**: ALL changes are in a single file. Tasks are ordered so
each one builds on the previous. Do NOT create new files. Do NOT change
any backend code, models, or services. Read the file first before making
any edits.

---

## Phase 1: Setup

**Purpose**: Read and understand the target file before making changes.

- [x] T001 Read the full file `frontend/lib/screens/system_status_screen.dart` to understand the current widget structure. Identify the three private widget classes that will be modified: `_SystemCard` (around line 1151), `_ExpandableGroup` (around line 1004), and `_HistoryCard` (around line 1251). Do NOT make any changes yet.

**Checkpoint**: You understand the current layout of all three widgets.

---

## Phase 2: User Story 1 — Compact System Status Cards (Priority: P1) MVP

**Goal**: Make `_SystemCard` single-row and increase grid aspect ratio so 50%+ more cards fit above the fold.

**Independent Test**: Open the System Status page — all system cards should be noticeably shorter, displaying name + SAT tag + status text + status dot all on ONE row.

### Implementation for User Story 1

- [x] T002 [US1] In the `_SystemCard.build()` method in `frontend/lib/screens/system_status_screen.dart`, convert the two-row Column layout into a single Row. Currently the widget has a Column with: (1) a Row containing the name, optional SAT tag, and status dot, then (2) a SizedBox(height: 4), then (3) a Container with the "OK"/"Issue" status badge text. **Remove the Column wrapper**, the `SizedBox(height: 4)`, and the standalone status badge Container below it. Instead, make the entire card body a single Row containing: the name Text (Expanded, with ellipsis overflow), then the optional SAT tag Container, then a small status text label (the "OK" or "Issue" text styled with fontSize 8, fontWeight w600, the same `statusColor`, no background container — just plain colored text), then a SizedBox(width: 4), then the status dot Container (7x7 circle). Also change the outer Container padding from `EdgeInsets.all(8)` to `EdgeInsets.symmetric(horizontal: 8, vertical: 5)`. Remove `mainAxisAlignment: MainAxisAlignment.center` from the Column since Column is gone.

- [x] T003 [US1] In the `_SystemStatusScreenState.build()` method in `frontend/lib/screens/system_status_screen.dart`, find the main GridView.builder (around line 938) and change its `childAspectRatio` from `1.6` to `3.0`. This makes each grid cell wider and shorter, matching the new single-row card layout. Keep `crossAxisCount: 3` and spacing values unchanged.

- [x] T004 [US1] In the same file, find the GridView.builder inside `_ExpandableGroup.build()` (inside the SizeTransition → FadeTransition → Padding → GridView.builder, around line 1125-1133) and change its `childAspectRatio` from `1.6` to `3.0` to match the main grid. This ensures grouped sub-system cards also use the compact layout.

**Checkpoint**: System cards are now single-row, ~42% shorter. All info retained.

---

## Phase 3: User Story 2 — Compact Expandable Group Sections (Priority: P2)

**Goal**: Tighten the expandable group header and spacing between groups.

**Independent Test**: Expand a group section — the header should be slightly shorter and the gap between groups reduced.

### Implementation for User Story 2

- [x] T005 [US2] In the `_ExpandableGroup.build()` method in `frontend/lib/screens/system_status_screen.dart`, find the header Container's padding (currently `EdgeInsets.symmetric(horizontal: 12, vertical: 10)`) and change it to `EdgeInsets.symmetric(horizontal: 10, vertical: 7)`. This reduces the group header height.

- [x] T006 [US2] In `_SystemStatusScreenState.build()` in the same file, find the `SizedBox(height: 12)` that appears before each `_ExpandableGroup` (around line 958, inside the `for` loop over `_groupedSystems.entries`) and change the height from `12` to `8`.

- [x] T007 [US2] In the same `_ExpandableGroup.build()` method, find the Padding inside the SizeTransition that wraps the GridView (around line 1123, `padding: const EdgeInsets.only(top: 10)`) and change `top: 10` to `top: 6`.

**Checkpoint**: Expandable groups are more compact. Animations still work.

---

## Phase 4: User Story 3 — Compact Recent Issues List (Priority: P3)

**Goal**: Reduce vertical space of each history card by consolidating rows and reducing padding.

**Independent Test**: Scroll to "Recent Issues" — each entry should be noticeably shorter while still showing system name, date, status, notes, and the action menu.

### Implementation for User Story 3

- [x] T008 [US3] In the `_HistoryCard.build()` method in `frontend/lib/screens/system_status_screen.dart`, make these padding/margin changes: (1) Change the outer Container margin from `EdgeInsets.only(bottom: 8)` to `EdgeInsets.only(bottom: 5)`. (2) Change the outer Container padding from `EdgeInsets.all(12)` to `EdgeInsets.symmetric(horizontal: 10, vertical: 7)`.

- [x] T009 [US3] In the same `_HistoryCard.build()` method, change the status dot size from `width: 8, height: 8` to `width: 6, height: 6`. Also change the SizedBox after the dot from `width: 10` to `width: 8`.

- [x] T010 [US3] In the same `_HistoryCard.build()` method, reduce font sizes: (1) System name `fontSize: 13` → `fontSize: 12`. (2) Date `fontSize: 11` → `fontSize: 10`. (3) Notes text `fontSize: 12` → `fontSize: 11`. (4) Status label ("Resolved"/"Unresolved") `fontSize: 11` → `fontSize: 10`.

- [x] T011 [US3] In the same `_HistoryCard.build()` method, move the status label ("Resolved"/"Unresolved") inline into the name row instead of being a separate row at the bottom. Currently the Column inside Expanded has: Row (name + date + menu), optional notes, then a status label Text. Move the status label into the top Row, between the system name Text and the Spacer. Wrap the status label in a Container with `padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1)`, `decoration` with `color: isResolved ? Color(0xFFDCFCE7) : Color(0xFFFEE2E2)`, `borderRadius: BorderRadius.circular(3)`. The text inside should be `isResolved ? 'Resolved' : 'Unresolved'` with `fontSize: 8, fontWeight: FontWeight.w600, color: isResolved ? Color(0xFF15803D) : Color(0xFFB91C1C)`. Add a `SizedBox(width: 6)` between the name Text and this badge. Remove the old standalone status label Text and its preceding `SizedBox(height: 2)` from the bottom of the Column.

**Checkpoint**: History cards are ~33% shorter. All info and interactions preserved.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final spacing adjustment and verification.

- [x] T012 In `_SystemStatusScreenState.build()` in `frontend/lib/screens/system_status_screen.dart`, find the `SizedBox(height: 24)` between the groups section and the "Recent Issues" header (around line 974) and change it to `SizedBox(height: 16)`.

- [x] T013 In the same build method, find the `SizedBox(height: 10)` between the "Recent Issues" title and the first history card (around line 987) and change it to `SizedBox(height: 8)`.

- [ ] T014 Visually verify the complete page in a browser at 1280x800 viewport: (1) All system cards show name, optional SAT tag, status text, and status dot on one row. (2) Expandable groups expand/collapse with animation. (3) History cards show name, inline status badge, date, menu, and optional notes. (4) No text is cut off (except long names which should show ellipsis). (5) Color scheme unchanged: green (#15803D) for OK/Resolved, red (#B91C1C) for Issue/Unresolved, amber (#B45309/#FEF3C7) for SAT tag.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: Read file — no code changes
- **Phase 2 (US1)**: T002 → T003 → T004 (sequential, same-file edits that build on each other)
- **Phase 3 (US2)**: Depends on Phase 2 completion (aspect ratio already changed). T005, T006, T007 are sequential.
- **Phase 4 (US3)**: Independent of Phase 2/3 (different widget). T008 → T009 → T010 → T011 (sequential).
- **Phase 5 (Polish)**: Depends on all previous phases.

### Important Notes for Implementation

- ALL tasks edit the same file: `frontend/lib/screens/system_status_screen.dart`
- Do NOT run tasks in parallel — they modify the same file and line numbers will shift after each edit
- After each task, the line numbers in subsequent tasks may have shifted — use the widget/method names and code patterns described to locate the correct positions
- Do NOT add new files, imports, or dependencies
- Do NOT modify any bottom-sheet modals, chart widgets, or service/model code
- Preserve ALL existing GestureDetector/onTap handlers and PopupMenuButton interactions
