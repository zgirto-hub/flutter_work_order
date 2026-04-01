# Work Order System — Architecture

## Overview

A full-stack work order management system with file management, built with:
- **Frontend**: Flutter (cross-platform mobile/web)
- **Backend**: FastAPI (Python)
- **Database**: Supabase (PostgreSQL)
- **Auth**: Supabase Authentication
- **Push**: OneSignal
- **Storage**: Local filesystem on Linux server (`backend/uploaded_files/`), served via FastAPI static mount
- **OCR**: pytesseract + pdf2image (Arabic + English)

---

## Database Schema

### Core Tables

| Table | Purpose |
|-------|---------|
| `departments` | Department list (Operations, ATC, Finance, etc.) |
| `users` | All users with `user_type`, `department_id`, auth link |
| `technician_departments` | Maps technicians to departments they handle (many-to-many) |
| `work_orders` | Work orders with status, department, creator tracking; includes `closed_by` (user UUID) and `closed_at` |
| `work_order_assignments` | Maps WOs to assigned technicians |
| `work_order_status_logs` | Audit trail of status changes |
| `work_order_comments` | Comments on WOs (comment, status_change, system) |
| `work_order_attachments` | File attachments on WOs |
| `recurring_inspections` | Scheduled recurring inspection tasks with frequency, department, and `next_due` date |
| `recurring_inspection_assignees` | Maps recurring inspections to assigned technicians (many-to-many) |
| `recurring_inspection_logs` | Completion log for each due instance of a recurring inspection |

### File Tables

| Table | Purpose |
|-------|---------|
| `files` | Uploaded files with metadata, parsed text, folder assignment |
| `file_folders` | Hierarchical folder structure (self-referencing `parent_id`) |
| `resource_permissions` | Role-based sharing for files and folders (viewer/editor) |

### Activity & Notification Tables

| Table | Purpose |
|-------|---------|
| `user_activity_log` | Comprehensive audit trail (auth, WO, file, folder actions) |
| `notifications` | In-app notification records |
| `notification_preferences` | Per-user notification settings (mute, filters) |
| `notification_delivery_logs` | Push delivery tracking with retry support |
| `work_order_watchers` | Users watching specific WOs |

### Key Relationships

```
users.department_id → departments.id          (user belongs to department)
technician_departments.technician_id → users.id   (technician handles departments)
technician_departments.department_id → departments.id
work_orders.department_id → departments.id     (WO targets a department)
work_orders.created_by → users.id              (who reported it)
work_orders.closed_by  → users.id              (who closed it — UUID, set on close)
work_order_assignments.technician_id → users.id (who's assigned)
work_order_assignments.work_order_id → work_orders.id
recurring_inspections.department_id → departments.id
recurring_inspection_assignees.recurring_inspection_id → recurring_inspections.id
recurring_inspection_assignees.fixer_id → users.id
files.folder_id → file_folders.id              (file in folder)
file_folders.parent_id → file_folders.id       (folder hierarchy)
resource_permissions.resource_id → files.id or file_folders.id
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
| Upload files | Yes | Yes | Yes |
| Share files | Own/Editor | Own/Editor | Own/Editor |

### Role Details

- **Reporter**: Belongs to a department (`users.department_id`). Can create WOs targeting any department. Can only view WOs they created.
- **Technician**: Assigned to one or more departments via `technician_departments`. Can view/update/close WOs in their assigned departments.
- **Admin**: Full access. Only role that can create user accounts, manage departments, and delete WOs.

### File Permission Model

Files and folders use a separate role-based permission system via `resource_permissions`:
- **Owner**: Full control (view, download, rename, move, delete, share, edit_type). Determined by `uploaded_by`/`created_by`.
- **Editor**: Can view, download, rename, move, share, edit_type — cannot delete.
- **Viewer**: Can view and download only.
- Permissions inherit through folder hierarchy (walks up parent chain via `backend/utils/permissions.py`).
- Role priority: viewer(1) < editor(2) < owner(3).

---

## API Endpoints

### Authentication & Users
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/user-role?email=` | Public | Get user role |
| GET | `/api/users/me?email=` | Public | Get current user profile |
| GET | `/api/users?department_id=` | Any | List users; optional `department_id` filters to technicians assigned to that department |
| GET | `/api/users/{id}` | Any | Get user by ID |
| POST | `/api/users?admin_email=` | Admin | Create user |
| PATCH | `/api/users/{id}?admin_email=` | Admin | Update user |
| PATCH | `/api/users/{id}/role?admin_email=` | Admin | Change role |
| PATCH | `/api/users/{id}/deactivate?admin_email=` | Admin | Deactivate |
| PATCH | `/api/users/{id}/activate?admin_email=` | Admin | Reactivate |

