# Work Order App — Agent Reference

## Project Overview

Flutter frontend + Django backend work order management app.
- Frontend: `frontend/` (Flutter web)
- Backend: `backend/` (Django + FastAPI)
- Database: Supabase (Postgres + Auth + Admin API)
- Push: OneSignal

---

## What We Built

### Notifications System (primary feature)

Full in-app + push notification system for work order comments.

**Goal**: When a comment is posted on a work order, notify: creator, requester, assigned employees, watchers, and opted-in admins. Exclude the commenter.

**DB Tables** (`backend/notifications_schema.sql`):

```sql
-- Per-user notification settings
notification_preferences (
  user_email text PK,
  push_enabled boolean default true,
  in_app_enabled boolean default true,
  mute_all boolean default false,
  comment_notifications boolean default true,
  status_notifications boolean default true,
  system_notifications boolean default true,
  admin_all_workorder_comments boolean default false,
  updated_at timestamptz default now()
)

-- Extra followers beyond assignees/requester/creator
work_order_watchers (
  id uuid PK,
  work_order_id uuid FK -> work_orders(id) on delete cascade,
  user_email text not null,
  created_at timestamptz default now(),
  unique(work_order_id, user_email)
)

-- In-app inbox (one row per recipient per event)
notifications (
  id uuid PK,
  user_email text not null,
  kind text not null,
  title text not null,
  body text not null,
  data jsonb default '{}',  -- contains work_order_id, comment_id, job_no
  source_type text not null,
  source_id text not null,
  read_at timestamptz nullable,
  created_at timestamptz default now()
  -- indexes: (user_email, read_at, created_at desc), (source_type, source_id)
)

-- Push delivery audit trail
notification_delivery_logs (
  id uuid PK,
  notification_id uuid FK -> notifications(id) on delete cascade,
  channel text not null,         -- push | in_app
  provider text nullable,         -- onesignal
  recipient text not null,
  status text not null,           -- queued | sent | failed
  provider_message_id text nullable,
  error text nullable,
  attempt integer default 1,
  next_retry_at timestamptz nullable,
  created_at timestamptz default now()
  -- indexes: (status, next_retry_at), (notification_id), (recipient, created_at desc)
)
```

**Notification Routing (comment event)**:

```
commenter_email
       |
       v
fetch work order (created_by, request_id)
       |
       +-- created_by_email  --> add to recipients
       |
       +-- request_id --> fetch request --> created_by --> add to recipients
       |
       +-- work_order_assignments --> employees.profile_id
                                    --> auth.users.email
                                    --> add to recipients
       |
       +-- work_order_watchers.user_email --> add to recipients
       |
       +-- opted-in admins
           (user_profiles.user_type='admin'
            AND notification_preferences.admin_all_workorder_comments=true)
           --> add to recipients
       |
       v
exclude commenter_email
       |
       v
apply per-user preferences
  (mute_all, comment_notifications, push_enabled, in_app_enabled)
       |
       v
insert notifications (in_app) + send push + log delivery
```

**Preference Cascade**:
```
prefs = DEFAULT_PREFS  (all true, mute_all false)
prefs.update(database_row or {})

if prefs.mute_all: skip
if event_type == 'comment' and not prefs.comment_notifications: skip
if not prefs.push_enabled: skip push (still insert inbox if in_app_enabled)
if not prefs.in_app_enabled: skip inbox (still send push if push_enabled)
```

**Backend files**:
- `backend/utils/notifications.py` — OneSignal HTTP helpers
  - `_post_onesignal(payload)` — generic HTTP helper for OneSignal API
  - `send_push_notification(title, body)` — legacy role-broadcast (admin/tech only)
  - `send_push_to_external_ids(title, body, external_ids, data)` — targeted send
    by email external IDs using `include_aliases.external_id`
