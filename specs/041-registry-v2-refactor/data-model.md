# Data Model: Document Registry V2 UI Refactor

**Date**: 2026-04-12  
**Branch**: `041-registry-v2-refactor`

## Overview

No data model changes. This is a frontend-only UI refactor. The existing `RegistryEntry` model and `DocumentRegistryService` are preserved exactly as-is.

## Existing Entities (unchanged)

### RegistryEntry

| Field | Type | Required | Description |
| ----- | ---- | -------- | ----------- |
| id | String | Yes | Unique identifier |
| documentName | String | Yes | Name of the document |
| documentNumber | String | Yes | Document reference number |
| date | String | Yes | Document date (YYYY-MM-DD format) |
| replied | bool | No (default: false) | Whether the document has been replied to |
| fileName | String? | No | Name of attached file |
| fileUrl | String? | No | URL path of attached file |
| createdBy | String | Yes | Email of creator |
| createdAt | String? | No | Creation timestamp |

**Computed properties**:
- `hasAttachment` → `fileUrl != null && fileUrl!.isNotEmpty`

**Serialization**: `fromJson()` / `toJson()` — maps to backend snake_case JSON.

## UI State Model (new, in-memory only)

The refactored screen introduces local UI state not persisted to any backend:

| State | Type | Scope | Description |
| ----- | ---- | ----- | ----------- |
| expandedIndex | int? | List screen | Index of the currently expanded card (null = all collapsed) |
| historyKey | Key | List screen | UniqueKey for forcing list rebuild after form submission |
| isLoading | bool | List screen | Whether entries are being fetched |
| searchQuery | String | List screen | Current search filter text |
| isSaving | bool | Form screen | Whether a create/update is in progress |
| isExtracting | bool | Form screen | Whether PDF field extraction is in progress |
| pendingAttachment | PlatformFile? | Form screen | PDF file pending upload after entry creation |

## Relationships

No changes to relationships. The registry entry's attachment is managed via the existing `DocumentRegistryService.uploadAttachment()` / `deleteAttachment()` methods.
