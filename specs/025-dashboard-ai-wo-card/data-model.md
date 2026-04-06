# Data Model: Dashboard AI Work Order Card with Draft Preview

**Branch**: `025-dashboard-ai-wo-card` | **Date**: 2026-04-06

## Overview

This feature introduces **no new database tables or persistent entities**. The draft preview is an in-memory transient state between AI parsing and work order creation. Work orders are created through the existing `WorkOrderService.addWorkOrder()` flow.

## Affected Existing Entities

### WorkOrder (unchanged)

Work orders created from the Dashboard follow the same creation path as those created from AddWorkOrderScreen. The existing fields are populated from the AI draft:

| Field            | Type   | Source               | Notes                                   |
|------------------|--------|----------------------|-----------------------------------------|
| `jobNo`          | String | Client-generated     | Timestamp pattern: `WO${YY}${MM}${DD}-${HH}${mm}${ss}` |
| `title`          | String | `draft.title`        | Required — Create button disabled if empty |
| `description`    | String | `draft.description`  | AI-expanded professional text           |
| `location`       | String | `draft.location`     | Extracted if mentioned, empty otherwise |
| `type`           | String | `draft.type`         | Constrained to valid types              |
| `status`         | String | `draft.status`       | Constrained to valid statuses           |
| `departmentId`   | String | Resolved from `draft.department` | Matched against department list |
| `departmentName` | String | `draft.department`   | AI-matched department name              |

No schema changes. No migrations required.

## New Transient State (in-memory only)

### NlInputCard State

| Property           | Type                   | Description                              |
|--------------------|------------------------|------------------------------------------|
| `controller`       | TextEditingController  | The NL text input (owned by parent)      |
| `_dictationLanguage` | String               | `"en"` or `"ar"` (internal to widget)    |
| `_expanded`        | bool                   | Collapse/expand state (when collapsible) |

### Dashboard AI State

| Property             | Type            | Description                                       |
|----------------------|-----------------|---------------------------------------------------|
| `_nlController`      | TextEditingController | NL text input for dashboard                  |
| `_isGenerating`      | bool            | Loading state during AI request                   |
| `_cachedDepartments` | List<Department>? | Fetched on first Generate, cached for session   |

### Draft Data (Map<String, dynamic>)

Passed from Dashboard to the bottom sheet:

| Key            | Type    | Nullable | Description                     |
|----------------|---------|----------|---------------------------------|
| `title`        | String  | Yes      | AI-extracted title              |
| `description`  | String  | Yes      | AI-expanded description         |
| `location`     | String  | Yes      | AI-extracted location           |
| `type`         | String  | Yes      | From valid types list           |
| `department`   | String  | Yes      | From valid departments list     |
| `departmentId` | String  | Yes      | Resolved from department name   |
| `status`       | String  | Yes      | From valid statuses list        |

All state is ephemeral. Nothing persists beyond the work order that gets created through the existing flow.
