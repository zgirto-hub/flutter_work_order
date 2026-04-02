# Quickstart: Edit Resolve Date

## Files to Modify

| # | File | What to change |
|---|------|---------------|
| 1 | `backend/routers/system_status.py` | Add `resolved_at` to `ResolveIssueBody` and `UpdateIssueBody`; add validation logic to both endpoints |
| 2 | `frontend/lib/services/system_status_service.dart` | Add optional `resolvedAt` param to `resolveIssue()` and `updateIssue()` |
| 3 | `frontend/lib/screens/system_status_screen.dart` | Add date picker to resolve sheet; add resolve date picker to edit sheet for resolved issues |

## Implementation Order

1. **Backend models + endpoints** — add fields and validation (no breaking changes; new fields are optional)
2. **Frontend service** — pass new optional parameter
3. **Frontend UI** — add date pickers to both sheets

## Verification

1. Start backend: `cd backend && uvicorn main:app --reload`
2. Hot-restart Flutter app
3. **Test P1 (edit resolve date)**:
   - Find a resolved issue in history
   - Tap edit → verify resolve date picker appears with current resolve date pre-selected
   - Change the date → save → verify the date is updated
   - Check uptime report reflects the new date
4. **Test P2 (custom resolve date during resolution)**:
   - Find an unresolved issue
   - Tap resolve → verify optional date picker appears (defaulting to today)
   - Select a past date → confirm → verify `resolved_at` uses the selected date
   - Resolve another issue without changing date → verify current timestamp is used
5. **Test validation**:
   - Try setting resolve date before report date → expect error
   - Try setting resolve date in the future → expect error
