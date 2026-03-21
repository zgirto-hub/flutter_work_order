# Work Order App — Agent Reference

## Project Overview

Flutter frontend + FastAPI backend work order management app.
- Frontend: `frontend/` (Flutter web)
- Backend: `backend/` (FastAPI)
- Database: Supabase (Postgres + Auth + Admin API)
- Push: OneSignal

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

- **Reporter**: Belongs to a department (`users.department_id`). Can create WOs targeting any department. Can only view WOs they created.
- **Technician**: Assigned to one or more departments via `technician_departments`. Can view/update/close WOs in their assigned departments.
- **Admin**: Full access. Only role that can create user accounts, manage departments, and delete WOs.

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
```

---

## API Endpoints

### Authentication & Users
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/user-role?email=` | Public | Get user role (404 if not found) |
| GET | `/api/users/me?email=` | Public | Get current user profile |
| GET | `/api/users` | Any | List all users |
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
| GET | `/api/activity-log?category=&limit=&offset=` | Get activity log |
| POST | `/api/activity-log/sign-in` | Log sign-in |
| POST | `/api/activity-log/sign-out` | Log sign-out |

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

### Foreground Sound Logic (work_order_home.dart)
- Poll unread count every 20s
- `SystemSound.play(SystemSoundType.alert)` only when:
  - App is in foreground (`WidgetsBindingObserver` + `AppLifecycleState.resumed`)
  - Unread count increased since last poll
  - First poll is always silent (`soundPrimed` flag)

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

---

## Supabase CLI & MCP

### CLI Setup
- **Binary**: `supabase.exe` in project root (v2.78.1)
- **Linked project**: `rydrqsjofoulwdtwfbgv` (Work orders Project)
- **Commands**:
  - `./supabase.exe db push` — push migrations to cloud
  - `./supabase.exe db reset` — reset cloud database
  - `./supabase.exe migration new <name>` — create new migration

### MCP Setup (Remote)
- **Config file**: `opencode.jsonc` in project root
- **URL**: `https://mcp.supabase.com/mcp`
- **Project scope**: `rydrqsjofoulwdtwfbgv`

---

## Conventions & Patterns

- **Lint**: `flutter analyze` (frontend), `python -m py_compile` (backend)
- **Deploy**: `bash scripts/deploy_frontend.sh --no-bump`
- **Version bump**: `bash scripts/bump_version.sh`
- **Migrations**: Run SQL files from `supabase/migrations/` in Supabase SQL Editor (in timestamp order), or use `supabase db push`
- **Debug notifications**: `GET /api/work-orders/{id}/notification-debug?commenter_email=...`
- **Backend failures are best-effort**: Comment creation must never block on notification failure. All notification calls wrapped in try/except.

---

## Project Structure

### Frontend (`frontend/lib/`)
```
models/            Data classes (WorkOrder, AppUser, TechnicianAssignment, etc.)
services/          API clients (WorkOrderService, UserService, TechnicianDepartmentService, etc.)
screens/           UI pages
  Work_Orders/     WO list, create/edit
  admin/           User management, technician departments, departments
  reports/         PDF report generation
  settings/        Activity log, app settings
widgets/           Reusable components (TechnicianSelector, work_order_card, etc.)
filters/           WO filter engine
theme/             Colors, typography, theme controller
config.dart        API base URL configuration
```

### Backend (`backend/`)
```
main.py            FastAPI app, router registration, CORS
db.py              Supabase client initialization
routers/
  work_orders.py   WO CRUD, comments, attachments, status history
  users.py         User management (admin-only creation), activity log
  departments.py   Department CRUD, technician/WO counts
  technician_departments.py  Technician-department mapping
  notifications.py Notification endpoints, watchers, preferences
  documents.py     Document management
  folders.py       Folder management
utils/
  notification_service.py  Recipient resolution + dispatch orchestration
  notifications.py         OneSignal HTTP helpers
  activity.py              Activity audit logging
migrations/        SQL migration scripts (legacy, use supabase/migrations/ instead)
```

### Supabase (`supabase/`)
```
migrations/        Schema migrations (run in timestamp order)
seed.sql           Initial seed data (departments, sample users, sample WOs)
```

---

## Relevant Files Directory

### Backend
- `backend/main.py` — router registration
- `backend/routers/work_orders.py` — WO CRUD, comments, attachments, notification dispatch
- `backend/routers/users.py` — user management (admin-only), role checks, activity log
- `backend/routers/departments.py` — department CRUD, technician/WO counts
- `backend/routers/technician_departments.py` — technician-department mapping CRUD
- `backend/routers/notifications.py` — notification/watcher/preference APIs
- `backend/utils/notification_service.py` — recipient resolution + dispatch orchestration
- `backend/utils/notifications.py` — OneSignal HTTP helpers
- `backend/utils/activity.py` — activity audit logging

### Frontend
- `frontend/lib/models/user.dart` — AppUser model (UserType: admin, technician, reporter)
- `frontend/lib/models/work_order.dart` — WorkOrder model with TechnicianAssignment list
- `frontend/lib/models/technician_assignment.dart` — TechnicianAssignment model
- `frontend/lib/services/user_service.dart` — user API client (fetchTechnicians, getTechnicianDepartments, etc.)
- `frontend/lib/services/work_order_service.dart` — work order API client
- `frontend/lib/services/technician_department_service.dart` — technician-department mapping API
- `frontend/lib/services/notification_service.dart` — notification API client
- `frontend/lib/screens/Work_Orders/work_order_home.dart` — WO list with badges + sound
- `frontend/lib/screens/Work_Orders/add_work_order.dart` — WO create/edit with technician selector
- `frontend/lib/screens/admin/user_management_screen.dart` — admin user CRUD
- `frontend/lib/screens/admin/technician_departments_screen.dart` — technician-department mapping UI
- `frontend/lib/screens/admin/departments_screen.dart` — department management
- `frontend/lib/screens/settings_page.dart` — notification toggles, admin panels
- `frontend/lib/screens/login_screen.dart` — login (no self-registration)
- `frontend/lib/widgets/technician_selector.dart` — technician picker bottom sheet
- `frontend/lib/widgets/work_order_card.dart` — WO card with unread badge support
- `frontend/lib/config.dart` — base URL

### Documentation
- `ARCHITECTURE.md` — full system architecture reference
- `AGENTS.md` — this file
