# Research / Decisions — Spec 090

**Feature**: Delete Legacy `manuals` Table & Dead Code
**Phase**: 0 (Outline & Research)
**Status**: Complete — no NEEDS CLARIFICATION markers in the spec; this document records the decisions that shaped the plan.

The spec had zero `[NEEDS CLARIFICATION]` markers. That does not mean every question was obvious — several non-trivial design choices were made with reasonable defaults, documented in the spec's Assumptions and surfaced here so a reviewer can challenge any of them without re-reading the whole spec.

---

## Decision 1 — `answer_ratings.manual_id`: drop the column, not just the FK

**Decision**: the migration drops the column outright (`ALTER TABLE answer_ratings DROP COLUMN manual_id`), not just the foreign-key constraint.

**Rationale**: after Story 2 ships, no Python code reads or writes this column. Its only historical semantic was "the manuals-table row this rating came from". Keeping the column as a loose UUID (the spec-080 pattern for `validated_qa.source_manual_id`) would leave a column that nothing reads and whose values permanently reference a table that no longer exists — pure cruft. Dropping it is cleaner.

**Alternatives considered**:

- *Drop only the FK constraint, leave the column as nullable UUID*. Chosen by spec 080 for `validated_qa.source_manual_id` because that column had active readers at the time (staleness logic). For `answer_ratings.manual_id` the column has no readers, so the argument doesn't transfer.
- *Rename the column to `source_document_id`*. Would require two-step data migration (repoint UUIDs to `knowledge_documents` IDs where possible). Rejected as scope creep — no surviving code actually wants this data.

**Override path**: if the user prefers the spec-080 pattern for consistency, change the migration to `ALTER TABLE answer_ratings DROP CONSTRAINT answer_ratings_manual_id_fkey` only. Column stays. One-line change; no other artifact needs updating.

---

## Decision 2 — `/manuals/*` URL prefix: keep it

**Decision**: the backend route prefix `/manuals/*` is retained. The AI-assistant surface (`/manuals/ask`, `/manuals/rate-answer`, `/manuals/verified-answers/…`, `/manuals/settings`, `/manuals/models`) continues to live under this prefix.

**Rationale**: the user's scope statement targets the SQL table and dead code, not the URL namespace. Roughly 24 of ~36 routes under `/manuals/*` are live AI-assistant endpoints with no relationship to the `manuals` SQL table — renaming them would touch the frontend service layer, every caller, and potentially break any bookmarked admin URLs. That is a separate refactor with its own justification and risk profile.

**Alternatives considered**:

- *Rename the prefix to `/ai-assistant/*` or `/rag/*` as part of this spec*. Rejected: triples the blast radius of a cleanup spec and creates a coupling between two unrelated concerns (SQL table deletion ↔ URL rename).
- *Rename only the routes that logically belong to the manuals feature (e.g., `/manuals/count`)*. Rejected: inconsistent and hard to reason about. All or nothing.

**Override path**: if the user wants the rename, it becomes a future spec (e.g., "091-rename-manuals-url-prefix") that can alias or redirect. That work is completely decoupled from the SQL-table deletion.

---

## Decision 3 — Preserved column names: `validated_qa.manual_ids`, `validated_qa.source_manual_id`

**Decision**: both columns keep their historical names. `manual_ids` stays as an UUID array whose semantics are now "IDs of source knowledge documents". `source_manual_id` stays as a loose UUID (FK already dropped by the spec-080 migration `20260418100000_train_ai_use_knowledge_documents.sql`).

**Rationale**: renaming would require a multi-step migration (create new column → backfill → drop old → update every reader). That's entirely separable from this spec and carries its own rollback risk. The names are misleading but the values are correct, and every caller of these columns already treats them as "source document IDs" regardless of name.

**Alternatives considered**:

- *Rename `manual_ids` → `source_document_ids`, `source_manual_id` → `source_document_id`*. Rejected: pure nomenclature fix, scope creep, and it would require changes in `validated_qa_service.py` and related readers that are otherwise untouched.
- *Rename only the more-visible one (`manual_ids`)*. Rejected: inconsistent.

**Override path**: future spec, out of scope here.

---

## Decision 4 — `backend/uploaded_files/manuals/` directory: preserved

**Decision**: the on-disk directory `backend/uploaded_files/manuals/` is **not** touched. No files are deleted.

**Rationale**: specs 070 and 072 established this directory as the storage location for `knowledge_documents` PDFs as well — it is a shared runtime directory, not exclusive to the legacy `manuals` table. Deleting it or pruning its contents would break the live knowledge-documents corpus. The directory is not committed (per constitution IV and AGENT.md) and its contents are managed by the knowledge-documents upload pipeline.

**Alternatives considered**:

- *Delete stale PDFs that correspond to dropped `manuals` rows*. Rejected because: (a) `manuals` has 0 rows per the production check, so there are no UUIDs to target; (b) the directory is shared and targeting by UUID carries risk of deleting a knowledge_documents file; (c) disk footprint of a few orphaned PDFs (if any) is negligible.
- *Move the directory to `uploaded_files/knowledge_documents/`*. Rejected — the path is hard-coded in knowledge-documents code. That's a rename refactor, out of scope.

---

## Decision 5 — Surgical trim of `manual_rag_service.py` vs. deleting the whole file

**Decision**: trim only the functions related to upload/delete/re-embed/chunk CRUD and the `manual_corpus_stats` reads/writes. Keep the ask-path helpers, prompt builders, and RAG-pipeline utilities that the retained `/manuals/ask*` routes still use.

