# Tasks: Edit Resolve Date

**Input**: Design documents from `/specs/006-edit-resolve-date/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api.md, quickstart.md
**Target executor**: Another LLM (OpenAI 5.4) — each task includes full context for standalone execution.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2)
- All file paths are relative to the repository root

---

## Phase 1: Foundational (Backend Models)

**Purpose**: Extend backend Pydantic models to accept `resolved_at` — required by both user stories.

- [X] T001 Add optional `resolved_at: Optional[str] = None` field to `ResolveIssueBody` model in `backend/routers/system_status.py`

**Details for T001**:
- File: `backend/routers/system_status.py`, around line 49-51
- Current model has only `resolved_by: str` and `resolved_notes: Optional[str] = ""`
- Add `resolved_at: Optional[str] = None` as a new field
- This is a date string in `YYYY-MM-DD` format, optional (defaults to None meaning "use current UTC time")

- [X] T002 [P] Add optional `resolved_at: Optional[str] = None` field to `UpdateIssueBody` model in `backend/routers/system_status.py`

**Details for T002**:
- File: `backend/routers/system_status.py`, around line 44-46
- Current model has only `notes: Optional[str] = None` and `report_date: Optional[str] = None`
- Add `resolved_at: Optional[str] = None` as a new field

**Checkpoint**: Both Pydantic models now accept `resolved_at`. No behavior changes yet.

---

## Phase 2: User Story 1 — Edit Resolve Date on Resolved Issues (Priority: P1) MVP

**Goal**: Allow users to edit the resolve date of an already-resolved issue so uptime reports accurately reflect the actual resolution date.

**Independent Test**: Resolve an issue → edit its resolve date to an earlier date → verify the uptime report reflects the corrected date.

### Backend for User Story 1

- [X] T003 [US1] Add resolve date validation and update logic to the PUT `/system-status/{report_id}` endpoint in `backend/routers/system_status.py`

**Details for T003**:
- File: `backend/routers/system_status.py`, the `update_issue` function (around line 174-218)
- After the existing `report_date` handling block, add a new block for `resolved_at`:
  1. Only process if `body.resolved_at is not None`
  2. Validate the issue is already resolved: check `old_report["resolved_at"]` is not None. If it IS None, raise `HTTPException(status_code=400, detail="Cannot edit resolve date on an unresolved issue")`
  3. Parse the date: `resolved_date = date.fromisoformat(body.resolved_at)`
  4. Determine the effective report_date for validation: use `body.report_date` if provided in this same request, otherwise use `old_report["report_date"]`
  5. Validate `resolved_date >= date.fromisoformat(effective_report_date)`. If not, raise `HTTPException(status_code=400, detail=f"Resolve date cannot be before the issue report date ({effective_report_date})")`
  6. Validate `resolved_date <= date.today()`. If not, raise `HTTPException(status_code=400, detail="Resolve date cannot be in the future")`
  7. Add to updates dict: `updates["resolved_at"] = f"{body.resolved_at}T23:59:59"`
- Note: `date` and `datetime` are already imported from the `datetime` module at the top of the file

### Frontend Service for User Story 1

- [X] T004 [US1] Add optional `resolvedAt` parameter to the `updateIssue()` method in `frontend/lib/services/system_status_service.dart`

**Details for T004**:
- File: `frontend/lib/services/system_status_service.dart`, the `updateIssue` method (around line 92-116)
- Add a new optional named parameter: `String? resolvedAt`
- In the body map construction, add: `if (resolvedAt != null) body['resolved_at'] = resolvedAt;`
- This follows the exact same pattern as the existing `notes` and `reportDate` parameters

### Frontend UI for User Story 1

- [X] T005 [US1] Add a resolve date picker to the `_showEditIssueSheet` method for resolved issues in `frontend/lib/screens/system_status_screen.dart`

**Details for T005**:
- File: `frontend/lib/screens/system_status_screen.dart`, the `_showEditIssueSheet` method (around line 488-642)
- Changes needed:
  1. Add a state variable for the resolve date. After the existing `DateTime selectedDate` line, add:
     ```dart
     DateTime? selectedResolveDate = report.isResolved && report.resolvedAt != null
         ? DateTime.tryParse(report.resolvedAt!)
         : null;
     ```
  2. Add a resolve date picker widget AFTER the notes TextField and BEFORE the Save button, but ONLY when `report.isResolved` is true. Use the same GestureDetector + Container pattern as the existing report date picker (lines 531-566). Key differences:
     - Label/icon should indicate "Resolve Date"
     - `firstDate` should be `selectedDate` (the report date) — not `DateTime(2024)`
     - `lastDate` should be `DateTime.now()`
     - `initialDate` should be `selectedResolveDate ?? DateTime.now()`
     - On pick, update: `setSheetState(() => selectedResolveDate = picked);`
  3. In the Save button's `onPressed` handler, pass the resolve date to the service call. After the existing `dateStr` variable, add:
     ```dart
     final resolveDateStr = selectedResolveDate != null
         ? '${selectedResolveDate!.year}-${selectedResolveDate!.month.toString().padLeft(2, '0')}-${selectedResolveDate!.day.toString().padLeft(2, '0')}'
         : null;
     ```
  4. Update the `_service.updateIssue()` call to include: `resolvedAt: resolveDateStr,`
  5. Add a "Resolve Date" label text above the date picker (similar style to how report date is shown), wrapped in a conditional: `if (report.isResolved) ...[` the label + picker widgets `]`

**Checkpoint**: User Story 1 complete. Users can now edit the resolve date of resolved issues via the edit sheet. Verify by:
1. Opening a resolved issue in history
2. Tapping edit
3. Seeing the resolve date picker with the current resolve date pre-selected
4. Changing the date and saving
5. Checking the uptime report reflects the new date

---

## Phase 3: User Story 2 — Custom Resolve Date During Resolution (Priority: P2)

**Goal**: Allow users to optionally pick a custom resolve date when resolving an issue, instead of always using the current server timestamp.

**Independent Test**: Resolve an unresolved issue with a custom past date → verify `resolved_at` stores the selected date, not the current timestamp.

### Backend for User Story 2

- [X] T006 [US2] Add resolve date handling to the PATCH `/system-status/{report_id}/resolve` endpoint in `backend/routers/system_status.py`

**Details for T006**:
- File: `backend/routers/system_status.py`, the `resolve_issue` function (around line 143-171)
- Currently line ~162 sets: `"resolved_at": datetime.utcnow().isoformat()`
- Change this to conditionally use the provided date:
  1. Before the update call, determine the resolved_at value:
     ```python
     if body.resolved_at:
         resolved_date = date.fromisoformat(body.resolved_at)
         report_date = date.fromisoformat(existing.data[0].get("report_date", "2024-01-01"))
     ```
     Wait — the current query only selects `"id, resolved_at"`. You need to also fetch `report_date` for validation. Change the select to: `.select("id, resolved_at, report_date")`
  2. Validate:
     - `resolved_date >= report_date`: raise `HTTPException(status_code=400, detail=f"Resolve date cannot be before the issue report date ({report_date})")` if not
     - `resolved_date <= date.today()`: raise `HTTPException(status_code=400, detail="Resolve date cannot be in the future")` if not
  3. Set: `resolved_at_value = f"{body.resolved_at}T23:59:59"`
  4. Else (no date provided): `resolved_at_value = datetime.utcnow().isoformat()`
  5. Use `resolved_at_value` in the update dict instead of the hardcoded `datetime.utcnow().isoformat()`

### Frontend Service for User Story 2

- [X] T007 [US2] Add optional `resolvedAt` parameter to the `resolveIssue()` method in `frontend/lib/services/system_status_service.dart`

**Details for T007**:
- File: `frontend/lib/services/system_status_service.dart`, the `resolveIssue` method (around line 76-90)
- Add a new optional named parameter: `String? resolvedAt`
- In the `jsonEncode` body, add: `if (resolvedAt != null) 'resolved_at': resolvedAt`
- The body currently is `{'resolved_by': resolvedBy, 'resolved_notes': resolvedNotes}`. Change to:
  ```dart
  body: jsonEncode({
    'resolved_by': resolvedBy,
    'resolved_notes': resolvedNotes,
    if (resolvedAt != null) 'resolved_at': resolvedAt,
  }),
  ```

### Frontend UI for User Story 2

- [X] T008 [US2] Add an optional date picker to the `_showResolveSheet` method in `frontend/lib/screens/system_status_screen.dart`

**Details for T008**:
- File: `frontend/lib/screens/system_status_screen.dart`, the `_showResolveSheet` method (around line 359-484)
- Changes needed:
  1. Add state variable after `bool resolving = false;`:
     ```dart
     DateTime selectedResolveDate = DateTime.now();
     ```
  2. Add a date picker widget BEFORE the "Confirm Resolve" button (after the notes TextField + SizedBox). Use the same GestureDetector + Container pattern from the edit sheet. Key settings:
     - `initialDate: selectedResolveDate`
     - `firstDate`: Parse `report.reportDate` to get the report date: `DateTime.tryParse(report.reportDate) ?? DateTime(2024)`
     - `lastDate: DateTime.now()`
     - On pick: `setSheet(() => selectedResolveDate = picked);`
  3. Add a small label above the picker like `Text('Resolve Date', style: TextStyle(fontSize: 13, color: AppColors.textSecondary))` and a `SizedBox(height: 8)` before the picker, then a `SizedBox(height: 16)` after.
  4. In the "Confirm Resolve" button's `onPressed`, format the date and pass it:
     ```dart
     final resolveDateStr = '${selectedResolveDate.year}-${selectedResolveDate.month.toString().padLeft(2, '0')}-${selectedResolveDate.day.toString().padLeft(2, '0')}';
     await _service.resolveIssue(
       reportId: report.id,
       resolvedBy: _email,
       resolvedNotes: notesCtrl.text.trim(),
       resolvedAt: resolveDateStr,
     );
     ```

**Checkpoint**: User Story 2 complete. Users can now pick a custom date when resolving. Verify by:
1. Resolving an issue with today's date (default) — should behave as before
2. Resolving an issue with a past date — verify `resolved_at` stores that date

---

## Phase 4: Polish & Cross-Cutting Concerns

- [ ] T009 Verify end-to-end: edit resolve date on a resolved issue and confirm uptime report reflects the change (manual test per quickstart.md)
- [ ] T010 Verify validation: attempt to set resolve date before report date and after today — both should show error messages

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Foundational)**: No dependencies — start immediately
- **Phase 2 (US1)**: Depends on T001 and T002 (models must have the new field)
- **Phase 3 (US2)**: Depends on T001 and T002. Independent of Phase 2 (US1) — can run in parallel
- **Phase 4 (Polish)**: Depends on all previous phases

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Phase 1 only. No dependency on US2.
- **User Story 2 (P2)**: Depends on Phase 1 only. No dependency on US1.

### Within Each User Story

- Backend endpoint changes before frontend service changes
- Frontend service changes before frontend UI changes

### Parallel Opportunities

- T001 and T002 can run in parallel (same file, different models — but recommend sequential to avoid conflicts)
- US1 (T003-T005) and US2 (T006-T008) are independent and can run in parallel IF working on different files or coordinating changes to shared files
- T009 and T010 can run in parallel

---

## Parallel Example: User Story 1

```
# Sequential within US1 (same files have dependencies):
T003 → T004 → T005

# T003: Backend endpoint (system_status.py)
# T004: Frontend service (system_status_service.dart)
# T005: Frontend UI (system_status_screen.dart)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Add fields to models (T001, T002)
2. Complete Phase 2: US1 backend → service → UI (T003, T004, T005)
3. **STOP and VALIDATE**: Edit a resolved issue's resolve date and check uptime report
4. Deploy if ready — this delivers the core value

### Incremental Delivery

1. Phase 1 (models) → Foundation ready
2. Add User Story 1 (T003-T005) → Test independently → Deploy (MVP!)
3. Add User Story 2 (T006-T008) → Test independently → Deploy
4. Polish (T009-T010) → Final validation

---

## Notes

- No database migration needed — `resolved_at` column already exists
- No frontend model changes needed — `SystemStatusReport` already has `resolvedAt` field
- The uptime calculation already uses `resolved_at` for downtime span (changed in a prior commit on `main`)
- Total: 10 tasks across 3 files
- Backend file: `backend/routers/system_status.py`
- Frontend service: `frontend/lib/services/system_status_service.dart`
- Frontend UI: `frontend/lib/screens/system_status_screen.dart`
