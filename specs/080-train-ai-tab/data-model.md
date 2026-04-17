# Data Model: 080 — Train the AI Tab

**Date**: 2026-04-17  
**Branch**: `080-train-ai-tab`

## Schema Changes

### Table: `validated_qa` (ALTER — add 2 columns)

| Column | Type | Default | Constraint | Purpose |
|--------|------|---------|------------|---------|
| `verified_at` | TIMESTAMPTZ | `now()` | NOT NULL after backfill | Last time an admin confirmed this entry is still current |
| `source_manual_id` | UUID | NULL | FK → `manuals(id)` ON DELETE SET NULL | Which manual this entry was generated from (NULL for real-usage entries) |

**Backfill**: `UPDATE validated_qa SET verified_at = created_at WHERE verified_at IS NULL`

**Index**: Partial index on `source_manual_id WHERE source_manual_id IS NOT NULL` for staleness query performance.

### Table: `manuals` (ALTER — add 1 column)

| Column | Type | Default | Constraint | Purpose |
|--------|------|---------|------------|---------|
| `updated_at` | TIMESTAMPTZ | `now()` | — | Tracks when manual content was last re-processed |

**Backfill**: `UPDATE manuals SET updated_at = created_at WHERE updated_at IS NULL`

**Trigger**: The re-embed endpoint sets `updated_at = now()` after successful chunk re-embedding.

## Existing Tables Referenced (no changes)

### Table: `answer_ratings`

| Column | Type | Purpose (for this spec) |
|--------|------|-------------------------|
| `id` | UUID PK | Rating identifier |
| `question_text` | TEXT | Original question asked |
| `answer_text` | TEXT | AI answer that was rated |
| `rating` | TEXT CHECK ('positive', 'negative') | User feedback — filter `= 'positive'` for suggestions |
| `review_status` | TEXT CHECK ('pending', 'approved', 'corrected') | NULL for positive ratings (no review needed) |
| `created_at` | TIMESTAMPTZ | Used as `last_asked_at` proxy |

### Table: `manual_chunks`

| Column | Type | Purpose (for this spec) |
|--------|------|-------------------------|
| `id` | UUID PK | Chunk identifier |
| `manual_id` | UUID FK → manuals | Link to source manual |
| `chunk_index` | INTEGER | Ordering |
| `source_page` | INTEGER | Page reference for source label |
| `content` | TEXT | Text content used in Q&A generation prompt |
| `embedding` | VECTOR(768) | Used for cache dedup check via similarity |

### Table: `manuals`

| Column | Type | Purpose (for this spec) |
|--------|------|-------------------------|
| `id` | UUID PK | Manual identifier |
| `title` | TEXT | Display name in dropdown and session history |
| `chunk_count` | INTEGER | Used to validate manual has chunks before generation |

## Entity Relationships

```
manuals (1) ──── (*) manual_chunks
   │                     │
   │ source_manual_id    │ embedding used for
   │ (nullable FK)       │ cache dedup check
   ▼                     ▼
validated_qa ◄──── search_validated_qa RPC
   │
   │ rating_id (nullable FK)
   ▼
answer_ratings ──── real-usage suggestions query
```

## State Transitions

### Q&A Candidate Lifecycle (Section A — From Manuals)

```
[Generated] → Approve → [Approved] → Save All → [Saved to validated_qa]
           → Edit    → [Editing]  → Approve  → [Approved]
           → Reject  → [Dismissed from UI]
```

### Usage Suggestion Lifecycle (Section B — From Real Usage)

```
[Surfaced] → Add to Cache   → [Saved to validated_qa]
           → Edit then Add  → [Editing] → Save → [Saved to validated_qa]
           → Dismiss         → [Hidden in UI, reappears on reload]
```

### Stale Entry Lifecycle (Section C — Needs Review)

```
[Stale: manual.updated_at > qa.verified_at]
  → Still Valid      → [verified_at = now(), exits stale list]
  → Edit & Reconfirm → [re-embed + verified_at = now(), exits stale list]
  → Remove from Cache → [DELETE qa + all variants sharing rating_id]
```

## Migration File

**Path**: `supabase/migrations/20260418000000_train_ai_staleness.sql`

```sql
-- Add staleness tracking to validated_qa
ALTER TABLE validated_qa
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ DEFAULT now(),
  ADD COLUMN IF NOT EXISTS source_manual_id UUID REFERENCES manuals(id) ON DELETE SET NULL;

UPDATE validated_qa SET verified_at = created_at WHERE verified_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_validated_qa_source_manual
  ON validated_qa(source_manual_id) WHERE source_manual_id IS NOT NULL;

-- Add updated_at to manuals for staleness trigger
ALTER TABLE manuals
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

UPDATE manuals SET updated_at = created_at WHERE updated_at IS NULL;
```