- `backend/utils/notification_service.py` — recipient resolution + dispatch
  - `resolve_comment_recipients(work_order_id, commenter_email)` — returns
    dict with recipients Set and debug info
  - `_resolve_assigned_emails(work_order_id)` — joins work_order_assignments ->
    employees.profile_id -> auth.users.email
  - `_resolve_watcher_emails(work_order_id)`
  - `_resolve_admin_opt_in_emails()` — admins with
    `notification_preferences.admin_all_workorder_comments=true`
  - `_get_preferences(emails)` — batch-fetch preferences
  - `dispatch_work_order_comment_notification(...)` — main orchestrator
- `backend/routers/notifications.py` — all notification/watcher/preference APIs
  - `GET /api/notification-preferences?email=...`
  - `PATCH /api/notification-preferences` — all preference fields including admin_all_workorder_comments
  - `GET /api/work-orders/{id}/watchers`
  - `POST /api/work-orders/{id}/watchers`
  - `DELETE /api/work-orders/{id}/watchers?email=...`
  - `GET /api/notifications?email=...&unread_only=...&limit=...&offset=...`
  - `GET /api/notifications/unread-count?email=...`
  - `PATCH /api/notifications/{id}/read?email=...`
  - `PATCH /api/notifications/read-all?email=...`
  - `DELETE /api/notifications?email=...` (clear all)
  - `GET /api/work-orders/{id}/notification-debug?commenter_email=...` — debug
    endpoint returning recipient resolution breakdown
- `backend/routers/work_orders.py` — comment creation calls
  `dispatch_work_order_comment_notification(...)` wrapped in try/except
  (best-effort, never fails comment creation)

**OneSignal Integration**:
- App ID: `760f00e5-fb08-4c0c-b898-ea35737bcc21`
- API key: env var `ONESIGNAL_API_KEY`
- Targeting: `include_aliases.external_id` with recipient email as external ID
- Frontend sets external ID via `OneSignal.login(email)` on web

**Frontend files**:
- `frontend/lib/services/notification_service.dart` — API client
- `frontend/lib/models/app_notification.dart` — data model
- `frontend/lib/screens/notifications_screen.dart` — notification inbox UI
- `frontend/lib/screens/more_screen.dart` — notification bell badge in header
- `frontend/lib/screens/Work_Orders/work_order_home.dart` — polls unread every
  20s, foreground-only sound alert, badges on WO cards, opens Activity tab
  marks notifications read
- `frontend/lib/widgets/work_order_card.dart` — `unreadActivityCount` prop, badge
  on card header and Activity button when expanded
- `frontend/lib/screens/Requests/requests_screen.dart` — maps unread
  notifications to requests via linked work orders, badges, Activity marks
  notifications read
- `frontend/lib/screens/settings_page.dart` — notification toggle for all
  roles + admin-only "Receive all work order comments" toggle

**Foreground sound logic** (in `work_order_home.dart`):
- Poll unread count every 20s
- `SystemSound.play(SystemSoundType.alert)` only when:
  - App is in foreground (`WidgetsBindingObserver` + `AppLifecycleState.resumed`)
  - Unread count increased since last poll
  - First poll is always silent (`soundPrimed` flag)

### UI Improvements

- Web launch ticket-style splash page (`frontend/web/index.html`)
- Login screen ticket-style logo card (`frontend/lib/screens/login_screen.dart`)
- Asterisk moved to left of "Work Order" title
- Tab favicon updated to branded asterisk icon
- Request list expandable cards with Activity + Details buttons
- Request detail: disabled "Working on it" replaced with working "Open Work Order"
- Request detail: "Convert to Work Order" when no link exists, "Open Work Order" when linked
- Activity compose bar moved to `Scaffold.bottomNavigationBar` with `SafeArea`
  + `AnimatedPadding` + `MediaQuery.viewInsetsOf(context).bottom` +
  `ScrollViewKeyboardDismissBehavior.onDrag` (fixes keyboard covering issue)

### Bug Fixes

- One-to-one request↔workorder enforced at DB (unique partial index) and API
  level (409 on duplicate)
