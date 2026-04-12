# Phase 1 Data Model: System Manual RAG Assistant

Derived from the Key Entities section of [spec.md](./spec.md) and the decisions recorded in [research.md](./research.md).

---

## 1. Postgres extension

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

Required before any of the tables below can be created. This must be the first statement of the migration so the `VECTOR(768)` column type parses. (Supabase supports `vector` on both free and pro tiers.)

---

## 2. Table `manuals`

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| `id` | `UUID` | NOT NULL | `gen_random_uuid()` | Primary key. Also used as the on-disk filename (see research §12). |
| `title` | `TEXT` | NOT NULL | — | User-supplied display title. Non-unique (same title allowed for different uploads per edge cases). |
| `file_name` | `TEXT` | NOT NULL | — | Original filename supplied by the user at upload time. Display-only; never used to resolve the file on disk. |
| `file_extension` | `TEXT` | NOT NULL | — | One of `'pdf'`, `'docx'`, `'txt'`, `'md'`. Derived from MIME type at upload, not from the user's filename. |
| `file_size_bytes` | `BIGINT` | NOT NULL | — | Original file size at upload, for audit and display. |
| `uploaded_by` | `UUID` | NULL | — | FK → `users(id)` ON DELETE SET NULL (preserves the manual if the uploader's account is removed, matching how existing `files` table behaves). |
| `chunk_count` | `INTEGER` | NOT NULL | 0 | Count of rows in `manual_chunks` for this manual. Denormalized for the Manuals tab list so we don't need a sub-query per row. |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | `now()` | Upload timestamp. |

**Indexes**:
- PK on `id`
- `CREATE INDEX manuals_uploaded_by_idx ON manuals (uploaded_by);` (for future per-user filtering and audit joins)
- `CREATE INDEX manuals_created_at_desc_idx ON manuals (created_at DESC);` (default list sort)

**Relationships**:
- 1 Manual → N Manual Chunks (`manual_chunks.manual_id`, ON DELETE CASCADE)

**Lifecycle**:
- `created` → (stays alive) → `deleted` (hard delete; no soft-delete column)

**Business rules**:
- No uniqueness constraint on `(title)` or `(file_name, uploaded_by)` — per [Assumptions](./spec.md), duplicate uploads are allowed and managed by the user via delete.
- Upload admission enforces [FR-004a](./spec.md) (per-manual cap) and [FR-004c](./spec.md) (corpus ceiling) *before* the INSERT runs, in the router layer — not as CHECK constraints — so the user-visible error messages can be actionable.

---

## 3. Table `manual_chunks`

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| `id` | `UUID` | NOT NULL | `gen_random_uuid()` | PK. |
| `manual_id` | `UUID` | NOT NULL | — | FK → `manuals(id)` ON DELETE CASCADE. |
| `chunk_index` | `INTEGER` | NOT NULL | — | Zero-based ordinal within the parent manual. Used for deterministic citation ordering. |
| `source_page` | `INTEGER` | NULL | — | 1-based page number. Always populated for PDFs (per research §3). Always NULL for DOCX/TXT/MD (per research §4–5). |
| `content` | `TEXT` | NOT NULL | — | The chunk's raw text, up to ~500 words. |
| `embedding` | `VECTOR(768)` | NOT NULL | — | nomic-embed-text output. |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | `now()` | For debug/audit only. |

**Indexes**:
- PK on `id`
- `CREATE INDEX manual_chunks_manual_id_idx ON manual_chunks (manual_id);` (for the filter-to-single-manual case in [FR-013](./spec.md) and for the CASCADE delete)
- `CREATE INDEX manual_chunks_embedding_ivfflat_idx ON manual_chunks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 50);` (per research §1)
- `CREATE UNIQUE INDEX manual_chunks_manual_id_chunk_index_uq ON manual_chunks (manual_id, chunk_index);` (enforces ordering contract)

**Relationships**:
- N Manual Chunks → 1 Manual (`manual_id`)

**Lifecycle**:
- Created as a batch when parent Manual is inserted
- Deleted as a batch via CASCADE when parent Manual is deleted
- Never updated in place (manuals are immutable per [Assumptions](./spec.md))

**Business rules**:
- `(manual_id, chunk_index)` must be unique — enforced at the DB level so duplicate chunks can't silently arise from a partial retry.
- If `source_page` is non-null, the value must be ≥ 1 — no CHECK constraint (router validates), per constitution VII (YAGNI).

---

## 4. Table `manual_corpus_stats`

Single-row counter for the [FR-004c](./spec.md) ceiling check. Rationale in research §10.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| `id` | `SMALLINT` | NOT NULL | 1 | Constant `1`, enforced by CHECK. Only one row ever exists. |
| `total_bytes` | `BIGINT` | NOT NULL | 0 | Running estimate of DB-side corpus size. |
| `manual_count` | `INTEGER` | NOT NULL | 0 | Denormalized count of rows in `manuals`, maintained alongside `total_bytes`. |
| `updated_at` | `TIMESTAMPTZ` | NOT NULL | `now()` | Last mutation timestamp (debug only). |

**Constraints**:
- `CHECK (id = 1)` — guarantees singleton.
- PK on `id`.

**Seed**:
```sql
INSERT INTO manual_corpus_stats (id, total_bytes, manual_count) VALUES (1, 0, 0);
```

**Mutations**:
- `+` on successful upload inside the same transaction as the chunk inserts.
- `-` on successful delete inside the same transaction as the CASCADE delete.
- No other writes; `UPDATE` is restricted to the service role via RLS.

**Why a table and not a cached value**:
- Survives backend restarts
- Transactional with the chunk writes (no drift)
- Introspectable via SQL for debugging

---

## 5. RLS policies

```sql
ALTER TABLE manuals ENABLE ROW LEVEL SECURITY;
ALTER TABLE manual_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE manual_corpus_stats ENABLE ROW LEVEL SECURITY;

-- manuals: any authenticated user can read/write
CREATE POLICY manuals_authenticated_all ON manuals
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- manual_chunks: same
CREATE POLICY manual_chunks_authenticated_all ON manual_chunks
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- manual_corpus_stats: read-only for authenticated, writes only via service role
CREATE POLICY manual_corpus_stats_authenticated_read ON manual_corpus_stats
  FOR SELECT TO authenticated USING (true);
-- (no INSERT/UPDATE/DELETE policy for authenticated → writes require service role)
```

Rationale in research §13: this is defense-in-depth. The backend uses the service-role key for all `/api/manuals/*` endpoints, so the policies above never block a legitimate request from the Flutter client routed through the backend.

---

## 6. Server filesystem layout

```text
backend/
└── uploaded_files/
    └── manuals/
        ├── 3f2504e0-4f89-41d3-9a0c-0305e82c3301.pdf
        ├── 7b44d891-3e7e-43b2-9ef4-5a0c9d3c21a7.docx
        ├── a8c0b2f9-1d2e-4f3a-bc77-6e4d8f09abcd.txt
        └── ...
```

- Directory created on first upload if it does not exist (`os.makedirs(..., exist_ok=True)` in `manual_storage_service.py`).
- Filenames are `{manuals.id}.{manuals.file_extension}` — unique by construction.
- Served at `/files/manuals/<id>.<ext>` by the existing FastAPI `StaticFiles` mount (constitution IV). **No UI action exposes these URLs in this feature** — the mount is a passive convention, unused by the ManualAssistantScreen. The future in-app viewer spec (OOS here) will be the first consumer.
- On manual delete, `os.unlink(path)` is called as part of [FR-022](./spec.md). Missing file → log and proceed ([FR-022](./spec.md) explicitly allows this).

---

## 7. Entity-to-spec traceability

| Spec entity | Table / artifact |
|---|---|
| **Manual** ([spec.md Key Entities](./spec.md)) | `manuals` + on-disk file |
| **Manual Section** | `manual_chunks` |
| **Question** (not persisted per spec) | Ephemeral — lives in the request body of `POST /api/manuals/ask` |
| **Answer** (not persisted per spec) | Ephemeral — returned in the response body of `POST /api/manuals/ask`; logged to `user_activity_log` for audit only |

---

## 8. Flutter model shapes (mirrors)

For symmetry with the backend and because Dart models are part of the Full-Stack Ownership principle (constitution I):

```dart
// frontend/lib/models/manual.dart
class Manual {
  final String id;
  final String title;
  final String fileName;
  final String fileExtension;
  final int fileSizeBytes;
  final String? uploadedBy;          // user id
  final String? uploadedByName;      // resolved display name, optional
  final int chunkCount;
  final DateTime createdAt;
}

// frontend/lib/models/manual_source.dart
class ManualSource {
  final String manualId;
  final String manualTitle;
  final int chunkIndex;
  final int? sourcePage;             // null for DOCX/TXT/MD
  final String contentPreview;       // first ~500 chars of the chunk
  final int? highlightStart;         // null if FR-012a cannot confidently mark
  final int? highlightEnd;
}

// frontend/lib/models/manual_qa_answer.dart
class ManualQaAnswer {
  final String answer;
  final List<ManualSource> sources;  // top-k used chunks; may be empty on "not in the available manuals"
  final bool grounded;               // false when the assistant returned the sentinel phrase
}
```

These model shapes are the UI contract. The JSON-level API contract that the backend must honor lives in [contracts/manuals-api.md](./contracts/manuals-api.md).