### Work Orders
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/work-orders?email=&user_role=&status=&type=` | Role-filtered | List WOs |
| GET | `/api/work-orders/{id}?email=&user_role=` | Role-checked | Get single WO |
| POST | `/api/work-orders` | Any | Create WO |
| PUT | `/api/work-orders/{id}?user_email=` | Tech/Admin | Update WO |
| POST | `/api/work-orders/{id}/close?user_email=` | Tech/Admin | Close WO |
| DELETE | `/api/work-orders/{id}?user_email=` | Tech/Admin | Delete WO |
| DELETE | `/api/work-orders?ids=&user_email=` | Tech/Admin | Bulk delete |

### Work Order Sub-resources
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/work-orders/{id}/comments` | List comments |
| POST | `/api/work-orders/{id}/comments` | Add comment (triggers notifications) |
| GET | `/api/work-orders/{id}/attachments` | List attachments |
| POST | `/api/work-orders/{id}/attachments` | Upload attachment |
| DELETE | `/api/work-orders/{id}/attachments/{att_id}` | Delete attachment |
| GET | `/api/work-orders/{id}/status-history` | Status audit trail |

### Departments
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/departments` | List active departments |
| GET | `/api/departments/all` | List all department names |
| GET | `/api/departments/{id}` | Get department by ID |
| POST | `/api/departments` | Create department |
| PATCH | `/api/departments/{id}` | Update department |
| DELETE | `/api/departments/{id}` | Delete department |
| GET | `/api/departments/{id}/technician-count` | Technician count |
| GET | `/api/departments/{id}/work-order-count` | WO count |

### Technician-Department Mapping
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/technician-departments` | All mappings |
| GET | `/api/technician-departments/user/{id}` | Departments for a technician |
| GET | `/api/technician-departments/department/{name}` | Technicians for a department |
| POST | `/api/technician-departments` | Add single mapping |
| POST | `/api/technician-departments/bulk/{id}` | Set all departments for technician |
| DELETE | `/api/technician-departments/{id}/{dept}` | Remove mapping |

### Files
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/upload` | Upload file with auto text extraction |
| DELETE | `/api/delete/{file_id}` | Delete file |
| POST | `/api/share-file` | Share file (form: file_id, owner_email, share_with, role) |
| GET | `/api/file-shares/{file_id}` | List shares on a file |
| DELETE | `/api/remove-share` | Revoke a file share |
| GET | `/api/file-uploaders` | List all distinct file uploaders |
| GET | `/api/files/{file_id}/my-role?user_email=` | Get user's effective role on file |

### Folders
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/folders?parent_id=&user_email=&all=` | List folders |
| POST | `/api/folders` | Create folder (body: name, parent_id, created_by, is_private) |
| PATCH | `/api/folders/{folder_id}/rename` | Rename folder |
| DELETE | `/api/folders/{folder_id}` | Delete folder (orphans files to root) |
| PATCH | `/api/folders/{folder_id}/move` | Move folder to new parent |
| PATCH | `/api/files/{file_id}/move` | Move file to folder |

