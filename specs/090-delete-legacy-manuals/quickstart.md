# Quickstart — Verification Recipe for Spec 090

**Feature**: Delete Legacy `manuals` Table & Dead Code
**Audience**: the developer (or opencode agent) executing the three stories. This is the per-story verification gate — do not proceed from one story to the next until the previous story's checks pass.

The server URL used in examples assumes Tailscale: `https://zorin.taila92fe8.ts.net`. The admin email used for gated routes is `salah@admin.com`.

---

## Story 1 — Frontend removal

### What to run

```bash
# From repo root, after applying Story 1 changes on branch 090-delete-legacy-manuals
cd frontend
flutter analyze
flutter test                # widget tests, if any survive the deletion
# Then deploy frontend only:
bash scripts/deploy_frontend.sh
```

### What to check in the browser

1. Log in as `salah@admin.com` (admin).
2. Open **Ask the AI** from the home grid.
3. Inspect the tab bar. **Pass**: no "Manuals" tab label anywhere. (It should already be absent on `main`; this spec deletes the orphaned file.)
4. Click the **Documents** tab. **Pass**: no "Old manuals detected", no "Migrate all" button, no migration-progress dialog.
5. Click **Train AI**, **RAG Logs**, **Verified Answers**, **Review Queue**, **Rules**, **Alerts**. **Pass**: all tabs render and their primary actions (view, sort, open detail) work.
6. Ask a question on the **Chat** tab. **Pass**: an answer streams in using the knowledge-documents corpus.
7. Rate an answer thumbs-down and add feedback. **Pass**: the rating posts successfully.
8. Open the admin-only "AI Settings" dialog and change a setting. **Pass**: save succeeds.

### Regressions to watch for

