# Notifications Implementation Plan

## Scope

Implement targeted work-order notifications with:

- Per-user preferences (mute and event toggles)
- Extra watchers/followers per work order
- Delivery logs for push attempts
- In-app inbox with read/unread APIs
- Recipient resolution for comments:
  - **Reporter** (requester) - the user who created the work order
  - **Fixer** - assigned fixers on the work order
  - **Admin** - opted-in admins
  - **Creator** - work-order creator (if different from reporter)
  - **Watchers** - extra followers on the work order
  - **Exclude commenter** - the person who posted the comment does not receive a notification

## Data Model

Apply `backend/notifications_schema.sql`.

Tables:

- `notification_preferences`
- `work_order_watchers`
- `notifications`
- `notification_delivery_logs`

## Backend Changes

### 1) OneSignal utility

File: `backend/utils/notifications.py`

- Keep existing role-broadcast function for legacy request alerts.
- Add targeted sender: `send_push_to_external_ids(...)`.

### 2) Notification service

File: `backend/utils/notification_service.py`

- Resolve recipients for comment events.
- Resolve assigned fixer emails via:
  - `work_order_assignments.fixer_id -> users.email`
- Apply preferences and event toggles.
- Insert in-app notifications.
- Send push notifications.
- Log delivery status.

### 3) Comment integration

File: `backend/routers/work_orders.py`

- On `POST /work-orders/{id}/comments` with `type=comment`:
  - create comment
  - dispatch notification workflow (best effort)
  - never fail comment creation if push fails

### 4) New notifications router

File: `backend/routers/notifications.py`

Endpoints:

- `GET /api/notification-preferences`
- `PATCH /api/notification-preferences`
- `GET /api/work-orders/{id}/watchers`
- `POST /api/work-orders/{id}/watchers`
- `DELETE /api/work-orders/{id}/watchers`
- `GET /api/notifications`
- `GET /api/notifications/unread-count`
- `PATCH /api/notifications/{id}/read`
- `PATCH /api/notifications/read-all`

### 5) App wiring

File: `backend/main.py`

- Register `notifications` router under `/api`.

## Frontend Compatibility Change

File: `frontend/lib/screens/main_screen.dart`

- Keep OneSignal subscription for requester users (do not auto-unsubscribe).
- This is required so requester can receive targeted comment notifications.

## Validation Checklist

1. Comment by fixer/admin/requester creates comment successfully.
2. Commenter does not receive own notification.
3. Requester receives notification when others comment.
4. Assigned fixers and creator receive notification.
5. Watchers receive notification.
6. `mute_all` or event toggle disables delivery.
7. In-app notification rows are created as expected.
8. Delivery logs record sent/failed attempts.

## Rollout Order

1. Run SQL migration in Supabase.
2. Deploy backend.
3. Deploy frontend.
4. Smoke-test comment notifications with 2-3 user roles.

## Notes

- Current delivery logging is best-effort with retry metadata fields.
- A dedicated retry worker can be added later to process failed push attempts.
