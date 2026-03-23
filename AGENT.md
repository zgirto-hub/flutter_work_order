# AGENT.md — Work Order System

Developer and agent operational guide. See `ARCHITECTURE.md` for structural details.

---

## Project Overview

A full-stack work order management system for civil aviation. Flutter web/mobile frontend, FastAPI + Python backend, Supabase (PostgreSQL) database. Deployed on a single Linux server behind Nginx.

---

## Tech Stack Quick Reference

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart) — primarily web target |
| Backend | FastAPI (Python 3), Uvicorn |
| Database | Supabase (PostgreSQL + Auth + RLS) |
| Auth | Supabase email/password — no self-registration |
| Push notifications | OneSignal |
| File storage | Linux server filesystem (`backend/uploaded_files/`) |
| PDF (client) | `pdf` Flutter package (`work_order_pdf_service.dart`) |
| PDF (server) | `reportlab` Python library (`backend/routers/reports.py`) |
| OCR | pytesseract + pdf2image |
| Recurring task calendar | `table_calendar` Flutter package |

---

## Repository Structure

```
backend/              FastAPI application
  routers/            Route handlers (one file per feature area)
  utils/              Shared utilities (notifications, permissions, OCR, activity log)
  assets/             Logo PNGs embedded in server-generated PDFs
  uploaded_files/     Runtime file storage (created on startup, not committed)
frontend/             Flutter application
  lib/
    models/           Data classes
    services/         HTTP API clients + PDF builders
    screens/          UI pages (feature-organized subdirectories)
    widgets/          Reusable UI components
    filters/          Work order filter logic
    theme/            App theme and color definitions
    config.dart       API base URL (toggle kIsProduction)
  assets/
    images/           Logo PNGs for frontend display
    report_preview*.html  PDF theme HTML design references (4 files)
scripts/              Deployment scripts (deploy, rollback, nginx, version bump)
supabase/
  migrations/         SQL schema migrations (apply in timestamp order)
  seed.sql            Initial data
```

---

## Local Development

### Backend

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

The backend reads `SUPABASE_URL`, `SUPABASE_KEY` (service role), and `ONESIGNAL_API_KEY` from environment variables. Copy `.env.example` if present, or set them in your shell.

`backend/uploaded_files/` is created automatically on startup. Do not commit its contents.

### Frontend

```bash
cd frontend
flutter pub get
flutter run -d chrome
```

Toggle between dev and production API in `frontend/lib/config.dart`:
- Dev: `http://100.85.73.37:8000/api` (direct to FastAPI)
- Production: `https://zorin.taila92fe8.ts.net/api` (via Nginx + Tailscale)

---

## Deployment

```bash
# Deploy frontend web build to Nginx root
scripts/deploy_frontend.sh

# Bump app version
scripts/bump_version.sh

# Apply updated Nginx config
scripts/update_nginx_config.sh

# Roll back frontend to previous build
scripts/rollback_frontend.sh
```

Backend is run under systemd or a process manager on the Linux server. After updating `backend/`, restart the service manually.

**Do not commit `backend/version.json`** — this file is managed separately on the server and will conflict with local state.

---

## Database Migrations

Migrations live in `supabase/migrations/` and are named by timestamp. Apply them in order via the Supabase dashboard SQL editor or the Supabase CLI:

```bash
supabase db push
```

Current migrations include:
- Initial schema (work orders, users, departments)
- Document management tables
- Notification and activity log tables
- `20260321_recurring_inspections.sql` — recurring_inspections, assignees, logs tables

---

## Key Patterns & Conventions

### User Roles
Three roles: `reporter`, `technician`, `admin`. Stored as `user_type` in the `users` table. No self-registration — admins create all accounts via `POST /api/users?admin_email=`.

Admins are included alongside technicians in technician-assignment dropdowns (`fetchTechnicians()` returns both `technician` and `admin` user types).

### Technician-to-Department Filtering
When opening the "Assign Technician" flow in `add_work_order.dart`:
1. `_loadEmployees(departmentId: dept.id)` is called with the selected department's UUID
2. `UserService.fetchTechnicians({departmentId})` sends `GET /api/users?department_id=<uuid>`
3. The backend queries `technician_departments` for that department and returns only those technicians in one query (no N+1)
4. Falls back to full list when no department is selected

### Work Order Closure
Both the `PUT /api/work-orders/{id}` (update) and `POST /api/work-orders/{id}/close` endpoints, as well as `POST /api/work-orders` when created directly as "Closed", set:
- `closed_at`: UTC timestamp
- `closed_by`: UUID of the closing user (resolved from email via `_get_user_id_by_email()`)

This data is consumed by `GET /api/reports/closed-work-orders` to build technician performance reports.

### PDF Report Themes
Four themes defined in `WorkOrderPdfTheme` enum in `work_order_pdf_service.dart`:

| Enum | Label | Preview HTML |
|---|---|---|
| `copperNight` | Claude Minimal | `assets/report_preview.html` |
| `forestLedger` | Forest Ledger | `assets/report_preview_green.html` |
| `signalOrange` | Signal Orange | `assets/report_preview_teal.html` |
| `formalElegant` | Formal Elegant | `assets/report_preview_burgundy.html` |

When adding a new theme: add the enum value, add cases in `label`, `description`, `previewAsset`, and `_ReportPalette.fromTheme()`, and add the corresponding HTML preview file to `frontend/assets/`.

### Monthly Task Report (Server-Side PDF)
`ReportService.generateMonthlyTasksReport()` POSTs task data to `POST /api/reports/monthly-tasks`. The backend (`backend/routers/reports.py`) renders a `reportlab` PDF using logos from `backend/assets/` and streams it back. The Flutter client receives raw bytes and passes them to `PdfPreviewScreen`.

### Recurring Inspections
- Frequency options: `daily`, `weekly`, `monthly`, `yearly` (with `interval` and `day_of_week`/`day_of_month` fields)
- `POST /api/recurring-inspections/generate` advances `next_due` for all overdue records — intended for periodic invocation (cron or manual trigger)
- The calendar screen does **not** use `GET /api/recurring-inspections/calendar`. Instead it loads all active inspections once (`GET /api/recurring-inspections?is_active=true`) and computes event placements entirely client-side. A bounded cache (`Map<DateTime, List<RecurringInspection>>`) covering 60 days past to 120 days future is built after load and on page-change when the user scrolls outside that window. The `eventLoader` callback is an O(1) map lookup against this cache.
- The backend `/api/recurring-inspections/calendar` endpoint still exists but is currently unused by the Flutter frontend. `RecurringInspectionService.fetchCalendar()` wraps it if a future screen needs it.

### N+1 Prevention in `GET /api/users`
`list_users()` uses a 2-query bulk fetch for technician department names: one query for all `technician_departments` rows, one for all `departments`, then resolves names in Python. The per-user N+1 pattern was removed in commit `ec1ef0a`.

### File Uploads
Files go to `backend/uploaded_files/` on the server filesystem — not cloud storage. Served at `/files/<filename>` via FastAPI `StaticFiles` mount. Images are auto-compressed (max 1920px, Pillow). Nginx enforces a 50MB ceiling.

---

## Adding a New Feature — Checklist

- [ ] Backend: add router in `backend/routers/<feature>.py`, register in `backend/main.py`
- [ ] Database: add migration in `supabase/migrations/<timestamp>_<feature>.sql`
- [ ] Frontend model: add `lib/models/<feature>.dart` with `fromJson`
- [ ] Frontend service: add `lib/services/<feature>_service.dart` for HTTP calls
- [ ] Frontend screen: add under `lib/screens/<feature>/`
- [ ] Navigation: wire screen into `more_screen.dart` or `main_screen.dart` as appropriate
- [ ] Update `ARCHITECTURE.md` with new tables, endpoints, and project structure entries
- [ ] Update this `AGENT.md` with any new patterns or workflow notes

---

## Common Gotchas

- **`backend/version.json`**: Never commit this file. It is managed on the server independently.
- **`uploaded_files/`**: Not backed up to cloud. Losing the server disk loses all binary files. Metadata (Supabase) survives, but files do not.
- **Role check for technician assignment**: `fetchTechnicians()` returns both `technician` and `admin` users — admins can be assigned to work orders.
- **`closed_by` is a UUID, not an email**: The `work_orders.closed_by` column stores the user's UUID from the `users` table, resolved at close time. Do not store email here.
- **Department filter uses `technician_departments`**: `GET /api/users?department_id=` filters by the many-to-many mapping, not by `users.department_id`. Technicians do not have a `department_id` on their user row.
- **HTML preview files are not the PDF output**: `frontend/assets/report_preview*.html` are design reference files used for the in-app theme picker preview only. The actual PDF is built by `WorkOrderPdfService` (Dart) or `reportlab` (Python).
- **Recurring inspection generation**: The `POST /api/recurring-inspections/generate` endpoint is not called automatically — it must be triggered externally or manually to advance due dates.
- **Calendar markers are computed client-side**: `CalendarScreen` builds its own recurrence schedule from the raw `RecurringInspection` list — it does not query the backend calendar endpoint. If recurrence logic in `_computeEventsForDay` diverges from the backend's `_compute_next_due()`, calendar markers and actual due-date generation will disagree. Keep both in sync when changing frequency semantics.
- **`yearly` not `custom`**: The `RecurringInspection.frequency` field uses `'yearly'` as the fourth frequency value. Older documentation and some comments may say `'custom'` — that is incorrect.