### Notifications
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/notification-preferences?email=` | Get preferences |
| PATCH | `/api/notification-preferences` | Update preferences |
| GET | `/api/work-orders/{id}/watchers` | List watchers |
| POST | `/api/work-orders/{id}/watchers` | Add watcher |
| DELETE | `/api/work-orders/{id}/watchers?email=` | Remove watcher |
| GET | `/api/notifications?email=&unread_only=&limit=&offset=` | List notifications |
| GET | `/api/notifications/unread-count?email=` | Unread count |
| PATCH | `/api/notifications/{id}/read?email=` | Mark as read |
| PATCH | `/api/notifications/read-all?email=` | Mark all read |
| DELETE | `/api/notifications?email=` | Clear all |
| GET | `/api/work-orders/{id}/notification-debug?commenter_email=` | Debug recipients |

### Activity Log
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/activity-log?category=&limit=&offset=` | Get activity log (category: `work_order`, `file`, `folder`, `auth`, `admin`) |
| POST | `/api/activity-log/sign-in` | Log sign-in |
| POST | `/api/activity-log/sign-out` | Log sign-out |
| POST | `/api/activity-log/update-check` | Log app update check |

### Reports
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/reports/closed-work-orders?technician_id=&start_date=&end_date=` | List closed WOs for a technician in a date range |
| POST | `/api/reports/monthly-tasks` | Generate monthly task PDF; returns raw PDF bytes (streams inline) |

The `/api/reports/monthly-tasks` endpoint accepts a JSON body with `name`, `start_date`, `end_date`, `tasks`, `department`, `section`, `title`, `dgca_id`, `civil_id`. Rendered by `reportlab` on the backend using logos from `backend/assets/`. The Flutter `ReportService` wraps both endpoints.

### Recurring Inspections
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/recurring-inspections?department_id=` | List all recurring inspections (optional department filter) |
| GET | `/api/recurring-inspections/{ri_id}` | Get single recurring inspection |
| POST | `/api/recurring-inspections` | Create recurring inspection |
| PUT | `/api/recurring-inspections/{ri_id}?user_email=` | Update recurring inspection |
| DELETE | `/api/recurring-inspections/{ri_id}?user_email=` | Delete recurring inspection |
| POST | `/api/recurring-inspections/generate` | Auto-generate due inspection instances |
| GET | `/api/recurring-inspections/calendar?month=&year=` | Calendar view of due dates for a given month |

---

## Authentication Flow

1. User enters email/password in Flutter login screen
2. Flutter calls `Supabase.instance.client.auth.signInWithPassword()`
3. Supabase returns JWT token + `auth.uid`
4. Frontend calls `GET /api/user-role?email=` to determine role
5. Role stored locally, used to filter views and API calls
6. Backend verifies role on each request via `user_type` in `users` table
7. RLS policies provide defense-in-depth for direct Supabase client access

**Account creation**: Admin-only. No self-registration. Admin calls `POST /api/users?admin_email=` which creates both the Supabase auth user and the `users` table record.

**PWA link handling**: The login screen opens external URLs (e.g., the system intro page) using `openInNewTab()` from `frontend/lib/utils/download_helper_web.dart` via conditional import, not `url_launcher`. This preserves the PWA gesture context. Any screen that needs to open a URL in the web/PWA build should follow this same pattern.

---

## File Storage & Upload

### Where Files Live

All uploaded files — both managed files and work order attachments — are stored on the **local Linux server filesystem**, not in a cloud object store.

```
backend/
└── uploaded_files/          ← runtime directory, created on startup
    ├── <uuid>.<ext>         ← files feature uploads (e.g. a1b2c3d4.pdf)
    └── wo_<uuid>.<ext>      ← work order attachments (e.g. wo_a1b2c3d4.jpg)
```

FastAPI mounts this directory as a static file server on startup (`main.py`):
```python
UPLOAD_DIR = "uploaded_files"
os.makedirs(UPLOAD_DIR, exist_ok=True)
app.mount("/files", StaticFiles(directory=UPLOAD_DIR), name="files")
```

Files are served at `GET /files/<filename>` and opened by the Flutter client via `url_launcher`.

