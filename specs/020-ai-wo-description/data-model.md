# Data Model: AI-Assisted Work Order Description

**Feature**: 020-ai-wo-description
**Date**: 2026-04-05

## Overview

This feature has no persistent data model. All interactions are request/response with no database storage. The entities below describe the transient data shapes used in the API contract.

## Entities

### AiSuggestRequest (transient)

Sent from Flutter frontend to FastAPI backend.

| Field    | Type   | Required | Description                              |
|----------|--------|----------|------------------------------------------|
| title    | string | Yes      | Work order title (must be non-empty)     |
| location | string | No       | Work order location                      |
| type     | string | No       | Work order type (e.g., "Electrical")     |

**Validation rules**:
- `title` must be a non-empty string after trimming whitespace
- `location` and `type` may be null/empty; omitted from AI prompt if absent

### AiSuggestResponse (transient)

Returned from FastAPI backend to Flutter frontend.

| Field       | Type   | Description                                      |
|-------------|--------|--------------------------------------------------|
| description | string | The AI-generated professional description (2-4 sentences, preamble stripped) |

**Validation rules**:
- `description` must be a non-empty string after preamble stripping
- If empty after processing, backend returns HTTP 502 (bad gateway — model returned unusable response)

## State Transitions

None. This feature has no stateful entities.

## Relationships

None. The request/response entities are independent and do not relate to persisted work order records.

## Database Changes

None required. No migrations needed.
