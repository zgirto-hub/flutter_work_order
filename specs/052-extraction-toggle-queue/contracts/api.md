# API Contracts: Entity Extraction Admin Toggle & AI Priority Queue

**Branch**: `052-extraction-toggle-queue` | **Date**: 2026-04-13

## Settings Endpoints

### GET /api/settings/{key}

Retrieve a single system setting by key.

**Auth**: Admin only

**Response 200**:
```json
{
  "key": "entity_extraction_enabled",
  "value": "false",
  "updated_at": "2026-04-13T12:00:00Z"
}
```

**Response 404**:
```json
{
  "detail": "Setting not found"
}
```

---

### PUT /api/settings/{key}

Update a system setting value.

**Auth**: Admin only

**Request body**:
```json
{
  "value": "true"
}
```

**Response 200**:
```json
{
  "key": "entity_extraction_enabled",
  "value": "true",
  "updated_at": "2026-04-13T12:05:00Z"
}
```

**Response 404**:
```json
{
  "detail": "Setting not found"
}
```

---

## Existing Endpoints (behavior changes)

### POST /work-orders

**Change**: Before enqueuing entity extraction as a background task, checks `entity_extraction_enabled` setting. If `false` or missing, extraction is skipped.

**Response**: Unchanged — WO creation response is not affected.

### POST /work-orders/{work_order_id}/close

**Change**: Same toggle check as create endpoint.

**Response**: Unchanged.

---

## Queue Behavior (internal, no API surface)

The AI priority queue has no external API. It is an internal mechanism that serializes all Ollama calls. Callers interact with it indirectly through `ollama_generator.generate()` and `ollama_embedder.embed_single()`/`embed_many()`, which now accept an optional `priority` parameter:

- `priority=1` (HIGH, default) — user-facing requests, result awaited via Future
- `priority=2` (LOW) — background extraction, fire-and-forget (no Future)
