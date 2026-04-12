# Quickstart: System Manual RAG Assistant

This document describes the minimum steps needed to bring the feature up from a clean checkout on a dev machine, plus the two manual test flows that exercise the P1 user stories end-to-end.

---

## 1. One-time server setup

On the backend host (dev or Zorin production):

```bash
# pull the embedding model alongside the existing gemma3 model
ollama pull nomic-embed-text
```

Verify both models are listed:

```bash
ollama list
# expect: gemma3:e2b, nomic-embed-text, ...
```

No other server-side setup is needed. Ollama is already running on `localhost:11434` per project convention.

---

## 2. Python dependencies

Add to `backend/requirements.txt`:

```
pymupdf==1.24.10
python-docx==1.1.2
```

Install:

```bash
cd backend
pip install -r requirements.txt
```

No new Flutter packages are required — the frontend uses `http`, `file_picker`, and `supabase_flutter`, all of which are already in `pubspec.yaml`.

---

## 3. Database migration

Apply the migration that creates the `vector` extension and the two new tables:

```bash
# from repo root
supabase db push  # or whatever command the project normally uses to apply migrations
```

The migration file is `supabase/migrations/20260411000000_create_manuals.sql`. It enables the pgvector extension, creates `manuals`, `manual_chunks`, `manual_corpus_stats`, the ivfflat index, and the RLS policies described in [data-model.md](./data-model.md).

Verify the tables exist:

```sql
-- run in Supabase SQL editor
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('manuals', 'manual_chunks', 'manual_corpus_stats');
-- expect 3 rows
```

---

## 4. Environment variables

Add (or confirm) to `backend/.env`:

```
OLLAMA_URL=http://localhost:11434
OLLAMA_GEN_MODEL=gemma3:e2b
OLLAMA_EMBED_MODEL=nomic-embed-text
MANUAL_CORPUS_CEILING_MB=400
```

`MANUAL_CORPUS_CEILING_MB` is the [FR-004c](./spec.md) configurable ceiling. Setting it below 400 on a dev machine lets you test the "library full" rejection path without uploading ~45k chunks.

---

## 5. Bring up the stack

```bash
# backend
cd backend
uvicorn main:app --reload

# in another terminal — frontend
cd frontend
flutter run -d chrome
```

The Manual Assistant entry should appear in the app's main navigation (drawer or bottom nav, depending on the role's shell). All three roles (`reporter`, `technician`, `admin`) should see it per [FR-001](./spec.md).

---

## 6. Manual acceptance flow — P1 user stories

These two scripts validate User Story 1 and User Story 2 from [spec.md](./spec.md) in under 3 minutes, satisfying [SC-001](./spec.md).

### Flow A — Upload → Ask (happy path, English)

1. Log in as any user. Open the Manual Assistant entry.
2. Switch to the **Manuals** tab. The empty state should say something like "Your library is empty. Upload a manual to get started."
3. Tap the upload FAB. Pick a small PDF from `tests/fixtures/manual_sample.pdf` (a 5–10 page PDF with extractable text).
4. Enter a title, e.g. `Sample Equipment Manual`. Confirm.
5. A loading indicator should show until processing completes. Expected time: < 10 seconds for a 5-page PDF.
6. The manuals list should now contain one row with the title, file name, your user display name, and today's date.
7. Switch to the **Chat** tab. The empty state should now invite you to ask a question.
8. Type a question whose answer is in the PDF, e.g. `What is the recommended torque for the main bolt?`.
9. Tap send. A loading indicator should appear. Expected first-response time: < 15 seconds (per [SC-004](./spec.md)).
10. The answer card should render with (a) the generated answer, (b) an expandable Sources section, (c) at least one source citing `Sample Equipment Manual` with a page number, and (d) one highlighted sentence in the source's content preview.
11. Expand the Sources section and verify the highlighted text matches the answer's substantive content.

### Flow B — Not-grounded rejection (English)

1. Continuing from Flow A, ask a question whose answer is clearly **not** in the PDF, e.g. `What is the capital of France?`.
2. Expected: the answer is exactly `This information is not in the available manuals.` (or a close equivalent). The Sources section is empty or hidden.
3. This validates [FR-010](./spec.md) and [SC-003](./spec.md).

### Flow C — Arabic round-trip

