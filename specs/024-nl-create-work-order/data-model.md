# Data Model: Natural Language Work Order Creation

**Branch**: `024-nl-create-work-order` | **Date**: 2026-04-06

## Overview

This feature introduces **no new database tables or persistent entities**. The AI parsing is a stateless request/response flow. The parsed output populates existing `work_orders` fields via the existing create flow.

## Affected Existing Entities

### WorkOrder (unchanged)

The following existing fields are populated by the AI parse response:

| Field            | Type   | Source in AI Response | Notes                                    |
|------------------|--------|----------------------|------------------------------------------|
| `title`          | String | `response.title`     | AI-generated from NL input               |
| `description`    | String | `response.description` | Expanded, professional version          |
| `location`       | String | `response.location`  | Extracted if mentioned, null otherwise   |
| `type`           | String | `response.type`      | Constrained to valid types list          |
| `departmentName` | String | `response.department`| Matched against user's department list   |
| `status`         | String | `response.status`    | Constrained to valid statuses list       |

No schema changes. No migrations required.

## New Transient Entities (request/response only)

### AiParseRequest (backend)

| Field       | Type     | Required | Description                                 |
|-------------|----------|----------|---------------------------------------------|
| text        | string   | Yes      | User's free-form NL input                   |
| language    | string   | Yes      | `"en"` or `"ar"`                            |
| departments | string[] | Yes      | Valid department names for constrained output|
| types       | string[] | Yes      | Valid work order types                       |
| statuses    | string[] | Yes      | Valid work order statuses                    |

### AiParseResponse (backend)

| Field       | Type    | Nullable | Description                                |
|-------------|---------|----------|--------------------------------------------|
| title       | string  | Yes      | Extracted/generated title                  |
| description | string  | Yes      | Expanded professional description          |
| location    | string  | Yes      | Extracted location                         |
| type        | string  | Yes      | From provided types list                   |
| department  | string  | Yes      | From provided departments list             |
| status      | string  | Yes      | From provided statuses list                |

### Frontend State (in-memory)

| Property              | Type                | Description                                    |
|-----------------------|---------------------|------------------------------------------------|
| `_nlInputController`  | TextEditingController| The NL text input field                       |
| `_isGenerating`       | bool                | Loading state during AI request                |
| `_highlightedFields`  | Set<String>         | Field names currently highlighted as auto-filled|
| `_nlLanguage`         | String              | Selected language for AI (`"en"` or `"ar"`)    |

All state is ephemeral. Nothing is persisted beyond the work order that the user submits through the existing flow.