### Upload Flow

```
Flutter (FilePicker)
  │  multipart/form-data POST
  ▼
Nginx (port 80, client_max_body_size 50MB)
  │  proxy_pass → http://127.0.0.1:8000
  ▼
FastAPI backend (port 8000)
  ├─ Validate: extension allowlist, 10 MB size limit
  ├─ Images: compress/resize to max 1920 px (Pillow), convert to JPEG if needed
  ├─ Generate filename: wo_<uuid>.<ext>  or  <uuid>.<ext>
  ├─ Write to  uploaded_files/<filename>
  └─ Insert metadata row in Supabase (work_order_attachments or files)
  │  returns { file_url: "/files/<filename>" }
  ▼
Flutter stores the URL and renders AttachmentWidget
User opens → launchUrl(baseUrl + file_url)
```

### Allowed File Types & Limits

| Upload type | Extensions | Max size (backend) | Notes |
|---|---|---|---|
| Work order attachment | pdf, doc, docx, jpg, jpeg, png, gif | 10 MB | Images auto-compressed |
| File | pdf, doc, docx, txt, jpg, jpeg, png | — | Text extracted for search |

Nginx enforces a separate 50 MB ceiling (`client_max_body_size 50M`).

---

## File Management System

### Folder Sidebar (Desktop/Web Layout)

The files screen uses a two-column layout on wider viewports: a left folder sidebar and a right content area. The sidebar width is user-adjustable via a drag handle (the `VerticalDivider` was replaced by a `MouseRegion` + `GestureDetector` resize handle). Width is clamped to 60–280 px (default 116 px) and stored in `_sidebarWidth` state on `FilesScreen`.

### Folder Navigation Transitions

Navigating between folders uses an animated horizontal slide transition powered by the `animations` package (`PageTransitionSwitcher` + `SharedAxisTransition`). The transition direction is determined by comparing the depth of the destination folder with the current folder: going deeper (or staying at the same level) slides forward; navigating to a parent slides backward. The `_navigateTo(String? folderId)` helper computes direction via `_folderDepth()` and updates `_navigatingForward` before changing `_selectedFolderId`. All folder tap handlers in the sidebar, breadcrumb, and subfolder chips use `_navigateTo()` instead of directly setting `_selectedFolderId`. The `animations` package is required in `pubspec.yaml`.

### Upload & Text Extraction
- Files uploaded via `POST /api/upload`, saved to `uploaded_files/` on the Linux server
- Auto text extraction on upload using `backend/utils/text_extraction.py`:
  - **PDF**: PyPDF2
  - **DOCX**: python-docx
  - **TXT**: direct read
  - **JPG/PNG**: OCR via pytesseract + pdf2image
- Supports Arabic + English (`lang="ara+eng"`)
- Arabic text normalized via NFKC (`normalize_arabic()`)
- Extracted text stored in `files.parsed_text`

### Folder Hierarchy
- Folders can be nested via `parent_id` self-reference on `file_folders`
- Deleting a folder orphans its files back to root (sets `folder_id = NULL`)
- Folders can be moved to new parents

### Permission Inheritance
- Permissions checked via `backend/utils/permissions.py`
- `get_effective_role(user_email, resource_id, resource_type)` resolves role; `resource_type` value is `'file'` (was `'document'`)
- For files in folders, permission walks up the folder chain
- Role priority: viewer(1) < editor(2) < owner(3)
- Owner is determined by `uploaded_by` (files) or `created_by` (folders)

---

## Work Order Assignment

Technician assignment is always explicit. When a WO is created via `POST /api/work-orders`:
- If the request body includes technician IDs, those technicians are inserted into `work_order_assignments`.
- If no technicians are selected and the creating user is a technician with `technician_auto_assign_self = true` in `notification_preferences`, the backend automatically assigns only that technician.
- There is no fallback that assigns all technicians in a department. If neither condition above is met, the WO is created unassigned.

---

## Work Order Closure Tracking

