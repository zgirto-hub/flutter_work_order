# Quickstart: Export PDF Report for Closed Work Orders

**Date**: 2026-04-04 | **Branch**: `015-export-wo-pdf`

## Prerequisites

- Python 3 with FastAPI backend running
- Flutter frontend configured
- Supabase database with existing `work_orders`, `work_order_signatures`, `users`, `departments` tables
- Logo files in `backend/assets/` (optional — PDF generates without them)

## Setup

### Backend

1. Install new dependency:
   ```bash
   pip install reportlab
   ```

2. Add `reportlab` to `requirements.txt`

3. Restart backend server

### Frontend

No new dependencies required.

## Files Modified

| File | Change |
|------|--------|
| `backend/requirements.txt` | Add `reportlab` |
| `backend/routers/reports.py` | Add `export_work_order_pdf` endpoint |
| `frontend/lib/services/report_service.dart` | Add `exportWorkOrderPdf()` method |
| `frontend/lib/screens/Work_Orders/add_work_order.dart` | Add "Export PDF Report" button for closed WOs |
| `frontend/lib/widgets/work_order_card.dart` | Add "Export PDF" icon on closed WO cards |

## Testing

### Manual Test: Export from Detail Screen

1. Open a closed work order in the detail screen
2. Scroll to bottom of Details tab
3. Tap "Export PDF Report" button
4. Verify loading indicator appears
5. Verify PDF preview opens with correct content:
   - Header: 3 logos + title + department
   - Details: all WO fields
   - Technicians: assigned technician names
   - Signatures: embedded images or placeholders
   - Footer: system name + timestamp + page number

### Manual Test: Export from List

1. Navigate to work order list
2. Expand a closed work order card
3. Tap the PDF export icon
4. Verify same PDF preview flow

### Manual Test: RBAC

1. Log in as Reporter → verify can only export own WOs
2. Log in as Technician → verify can only export department WOs
3. Log in as Admin → verify can export any WO

### Manual Test: Edge Cases

1. Export WO with no signatures → verify "Awaiting Signature" placeholders
2. Export WO with one signature → verify partial report with "Pending Signature"
3. Export WO with very long description → verify text wraps to page 2