**Rationale**: the file mixes (a) upload/delete pipeline that touches the `manuals` family of tables, and (b) the question-answering RAG pipeline that reads `document_chunks`. Deleting the whole file would break every retained AI-assistant route. The only viable approach is a targeted diff.

**Alternatives considered**:

- *Split `manual_rag_service.py` into `document_upload_service.py` (delete) and `rag_service.py` (retained) before trimming*. Rejected: that's a refactor on top of a cleanup. The spec prioritizes minimal churn — let a future developer split if they want.
- *Copy the ask-path helpers into a new file and delete the old one wholesale*. Same rejection as above plus the risk of missing a subtle helper.

**Concrete trim targets** (by line number in current main):

- `upload_manual` pipeline (calls `create_manual_with_chunks` RPC near line 984; `manual_corpus_stats` reads near line 947): **delete**.
- `delete_manual_with_stats` RPC callsite (near line 2225): **delete**.
- `manual_corpus_stats` update at line 1248 (within a delete path): **delete**.
- `manual_corpus_stats` update at line 1623 (within another delete path): **delete**.
- Helper functions `preprocess_pages`, `chunk_paragraphs`, `apply_contextual_prefix`, `embed_many` and the ask-path logic: **keep**.

Tasks phase (`/speckit.tasks`) will generate the precise diff. This research doc just confirms the file is not deletable wholesale.

---

## Decision 6 — Test handling: delete entire files that exclusively cover removed routes; trim shared files

**Decision**: delete test files whose every test targets a removed route/service. For files that mix removed-route tests with retained-route tests, delete the individual test cases and keep the file.

**Rationale**: this matches the surgical approach for `manual_rag_service.py`. Deleting a whole file wholesale is cheaper when all its content goes away; trimming per-case is required when the file covers both.

**Files to delete wholesale** (every test covers a removed route or service):

- `backend/tests/routers/test_manuals_bulk_delete.py` — bulk-delete of chunks
- Any other `tests/routers/test_manuals_*` that exclusively targets upload/chunk CRUD (tasks phase will enumerate)
- `backend/scripts/backfill_validated_qa_manual_ids.py` is a script, not a test, but same disposition — delete.

**Files to trim** (mix of removed and retained):

- `backend/tests/test_derive_manual_ids.py` — keep assertions that exercise derive logic against `knowledge_documents`, delete assertions that require a row in `manuals`.
- `backend/tests/test_manual_rag_latency.py` — keep ask-path latency assertions, delete upload-path setup if present.
- `backend/tests/test_rag_quality.py`, `test2_rag_quality.py`, `test_rag_diagnostic_service.py`, `test_admin_rag_diagnostics.py`, `test_paraphrase_generation.py`, `test_sentinel_phrases.py`, `test_verified_sort.py` — each requires per-test inspection; most likely to keep with small edits to stop referencing the `manuals` table fixture.

Tasks phase will enumerate the exact tests.

---

## Decision 7 — Deploy order: hard constraint Stories 1 → 2 → 3

**Decision**: the three stories MUST ship in order 1 → 2 → 3, each with its own verification gate before the next proceeds. No collapsing into one big PR or deploy.

**Rationale**: each order inversion creates a broken state:

- **Story 2 before Story 1** → frontend still has UI buttons that call removed routes. Admin sees "Migrate all" button return 404. Regression.
- **Story 3 before Story 2** → backend routes still exist and attempt to query dropped tables. First call returns 500. Regression.

**Alternatives considered**:

- *Ship 1 + 2 together*. Possible (both are application code), but separate deploys give a cleaner blast-radius boundary if one story needs rollback.
- *Ship 2 + 3 together*. Rejected — the point of separating Story 3 is to let application code soak in production before the irreversible DB change.

**Override path**: if the project is on a tight timeline and both 1 and 2 have been thoroughly tested, combining them into one deploy is acceptable. Story 3 stays separate.

---

## Decision 8 — Pre-migration safety check (Story 3 gate)

**Decision**: the migration's first statement is a safety check that fails loudly if `manuals` or `manual_chunks` has any rows:

```sql
DO $$
DECLARE
  manuals_n INT;
  chunks_n INT;
BEGIN
  SELECT COUNT(*) INTO manuals_n FROM manuals;
  SELECT COUNT(*) INTO chunks_n FROM manual_chunks;
  IF manuals_n > 0 OR chunks_n > 0 THEN
    RAISE EXCEPTION 'Aborting: manuals=% rows, manual_chunks=% rows; expected 0/0', manuals_n, chunks_n;
  END IF;
END $$;
```

**Rationale**: the whole premise of the spec is that these tables are empty. A defensive check at migration time catches a drift between audit-time assumption and execution-time reality. The migration fails fast and cleanly rather than silently dropping rows.

**Alternatives considered**:

- *Rely on the prior-session check*. Rejected — production state can change between audit and execution; the window is the whole duration of this spec.
- *Manual `SELECT COUNT(*)` as a step in the deployment runbook*. Rejected — humans forget runbook steps. Belt-and-suspenders: do both.

---

## Out of research scope

- **Renaming anything** — URLs, column names, table names. All deferred to separate specs.
- **Deleting `manual_assistant_settings`** — actively used for Layer 2 system instructions. Not in scope.
- **Refactoring `manual_rag_service.py`** beyond the targeted trim. Future spec can split upload/ask concerns.
- **Audit log retention policy** — the `user_activity_log` rows emitted by the removed `/migrate-*` routes stay in history; no log-retention change is part of this spec.
