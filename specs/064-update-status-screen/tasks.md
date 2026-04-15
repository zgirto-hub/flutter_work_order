---
description: "Task list for spec 064 — System Status infra compatibility cleanup"
---

# Tasks: System Status — Infrastructure Compatibility

**Input**: Design documents from `/specs/064-update-status-screen/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

---

## ⚠️ Implementer instructions (opencode, read this first)

**You are implementing a single-file Flutter refactor on a worktree-locked branch.**

1. **Worktree + branch lock**: You are in `c:\Development\flutter_work_order_spec064` on branch `064-update-status-screen`. **Do not** `cd` elsewhere, **do not** `git checkout`, **do not** `git worktree ...`, **do not** push. The sibling worktree at `c:\Development\flutter_work_order` is off-limits.
2. **Single file touched**: Every code task below modifies only `frontend/lib/screens/system_status_screen.dart`. If you find yourself editing any other file, stop and ask.
3. **This is a deletion-only refactor.** You are removing dead code; you are not adding features, abstractions, comments, or tests. Do not "improve" adjacent code while you're in the file. YAGNI is a hard rule here (constitution VII).
4. **Preserve exactly**:
   - The `StatefulWidget` class name, its `State` class name, and `Widget build(...)` signature
   - All `_show*Sheet` helpers (`_showReportIssueSheet`, `_showIssueDetailsSheet`, `_showEditIssueSheet`, `_confirmDelete`, and the uptime-report helper)
   - `_HistoryCard` widget in full
   - Grid constants: `crossAxisCount: 3`, `crossAxisSpacing: 8`, `mainAxisSpacing: 8`, `childAspectRatio: 3.0`
   - `SystemStatusService`, `SystemStatus` model, `SystemStatusReport` model — **do not touch**
5. **Do not commit.** Leave the diff uncommitted; the reviewer (Claude Code with superpowers:code-reviewer) will inspect the working tree and decide what lands.
6. **Line numbers below reference the pre-edit file.** They will shift as you delete. Match by surrounding code, not by absolute line number.

---

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies) — **not used in this spec**; all tasks touch the same file and must be sequential.
- **[Story]**: Which user story this task supports (US1, US2, US3).

---

## Path Conventions

- Flutter monorepo. Frontend code at `frontend/lib/`. Only `frontend/lib/screens/system_status_screen.dart` is modified.

---

## Phase 1: Setup

**Purpose**: Confirm the work environment is correct before touching code.

- [ ] T001 Run `git rev-parse --abbrev-ref HEAD` in `c:\Development\flutter_work_order_spec064`. Confirm output is exactly `064-update-status-screen`. If not, STOP and report to the user.
- [ ] T002 Run `git status --short` in `c:\Development\flutter_work_order_spec064`. Record the starting working-tree state so the reviewer can see your diff cleanly later. Expect only `specs/064-update-status-screen/` files to be present/new.
- [ ] T003 Open `frontend/lib/screens/system_status_screen.dart` and confirm it contains all four deletion targets listed in `research.md`: `_mainSystems`/`_groupedSystems` fields, `_expandedGroups` field, `_ExpandableGroup` class, `_satSystems`/SAT badge in `_SystemCard`. If any is missing, STOP and report.

---

## Phase 2: Foundational

**Purpose**: None. This spec has no blocking shared infrastructure; the UI layer and service layer are already in place from spec 061. Skip directly to Phase 3.

---

## Phase 3: User Story 1 — Clean flat system grid (Priority: P1) 🎯 MVP

**Goal**: Render all systems returned by the API as a flat peer grid. Remove grouping logic and the expandable group widget.

**Independent Test**: After this phase, reload the System Status screen. Exactly the number of systems returned by the API render as peer cards in a 3-column grid. No expandable group rows are present. Tapping any card opens Report Issue (when OK) or Issue Details (when Issue).

**Files touched**: `frontend/lib/screens/system_status_screen.dart` only.

### Implementation

- [ ] T004 [US1] In `frontend/lib/screens/system_status_screen.dart`, inside `_SystemStatusScreenState`, delete the fields `List<SystemStatus> _mainSystems = [];` and `Map<String, List<SystemStatus>> _groupedSystems = {};` (pre-edit ~lines 20–21). Keep `_systems`, `_history`, `_loading`, and every other field untouched.

- [ ] T005 [US1] In the same file, inside `_loadData()`'s `setState` callback (pre-edit ~lines 62–76), delete the entire grouping block — the two `_mainSystems = []; _groupedSystems = {};` reassignments plus the `for (final s in _systems) { if (s.systemName.contains(' - ')) ... else ... }` loop. Keep `_systems = results[0] as List<SystemStatus>;`, `_history = results[1] as List<SystemStatusReport>;`, and `_loading = false;`.

- [ ] T006 [US1] In the same file, inside the `build` method's grid section (pre-edit ~lines 1078–1093), change `GridView.builder`'s `itemCount` from `_mainSystems.length` to `_systems.length` and both `_mainSystems[i]` references to `_systems[i]`. Preserve every grid-delegate constant (`crossAxisCount: 3`, `crossAxisSpacing: 8`, `mainAxisSpacing: 8`, `childAspectRatio: 3.0`) verbatim.

- [ ] T007 [US1] In the same file, immediately after the grid (pre-edit ~lines 1095–1112), delete the entire `// Grouped sub-systems (expandable with animation)` comment and the `for (final entry in _groupedSystems.entries) ...[ ... _ExpandableGroup( ... ) ]` spread block. Keep the subsequent `const SizedBox(height: 16),` and the Recent Issues block exactly as-is.