When a work order is closed — either at creation time (created directly as "Closed") or via the `POST /close` endpoint — the backend records:
- `closed_at`: UTC timestamp of the closure
- `closed_by`: UUID of the user who closed it (resolved from `user_email` via `_get_user_id_by_email()`)

Both fields are set in `backend/routers/work_orders.py`. The `closed_by` UUID is used by the Reports feature to query each technician's closed work history.

---

## PDF Report Generation

Two report types are available, each with a separate generation path.

### Work Order Report (client-side PDF)
- Screen: `frontend/lib/screens/reports/workorder_report_screen.dart`
- Service: `frontend/lib/services/pdf/work_order_pdf_service.dart` + `ReportService.getClosedWorkOrders()`
- Data source: `GET /api/reports/closed-work-orders` returns WOs closed by a technician in a date range
- PDF is built in-browser using the `pdf` Flutter package (no server rendering)
- Theme is selected from `WorkOrderPdfTheme` enum (four variants)

#### PDF Theme Variants

| Enum value | Label | Preview asset |
|---|---|---|
| `copperNight` | Claude Minimal | `assets/report_preview.html` |
| `forestLedger` | Forest Ledger | `assets/report_preview_green.html` |
| `signalOrange` | Signal Orange | `assets/report_preview_teal.html` |
| `formalElegant` | Formal Elegant | `assets/report_preview_burgundy.html` |

Each HTML file in `frontend/assets/` is a self-contained design reference rendered inside `HtmlPreviewScreen` (web `iframe` via `html_unescape`). The enum's `previewAsset` getter maps each theme to its file. The `formalElegant` theme uses a full-bleed dark top bar with Times Roman serif typography; all others share a card-based layout with palette-specific accent colors.

### Monthly Task Report (server-side PDF)
- Screen: `frontend/lib/screens/reports/monthly_task_report_screen.dart`
- Service: `frontend/lib/services/report_service.dart` (`ReportService.generateMonthlyTasksReport()`)
- Data flow: Flutter POSTs task list JSON to `POST /api/reports/monthly-tasks`; backend renders PDF via `reportlab` and streams it back as `application/pdf`
- Backend logos (`backend/assets/logo_civilaviation.png`, `logo_emblem.png`, `logo_newkuwait.png`) are embedded into the PDF header

---

## Recurring Inspections

### Overview
Recurring inspections are scheduled maintenance tasks that repeat on a defined frequency. They are distinct from one-off work orders and have their own calendar-driven UI.

### Database Tables
- `recurring_inspections`: core record — title, department, frequency (`daily`/`weekly`/`monthly`/`yearly`), interval, `day_of_week`, `day_of_month`, `next_due`, `start_date`. The API may return a computed `generated_today` boolean indicating a work order was created from this inspection today.
- `recurring_inspection_assignees`: many-to-many link between inspection and assigned technicians (`fixer_id → users.id`)
- `recurring_inspection_logs`: completion records per due instance

### Frequency Computation
`_compute_next_due()` and `_advance_next_due()` in `backend/routers/recurring_inspections.py` calculate the next due date from frequency parameters. The `POST /api/recurring-inspections/generate` endpoint should be called periodically (e.g., via cron) to advance `next_due` for overdue inspections and write log entries.

### Frontend

#### Calendar Screen (`frontend/lib/screens/calendar/calendar_screen.dart`)

The calendar screen computes all event placements entirely on the client. It does **not** use the `/api/recurring-inspections/calendar` backend endpoint for rendering markers; that endpoint remains available but is unused by this screen.

**Data flow:**
1. On init, `_loadInspections()` calls `RecurringInspectionService.fetchAll(isActive: true)` — `GET /api/recurring-inspections?is_active=true` — loading the full active inspection list once.
2. `_buildEventCache()` iterates a bounded window (60 days past → 120 days future from today) and calls `_computeEventsForDay()` for each day, storing results in `Map<DateTime, List<RecurringInspection>>`.
3. `TableCalendar`'s `eventLoader` calls `_getEventsForDay()`, which is an O(1) map lookup against the pre-built cache.
4. When the user pages the calendar outside the cache window, `_buildEventCache()` is triggered again to cover the new viewport.

