# Data Model: Entity Extraction Admin Toggle & AI Priority Queue

**Branch**: `052-extraction-toggle-queue` | **Date**: 2026-04-13

## New Tables

### system_settings

Generic key-value store for global application settings.

| Column     | Type                       | Constraints              | Description                          |
| ---------- | -------------------------- | ------------------------ | ------------------------------------ |
| key        | TEXT                       | PRIMARY KEY              | Setting identifier                   |
| value      | TEXT                       | NOT NULL                 | Setting value (string representation)|
| updated_at | TIMESTAMPTZ                | NOT NULL DEFAULT now()   | Last modification timestamp          |

**Seed data**:
- `entity_extraction_enabled` = `'false'` (toggle defaults OFF)

**Uniqueness**: Primary key on `key` ensures one value per setting.

**Access pattern**: Single-row SELECT by key on each WO save to check toggle state. Single-row UPSERT from admin settings screen.

## In-Memory Entities (not persisted)

### AI Job

Transient job object in the priority queue. Never stored in database.

| Field    | Type                    | Description                                                    |
| -------- | ----------------------- | -------------------------------------------------------------- |
| priority | int                     | 1 = HIGH (user-facing), 2 = LOW (background)                  |
| seq      | int                     | Monotonic counter for FIFO ordering within same priority level |
| func     | Callable                | The async function to execute                                  |
| args     | tuple                   | Positional arguments to pass to func                           |
| kwargs   | dict                    | Keyword arguments to pass to func                              |
| future   | asyncio.Future or None  | Future for result delivery (None for fire-and-forget)          |

**Ordering**: `(priority, seq)` tuple comparison ensures HIGH before LOW, FIFO within same priority.

## Existing Tables (no changes)

- `work_order_entities` — unchanged, receives extraction results as before
- `extraction_failures` — unchanged, receives failure logs as before
- `work_orders` — unchanged, extraction trigger points unchanged

## Relationships

```
system_settings
  └── (read by) entity_extractor → decides whether to enqueue extraction job

AI Job (in-memory)
  └── (processed by) queue worker → calls ollama_generator/ollama_embedder
  └── (result via) asyncio.Future → returned to awaiting caller
```