- Any broken import warning in `flutter analyze` mentioning `manual.dart`, `manuals_tab.dart`, `chunk_editor_screen.dart`, or `upload_dialog.dart`.
- Any tab bar that shifts or goes blank (indicates the `TabController` length or children count is mis-aligned).
- Any "Method not found on ManualAssistantService" error at runtime (indicates a call site for a removed service method wasn't cleaned up).

### Gate to Story 2

Frontend must be in production and exercised for at least one admin session with no regressions reported before Story 2 ships.

---

## Story 2 — Backend removal

### What to run

```bash
# Local: verify backend still imports
cd backend
python -c "import routers.manuals; import routers.documents; import services.manual_rag_service"
pytest tests/ -x            # all surviving tests must pass

# On the server (after pushing the backend changes and `pip install -r requirements.txt`):
sudo systemctl restart document_server.service
sudo systemctl status document_server.service
journalctl -u document_server.service --since "1 min ago" | tail -50
```

### What to check via curl

Every removed route must return `404`:

```bash
BASE=https://zorin.taila92fe8.ts.net
ADMIN="user_email=salah@admin.com"

for path in \
  "/manuals/" \
  "/manuals/upload" \
  "/manuals/00000000-0000-0000-0000-000000000000" \
  "/manuals/00000000-0000-0000-0000-000000000000/chunks" \
  "/manuals/00000000-0000-0000-0000-000000000000/chunks/re-embed" \
  "/manuals/00000000-0000-0000-0000-000000000000/chunks/bulk-delete" \
  "/migrate-all" \
  "/migration-status" \
  "/migrate-cleanup"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE$path?$ADMIN")
  echo "$code  $path"   # expect 404 for every line
done
```

Every retained route must respond normally — spot-check:

```bash
# Models / settings should return 200 with JSON
curl -s "$BASE/manuals/models"            | head -c 200 ; echo
curl -s "$BASE/manuals/active-provider"   | head -c 200 ; echo
curl -s "$BASE/manuals/settings"          | head -c 200 ; echo

# Ask-the-AI should still answer
curl -s -X POST "$BASE/manuals/ask" \
  -H 'Content-Type: application/json' \
  -d '{"question":"test","user_email":"salah@admin.com","conversation":[]}' | head -c 300 ; echo
```

### What to check in the browser (admin session)

Repeat every Story 1 UI check. **Pass**: identical behavior. No dev-tools network error rows pointing at `/manuals/*` or `/migrate-*`.

### Gate to Story 3

Backend must be in production. Smoke test (ask a question + rate it + check verified answers) must pass end-to-end. At least one full working day in production with no regression reports before Story 3 ships.

---

## Story 3 — Database migration

### Pre-migration verification

Run these on production Supabase (read-only):

```sql
-- Expect: 0 rows. If either is non-zero, do NOT proceed.
SELECT COUNT(*) AS manuals_count FROM manuals;
SELECT COUNT(*) AS manual_chunks_count FROM manual_chunks;

-- Record what will be dropped (for after-action review)
SELECT 'manuals' AS obj, count(*) AS n FROM manuals
UNION ALL SELECT 'manual_chunks', count(*) FROM manual_chunks
UNION ALL SELECT 'manual_corpus_stats', count(*) FROM manual_corpus_stats
UNION ALL SELECT 'answer_ratings.manual_id NOT NULL', count(*)
  FROM answer_ratings WHERE manual_id IS NOT NULL;
```

### Apply the migration

Using the Supabase MCP or CLI:

```bash
# Option A — via Supabase MCP server (from Claude)
# apply_migration: 20260420_drop_legacy_manuals

# Option B — via psql (if running ad-hoc)
psql "$SUPABASE_URL" -f supabase/migrations/20260420_drop_legacy_manuals.sql
```

The migration's first statement is a `DO $$ … RAISE EXCEPTION` safety gate that aborts if either legacy table has rows. If the migration aborts, no data is dropped — investigate the non-zero rows before retrying.

### Post-migration verification

```sql
-- Absent tables (expect 0)
SELECT count(*) FROM information_schema.tables
  WHERE table_schema='public' AND table_name IN ('manuals','manual_chunks','manual_corpus_stats');

-- Absent RPCs (expect 0)
SELECT count(*) FROM pg_proc
  WHERE proname IN ('search_manual_chunks','create_manual_with_chunks','delete_manual_with_stats');

-- answer_ratings: no manual_id column, no FK (expect 0 for both)
SELECT count(*) FROM information_schema.columns
  WHERE table_name='answer_ratings' AND column_name='manual_id';
SELECT count(*) FROM information_schema.table_constraints
  WHERE table_name='answer_ratings' AND constraint_name='answer_ratings_manual_id_fkey';

-- Retained objects still present
SELECT count(*) FROM manual_assistant_settings WHERE id = 1;   -- expect 1
SELECT count(*) FROM information_schema.columns
  WHERE table_name='validated_qa' AND column_name='source_manual_id';  -- expect 1
SELECT count(*) FROM information_schema.columns
  WHERE table_name='validated_qa' AND column_name='manual_ids';        -- expect 1
```

### End-to-end app verification

Log in as `salah@admin.com` and run the same browser checklist from Story 1. Every check MUST still pass. Watch the server journal while doing this:

```bash
sudo journalctl -u document_server.service -f
```

No entries should reference `manuals`, `manual_chunks`, `manual_corpus_stats`, `search_manual_chunks`, `create_manual_with_chunks`, or `delete_manual_with_stats`.

### 7-day soak

Per SC-006 in the spec, no user-reported regression tracing to a removed route, RPC, or table for at least 7 days after Story 3 ships.

---

## Rollback paths

- **Story 1 rollback**: git revert on the frontend branch, redeploy via `scripts/deploy_frontend.sh`. Fully reversible.
- **Story 2 rollback**: git revert on backend branch, re-run `pip install -r requirements.txt` if needed, `sudo systemctl restart document_server.service`. Fully reversible.
- **Story 3 rollback**: the migration is irreversible in the sense that the dropped tables are gone. However, because the tables were empty (gated by the safety check), recreating the schema from the original migration files (`20260411000000_create_manuals.sql`, `20260413000000_create_feedback_loop.sql` for the FK, `20260418000000_train_ai_staleness.sql` for the `source_manual_id` FK which was already dropped separately) restores the structure. No data is recoverable because none existed to lose.

If a rollback is needed, stop at Story 3 boundary: Stories 1 and 2 can always be re-shipped without DB intervention.