**Client-side recurrence matching (`_computeEventsForDay`):**

| Frequency | Match condition |
|-----------|----------------|
| `daily` | Every `interval` days from `startDate` |
| `weekly` | Matches `dayOfWeek` (0=Mon..6=Sun); every `interval` weeks from `startDate` |
| `monthly` | Matches `dayOfMonth`; every `interval` months from `startDate` |
| `yearly` | Matches month+day of `startDate`; every `interval` years |

Days before `startDate` and after `endDate` (when set) are always excluded.

**Role-gated actions in header (both require `admin` or `technician` role):**
- Bolt icon button: calls `_generateDue()`, which invokes `RecurringInspectionService.generateDue()` → `POST /api/recurring-inspections/generate`. Shows a spinner while in-flight and a floating snackbar with the count of work orders created or skipped. Reloads the inspection list if any were created.
- Plus icon button: navigates to `AddRecurringInspectionScreen`.

Tapping an inspection card in the day's event list navigates to `AddRecurringInspectionScreen` with the existing `RecurringInspection` passed as `existing`, enabling inline editing.

**"Generated" badge:** Each inspection card in the event list shows a green "Generated" badge when `RecurringInspection.generatedToday == true`. This field is populated from the `generated_today` boolean returned by the API.

**Other files:**
- Add/Edit screen: `frontend/lib/screens/calendar/add_recurring_inspection_screen.dart`
- Model: `frontend/lib/models/recurring_inspection.dart`
- Service: `frontend/lib/services/recurring_inspection_service.dart`

#### Add/Edit Screen (`frontend/lib/screens/calendar/add_recurring_inspection_screen.dart`)

Redesigned with an iOS Calendar-style header (circular X cancel, checkmark save, and delete buttons). When **creating** a new entry, the screen shows a two-tab selector — but only for `admin` role. `technician` role always opens directly in inspection mode.

| Tab | Role visibility | Purpose |
|-----|----------------|---------|
| `workOrder` | `admin` only | Create a one-off work order directly from the calendar screen |
| `inspection` | `admin` and `technician` | Create a new recurring inspection |

When **editing** an existing inspection (`existing != null`), the tab selector is hidden regardless of role and the form always opens in inspection mode.

**Repeat options** are expressed via the `_RepeatOption` enum and rendered as inline picker rows (no bottom sheet):

| `_RepeatOption` | Maps to frequency/interval |
|---|---|
| `never` | One-time (end date = start date) |
| `everyDay` | `daily`, interval 1 |
| `everyWeek` | `weekly`, interval 1 |
| `every2Weeks` | `weekly`, interval 2 |
| `everyMonth` | `monthly`, interval 1 |
| `everyYear` | `yearly`, interval 1 |
| `custom` | User-specified frequency string + interval |

**Inspection type** is a separate picker (`_showInspectionTypePicker`) that opens as a modal bottom sheet. Valid values are `Technical`, `Inspection`, and `Other`. The selected type is stored in `_inspectionType` and submitted as `type` in both create and update calls. When editing, the existing `type` value is restored from `widget.existing!.type`.

Department and work-order type selections open as modal bottom sheets (`_showDepartmentPicker`, `_showTypePicker`). Technician selection uses the shared `TechnicianSelector` bottom sheet; selecting technicians no longer auto-dismisses the bottom sheet (the `Navigator.pop` in `onChanged` was removed — the user must close it manually).

The screen imports and uses `WorkOrderService` to create a work order when the Work Order tab is saved.

---

## Notification System

### Comment Notifications
When a comment is added to a WO, notifications go to:
1. **Creator** — the user who created the WO (`work_orders.created_by`)
2. **Assigned technicians** — from `work_order_assignments.technician_id`
3. **Watchers** — from `work_order_watchers`
4. **Admin opt-in** — admins with `admin_all_workorder_comments = true`

