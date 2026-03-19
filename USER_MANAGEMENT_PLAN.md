# User Management Feature Plan

## Overview

Create a dedicated **User Management** screen for Admins to manage all users in the system.

---

## Goals

1. Allow Admins to view all users
2. Edit user details (name, department, mobile, location)
3. Change user roles (requester ↔ tech)
4. Assign IT teams to tech users
5. Search and filter users

---

## Architecture

### Database Tables

**`user_profiles`** - User role info:
- email (PK)
- user_type ('tech' | 'requester')

**`employees`** - User details:
- email, full_name, department, it_team, mobile, location, profile_id, active

### Backend API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/users` | GET | Get all users with details |
| `/api/users/{email}` | PATCH | Update user details |
| `/api/users/{email}/role` | PATCH | Change user role |
| `/api/users/{email}/it-team` | PATCH | Change IT team assignment |

---

## Frontend Files

| File | Purpose |
|------|---------|
| `services/user_service.dart` | API client for user endpoints |
| `screens/admin/user_management_screen.dart` | Main screen with user list |

### UI Design

```
Settings → User Management
├── Search bar (by name/email)
├── Filter chips: [All] [Tech] [Requester]
└── User cards with editable fields:
    ├── Avatar + Name + Email
    ├── Role dropdown
    ├── Department (editable)
    ├── Mobile (editable)
    ├── Location (editable)
    └── IT Team dropdown (if tech)
```

---

## Features

- **No pagination** - Load all users at once
- **Real-time search** - Filter as user types
- **Optimistic updates** - Update UI immediately
- **Safety checks** - Prevent admin from demoting themselves

---

## Implementation Steps

### Backend
1. Add `GET /api/users` endpoint
2. Add `PATCH /api/users/{email}` endpoint
3. Add `PATCH /api/users/{email}/role` endpoint
4. Add `PATCH /api/users/{email}/it-team` endpoint

### Frontend
1. Create `services/user_service.dart`
2. Create `screens/admin/user_management_screen.dart`
3. Add navigation in `settings_page.dart`

---

## Status

- [ ] Backend: Add user management endpoints
- [ ] Frontend: Create user service
- [ ] Frontend: Create User Management screen
- [ ] Frontend: Add navigation to Settings
- [ ] Test: Deploy and verify