- [ ] T008 [US1] In the same file, delete the entire `_ExpandableGroup` `StatefulWidget` class and its `_ExpandableGroupState` — everything from the `// ── Expandable Group ──` section header (pre-edit ~line 1141) through the closing `}` of `_ExpandableGroupState` (pre-edit ~line 1287). Leave the following `// ── System Card ──` section intact.

- [ ] T009 [US1] Run `cd frontend && flutter analyze lib/screens/system_status_screen.dart`. Expect zero errors and zero new warnings. If any appear, fix them (they will typically be "unused import" or "unused field" if T004–T008 missed something).

**Checkpoint**: User Story 1 complete. The screen renders flat. Expandable groups are gone. All existing report/issue-details/history interactions still work because no sheet helper was touched.

---

## Phase 4: User Story 2 — No truncated names, no SAT badge (Priority: P1)

**Goal**: `_SystemCard` shows `system.systemName` directly with no prefix-stripping, and no SAT badge.

**Independent Test**: After this phase, inspect every card: label reads the full API name (no substring like "Sector A"), and no yellow "SAT" pill appears anywhere.

**Files touched**: `frontend/lib/screens/system_status_screen.dart` only.

### Implementation

- [ ] T010 [US2] In `frontend/lib/screens/system_status_screen.dart`, in `_SystemCard`:
  - Delete the line `static const _satSystems = {'VAS', 'DRP'};` (pre-edit ~line 1292).
  - Delete the field `final String? displayName;` (pre-edit ~line 1295).
  - Update the constructor from `const _SystemCard({required this.system, this.displayName, required this.onTap});` to `const _SystemCard({required this.system, required this.onTap});`.
  - Delete the getter `bool get _isSat => _satSystems.contains(system.systemName);` (pre-edit ~line 1301).

- [ ] T011 [US2] In the same file, inside `_SystemCard.build`, change the `Text(displayName ?? system.systemName, ...)` widget (pre-edit ~line 1322) to `Text(system.systemName, ...)`. Preserve every other style, `maxLines`, and `overflow` property exactly.

- [ ] T012 [US2] In the same file, inside `_SystemCard.build`, delete the entire `if (_isSat) Container( ... 'SAT' ... )` block (pre-edit ~lines 1332–1348). Keep the `const SizedBox(width: 4),` that follows and the subsequent `Text(isIssue ? 'Issue' : 'OK', ...)` and status-dot `Container`.

- [ ] T013 [US2] Confirm there are no remaining callers passing `displayName:` anywhere in the file. Run a grep for `displayName` inside `frontend/lib/screens/system_status_screen.dart`. If any hit comes back other than unrelated strings, stop and reconcile.

- [ ] T014 [US2] Run `cd frontend && flutter analyze lib/screens/system_status_screen.dart`. Expect zero errors and zero new warnings.