The commenter is always excluded from their own notification.

### Delivery Channels
- **In-app**: Stored in `notifications` table, queried by frontend
- **Push**: Sent via OneSignal to user's external ID (email)

### Preference Filtering
Each user can control via `notification_preferences`:
- `mute_all` — suppress all notifications
- `comment_notifications` — toggle comment notifications
- `status_notifications` — toggle status change notifications
- `push_enabled` / `in_app_enabled` — per-channel toggles
- `admin_all_workorder_comments` — admin opt-in for all WO comment notifications
- `technician_auto_assign_self` — (technician only) auto-assign the technician to any work order they create; surfaced as "Auto-assign me" in Settings > Notifications

### OneSignal Integration
- App ID: `760f00e5-fb08-4c0c-b898-ea35737bcc21`
- API key: env var `ONESIGNAL_API_KEY`
- Frontend sets external ID via `OneSignal.login(email)` on web

### Foreground Sound Logic (work_order_home.dart)
- Poll unread count every 20s
- `SystemSound.play(SystemSoundType.alert)` only when:
  - App is in foreground (`WidgetsBindingObserver` + `AppLifecycleState.resumed`)
  - Unread count increased since last poll
  - First poll is always silent (`soundPrimed` flag)

---

## Row Level Security (RLS)

RLS is enabled on `work_orders` as defense-in-depth:

| Policy | Role | Access |
|--------|------|--------|
| `reporter_own_wos` | Reporter | SELECT own WOs only |
| `technician_department_wos` | Technician | SELECT department WOs only |
| `admin_all_wos` | Admin | SELECT all |
| `authenticated_insert_wos` | Any auth'd | INSERT |
| `admin_technician_update_wos` | Tech/Admin | UPDATE |
| `admin_delete_wos` | Admin | DELETE |

**Note**: The backend uses a Supabase service role key, so RLS does not affect backend queries. RLS protects against direct Flutter/Supabase SDK access only.

---

## Project Structure

### Frontend (`frontend/lib/`)
```
models/            Data classes (WorkOrder, AppUser, TechnicianAssignment, FileModel,
                   FolderModel, ActivityLogEntry, WorkOrderReport, RecurringInspection)
services/          API clients
  WorkOrderService, UserService, FileService, FolderService,
  ActivityLogService, RecurringInspectionService,
  ReportService              (closed-WO query + monthly-task PDF generation)
  pdf/work_order_pdf_service.dart  (client-side PDF builder with 4 themes)
screens/           UI pages
  Work_Orders/     WO list, create/edit (add_work_order.dart: department-filtered technician load)
  Files/           File list, upload, details, viewer (with web-specific viewer)
  admin/           User management, technician departments, departments
  calendar/        Recurring inspections calendar + add/edit screen
  reports/         workorder_report_screen.dart  (WO PDF with theme picker)
                   monthly_task_report_screen.dart  (monthly PDF, server-rendered)
                   html_preview_screen.dart  (PDF theme preview via HTML iframe)
  settings/        Activity log, app settings
widgets/           Reusable components (TechnicianSelector, work_order_card, file_card,
                   move_to_folder_dialog, pdf_preview_screen, etc.)
filters/           WO filter engine, file_filter_engine.dart
theme/             Colors, typography, theme controller
config.dart        API base URL configuration
```

**Frontend assets (`frontend/assets/`)**
```
images/                       Logo PNGs (logo_civilaviation, logo_emblem, logo_newkuwait)
report_preview.html           Claude Minimal PDF theme design reference
report_preview_green.html     Forest Ledger PDF theme design reference
report_preview_teal.html      Signal Orange PDF theme design reference
report_preview_burgundy.html  Formal Elegant PDF theme design reference
```

