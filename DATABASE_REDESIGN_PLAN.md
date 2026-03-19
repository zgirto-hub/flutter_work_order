# Database Redesign Implementation Plan

## Overview
Redesign database schema for Work Order system with three roles: **Admin**, **Fixer**, **Reporter**.

---

## Role Permissions

| Role | See Own WO | See All WO | Create WO | Handle WO | Create Users |
|------|------------|------------|-----------|-----------|-------------|
| **Reporter** | ✅ | ❌ | ✅ | ❌ | Self only |
| **Fixer** | ✅ | ✅ (assigned depts) | ✅ | ✅ | ❌ |
| **Admin** | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Account Creation

| Role | How Created | Who Creates |
|------|-------------|------------|
| **Reporter** | Self-register via "Create Account" screen | Anyone |
| **Fixer** | Admin via User Management screen | Admin |
| **Admin** | Manual database seed | Initial setup |

---

## Database Schema

### Tables

#### 1. users
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_id UUID UNIQUE,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    mobile TEXT,
    location TEXT,
    user_type TEXT NOT NULL CHECK (user_type IN ('admin', 'fixer', 'reporter')),
    department TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

#### 2. fixer_reporters
```sql
CREATE TABLE fixer_reporters (
    fixer_department TEXT PRIMARY KEY,
    reporter_departments TEXT[] NOT NULL
);
```

#### 3. work_orders
```sql
CREATE TABLE work_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_no TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    location TEXT,
    mobile_number TEXT,
    department TEXT NOT NULL,
    type TEXT DEFAULT 'Technical',
    status TEXT DEFAULT 'Pending',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);
```

#### 4. work_order_assignments
```sql
CREATE TABLE work_order_assignments (
    work_order_id UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (work_order_id, user_id)
);
```

### Existing Tables to KEEP
- `auth.users` (Supabase Auth)
- `profiles` (Supabase Auth)
- `notification_preferences`
- `notification_delivery_logs`
- `notifications`
- `work_order_watchers`
- `work_order_comments`
- `work_order_attachments`

---

## SQL Migration Steps

### 1. DROP Old Tables
```sql
DROP TABLE IF EXISTS work_order_watchers;
DROP TABLE IF EXISTS work_order_assignments;
DROP TABLE IF EXISTS work_order_attachments;
DROP TABLE IF EXISTS notifications;
DROP TABLE IF EXISTS notification_delivery_logs;
DROP TABLE IF EXISTS notification_preferences;
DROP TABLE IF EXISTS work_orders;
DROP TABLE IF EXISTS it_department_reporters;
DROP TABLE IF EXISTS it_teams;
DROP TABLE IF EXISTS departments;
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS user_profiles;
```

### 2. CREATE New Tables
```sql
-- users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_id UUID UNIQUE,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    mobile TEXT,
    location TEXT,
    user_type TEXT NOT NULL CHECK (user_type IN ('admin', 'fixer', 'reporter')),
    department TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- fixer_reporters
CREATE TABLE fixer_reporters (
    fixer_department TEXT PRIMARY KEY,
    reporter_departments TEXT[] NOT NULL
);

-- work_orders
CREATE TABLE work_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_no TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    location TEXT,
    mobile_number TEXT,
    department TEXT NOT NULL,
    type TEXT DEFAULT 'Technical',
    status TEXT DEFAULT 'Pending',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- work_order_assignments
CREATE TABLE work_order_assignments (
    work_order_id UUID REFERENCES work_orders(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (work_order_id, user_id)
);
```

### 3. SEED Initial Data
```sql
-- Seed fixer_reporters
INSERT INTO fixer_reporters (fixer_department, reporter_departments) VALUES
  ('AFTN', ARRAY['Operations', 'ATC', 'Finance', 'NOTAM', 'General', 'MET']),
  ('Network', ARRAY['IT-Support', 'Helpdesk']),
  ('Security', ARRAY['General', 'Operations', 'ATC', 'Finance', 'NOTAM', 'MET', 'IT-Support', 'Helpdesk']);
```

### 4. Create Initial Admin (Manual)
```sql
-- Run this manually after creating auth user:
-- INSERT INTO users (auth_id, email, full_name, user_type)
-- SELECT id, email, 'Admin', 'admin'
-- FROM auth.users WHERE email = 'your_admin_email@domain.com';
```

