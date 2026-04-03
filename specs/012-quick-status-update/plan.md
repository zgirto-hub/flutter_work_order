# Implementation Plan: Quick Status Update

**Branch**: `012-quick-status-update` | **Date**: 2026-04-03 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/012-quick-status-update/spec.md`

## Summary

Add a tappable status badge on work order cards that opens a minimal bottom sheet for quick status advancement (Pending → In Progress → Resolved → Closed) without navigating to the full edit screen. Uses existing `updateWorkOrder()` and `closeWorkOrder()` service methods and backend endpoints. Frontend-only change — no new backend work required.

## Technical Context

**Language/Version**: Dart 3.x / Flutter 3.x  
**Primary Dependencies**: Flutter Material (BottomSheet, AlertDialog), existing WorkOrderService, StatusBadge widget  
**Storage**: N/A (uses existing Supabase endpoints via WorkOrderService)  
**Testing**: Manual testing (no automated test framework currently in use)  
**Target Platform**: Flutter Web (PWA)  
**Project Type**: Mobile/web app (Flutter frontend)  
**Performance Goals**: Status change reflected on card within 2 seconds of confirmation  
**Constraints**: Must not break existing card interactions (tap to expand, long-press for selection)  
**Scale/Scope**: ~3 files modified (work_order_card.dart, work_order_home.dart, claude_widgets.dart)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Full-Stack Ownership | PASS (justified exclusion) | Frontend-only change. Backend already has PUT /work-orders/{id} and PATCH /work-orders/{id}/close endpoints that handle status updates, audit logging to work_order_status_logs, and system comment creation. No new backend endpoint, migration, or model needed. |
| II. Explicit Over Automatic | PASS | Status transitions are explicit user actions (tap badge → confirm in bottom sheet). Close flow records closed_by from authenticated session and closed_at is set server-side. No implicit state changes. |
| III. Role-Based Access Control | PASS | Badge is tappable only for technician/admin roles. Reporter sees read-only badge. Role check happens client-side using existing _userRole from getEmployeeProfile(). Server-side role enforcement already exists on the endpoints. |
| IV. Server-First File Storage | N/A | No file operations in this feature. |
| V. Client-Side Computation | PASS | In-place card update avoids unnecessary API calls for list reload. Status transition logic (next valid status) computed client-side. |
| VI. Audit Everything | PASS | Existing backend endpoints already log status changes to work_order_status_logs with old_status, new_status, changed_by. Also creates system comments in work_order_comments with type status_change. No additional audit code needed. |
| VII. Simplicity & YAGNI | PASS | Minimal bottom sheet with single next-status option. No configurability, no abstraction layers. Reuses existing StatusBadge widget and WorkOrderService methods. |

## Project Structure

### Documentation (this feature)

```text
specs/012-quick-status-update/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
frontend/
├── lib/
│   ├── widgets/
│   │   ├── work_order_card.dart    # Add onStatusTap callback, wrap StatusBadge in GestureDetector
│   │   └── claude_widgets.dart     # StatusBadge widget (no changes needed)
│   ├── screens/
│   │   └── Work_Orders/
│   │       └── work_order_home.dart  # Add _showQuickStatusSheet(), handle onStatusTap callback, in-place update
│   └── services/
│       └── work_order_service.dart   # Existing service (no changes needed)
```

**Structure Decision**: Frontend-only modification. Three files touched: work_order_card.dart (add callback + gesture), work_order_home.dart (bottom sheet logic + state update), claude_widgets.dart (no changes — StatusBadge reused as-is).

## Complexity Tracking

No constitution violations. No complexity justifications needed.
