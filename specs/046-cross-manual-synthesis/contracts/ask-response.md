# API Contract: POST /manuals/ask Response

**Date**: 2026-04-13 | **Branch**: `046-cross-manual-synthesis`

## Endpoint

`POST /manuals/ask`

No changes to the request body. Changes are response-only (additive fields).

## Response Schema

### Single-manual response (manual_id provided) — UNCHANGED

```json
{
  "answer": "string",
  "grounded": true,
  "sources": [
    {
      "manual_id": "uuid",
      "manual_title": "string",
      "chunk_index": 0,
      "source_page": 1,
      "content_preview": "string (max 500 chars)",
      "highlight_start": 42,
      "highlight_end": 87
    }
  ],
  "model": "gemma4:e2b",
  "duration_seconds": 12.3,
  "session_summary": "string or null"
}
```

### Cross-manual response (manual_id is null) — NEW FIELDS

```json
{
  "answer": "According to AMM Chapter 12, the torque value is... According to CMM Engine 737, ...",
  "grounded": true,
  "sources": [
    {
      "manual_id": "uuid-1",
      "manual_title": "AMM Chapter 12",
      "chunk_index": 2,
      "source_page": 45,
      "content_preview": "...",
      "highlight_start": null,
      "highlight_end": null
    },
    {
      "manual_id": "uuid-2",
      "manual_title": "CMM Engine 737",
      "chunk_index": 0,
      "source_page": 12,
      "content_preview": "...",
      "highlight_start": 10,
      "highlight_end": 55
    }
  ],
  "model": "gemma4:e2b",
  "duration_seconds": 42.1,
  "session_summary": "string or null",
  "manuals_consulted": [
    {"id": "uuid-1", "title": "AMM Chapter 12"},
    {"id": "uuid-2", "title": "CMM Engine 737"}
  ],
  "has_conflicts": false
}
```

### Not-grounded response — UNCHANGED

```json
{
  "answer": "This information is not in the available manuals.",
  "grounded": false,
  "sources": [],
  "model": "gemma4:e2b",
  "duration_seconds": 5.2,
  "session_summary": "string or null"
}
```

## Field Rules

| Field | Presence | Notes |
|-------|----------|-------|
| `manuals_consulted` | Only when `manual_id` is null AND `grounded` is true | Array of {id, title} objects |
| `has_conflicts` | Only when `manuals_consulted` is present | Boolean based on "⚠ CONFLICT:" marker detection |
