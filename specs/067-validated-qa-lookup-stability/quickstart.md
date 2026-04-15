# Quickstart: Validated-QA Lookup Stability

**Branch**: `067-validated-qa-lookup-stability`

## Prerequisites

- At least one validated-QA entry exists in the `validated_qa` table for a self-contained question (e.g., "what is the password of AIDA NG system?"). Verify via Supabase dashboard.
- Local backend runs with `uvicorn` against the live Supabase; or Zorin server restarted after deploy.

## Verification steps (manual, browser-based)

### 1. Story 1 — five identical asks must all hit the cache

1. Open Ask-the-AI in a fresh browser session (hard reload / incognito).
2. Ask: `what is the password of AIDA NG system?`
   - **Expect**: "Verified Answer" badge, `Username=SUPERUSER / password=Aftnlinux1`, pipeline < 2 s.
3. Without reloading or clearing the conversation, ask the exact same question **four more times** back-to-back.
   - **Expect**: All four responses are identical Verified Answers, each under 2 s.
4. **Pass criteria**: 5 / 5 responses are cache hits. No response says "This information is not in the available manuals." No response takes more than ~2 s.

### 2. Story 2 — topic switch does not break the cache

1. Fresh session. Ask `what is the password of AIDA NG system?` → expect cache hit.
2. Ask an unrelated question: `how do I check the system status?` → expect normal RAG response.
3. Re-ask `what is the password of AIDA NG system?`
   - **Expect**: Cache hit, same Verified Answer as step 1.
4. Ask a trivially paraphrased form: `what's the password of aida-ng?`
   - **Expect**: Cache hit (same entry matched).

### 3. Regression — context-dependent follow-up still flows through rewrite

1. Fresh session. Ask `how do I restart CADAS-ATS?` → expect full RAG answer (not necessarily cached).
2. Ask the follow-up: `any other steps?`
   - **Expect**: Meaningful response scoped to CADAS-ATS (not "information not in manuals", not a cross-topic cached answer). Behavior must be identical to pre-fix baseline.

### 4. Regression — genuinely unknown question still answers correctly

1. Fresh session. Ask `what is the serial number of the coffee machine?`
   - **Expect**: Exactly `This information is not in the available manuals.`
   - **Expect**: Pipeline time comparable to pre-fix miss (within ~1 s — the new pre-rewrite lookup adds its own embed+RPC cost on miss).

## Verification steps (automated, pytest)

From `backend/`:

```bash
pytest tests/test_validated_qa_lookup.py -v
```

Expected tests:

- `test_pre_rewrite_hit_returns_cached_answer_without_rewrite` — mocks rewrite + HyDE, asserts they are NOT called when the pre-rewrite lookup hits.
- `test_pre_rewrite_miss_falls_through_to_existing_pipeline` — mocks pre-rewrite lookup to return `none`, asserts rewrite is called and the existing post-rewrite lookup runs.
- `test_context_dependent_followup_hits_post_rewrite_path` — simulates `"any other steps?"` after CADAS-ATS turn; asserts pre-rewrite misses and post-rewrite path is exercised.
- `test_system_filter_applied_on_pre_rewrite_lookup` — asserts `detected_system` is passed to the raw-question `check_validated_match` call.
- `test_validated_qa_never_written_on_read_path` — asserts no insert/update/delete RPCs are called against `validated_qa` during an ask cycle.

## Deploy & smoke check

1. Merge branch to main.
2. On Zorin server: `git pull && sudo systemctl restart document_server.service`.
3. Tail logs: `sudo journalctl -u document_server.service -f`.
4. Run verification step 1 above from a browser.
5. Grep logs for `validated_qa hit (pre-rewrite)` — should appear on each of the five asks.

## Rollback

If cache-hit rate degrades or latency regresses on the miss path:

```bash
git revert <commit-sha>
sudo systemctl restart document_server.service
```

Zero DB state to roll back. Rollback is safe at any time.
