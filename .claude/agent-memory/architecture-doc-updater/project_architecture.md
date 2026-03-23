---
name: flutter_work_order project architecture
description: Key architectural facts about the flutter_work_order codebase — file locations, patterns, and decisions
type: project
---

Flutter + FastAPI work order management system for civil aviation (Kuwait).

**Why:** Helps future doc-update sessions locate files and understand patterns without re-exploring the codebase from scratch.

**How to apply:** Use these facts to go directly to the right files when reviewing changes and updating docs.

## Documentation files
- Architecture: `C:\Development\flutter_work_order\ARCHITECTURE.md`
- Agent guide: `C:\Development\flutter_work_order\AGENT.md` (created 2026-03-23)

## Flutter architecture pattern
- No BLoC/Riverpod. Plain `StatefulWidget` + service classes.
- Services are plain Dart classes making `http` package calls to FastAPI.
- One service file per feature area: `UserService`, `WorkOrderService`, `ReportService`, `RecurringInspectionService`, etc.

## Key file locations
- API base URL toggle: `frontend/lib/config.dart` (`kIsProduction`)
- PDF theme enum + builder: `frontend/lib/services/pdf/work_order_pdf_service.dart`
- PDF theme HTML previews: `frontend/assets/report_preview*.html` (4 files)
- Monthly task PDF (server-rendered): `backend/routers/reports.py` (reportlab)
- Recurring inspections: `backend/routers/recurring_inspections.py`, `frontend/lib/screens/calendar/`
- File storage: `backend/uploaded_files/` (local Linux filesystem, not cloud)
- Backend logos for PDFs: `backend/assets/` (3 PNG files)

## Recurring patterns / decisions
- N+1 fix in `GET /api/users`: bulk-fetches technician_departments in 2 queries, resolves in Python
- `GET /api/users?department_id=` filters via technician_departments many-to-many (not users.department_id)
- `fetchTechnicians()` returns both `technician` AND `admin` user types
- `work_orders.closed_by` is a UUID (not email); resolved at close time via `_get_user_id_by_email()`
- `POST /api/recurring-inspections/generate` must be triggered externally — not automatic; the calendar UI no longer has a "Generate" button (removed 2026-03-24)
- `backend/version.json` must never be committed (server-managed file)
- `CalendarScreen` computes recurrence client-side from the full inspection list (fetchAll); does NOT use `/api/recurring-inspections/calendar`. Cache window: 60 days past to 120 days future. `RecurringInspectionService.fetchCalendar()` exists but is unused by Flutter.
- Frequency values are `daily`, `weekly`, `monthly`, `yearly` — NOT `custom`; `yearly` matches month+day of startDate
- `RecurringInspection.generatedToday` (bool) comes from `json['generated_today']`; drives the "Generated" badge on calendar cards
- `AddRecurringInspectionScreen` uses an internal `_RepeatOption` enum (not the raw frequency string) for UI; derives frequency/interval at save time. When creating new, a tab picker lets the user choose between work order creation and recurring inspection creation from the same screen.
- "Add recurring inspection" button in calendar header: accessible to both `admin` and `technician` roles
- Documents screen folder sidebar width is user-resizable (60–280 px, default 116 px) via a drag handle; stored in `_sidebarWidth` state