- Requester role blocked from editing/deleting work orders (UI + API 403)
- Commenter exclusion in notification routing (always exclude at end)
- Requester auto-unsubscribed from OneSignal on login — removed so requesters
  can receive targeted push
- `work_orders.created_by_email` column did not exist — changed to use
  `work_orders.created_by` + Supabase Admin API resolution
- `DropdownButtonFormField.value` deprecated in Flutter 3.33+ — use
  `initialValue` instead
- Deploy script was uploading `backend/version.json` into server git repo,
  causing conflicts on pull — fixed by removing that scp step

---

## Key Architecture Notes

### Supabase Auth Mapping
```
employees.profile_id -> profiles.id -> auth.users.id -> auth.users.email
```

### Request ↔ Work Order
```
work_orders.request_id -> requests.id  (one-to-one, enforced at DB level)
```

### Supabase Admin API
Used for email resolution in notification service:
```
supabase.auth.admin.get_user_by_id(user_id)  # requires service role key
```

### Backend failures are best-effort
Comment creation must never block on notification failure. All notification
calls wrapped in try/except.

---

## Conventions & Patterns

- **Lint**: `flutter analyze` (frontend), `python -m py_compile` (backend)
- **Deploy**: `bash scripts/deploy_frontend.sh --no-bump` (no version scp)
- **Version bump**: `bash scripts/bump_version.sh`
- **Migration**: run `backend/notifications_schema.sql` in Supabase SQL editor
- **Debug**: `GET /api/work-orders/{id}/notification-debug?commenter_email=...`
  for diagnosing recipient resolution
- **Plan mode first**: explain changes before executing when in plan mode

---

## Future Enhancements (not yet implemented)

- Retry worker for failed push deliveries (scheduled job on
  `notification_delivery_logs` with exponential backoff, max 5 attempts)
- Dedicated notification preferences screen (vs. Settings toggle only)
- Per-work-order watcher toggle in work order detail
- Delivery log admin UI for inspecting push delivery status
- Webhook receiver for external notification events
- Email fallback for critical notifications

---

## Relevant Files Directory

### Backend
- `backend/routers/work_orders.py` — comment creation + notification dispatch
- `backend/routers/notifications.py` — all notification/watcher/preference APIs
- `backend/utils/notification_service.py` — recipient resolution + dispatch orchestration
- `backend/utils/notifications.py` — OneSignal HTTP helpers
- `backend/notifications_schema.sql` — DB migration script
- `backend/main.py` — router registration
- `backend/version.json` — version metadata
- `scripts/deploy_frontend.sh` — deployment script
- `scripts/bump_version.sh` — version bumping

### Frontend
- `frontend/lib/screens/Work_Orders/work_order_home.dart` — WO list with badges + sound
- `frontend/lib/screens/Work_Orders/add_work_order.dart` — Activity compose keyboard fix
- `frontend/lib/screens/Requests/requests_screen.dart` — request list with badges
- `frontend/lib/screens/notifications_screen.dart` — notification inbox UI
- `frontend/lib/screens/more_screen.dart` — notification bell badge
- `frontend/lib/screens/settings_page.dart` — notification toggles
- `frontend/lib/screens/login_screen.dart` — ticket-style logo card
- `frontend/lib/widgets/work_order_card.dart` — unread badge support
- `frontend/lib/services/notification_service.dart` — notification API client
- `frontend/lib/services/work_order_service.dart` — work order API
- `frontend/lib/models/app_notification.dart` — notification data model
- `frontend/lib/screens/main_screen.dart` — requester subscription
- `frontend/web/index.html` — ticket-style launch splash
- `frontend/lib/config.dart` — base URL
- `frontend/pubspec.yaml` — dependencies

### Documentation
- `NOTIFICATIONS_IMPLEMENTATION_PLAN.md` — original feature plan
- `NOTIFICATIONS_SYSTEM_SUMMARY.md` — system summary
- `AGENTS.md` — this file
