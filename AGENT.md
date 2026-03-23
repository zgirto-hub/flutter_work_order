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

## Database Schema

### Core Tables

```sql
departments (
  id UUID PK,
  name TEXT UNIQUE NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ
)

users (
  id UUID PK,
  auth_id UUID UNIQUE,          -- links to Supabase auth.users
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  mobile TEXT,
  location TEXT,
  department_id UUID FK -> departments(id),  -- user's own department
  user_type TEXT CHECK ('admin', 'technician', 'reporter'),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ
)

technician_departments (
  id UUID PK,
  technician_id UUID FK -> users(id) CASCADE,
  department_id UUID FK -> departments(id) CASCADE,
  UNIQUE (technician_id, department_id)
)

work_orders (
  id UUID PK,
  job_no TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  location TEXT,
  mobile_number TEXT,
  department_id UUID FK -> departments(id),
  type TEXT DEFAULT 'Technical',
  status TEXT CHECK ('Pending', 'In Progress', 'Resolved', 'Closed'),
  tech_notes TEXT,
  created_by UUID FK -> users(id),
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  closed_by UUID FK -> users(id),
  closed_at TIMESTAMPTZ
)

work_order_assignments (
  work_order_id UUID FK -> work_orders(id) CASCADE,
  technician_id UUID FK -> users(id) CASCADE,
  assigned_at TIMESTAMPTZ,
  assigned_by UUID FK -> users(id),
  PK (work_order_id, technician_id)
)

work_order_status_logs (
  id UUID PK,
  work_order_id UUID FK -> work_orders(id) CASCADE,
  changed_by UUID FK -> users(id),
  old_status TEXT,
  new_status TEXT,
  note TEXT,
  changed_at TIMESTAMPTZ
)

work_order_comments (
  id UUID PK,
  work_order_id UUID FK -> work_orders(id) CASCADE,
  author_email TEXT,
  author_name TEXT,
  body TEXT,
  type TEXT DEFAULT 'comment',  -- 'comment', 'status_change', 'system'
  meta JSONB,
  created_at TIMESTAMPTZ
)

work_order_attachments (
  id UUID PK,
  work_order_id UUID FK -> work_orders(id) CASCADE,
  file_name TEXT,
  file_url TEXT,
  file_type TEXT,
  uploaded_by TEXT,
  created_at TIMESTAMPTZ
)
```

### Document Tables

```sql
documents (
  id UUID PK,
  title TEXT,
  file_name TEXT,
  file_extension TEXT,
  mime_type TEXT,
  file_path TEXT,              -- path under backend/uploaded_files/
  parsed_text TEXT,            -- extracted text content (OCR/PDF/DOCX)
  is_private BOOLEAN DEFAULT false,
  uploaded_by TEXT,            -- user email
  file_size BIGINT,
  folder_id UUID FK -> document_folders(id),
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)

document_folders (
  id UUID PK,
  name TEXT NOT NULL,
  parent_id UUID FK -> document_folders(id),  -- hierarchical folders
  created_by TEXT,             -- user email
  is_private BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ
)

resource_permissions (
  id UUID PK,
  resource_id UUID NOT NULL,   -- document or folder ID
  resource_type TEXT,           -- 'document' | 'folder'
  user_email TEXT NOT NULL,
  role TEXT,                    -- 'viewer' | 'editor'
  granted_by TEXT,             -- granter email
  created_at TIMESTAMPTZ
)
```

### Activity Log Table

```sql
user_activity_log (
  id UUID PK,
  user_email TEXT,
  user_name TEXT,
  category TEXT,               -- 'work_order', 'document', 'folder', 'request', 'auth', 'admin'
  action TEXT,                 -- 'created', 'updated', 'deleted', 'uploaded', 'shared', 'closed', 'signed_in', etc.
  target_label TEXT,
  target_id TEXT,
  detail TEXT,
  created_at TIMESTAMPTZ
)
```

### Notification Tables