### Backend (`backend/`)
```
main.py            FastAPI app, router registration, CORS
db.py              Supabase client initialization
routers/
  work_orders.py   WO CRUD, comments, attachments, status history; sets closed_by + closed_at on close
  users.py         User management; GET /users accepts ?department_id for server-side technician filter;
                   list_users() uses 2-query bulk fetch (no N+1) for technician departments
  departments.py   Department CRUD, technician/WO counts
  technician_departments.py  Technician-department mapping
  notifications.py Notification endpoints, watchers, preferences
  files.py         File upload, delete, sharing, permissions
  folders.py       Folder CRUD, move files/folders
  reports.py       GET /reports/closed-work-orders; POST /reports/monthly-tasks (reportlab PDF)
  recurring_inspections.py  Recurring inspection CRUD, calendar view, due-instance generation
assets/
  logo_civilaviation.png    Embedded in monthly task PDF header
  logo_emblem.png
  logo_newkuwait.png
utils/
  notification_service.py  Recipient resolution + dispatch orchestration
  notifications.py         OneSignal HTTP helpers
  activity.py              Activity audit logging (fire-and-forget)
  permissions.py           File/folder permission engine (role inheritance)
  text_extraction.py       Text extraction from PDF, DOCX, TXT, images (OCR)
migrations/        SQL migration scripts (legacy, use supabase/migrations/ instead)
```

### Scripts (`scripts/`)
```
deploy_frontend.sh       Frontend deployment
bump_version.sh          Version bumping
update_nginx_config.sh   Nginx configuration update
rollback_frontend.sh     Frontend rollback
```

### Supabase (`supabase/`)
```
migrations/        Schema migrations (run in order by timestamp)
  20260321_recurring_inspections.sql  Adds recurring_inspections, recurring_inspection_assignees,
                                      recurring_inspection_logs tables
seed.sql           Initial seed data (departments, sample users, sample WOs)
```

---

## Deployment & Infrastructure

### Linux Server

The backend and web frontend are hosted on a single Linux server. Nginx acts as the reverse proxy, and the Flutter web build is served as static files.

```
Internet / Tailscale
        │
        ▼
   Nginx (port 80 / 443)
   ┌─────────────────────────────────────────────────────┐
   │  /              → serve Flutter web build (static)  │
   │  /api/*         → proxy_pass http://127.0.0.1:8000  │
   │  /files/*       → proxy_pass http://127.0.0.1:8000  │
   │  client_max_body_size 50M                           │
   └─────────────────────────────────────────────────────┘
        │
        ▼
   FastAPI / Uvicorn (port 8000)
   ├─ API routes  (/api/*)
   └─ Static files (/files/* → uploaded_files/)
```

### Environments

| Environment | API Base URL | Notes |
|---|---|---|
| Development | `http://100.85.73.37:8000/api` | Direct to FastAPI, no Nginx |
| Production | `https://zorin.taila92fe8.ts.net/api` | Via Tailscale, through Nginx |

Configured in `frontend/lib/config.dart` — toggle `kIsProduction` to switch.

### Nginx Key Settings (`nginx_flutter_app.conf`)

```nginx
client_max_body_size 50M;          # upload ceiling

location /api/ {
    proxy_pass http://127.0.0.1:8000;
}

location /files/ {
    proxy_pass http://127.0.0.1:8000;  # served by FastAPI StaticFiles
}

location / {
    root /path/to/flutter/build/web;   # Flutter web build
    try_files $uri $uri/ /index.html;
}
```

### Deployment Scripts (`scripts/`)

| Script | Purpose |
|---|---|
| `deploy_frontend.sh` | Build Flutter web and copy to Nginx root |
| `bump_version.sh` | Bump app version in pubspec.yaml |
| `update_nginx_config.sh` | Apply updated Nginx config and reload |
| `rollback_frontend.sh` | Roll back to previous frontend build |

### Key Runtime Directories on Server

```
backend/
└── uploaded_files/     ← all uploaded files (files feature + WO attachments)
                          persisted on disk; not backed up to cloud storage
```

> **Note**: Files in `uploaded_files/` are not replicated or backed up automatically. Server disk is the single source of truth for binary files; metadata is in Supabase.