**Checkpoint**: User Story 2 complete. Cards render full canonical names. No SAT badge anywhere.

---

## Phase 5: User Story 3 — Recent Issues regression guard (Priority: P2)

**Goal**: Verify Recent Issues, edit/delete/resolve, and the uptime report still work identically to pre-change.

**Independent Test**: Scroll to Recent Issues; entries render with their stored system names (including repointed "AIDA-NG" where applicable). Exercise Edit, Delete, Resolve from the overflow menu. Open the uptime report.

**Files touched**: None. This is a verification-only phase.

### Implementation

- [ ] T015 [US3] Confirm that `_HistoryCard`, `_showEditIssueSheet`, `_confirmDelete`, and any uptime-report helper are untouched by the diff so far. If they have been modified, revert those changes — they are explicitly out of scope per FR-006.

- [ ] T016 [US3] Confirm that `frontend/lib/services/system_status_service.dart`, `frontend/lib/models/system_status.dart`, `backend/routers/system_status.py`, and `supabase/migrations/` show zero modifications in `git status --short`. If anything in those paths is modified, revert it.

**Checkpoint**: All three user stories complete.

---

## Phase 6: Polish & Verification

**Purpose**: Final gates before handing off to the reviewer.

- [ ] T017 Run `cd frontend && flutter analyze lib/screens/system_status_screen.dart` one final time. Record the output.
- [ ] T018 Run `git diff --stat` and confirm exactly one file is modified: `frontend/lib/screens/system_status_screen.dart`. If more files are modified, revert them unless they are strictly spec documentation fixes inside `specs/064-update-status-screen/`.
- [ ] T019 Run `git rev-parse --abbrev-ref HEAD` one more time and confirm still `064-update-status-screen`.
- [ ] T020 **Do not commit.** Leave the diff uncommitted in the working tree. Report "implementation complete, awaiting review" with a short summary of what was deleted and the analyze output.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Must complete first. Confirms environment.
- **Foundational (Phase 2)**: Empty.
- **User Story 1 (Phase 3)**: Depends on Phase 1. Must complete before Phase 4 because T010–T012 assume the grouped-subsystem grid callsite (which was the only caller passing `displayName:`) has already been removed.
- **User Story 2 (Phase 4)**: Depends on Phase 3.
- **User Story 3 (Phase 5)**: Verification-only; can be performed after Phase 4.
- **Polish (Phase 6)**: Last.

### Within a single file

Every task in Phases 3–5 edits the same file. **No `[P]` parallelism is possible here.** Execute strictly in numeric order T004 → T020.

### Parallel Opportunities

None. Single-file sequential edit.

---

## Implementation Strategy

### MVP First (User Story 1 only)

T001 → T009 delivers a working flat grid. It is safe to pause there and demo, but shipping without Phase 4 leaves the SAT badge and truncation bug in place, so prefer to push through to T014.

### Incremental Delivery

Recommended path: complete T001–T020 in one continuous pass. The surface area is small (~150 lines deleted from one 1790-line file), and splitting into multiple sessions invites drift.

---

## Review handoff

When T020 reports "implementation complete, awaiting review":

1. The user will switch to Claude Code.
2. Claude Code will run the `superpowers:code-reviewer` agent against the uncommitted diff, checking:
   - Plan compliance: only the deletions listed in `research.md` happened
   - Constitution compliance (especially VII Simplicity & YAGNI — no added abstractions, no scope creep)
   - `flutter analyze` clean
   - Grid constants preserved (FR-008)
   - No backend/service/model changes (FR-007)
   - No touching `_HistoryCard`, `_showReportIssueSheet`, `_showIssueDetailsSheet`, `_showEditIssueSheet`, `_confirmDelete`, or the uptime-report helper (FR-006)
   - No new files outside `specs/064-update-status-screen/`
3. Reviewer either approves or reports specific issues for opencode to fix.

## Notes

- Every code task is the same file. [P] is never used.
- No tests are requested by the spec; SC-005 is analyzer-only.
- No commits during implementation — reviewer inspects the uncommitted diff.
- If opencode is uncertain about a removal, it should prefer leaving more code in place and flagging the uncertainty for the reviewer rather than deleting aggressively.