```sql
notification_preferences (
  user_id UUID PK FK -> users(id) CASCADE,
  user_email TEXT,
  push_enabled BOOLEAN DEFAULT true,
  in_app_enabled BOOLEAN DEFAULT true,
  mute_all BOOLEAN DEFAULT false,
  comment_notifications BOOLEAN DEFAULT true,
  status_notifications BOOLEAN DEFAULT true,
  system_notifications BOOLEAN DEFAULT true,
  admin_all_workorder_comments BOOLEAN DEFAULT false,
  updated_at TIMESTAMPTZ
)

work_order_watchers (
  id UUID PK,
  work_order_id UUID FK -> work_orders(id) CASCADE,
  user_id UUID FK -> users(id) CASCADE,
  user_email TEXT,
  created_at TIMESTAMPTZ,
  UNIQUE(work_order_id, user_id)
)

notifications (
  id UUID PK,
  user_id UUID FK -> users(id) CASCADE,
  user_email TEXT,
  kind TEXT,
  title TEXT,
  body TEXT,
  data JSONB DEFAULT '{}',
  source_type TEXT,
  source_id TEXT,
  read_at TIMESTAMPTZ NULLABLE,
  created_at TIMESTAMPTZ
)

notification_delivery_logs (
  id UUID PK,
  notification_id UUID FK -> notifications(id) CASCADE,
  user_id UUID FK -> users(id) CASCADE,
  user_email TEXT,
  channel TEXT,           -- push | in_app
  provider TEXT,          -- onesignal
  status TEXT,            -- queued | sent | failed
  provider_message_id TEXT,
  error TEXT,
  attempt INTEGER DEFAULT 1,
  next_retry_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ
)
```

### Row Level Security (RLS)

RLS is enabled on `work_orders` as defense-in-depth:

| Policy | Role | Access |
|--------|------|--------|
| `reporter_own_wos` | Reporter | SELECT own WOs only |
| `technician_department_wos` | Technician | SELECT department WOs only |
| `admin_all_wos` | Admin | SELECT all |
| `authenticated_insert_wos` | Any auth'd | INSERT |
| `admin_technician_update_wos` | Tech/Admin | UPDATE |
| `admin_delete_wos` | Admin | DELETE |

**Note**: Backend uses Supabase service role key, so RLS does not affect backend queries. RLS protects against direct Flutter/Supabase SDK access only.

### Key Relationships

```
users.department_id -> departments.id             (user belongs to department)
technician_departments.technician_id -> users.id  (technician handles departments)
technician_departments.department_id -> departments.id
work_orders.department_id -> departments.id       (WO targets a department)
work_orders.created_by -> users.id                (who reported it)
work_order_assignments.technician_id -> users.id  (who's assigned)
work_order_assignments.work_order_id -> work_orders.id
documents.folder_id -> document_folders.id        (document in folder)
document_folders.parent_id -> document_folders.id (folder hierarchy)
resource_permissions.resource_id -> documents.id or document_folders.id
```

---

## User Roles & Permissions

| Action | Reporter | Technician | Admin |
|--------|----------|------------|-------|
| Create WO | Yes | Yes | Yes |
| View WOs | Own only | Own dept only | All |
| Update/Close WO | No | Yes | Yes |
| Delete WO | No | No | Yes |
| Create accounts | No | No | Yes |
| Manage departments | No | No | Yes |
| Comment on WO | Yes | Yes | Yes |
| Receive notifications | Own WOs | Assigned WOs | Opt-in all |
| Mute notifications | Yes | Yes | Yes |
| Upload documents | Yes | Yes | Yes |
| Share documents | Own/Editor | Own/Editor | Own/Editor |
| View shared docs | If shared | If shared | If shared |

- **Reporter**: Belongs to a department (`users.department_id`). Can create WOs targeting any department. Can only view WOs they created.
- **Technician**: Assigned to one or more departments via `technician_departments`. Can view/update/close WOs in their assigned departments.
- **Admin**: Full access. Only role that can create user accounts, manage departments, and delete WOs.

### Document Permission Model

Documents and folders use a separate permission model via `resource_permissions`:

- **Owner**: Full control (view, download, rename, move, delete, share, edit_type). Determined by `uploaded_by` (documents) or `created_by` (folders).
- **Editor**: Can view, download, rename, move, share, edit_type — cannot delete.
- **Viewer**: Can view and download only.
- Permissions inherit through folder hierarchy (walks up parent chain via `backend/utils/permissions.py`).
- Role priority: viewer(1) < editor(2) < owner(3).

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

## Notifications System

### Comment Notification Routing

When a comment is posted on a work order, notify:
1. **Creator** — `work_orders.created_by` → `users.email`
2. **Assigned technicians** — `work_order_assignments.technician_id` → `users.email`
3. **Watchers** — `work_order_watchers.user_email`
4. **Opted-in admins** — admins with `notification_preferences.admin_all_workorder_comments = true`

The commenter is always excluded from their own notification.

### Preference Cascade

