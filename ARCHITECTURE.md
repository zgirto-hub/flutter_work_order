# Work Order System — Architecture

## Overview

A full-stack work order management system with document management, built with:
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
| `work_orders` | Work orders with status, department, creator tracking |
| `work_order_assignments` | Maps WOs to assigned technicians |
| `work_order_status_logs` | Audit trail of status changes |
| `work_order_comments` | Comments on WOs (comment, status_change, system) |
| `work_order_attachments` | File attachments on WOs |

### Document Tables

| Table | Purpose |
|-------|---------|
| `documents` | Uploaded documents with metadata, parsed text, folder assignment |
| `document_folders` | Hierarchical folder structure (self-referencing `parent_id`) |
| `resource_permissions` | Role-based sharing for documents and folders (viewer/editor) |

### Activity & Notification Tables

| Table | Purpose |
|-------|---------|
| `user_activity_log` | Comprehensive audit trail (auth, WO, document, folder actions) |
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
documents.folder_id → document_folders.id      (document in folder)
document_folders.parent_id → document_folders.id (folder hierarchy)
resource_permissions.resource_id → documents.id or document_folders.id
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

### Role Details

- **Reporter**: Belongs to a department (`users.department_id`). Can create WOs targeting any department. Can only view WOs they created.
- **Technician**: Assigned to one or more departments via `technician_departments`. Can view/update/close WOs in their assigned departments.
- **Admin**: Full access. Only role that can create user accounts, manage departments, and delete WOs.

### Document Permission Model

Documents and folders use a separate role-based permission system via `resource_permissions`:
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

### Documents
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/upload` | Upload file with auto text extraction |
| DELETE | `/api/delete/{doc_id}` | Delete document |
| POST | `/api/share-document` | Share document (form: document_id, owner_email, share_with, role) |
| GET | `/api/document-shares/{doc_id}` | List shares on a document |
| DELETE | `/api/remove-share` | Revoke a document share |
| GET | `/api/document-uploaders` | List all distinct document uploaders |
| GET | `/api/documents/{doc_id}/my-role?user_email=` | Get user's effective role on document |

### Folders
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/folders?parent_id=&user_email=&all=` | List folders |
| POST | `/api/folders` | Create folder (body: name, parent_id, created_by, is_private) |
| PATCH | `/api/folders/{folder_id}/rename` | Rename folder |
| DELETE | `/api/folders/{folder_id}` | Delete folder (orphans documents to root) |
| PATCH | `/api/folders/{folder_id}/move` | Move folder to new parent |
| PATCH | `/api/documents/{doc_id}/move` | Move document to folder |

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
| POST | `/api/activity-log/update-check` | Log app update check |

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

## File Storage & Upload

### Where Files Live

All uploaded files — both documents and work order attachments — are stored on the **local Linux server filesystem**, not in a cloud object store.

```
backend/
└── uploaded_files/          ← runtime directory, created on startup
    ├── <uuid>.<ext>         ← documents (e.g. a1b2c3d4.pdf)
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
  └─ Insert metadata row in Supabase (work_order_attachments or documents)
  │  returns { file_url: "/files/<filename>" }
  ▼
Flutter stores the URL and renders AttachmentWidget
User opens → launchUrl(baseUrl + file_url)
```

### Allowed File Types & Limits

| Upload type | Extensions | Max size (backend) | Notes |
|---|---|---|---|
| Work order attachment | pdf, doc, docx, jpg, jpeg, png, gif | 10 MB | Images auto-compressed |
| Document | pdf, doc, docx, txt, jpg, jpeg, png | — | Text extracted for search |

Nginx enforces a separate 50 MB ceiling (`client_max_body_size 50M`).

---

## Document Management System

### Upload & Text Extraction
- Files uploaded via `POST /api/upload`, saved to `uploaded_files/` on the Linux server
- Auto text extraction on upload using `backend/utils/text_extraction.py`:
  - **PDF**: PyPDF2
  - **DOCX**: python-docx
  - **TXT**: direct read
  - **JPG/PNG**: OCR via pytesseract + pdf2image
- Supports Arabic + English (`lang="ara+eng"`)
- Arabic text normalized via NFKC (`normalize_arabic()`)
- Extracted text stored in `documents.parsed_text`

### Folder Hierarchy
- Folders can be nested via `parent_id` self-reference on `document_folders`
- Deleting a folder orphans its documents back to root (sets `folder_id = NULL`)
- Folders can be moved to new parents

### Permission Inheritance
- Permissions checked via `backend/utils/permissions.py`
- `get_effective_role(user_email, resource_id, resource_type)` resolves role
- For documents in folders, permission walks up the folder chain
- Role priority: viewer(1) < editor(2) < owner(3)
- Owner is determined by `uploaded_by` (documents) or `created_by` (folders)

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
models/            Data classes (WorkOrder, AppUser, TechnicianAssignment, DocumentModel, FolderModel, ActivityLogEntry, WorkOrderReport)
services/          API clients (WorkOrderService, UserService, DocumentService, FolderService, ActivityLogService, etc.)
screens/           UI pages
  Work_Orders/     WO list, create/edit
  Documents/       Document list, upload, details, viewer (with web-specific viewer)
  admin/           User management, technician departments, departments
  reports/         PDF report generation
  settings/        Activity log, app settings
widgets/           Reusable components (TechnicianSelector, work_order_card, document_card, move_to_folder_dialog, etc.)
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
  documents.py     Document upload, delete, sharing, permissions
  folders.py       Folder CRUD, move documents/folders
utils/
  notification_service.py  Recipient resolution + dispatch orchestration
  notifications.py         OneSignal HTTP helpers
  activity.py              Activity audit logging (fire-and-forget)
  permissions.py           Document/folder permission engine (role inheritance)
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
└── uploaded_files/     ← all uploaded files (documents + WO attachments)
                          persisted on disk; not backed up to cloud storage
```

> **Note**: Files in `uploaded_files/` are not replicated or backed up automatically. Server disk is the single source of truth for binary files; metadata is in Supabase.
