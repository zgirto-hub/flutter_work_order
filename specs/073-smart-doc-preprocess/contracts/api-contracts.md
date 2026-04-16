# API Contracts: Smart Document Preprocessing

**Feature**: 073-smart-doc-preprocess  
**Date**: 2026-04-16

## Modified Endpoints

### GET /documents/{document_id}/status

**Change**: Response `status` field now includes `"preprocessing"` as a valid value.

**Response (existing structure, updated status enum)**:
```json
{
  "id": "uuid",
  "status": "pending | preprocessing | indexing | ready | failed",
  "total_pages": 30,
  "total_chunks": 45,
  "error_message": null
}
```

**Frontend impact**: Status polling logic (`documents_tab.dart`) already handles unknown statuses gracefully (displays raw string). The UI should render `"preprocessing"` as a user-friendly label (e.g., "Enhancing content...").

### POST /documents/upload

**Change**: No request/response changes. The background indexing task now includes a preprocessing step between extraction and chunking. The upload response is unchanged.

### POST /manuals/upload

**Change**: No request/response changes. Same preprocessing step added to the background manual indexing flow.

## New Endpoints

### GET /settings/smart-preprocessing

**Purpose**: Check if smart preprocessing is enabled (admin only).

**Response**:
```json
{
  "enabled": true
}
```

### PUT /settings/smart-preprocessing

**Purpose**: Toggle smart preprocessing on/off (admin only).

**Request**:
```json
{
  "enabled": true,
  "user_email": "admin@example.com"
}
```

**Response**:
```json
{
  "enabled": true,
  "updated_at": "2026-04-16T12:00:00Z"
}
```

**Note**: These settings endpoints may be consolidated into existing admin settings routes if an appropriate pattern already exists. The contract defines the logical operation, not necessarily a standalone route.

## Internal Service Contract

### document_preprocessor.preprocess_page()

**Purpose**: Transform a single page's raw text into structured Markdown.

**Input**:
- `raw_text` (str): The raw extracted text from one page
- `page_number` (int): Page number for logging/debugging
- `document_title` (str, optional): Document title for context injection

**Output**:
- `PreprocessResult`: dataclass with `preprocessed_text` (str), `success` (bool), `fallback_used` (bool)

**Behavior**:
- Returns preprocessed Markdown on success
- Returns original `raw_text` with `fallback_used=True` on any failure
- Skips pages with < 50 characters (returns raw text, `success=True`, `fallback_used=False`)
- Timeout: 30 seconds per page
- Retry: Up to 3 attempts with exponential backoff on rate limit (429)
