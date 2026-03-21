# Work Order System — Architecture

## Overview

A full-stack work order management system built with:
- **Frontend**: Flutter (cross-platform mobile/web)
- **Backend**: FastAPI (Python)
- **Database**: Supabase (PostgreSQL)
- **Auth**: Supabase Authentication
- **Push**: OneSignal

---

## Database Schema

### Core Tables

| Table | Purpose |
|-------|---------|
| `departments` | Department list (Operations, ATC, Finance, etc.) |
| `users` | All users with `user_type`, `department_id`, auth link |
| `technician_departments` | Maps technicians to departments they handle (many-to-many) |
| `work_orders` | Work orders with status, department, creator tracking |
| `work_order_assignments` | Maps WOs to assigned technicians |
| `work_order_status_logs` | Audit trail of status changes |
| `work_order_comments` | Comments on WOs (comment, status_change, system) |
| `work_order_attachments` | File attachments on WOs |

### Notification Tables

| Table | Purpose |
|-------|---------|
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
work_order_assignments.technician_id → users.id (who's assigned)
work_order_assignments.work_order_id → work_orders.id
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

### Role Details

- **Reporter**: Belongs to a department (`users.department_id`). Can create WOs targeting any department. Can only view WOs they created.
- **Technician**: Assigned to one or more departments via `technician_departments`. Can view/update/close WOs in their assigned departments.
- **Admin**: Full access. Only role that can create user accounts, manage departments, and delete WOs.

---

## API Endpoints

### Authentication & Users
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/user-role?email=` | Public | Get user role |
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
| POST | `/api/work-orders/{id}/comments` | Add comment |
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
| GET | `/api/notifications?email=` | List user notifications |
| POST | `/api/notifications/{id}/read` | Mark as read |
| POST | `/api/notifications/read-all?email=` | Mark all read |
| GET | `/api/notification-preferences?email=` | Get preferences |
| PUT | `/api/notification-preferences` | Update preferences |

---

## Authentication Flow

1. User enters email/password in Flutter login screen
2. Flutter calls `Supabase.instance.client.auth.signInWithPassword()`
3. Supabase returns JWT token + `auth.uid`
4. Frontend calls `GET /api/user-role?email=` to determine role
5. Role stored locally, used to filter views and API calls
6. Backend verifies role on each request via `user_type` in `users` table
7. RLS policies provide defense-in-depth for direct Supabase client access

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
models/            Data classes (WorkOrder, AppUser, TechnicianAssignment, etc.)
services/          API clients (WorkOrderService, UserService, etc.)
screens/           UI pages
  Work_Orders/     WO list, create/edit
  admin/           User management, technician departments, departments
  reports/         PDF report generation
  settings/        Activity log, app settings
widgets/           Reusable components (TechnicianSelector, cards, etc.)
filters/           WO filter engine
theme/             Colors, typography, theme controller
config.dart        API base URL configuration
```

### Backend (`backend/`)
```
main.py            FastAPI app, router registration, CORS
db.py              Supabase client initialization
routers/
  work_orders.py   WO CRUD, comments, attachments
  users.py         User management, activity log
  departments.py   Department CRUD
  technician_departments.py  Technician-department mapping
  notifications.py Notification endpoints
  documents.py     Document management
  folders.py       Folder management
utils/
  notification_service.py  Recipient resolution, dispatch
  notifications.py         OneSignal push integration
  activity.py              Activity audit logging
migrations/        SQL migration scripts
```

### Supabase (`supabase/`)
```
migrations/        Schema migrations (run in order by timestamp)
seed.sql           Initial seed data (departments, sample users, sample WOs)
```
