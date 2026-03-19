# Work Order App - UI/UX Documentation

> **Version:** 1.0.0
> **Last Updated:** March 2026
> **Purpose:** Reference guide for frontend design decisions and improvement roadmap

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Visual Design System](#2-visual-design-system)
3. [Component Library](#3-component-library)
4. [Screen Architecture](#4-screen-architecture)
5. [Navigation & User Flows](#5-navigation--user-flows)
6. [Brand Identity](#6-brand-identity)
7. [Current Issues & Recommended Fixes](#7-current-issues--recommended-fixes)
8. [Future Enhancement Roadmap](#8-future-enhancement-roadmap)


# 1. Project Overview

## 1.1 Application Purpose

The Work Order application is a Flutter web-based work order management system enabling users to create, assign, track, and complete work orders. The system supports multiple user roles with role-based access control.

## 1.2 Tech Stack

| Layer | Technology |
|-------|------------|
| Frontend | Flutter Web |
| Backend | FastAPI (Python) |
| Database | Supabase (Postgres) |
| Auth | Supabase Auth |
| Push Notifications | OneSignal |
| Deployment | PWA (Progressive Web App) |

## 1.3 User Roles

| Role | Permissions |
|------|-------------|
| **Requester** | Create work orders, view own work orders, comment |
| **Fixer (Technician)** | View assigned work orders, update status, comment, upload attachments |
| **Admin** | Full CRUD on work orders, users, departments, documents, reports, settings |

## 1.4 Architecture Summary

```
Flutter Frontend
  Screens | Widgets | Services
  Models | Theme | Filters
  
FastAPI Backend
  Routers | Utils | Services
  
Supabase
  Auth | Database | Admin API
```


# 2. Visual Design System

## 2.1 Color Palette

### Light Mode Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `bgPrimary` | `#FAF9F7` | Page backgrounds |
| `bgSurface` | `#FFFFFF` | Card backgrounds, surfaces |
| `bgSurface2` | `#F5F4F0` | Input fields, secondary surfaces |
| `textPrimary` | `#1A1915` | Headlines, primary text |
| `textSecondary` | `#6B6860` | Body text, labels |
| `textTertiary` | `#9B9A96` | Captions, hints |
| `accent` | `#CC785C` | Primary actions, FABs, links |
| `accentHover` | `#B5684A` | Button hover states |
| `border` | `rgba(0,0,0,0.08)` | Card borders |
| `border2` | `rgba(0,0,0,0.12)` | Input field borders |

### Dark Mode Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `bgPrimary` | `#1A1917` | Page backgrounds |
| `bgSurface` | `#212120` | Card backgrounds, surfaces |
| `bgSurface2` | `#2A2A28` | Input fields, secondary surfaces |
| `textPrimary` | `#EDEDEA` | Headlines, primary text |
| `textSecondary` | `#9B9A96` | Body text, labels |
| `textTertiary` | `#5E5D5A` | Captions, hints |
| `accent` | `#CC785C` | Primary actions, FABs, links |
| `border` | `rgba(255,255,255,0.07)` | Card borders |
| `border2` | `rgba(255,255,255,0.11)` | Input field borders |

### Status Colors

| Status | Light Mode | Dark Mode | Usage |
|--------|------------|-----------|-------|
| `pending` | `#B45309` | `#D97706` | Pending work orders |
| `inProgress` | `#1D4ED8` | `#3B82F6` | In-progress work orders |
| `closed` | `#15803D` | `#22C55E` | Closed/completed work orders |
| `danger` | `#DC2626` | `#EF4444` | Errors, delete actions |
| `warning` | `#D97706` | `#F59E0B` | Warnings |

## 2.2 Typography

### Font Configuration

**Primary Font:** DM Sans (with fallback options)

Available font families: DM Sans (default), Inter, Roboto, Poppins, Lato, Nunito

### Type Scale

| Style | Font Size | Weight | Line Height | Usage |
|-------|-----------|--------|-------------|-------|
| `displayLarge` | 28px | 600 | 1.3 | Hero titles |
| `titleLarge` | 20px | 600 | 1.3 | Screen titles |
| `titleMedium` | 16px | 600 | 1.3 | Card titles, section headers |
| `bodyLarge` | 14px | 400 | 1.5 | Primary body text |
| `bodyMedium` | 13px | 400 | 1.5 | Secondary body text |
| `bodySmall` | 11px | 400 | 1.4 | Captions |
| `labelSmall` | 10px | 500 | 1.4 | Labels, badges |

## 2.3 Spacing System

Base unit: 4px

| Token | Value | Usage |
|-------|-------|-------|
| `xs` | 4px | Tight spacing |
| `sm` | 8px | Between list items |
| `md` | 14px | Card padding |
| `lg` | 20px | Section spacing |
| `xl` | 28px | Major section gaps |

## 2.4 Border & Radius

### Border Radius

| Element | Radius |
|---------|--------|
| Cards | 12-14px |
| Buttons | 9-10px |
| Input fields | 9-10px |
| FAB | 14px |
| Dialogs | 14-16px |
| Avatars | 50% (circular) |
| Badges | 6px |
| Chips | 8px |

### Border Width

| Element | Width |
|---------|-------|
| Card border | 0.5px |
| Input border | 0.5px |
| Dividers | 0.5px |

## 2.5 Shadows & Elevation

**Current Implementation:** Minimal shadows throughout the app. Cards, FAB, Dialogs, and AppBar all use elevation 0 (border-only).

## 2.6 Dark Mode Implementation

The app supports system-aware dark mode via ThemeController with:
- ThemeMode: light / dark / system
- Font scale: 0.85 - 1.3
- Customizable font family
- Customizable accent color

Preferences persist via SharedPreferences.


# 3. Component Library

## 3.1 Core Widgets

Location: `lib/widgets/claude_widgets.dart`

### StatusBadge
Colored pill displaying work order status.

```dart
StatusBadge(
  status: 'pending',     // 'pending' | 'in_progress' | 'closed'
  isSmall: false,
)
```

| Status | Background | Text |
|--------|------------|------|
| pending | `#FEF3C7` | `#B45309` |
| in_progress | `#DBEAFE` | `#1D4ED8` |
| closed | `#DCFCE7` | `#15803D` |

### SurfaceCard
Bordered container for content grouping.

```dart
SurfaceCard(
  child: Text('Card content'),
  padding: EdgeInsets.all(14),
  borderRadius: 12,
)
```

### FilterChipRow
Horizontal scrolling row of filter chips.

```dart
FilterChipRow(
  chips: ['All', 'Pending', 'In Progress', 'Closed'],
  selectedIndex: 0,
  onSelected: (index) => setState(() => _selectedIndex = index),
)
```

### SectionLabel
UPPERCASE section header with consistent styling.

### ClaudeSearchBar
Custom search input with icon.

### InitialsAvatar
User avatar displaying initials.

### ClaudeIconButton
Circular icon button with consistent styling.

### ClaudeFAB
Floating action button styled with accent color.

### SettingsRow
List item for settings screens.

### GlassContainer
Frosted glass effect container (used for overlays).

## 3.2 Specialized Widgets

### WorkOrderCard (`lib/widgets/work_order_card.dart`)
Expandable card displaying work order summary with activity indicators.

Features:
- Expandable to show details and activity
- Unread activity badge
- Status badge in header
- Assignment avatars
- Activity compose bar when expanded
- Comment threading

### DocumentCard (`lib/widgets/document_card.dart`)
List item for document display with file type icon, name, metadata, selection checkbox.

### EmployeeSelector (`lib/widgets/employee_selector.dart`)
Dropdown/picker for selecting employees with multi-select support.

### StatusFilterBar (`lib/widgets/status_filter_bar.dart`)
DEPRECATED - Use FilterChipRow from claude_widgets.dart instead. See Section 7.1.

## 3.3 Dialogs

### ConfirmDialog (`lib/widgets/confirm_dialog.dart`)
Confirmation dialog with optional destructive styling.

### ChangePasswordDialog (`lib/widgets/change_password_dialog.dart`)
Modal for changing user password.

### MoveToFolderDialog (`lib/widgets/move_to_folder_dialog.dart`)
Folder picker for document organization.

### DeletingOverlay (`lib/widgets/deleting_overlay.dart`)
Full-screen overlay during delete operations.

## 3.4 Layout Components

### SearchAppBar (`lib/widgets/search_appbar.dart`)
Custom app bar with integrated search.

### ActiveFiltersRow (`lib/widgets/active_filters_row.dart`)
Displays active filter chips with remove capability.

### AnimatedEntityList (`lib/widgets/animated_entity_list.dart`)
Animated list for adding/removing items with smooth transitions.

### LoadingIndicator (`lib/widgets/loading_indicator.dart`)
Consistent loading spinner used throughout the app.

## 3.5 Form Components

### Standard Input Fields
Used throughout add_work_order.dart, register_screen.dart, admin screens.

Field Structure:
- filled: true
- fillColor: AppColors.bgSurface2
- borderRadius: 9
- contentPadding: horizontal 12, vertical 11

### Dropdown Fields
DEPRECATED `value` property - Use `initialValue` instead (Flutter 3.33+).

Locations requiring update:
- `lib/screens/Work_Orders/add_work_order.dart:554,585`
- `lib/screens/register_screen.dart:277`


# 4. Screen Architecture

## 4.1 Screen Hierarchy

```
AuthWrapper
  SplashScreen --> LoginScreen --> MainScreen
                                        |
                    Role: Admin/Fixer   | Role: Requester
                    Dashboard (0)        WorkOrderHome (0)
                    WorkOrderHome (1)   SettingsPage (1)
                    MoreScreen (2)
                      Documents, Notifications, Reports, Settings
                      Activity Log (Admin)
                      UserManagement, Departments, IT Teams (Admin)
```

## 4.2 Screen Descriptions

### Authentication Screens

#### LoginScreen (`lib/screens/login_screen.dart`)
User authentication entry point with ticket-styled logo card, email/password fields, remember me, forgot password, create account.

#### RegisterScreen (`lib/screens/register_screen.dart`)
New user registration with role selection (Reporter/Fixer) and department assignment.

### Main Screens

#### DashboardScreen (`lib/screens/dashboard_screen.dart`)
Home dashboard for Admin/Fixer roles with stats cards, quick actions, recent work orders.

#### WorkOrderHome (`lib/screens/Work_Orders/work_order_home.dart`)
Main work order listing with search, status filters, expandable cards, notification polling (20s), foreground sound alerts.

Key features:
- Search bar with filters
- Status filter chips
- Expandable work order cards
- Selection mode for bulk actions
- FAB for new work order
- Unread notification polling
- Activity tab with comment compose

#### AddWorkOrder (`lib/screens/Work_Orders/add_work_order.dart`)
Create or edit work orders with tabbed form (Details/Assignments/Activity).

Keyboard handling uses Scaffold.bottomNavigationBar with SafeArea, AnimatedPadding, and MediaQuery.viewInsets.

#### MoreScreen (`lib/screens/more_screen.dart`)
Hub for secondary features with grid of feature cards.

#### NotificationsScreen (`lib/screens/notifications_screen.dart`)
In-app notification inbox with mark read, mark all read, clear all.

#### SettingsPage (`lib/screens/settings_page.dart`)
User preferences with Account, Appearance, Notifications, About sections.

SIZE WARNING: This file is 1072 lines. Consider splitting.

#### DocumentsScreen (`lib/screens/Documents/documents_screen.dart`)
File management with folder sidebar (116px fixed), document list, selection mode.

#### WorkOrderReportScreen (`lib/screens/reports/workorder_report_screen.dart`)
Work order analytics with date range filter, status counts, resolution time.

### Admin Screens

#### UserManagementScreen (`lib/screens/admin/user_management_screen.dart`)
User CRUD with role/department management.

WARNING: Has BuildContext async gap issues at lines 384, 388, 551, 568, 592, 596.

#### DepartmentsScreen (`lib/screens/admin/departments_screen.dart`)
Department management with create/edit, employee assignment.

WARNING: Has unused variable (hasText at line 230).

#### FixerReportersScreen (`lib/screens/admin/fixer_reporters_screen.dart`)
Team assignment management.

#### ITTeamsScreen (`lib/screens/admin/it_teams_screen.dart`)
IT team management with create/edit, member assignment.

#### TechDepartmentsScreen (`lib/screens/admin/tech_departments_screen.dart`)
Technical department management.

ERROR: Calls undefined method getDepartments() from DepartmentService. See Section 7.2.

# 5. Navigation & User Flows

## 5.1 Navigation Pattern

Primary Navigation: Bottom Navigation Bar with 3 tabs (60px height)
- Dashboard (index 0)
- Work Orders (index 1) - with badge for unread count
- More (index 2)

Secondary Navigation: Navigator.push() for pushed screens

Transition Animation: Custom ClaudeTransitionsBuilder (fade + slide-up)

## 5.2 Key User Flows

### Flow 1: Create Work Order
Login -> Dashboard -> FAB (+) -> AddWorkOrder -> Fill Details/Assignments -> Submit -> Work Order Home

### Flow 2: View Notification
Notification Received -> NotificationsScreen -> Tap notification -> WorkOrderCard expanded -> View/Add comment

### Flow 3: Admin User Management
More -> Users -> UserManagementScreen -> Search/Select user -> Edit role/department -> Save

## 5.3 Authentication Flow

App Launch -> SplashScreen (ticket-styled) -> LoginScreen (if no session) -> MainScreen (authenticated)

New users: LoginScreen -> RegisterScreen -> MainScreen

# 6. Brand Identity

## 6.1 Logo System

### App Icon
- Shape: Rounded square (iOS-style corners)
- Background: Terracotta gradient (#DA8C6A to #AF5335)
- Mark: 3-pill asterisk symbol
- Size: 1024x1024px source

### Web Favicon
- Design: Asterisk symbol
- Color: Terracotta (#CC785C)
- Format: 32x32px ICO

### Logo Usage
| Context | Size | Usage |
|---------|------|-------|
| Splash screen | 120x120 | Centered, ticket card |
| Login screen | 80x80 | Ticket card header |
| App bar | 32x32 | Small icon |
| PWA manifest | 192x192, 512x512 | Various |

## 6.2 Ticket Theme

The app uses a ticket visual metaphor throughout splash and login screens with border radius 16px, centered content, terracotta accents.

## 6.3 Color Usage Guidelines

### Accent Color Application
| Element | Color |
|---------|-------|
| FAB background | AppColors.accent |
| Primary buttons | AppColors.accent |
| Button hover | AppColors.accentHover |
| Links | AppColors.accent |

### Status Color Application
| Status | Badge BG | Badge Text | Card Accent |
|--------|----------|------------|-------------|
| Pending | #FEF3C7 | #B45309 | Left border #D97706 |
| In Progress | #DBEAFE | #1D4ED8 | Left border #3B82F6 |
| Closed | #DCFCE7 | #15803D | Left border #22C55E |

## 6.4 Typography Guidelines

```dart
// Screen titles
Text('Work Orders', style: TextStyle(fontSize: 20, fontWeight: w600))

// Section headers
SectionLabel(text: 'DETAILS')

// Card titles
Text('Title', style: TextStyle(fontSize: 16, fontWeight: w600))

// Body text
Text('Description...', style: TextStyle(fontSize: 14))

// Captions
Text('Due: date', style: TextStyle(fontSize: 11, color: AppColors.textTertiary))
```


# 7. Current Issues & Recommended Fixes

## 7.1 Duplicate StatusFilterBar

### Issue
Two implementations exist:
1. `lib/widgets/status_filter_bar.dart` (53 lines) - Uses Material colors
2. `lib/widgets/claude_widgets.dart` -> FilterChipRow - Custom styled

### Impact
Code duplication, inconsistent styling (Material vs. app theme).

### Recommended Fix
1. Find all usages: `grep -r "StatusFilterBar" lib/`
2. Replace with FilterChipRow
3. Delete `lib/widgets/status_filter_bar.dart`
4. Run `flutter analyze`

## 7.2 Undefined Method Error

### Issue
`lib/screens/admin/tech_departments_screen.dart:56` calls undefined `getDepartments()`.

### Error
```
error - The method 'getDepartments' isn't defined for the type 'DepartmentService'
```

### Recommended Fix
Option A - Add the missing method to DepartmentService:
```dart
Future<List<Department>> getDepartments() async { ... }
```

Option B - Use existing method (likely `fetchDepartments`):
```dart
final departments = await _departmentService.fetchDepartments();
```

## 7.3 BuildContext Async Gaps

### Issue
Using BuildContext after async operations without checking `mounted` state.

### Affected Files
| File | Lines |
|------|-------|
| `lib/screens/Documents/documents_screen.dart` | 407, 416 |
| `lib/screens/admin/user_management_screen.dart` | 384, 388, 551, 568, 592, 596 |

### Pattern (Problematic)
```dart
// BEFORE (problematic)
Future<void> _loadData() async {
  await _service.fetch();
  setState(() => _loading = false);  // Context used after potential unmount
}
```

### Pattern (Fixed)
```dart
// AFTER (correct)
Future<void> _loadData() async {
  final result = await _service.fetch();
  if (!mounted) return;
  setState(() => _data = result);
  
  await _service.process();
  if (!mounted) return;
  
  setState(() => _loading = false);
}
```

## 7.4 Deprecated API Replacements

### Issue: DropdownButtonFormField.value
**Deprecated in:** Flutter 3.33.0
**Replace with:** `initialValue`

Locations: `add_work_order.dart:554,585`, `register_screen.dart:277`

```dart
// BEFORE (deprecated)
DropdownButtonFormField(value: _selectedValue, ...)

// AFTER (correct)
DropdownButtonFormField(initialValue: _selectedValue, ...)
```

### Issue: Switch.activeColor
**Deprecated in:** Flutter 3.31.0
**Replace with:** `activeThumbColor`

### Issue: withOpacity()
**Deprecated in:** Recent Flutter
**Replace with:** `withValues(alpha: x)`

Locations: `add_document_screen.dart:333,383`, `document_card.dart:78`, `glass_container.dart:18,21`

## 7.5 Dead Code Cleanup

### Unused Imports in main_screen.dart (Lines 3, 9-11, 14-15, 19)
```dart
// Remove these unused imports:
import 'package:package_info_plus/package_info_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/claude_widgets.dart';
import '../widgets/change_password_dialog.dart';
import '../screens/Documents/documents_screen.dart';
import '../screens/reports/workorder_report_screen.dart';
import '../services/work_order_service.dart';
```

### Unused Variables

| File | Line | Variable | Action |
|------|------|----------|--------|
| `dashboard_screen.dart` | 36 | `_pendingWorkOrders` | Remove or use |
| `departments_screen.dart` | 230 | `hasText` | Remove |
| `work_order_service.dart` | 253 | `data` | Remove |

# 8. Future Enhancement Roadmap

## 8.1 State Management Migration

### Current State
- Simple StatefulWidget with direct service calls
- No formal state management library
- ChangeNotifier only for ThemeController

### Recommended: Provider

```dart
// pubspec.yaml
dependencies:
  provider: ^6.1.0

// Example Provider
class WorkOrderProvider extends ChangeNotifier {
  List<WorkOrder> _workOrders = [];
  bool _isLoading = false;
  
  Future<void> loadWorkOrders() async {
    _isLoading = true;
    notifyListeners();
    _workOrders = await WorkOrderService().fetchWorkOrders();
    _isLoading = false;
    notifyListeners();
  }
}
```

Benefits: Official solution, easy migration, built-in context.watch<T>().

## 8.2 Component Consolidation

### Large Files to Split

| File | Lines | Recommendation |
|------|-------|----------------|
| `settings_page.dart` | 1072 | Split into smaller widgets |
| `user_management_screen.dart` | ~600 | Extract form dialogs |
| `add_work_order.dart` | ~600 | Use existing tab structure |

### Suggested Settings Structure
```
lib/screens/settings/
  settings_page.dart (orchestrator)
  widgets/
    account_settings.dart
    appearance_settings.dart
    notification_settings.dart
    about_settings.dart
```

## 8.3 Animation Standardization

Create animation constants:
```dart
class AppAnimations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Curve defaultCurve = Curves.easeInOut;
}
```

## 8.4 Empty State Components

Screens needing empty states:
| Screen | Recommended |
|--------|------------|
| Work Order Home | "No work orders found" + illustration + CTA |
| Documents | "No documents yet" + upload button |
| Notifications | "All caught up!" + illustration |
| Users | "No users" + invite button |

## 8.5 Responsive Design Improvements

### Breakpoint Constants
```dart
class AppBreakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  
  static bool isMobile(BuildContext context) => 
    MediaQuery.of(context).size.width < mobile;
}
```

### Adaptive Documents Layout
```dart
Row(
  children: [
    if (!AppBreakpoints.isMobile(context))
      SizedBox(
        width: MediaQuery.of(context).size.width < tablet ? 80 : 200,
        child: FolderSidebar(),
      ),
    Expanded(child: DocumentList()),
  ],
)
```

## 8.6 Error Handling Standardization

### Error Display Widget
```dart
class ErrorDisplay extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  // ... build method with icon, text, retry button
}
```

### Service-level Error Handling
```dart
Future<T> safeCall(Future<T> Function() call) async {
  try {
    return await call();
  } on SocketException {
    throw NetworkException('No internet connection');
  } catch (e) {
    throw AppException(e.toString());
  }
}
```

## 8.7 Testing Infrastructure

1. Add widget tests for core components (StatusBadge, SurfaceCard, etc.)
2. Add integration tests for user flows (create work order, login, etc.)

## 8.8 Performance Optimizations

1. Add const constructors where possible
2. Use ListView.builder for large lists (lazy loading)
3. Memoize expensive computations with compute()

## 8.9 Accessibility Improvements

1. Add semantic labels to all custom widgets
2. Ensure color contrast meets WCAG AA (4.5:1 text, 3:1 large text)
3. Add focus indicators for keyboard navigation

```dart
IconButton(
  icon: Icon(Icons.edit),
  onPressed: () {},
  tooltip: 'Edit work order',
  semanticLabel: 'Edit work order',
)
```


# Appendix A: File Structure

```
frontend/
├── lib/
│   ├── main.dart                      # App entry point
│   ├── config.dart                    # API configuration
│   │
│   ├── models/                        # Data models
│   │   ├── work_order.dart
│   │   ├── work_order_comment.dart
│   │   ├── work_order_attachment.dart
│   │   ├── employee.dart
│   │   ├── employee_assignment.dart
│   │   ├── app_user.dart
│   │   ├── app_notification.dart
│   │   ├── document.dart
│   │   ├── folder_model.dart
│   │   ├── activity_log_entry.dart
│   │   └── workorder_report.dart
│   │
│   ├── services/                      # API clients
│   │   ├── work_order_service.dart
│   │   ├── notification_service.dart
│   │   ├── document_service.dart
│   │   ├── folder_service.dart
│   │   ├── user_service.dart
│   │   ├── employee_service.dart
│   │   ├── department_service.dart
│   │   ├── activity_log_service.dart
│   │   ├── it_team_service.dart
│   │   ├── it_department_service.dart
│   │   ├── fixer_reporter_service.dart
│   │   ├── onesignal_service.dart
│   │   ├── webauthn_service.dart
│   │   ├── pwa_update_service.dart
│   │   ├── platform_ua_service.dart
│   │   └── download_helper.dart
│   │
│   ├── screens/                       # Screen widgets
│   │   ├── main_screen.dart
│   │   ├── login_screen.dart
│   │   ├── register_screen.dart
│   │   ├── dashboard_screen.dart
│   │   ├── more_screen.dart
│   │   ├── settings_page.dart
│   │   ├── notifications_screen.dart
│   │   │
│   │   ├── Work_Orders/
│   │   │   ├── work_order_home.dart
│   │   │   └── add_work_order.dart
│   │   │
│   │   ├── Documents/
│   │   │   ├── documents_screen.dart
│   │   │   ├── document_details_screen.dart
│   │   │   ├── add_document_screen.dart
│   │   │   └── document_viewer_screen.dart
│   │   │
│   │   ├── reports/
│   │   │   └── workorder_report_screen.dart
│   │   │
│   │   ├── admin/
│   │   │   ├── user_management_screen.dart
│   │   │   ├── departments_screen.dart
│   │   │   ├── fixer_reporters_screen.dart
│   │   │   ├── it_teams_screen.dart
│   │   │   └── tech_departments_screen.dart
│   │   │
│   │   └── settings/
│   │       └── activity_log_screen.dart
│   │
│   ├── widgets/                       # Reusable widgets
│   │   ├── claude_widgets.dart        # Core widgets
│   │   ├── work_order_card.dart
│   │   ├── document_card.dart
│   │   ├── status_filter_bar.dart    # DEPRECATED
│   │   ├── search_appbar.dart
│   │   ├── employee_selector.dart
│   │   ├── confirm_dialog.dart
│   │   ├── change_password_dialog.dart
│   │   ├── move_to_folder_dialog.dart
│   │   ├── deleting_overlay.dart
│   │   ├── attachment_widget.dart
│   │   ├── loading_indicator.dart
│   │   ├── glass_container.dart
│   │   ├── animated_entity_list.dart
│   │   ├── active_filters_row.dart
│   │   ├── work_order_list.dart
│   │   └── app_footer.dart
│   │
│   ├── theme/                         # Theming
│   │   ├── app_theme.dart            # Colors, text styles
│   │   ├── theme_controller.dart     # Theme persistence
│   │   └── app_transitions.dart      # Page transitions
│   │
│   ├── filters/                      # Filter logic
│   │   ├── work_order_filter_engine.dart
│   │   └── document_filter_engine.dart
│   │
│   └── controllers/                  # State controllers
│       └── filter_controller.dart
│
├── web/
│   ├── index.html                    # PWA entry + ticket splash
│   ├── manifest.json
│   └── icons/
│
└── pubspec.yaml
```

# Appendix B: API Endpoints Reference

## Work Orders

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/work-orders` | List work orders |
| POST | `/api/work-orders` | Create work order |
| GET | `/api/work-orders/{id}` | Get work order |
| PUT | `/api/work-orders/{id}` | Update work order |
| DELETE | `/api/work-orders/{id}` | Delete work order |
| GET | `/api/work-orders/{id}/comments` | List comments |
| POST | `/api/work-orders/{id}/comments` | Add comment |
| POST | `/api/work-orders/{id}/attachments` | Upload attachment |
| GET | `/api/work-orders/{id}/notification-debug` | Debug notifications |

## Documents

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/documents` | List documents |
| POST | `/api/documents` | Upload document |
| GET | `/api/documents/{id}` | Get document |
| PUT | `/api/documents/{id}` | Update document |
| DELETE | `/api/documents/{id}` | Delete document |
| POST | `/api/documents/move` | Move to folder |

## Notifications

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/notifications` | List notifications |
| GET | `/api/notifications/unread-count` | Unread count |
| PATCH | `/api/notifications/{id}/read` | Mark read |
| PATCH | `/api/notifications/read-all` | Mark all read |
| DELETE | `/api/notifications` | Clear all |
| GET | `/api/notification-preferences` | Get preferences |
| PATCH | `/api/notification-preferences` | Update preferences |

## Users & Admin

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/users` | List users |
| POST | `/api/users` | Create user |
| GET | `/api/users/{id}` | Get user |
| PUT | `/api/users/{id}` | Update user |
| DELETE | `/api/users/{id}` | Delete user |
| GET | `/api/departments` | List departments |
| POST | `/api/departments` | Create department |
| GET | `/api/it-teams` | List IT teams |
| GET | `/api/activity-log` | Activity log |

# Appendix C: Dependencies

```yaml
# Core
flutter: sdk

# State Management (consider adding)
provider: ^6.1.0

# HTTP & Networking
http: ^1.1.0

# Local Storage
shared_preferences: ^2.2.0

# File Handling
file_picker: ^6.1.0

# PDF Generation
pdf: ^3.10.0
printing: ^5.11.0

# UI Components
flutter_svg: ^2.0.0
cached_network_image: ^3.3.0
shimmer: ^3.1.0

# Utilities
intl: ^0.19.0
uuid: ^4.2.0
```

---

*Document generated for Work Order App*  
*Last updated: March 2026*