```
prefs = DEFAULT_PREFS  (all true, mute_all false)
prefs.update(database_row or {})

if prefs.mute_all: skip
if event_type == 'comment' and not prefs.comment_notifications: skip
if not prefs.push_enabled: skip push (still insert inbox if in_app_enabled)
if not prefs.in_app_enabled: skip inbox (still send push if push_enabled)
```

### Delivery Channels
- **In-app**: Stored in `notifications` table, queried by frontend
- **Push**: Sent via OneSignal using `include_aliases.external_id` (user email)

### OneSignal Integration
- App ID: `760f00e5-fb08-4c0c-b898-ea35737bcc21`
- API key: env var `ONESIGNAL_API_KEY`
- Frontend sets external ID via `OneSignal.login(email)` on web

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

---

## Relevant Files Directory

### Backend
- `backend/main.py` — router registration
- `backend/routers/work_orders.py` — WO CRUD, comments, attachments, notification dispatch
- `backend/routers/users.py` — user management (admin-only), role checks, activity log
- `backend/routers/departments.py` — department CRUD, technician/WO counts
- `backend/routers/technician_departments.py` — technician-department mapping CRUD
- `backend/routers/notifications.py` — notification/watcher/preference APIs
- `backend/routers/documents.py` — document upload, delete, sharing, role check
- `backend/routers/folders.py` — folder CRUD, move operations
- `backend/utils/notification_service.py` — recipient resolution + dispatch orchestration
- `backend/utils/notifications.py` — OneSignal HTTP helpers
- `backend/utils/activity.py` — activity audit logging
- `backend/utils/permissions.py` — document/folder permission engine with inheritance
- `backend/utils/text_extraction.py` — text extraction (PDF, DOCX, TXT, OCR for images)

### Frontend
- `frontend/lib/models/user.dart` — AppUser model (UserType: admin, technician, reporter)
- `frontend/lib/models/work_order.dart` — WorkOrder model with TechnicianAssignment list
- `frontend/lib/models/technician_assignment.dart` — TechnicianAssignment model
- `frontend/lib/models/document.dart` — DocumentModel with DocumentCapabilities (role-based)
- `frontend/lib/models/folder_model.dart` — FolderModel (hierarchical)
- `frontend/lib/models/activity_log_entry.dart` — ActivityLogEntry with category/action
- `frontend/lib/models/workorder_report.dart` — WorkOrderReport for PDF generation
- `frontend/lib/services/user_service.dart` — user API client (fetchTechnicians, getTechnicianDepartments, etc.)
- `frontend/lib/services/work_order_service.dart` — work order API client
- `frontend/lib/services/technician_department_service.dart` — technician-department mapping API
- `frontend/lib/services/notification_service.dart` — notification API client
- `frontend/lib/services/document_service.dart` — document API client (fetch, insert, search)
- `frontend/lib/services/folder_service.dart` — folder API client (CRUD, move operations)
- `frontend/lib/services/activity_log_service.dart` — activity log API client
- `frontend/lib/screens/Work_Orders/work_order_home.dart` — WO list with badges + sound
- `frontend/lib/screens/Work_Orders/add_work_order.dart` — WO create/edit with technician selector
- `frontend/lib/screens/Documents/documents_screen.dart` — document list with folder sidebar, search, filters, multi-select
- `frontend/lib/screens/Documents/add_document_screen.dart` — upload documents (single/multi mode)
- `frontend/lib/screens/Documents/document_details_screen.dart` — document viewer with share/permissions UI
- `frontend/lib/screens/Documents/document_viewer_screen.dart` — document content viewer
- `frontend/lib/screens/Documents/document_viewer_web.dart` — web-specific document viewer
- `frontend/lib/screens/admin/user_management_screen.dart` — admin user CRUD
- `frontend/lib/screens/admin/technician_departments_screen.dart` — technician-department mapping UI
- `frontend/lib/screens/admin/departments_screen.dart` — department management
- `frontend/lib/screens/settings_page.dart` — notification toggles, admin panels
- `frontend/lib/screens/settings/activity_log_screen.dart` — activity audit log viewer with category filtering
- `frontend/lib/screens/login_screen.dart` — login (no self-registration)
- `frontend/lib/widgets/technician_selector.dart` — technician picker bottom sheet
- `frontend/lib/widgets/work_order_card.dart` — WO card with unread badge support
- `frontend/lib/widgets/document_card.dart` — document list item with selection, rename, delete, move, share
- `frontend/lib/widgets/move_to_folder_dialog.dart` — bottom sheet for moving documents/folders
- `frontend/lib/config.dart` — base URL

### Documentation
- `ARCHITECTURE.md` — full system architecture reference
- `AGENT.md` — this file