---

## Backend Changes

### Files to Modify
| File | Changes |
|------|---------|
| `routers/users.py` | Rewrite for new `users` table |
| `routers/work_orders.py` | Use UUID for created_by, simplified filtering |
| `routers/it_teams.py` | Rename/update to `fixer_reporters` |
| `routers/departments.py` | Keep for department management |
| `routers/notifications.py` | Update to new user IDs |
| `db.py` | Update queries to new schema |

### Work Order Filtering Logic
```python
def get_visible_work_orders(email, user_type):
    if user_type == 'admin':
        return all_work_orders()
    elif user_type == 'fixer':
        fixer = get_user(email)
        reporters = get_fixer_reporters(fixer.department)
        return work_orders.where(department IN reporters)
    elif user_type == 'reporter':
        return work_orders.where(created_by == email)
```

---

## Frontend Changes

### Files to Create
| File | Purpose |
|------|---------|
| `services/user_service.dart` | API client for user endpoints |
| `screens/admin/user_management_screen.dart` | Admin: Create/Edit/Manage users |
| `screens/admin/fixer_reporters_screen.dart` | Admin: Assign reporters to fixer teams |

### Files to Modify
| File | Changes |
|------|---------|
| `models/employee.dart` | Rename → `user.dart`, update fields |
| `services/work_order_service.dart` | Use UUID for created_by |
| `screens/register_screen.dart` | Keep for reporter self-registration |
| `screens/settings_page.dart` | Update navigation, remove old entries |

---

## Implementation Order

| Step | Task | Status |
|------|------|--------|
| 1 | SQL: DROP old tables | ⏳ |
| 2 | SQL: CREATE new tables | ⏳ |
| 3 | SQL: SEED fixer_reporters | ⏳ |
| 4 | Backend: Rewrite users router | ⏳ |
| 5 | Backend: Update work_orders router | ⏳ |
| 6 | Backend: Update fixer_reporters router | ⏳ |
| 7 | Backend: Update notifications | ⏳ |
| 8 | Frontend: Create user_service.dart | ⏳ |
| 9 | Frontend: Create user_management_screen.dart | ⏳ |
| 10 | Frontend: Create fixer_reporters_screen.dart | ⏳ |
| 11 | Frontend: Update models | ⏳ |
| 12 | Frontend: Update all screens | ⏳ |
| 13 | Test: End-to-end testing | ⏳ |

---

## User Management Screen Features

### Admin Actions
- View all users (admins, fixers, reporters)
- Create new user (fixer or reporter)
- Edit user details
- Change user role (fixer ↔ reporter)
- Assign fixer to department
- Deactivate/Reactivate user
- Search/Filter users

### User List Display
```
┌────────────────────────────────────────────────────┐
│ 👤 John Doe (john@email.com)                      │
│    Role: Fixer | Dept: AFTN | Status: Active     │
│    [Edit] [Change Role] [Deactivate]              │
├────────────────────────────────────────────────────┤
│ 👤 Jane Smith (jane@email.com)                    │
│    Role: Reporter | Dept: Operations | Status: Active│
│    [Edit] [Change Role] [Deactivate]              │
└────────────────────────────────────────────────────┘
```

---

## Fixer Reporters Screen Features

### Admin Actions
- View all fixer teams
- Add/Edit fixer team (department)
- Assign reporter departments to fixer team
- Remove reporter department from fixer team

### Display
```
┌────────────────────────────────────────────────────┐
│ AFTN Fixers                                           │
│ Handles: Operations, ATC, Finance, NOTAM, MET      │
│ Fixers: Salah, Hasan, Mohammad                    │
│ [+ Add Dept] [- Remove Dept]                        │
├────────────────────────────────────────────────────┤
│ Network Fixers                                       │
│ Handles: IT-Support, Helpdesk                      │
│ Fixers: (list of network fixers)                   │
│ [+ Add Dept] [- Remove Dept]                        │
└────────────────────────────────────────────────────┘
```

---

## Status
- [ ] SQL Migration
- [ ] Backend Updates
- [ ] Frontend Updates
- [ ] Testing
