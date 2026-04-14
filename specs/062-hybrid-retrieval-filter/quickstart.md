# Quickstart — Verifying Hybrid Retrieval System Pre-filter

**Feature**: 062-hybrid-retrieval-filter
**Audience**: developer implementing or reviewing the feature; reviewer verifying the 5 benchmark questions from spec SC-001/SC-002/SC-004.

---

## Prerequisites

- Dev backend running (`uvicorn backend.main:app` locally OR systemd `document_server.service` on the Zorin server after deploy).
- Ollama reachable on localhost:11434 (gemma4:e2b for generation, nomic-embed-text for embedding).
- Supabase dev/prod DB reachable with `manuals` + `manual_chunks` tables populated.
- **For US1/US2**: both CADAS-ATS and CADAS-IMS manuals uploaded.
- **For US3**: CADAS-ATS manual temporarily removed (or a fresh environment where it was never uploaded).
- **For US4**: Flutter app running; know how to select a specific manual from the assistant dropdown.

---

## Step 1 — Unit-test the registry (no external services needed)

```bash
cd backend
pytest tests/test_system_registry.py -v
```

Expected: all cases pass — CADAS-ATS vs CADAS-IMS disambiguation, case-insensitivity, longest-match-wins, None for generic questions.

---

## Step 2 — Backend integration sanity (curl / httpie against running backend)

Replace `$TOKEN` and base URL as appropriate.

```bash
# Benchmark 1: CADAS-ATS specific → should narrow
curl -s -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"question":"what is the backup for CADAS-ATS?"}' \
  http://localhost:8000/manual-assistant/ask | jq '.retrieval_info'
# Expect: {"detected_system":"CADAS-ATS", "filtered_manual_ids":["..."], "filter_applied":true, "fallback_reason":null}

# Benchmark 2: CADAS-IMS specific → should narrow to different manuals
curl -s -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"question":"what is the backup for CADAS-IMS?"}' \
  http://localhost:8000/manual-assistant/ask | jq '.retrieval_info'
# Expect: detected_system="CADAS-IMS", filter_applied=true, different IDs than benchmark 1

# Benchmark 3: AIDA-NG lowercase → case-insensitive detection
curl -s -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"question":"how to restart aida-ng?"}' \
  http://localhost:8000/manual-assistant/ask | jq '.retrieval_info'
# Expect: detected_system="AIDA-NG", filter_applied=true

# Benchmark 4: general question → no filter
curl -s -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"question":"what are the general maintenance rules?"}' \
  http://localhost:8000/manual-assistant/ask | jq '.retrieval_info'
# Expect: detected_system=null, filter_applied=false

# Benchmark 5: ambiguous bare word → no filter
curl -s -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"question":"backup procedure"}' \
  http://localhost:8000/manual-assistant/ask | jq '.retrieval_info'
# Expect: detected_system=null, filter_applied=false
```

---

## Step 3 — Content correctness spot-check

For benchmarks 1 and 2, inspect `.sources[*].manual_title` in the response:

```bash
curl -s ... | jq '.sources[] | .manual_title' | sort -u
```

- Benchmark 1 (CADAS-ATS): every title MUST contain "CADAS-ATS" (no CADAS-IMS titles).
- Benchmark 2 (CADAS-IMS): every title MUST contain "CADAS-IMS" (no CADAS-ATS titles).

This is the direct verification of SC-001 and SC-002.

---

## Step 4 — Missing-manual fallback (SC-004)

1. Temporarily remove the CADAS-ATS manual from the dev environment (delete via the manuals admin UI, or use `delete_manual` RPC).
2. Ask benchmark 1 again.
3. Expected response shape:
   ```json
   {
     "answer": "<answer stating CADAS-ATS info is not available>",
     "retrieval_info": {
       "detected_system": "CADAS-ATS",
       "filtered_manual_ids": [],
       "filter_applied": false,
       "fallback_reason": "no_manuals_for_system"
     }
   }
   ```
4. CRITICAL: the `answer` text MUST NOT contain CADAS-IMS procedures. If it does, the generator prompt directive (R5) is not being applied — check backend logs for `[hybrid-retrieval] System 'CADAS-ATS' detected but no manuals found`.
5. Re-upload the CADAS-ATS manual.

---

## Step 5 — User-selected manual takes precedence (US4)

1. In the Flutter app, select the CADAS-IMS manual from the dropdown.
2. Ask "what is the backup for CADAS-ATS?".
3. Expected: response's `retrieval_info.detected_system="CADAS-ATS"` but `filter_applied=false`; `sources[*].manual_title` all contain "CADAS-IMS" (the selected manual).

---

## Step 6 — UI chip visibility (US5 / FR-011)

1. In the Flutter app with no manual selected, ask benchmark 1 (system-named).
2. Observe the answer card: a small "Filtered to: CADAS-ATS" chip SHOULD appear under the "Synthesized from N manuals" banner.
3. Ask benchmark 4 (general).
4. Observe: no chip; layout identical to pre-feature.
5. Widget test: `flutter test test/widget/answer_card_filter_chip_test.dart` — asserts chip presence when `filterApplied=true`, absence when `false`.

---

## Step 7 — Regression guard (SC-003)

For benchmark 4 ("what are the general maintenance rules?") and benchmark 5 ("backup procedure"):
- Retrieved chunk count SHOULD match pre-feature behavior (no change to the per-manual retrieval path inputs).
- Answer content SHOULD be materially similar to pre-feature answers for the same questions (LLM sampling variance aside).

---

## Logging keys to grep in backend logs

- `[hybrid-retrieval] detected_system=`
- `[hybrid-retrieval] filter_applied=true`
- `[hybrid-retrieval] System '{name}' detected but no manuals found, falling back to all`
- `[hybrid-retrieval] User selected manual — skipping filter`

These four log lines cover every branch of the feature and are the fastest way to confirm which path any given request took.