1. Upload a second manual: `tests/fixtures/manual_sample_ar.pdf` with Arabic extractable text.
2. In the Chat tab, do not filter. Ask in Arabic: `ما هو الحد الأقصى لضغط النظام الهيدروليكي؟`
3. Expected: the answer is in Arabic, cites the Arabic manual, and includes a highlighted source. Validates [FR-011](./spec.md) and [SC-009](./spec.md).

### Flow D — Strict filter

1. With both manuals uploaded, open the Chat tab.
2. In the manual filter dropdown, select `Sample Equipment Manual` only.
3. Ask: `ما هو الحد الأقصى لضغط النظام الهيدروليكي؟` (the Arabic question from Flow C).
4. Expected: `This information is not in the available manuals.` with no hint that the Arabic manual might have the answer. Validates the strict-filter decision from Q3 and [FR-013](./spec.md).

### Flow E — Delete cascade

1. On the Manuals tab, long-press (or swipe) one of the uploaded manuals. Tap Delete.
2. Confirm the dialog.
3. Expected: the row disappears; corpus usage in the bottom hint decreases; a follow-up question against that manual's content returns the not-grounded sentinel.
4. On the server, verify `backend/uploaded_files/manuals/<manual_id>.pdf` is gone:
   ```bash
   ls backend/uploaded_files/manuals/
   ```
   Validates [FR-022](./spec.md).

### Flow F — Corpus ceiling rejection (optional)

1. Temporarily set `MANUAL_CORPUS_CEILING_MB=1` in `backend/.env` and restart the backend.
2. Try to upload any manual larger than ~200 KB.
3. Expected: the upload is rejected with an actionable "library full — delete a manual to make room" message. No partial state is left behind.
4. Restore `MANUAL_CORPUS_CEILING_MB=400` after testing. Validates [FR-004c](./spec.md) and [SC-007b](./spec.md).

---

## 7. Contract test fixtures

Under `backend/tests/fixtures/`:

```text
manual_sample.pdf            # ~5 pages, English, known content
manual_sample_ar.pdf         # ~5 pages, Arabic, known content
manual_sample_empty.pdf      # 1 page, only images (for no_extractable_text test)
manual_sample_large.pdf      # 501 pages (for too_many_pages test) — can be synthesized
manual_sample_oversize.bin   # 21 MB random bytes renamed to .pdf (for file_too_large test)
```

Only `manual_sample.pdf` and `manual_sample_ar.pdf` need to exist for the quickstart flows; the rest are used by the contract tests enumerated in [contracts/manuals-api.md](./contracts/manuals-api.md).

---

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Upload fails with 504 `embedder_unavailable` | Ollama not running or model not pulled | `ollama serve`, then `ollama pull nomic-embed-text` |
| Ask returns 504 `assistant_unavailable` consistently | Gemma cold-start or RAM pressure | First call after idle takes ~30s; retry once. If persistent, check server RAM and that `gemma3:e2b` (not `e4b`) is the loaded model. |
| "corpus_full" immediately on first upload | `MANUAL_CORPUS_CEILING_MB` set too low or stats table not seeded | Check `SELECT * FROM manual_corpus_stats;` — should have exactly one row with `id=1`. If missing, the migration did not run correctly. |
| Answer is always `This information is not in the available manuals.` even though content exists | Nearest-neighbor returned low-similarity chunks OR Gemma ignored them | Inspect retrieved chunks via the audit log (`asked_manual` action) and the Chat tab's expanded sources when `grounded=false`. If top-chunk distance > 0.5, the embedder/embedder model mismatch is likely — verify both upload and ask use `nomic-embed-text`. |
| Uploads succeed but chat shows no sources on answer | `manual_chunks` embedding dim mismatch | Confirm the migration created `VECTOR(768)` not `VECTOR(384)` or other size. nomic-embed-text is 768-d. |
| Delete leaves orphaned file on disk | The file was written during a failed upload before the compensating unlink | Manually remove the orphan; then file a bug if reproducible, since research §11 guarantees cleanup. |

---

## 9. What success looks like

The feature is considered ship-ready when:

- Flows A, B, C, D, E above all pass on a fresh database.
- The contract test suite in `backend/tests/routers/test_manuals.py` is green.
- The `AGENT.md` new-feature checklist (constitution I) is complete: backend router, migration, model, service, screen, navigation, docs update.
- A 500-page PDF (the worst-case manual within the cap) completes the full upload pipeline in under 3 minutes on the Zorin server.
- A typical question returns its first visible response in under 15 seconds against a corpus of ~100 manuals (validates [SC-004](./spec.md) and [SC-007a](./spec.md)).
