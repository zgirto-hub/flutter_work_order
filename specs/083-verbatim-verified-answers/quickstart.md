# Quickstart: Verbatim Verified Answers — manual verification

**Feature**: 083-verbatim-verified-answers
**Audience**: Reviewer / QA / post-deploy validator
**Prerequisite**: Feature branch deployed to the Zorin server; backend restarted via `sudo systemctl restart document_server.service`; frontend built and deployed via `scripts/deploy_frontend.sh`.

This is a 10-minute walkthrough of the golden paths and the main edge cases. No unit-test framework is invoked at this layer; `backend/tests/test_verbatim_helper.py` covers the helper in isolation.

---

## 0. Pre-flight

1. Confirm the backend is up: `curl https://zorin.taila92fe8.ts.net/api/health` — expect 200.
2. Confirm you have at least one curated `validated_qa` row with a clearly-unique question. If not, add one via the Train AI tab (spec 080) with a distinctive question such as "how to backup CADAS ATS".
3. Open the PWA and authenticate.
4. Open browser devtools → Network tab (filter: `ask` or `ask-stream`). You'll inspect the JSON payload per step.

---

## 1. Verbatim path — SC-1 & SC-7

**Goal**: Single strong match → answer served verbatim in < 2 seconds, byte-identical to the stored `validated_answer`.

1. In the Manual Assistant screen, type the **exact** question text of your curated Q&A (e.g., "how to backup CADAS ATS"), send.
2. Observe the answer card.
3. In devtools, inspect the `event: metadata` payload (or the non-streaming JSON response).

**Expected**:

- ✅ Answer appears within ~2 seconds.
- ✅ Green "Verified Answer" badge shown at the top of the answer card.
- ✅ **No** "Synthesized from N verified sources" grey footer under the answer body.
- ✅ Response JSON contains:
  - `is_verified: true`
  - `verification_mode: "verbatim"`
  - `verified_source_count: 1`
  - `provider_used: "verbatim"`
  - `duration_seconds: 0.0`
  - `answer` byte-identical to the curated `validated_answer` (copy both to a diff tool to verify)
- ✅ `latency_breakdown.generator_ms: 0`

**Telemetry check** (Supabase SQL editor):

```sql
SELECT action, target_label, detail, created_at
FROM user_activity_log
WHERE action = 'verified_answer_served'
ORDER BY created_at DESC
LIMIT 1;
```

Expect one row with `detail` matching `mode=verbatim;top1=0.XXX;top2=0.000` (or `top2=` a real second score if more than one match was returned but one was clearly dominant).

---

## 2. Synthesis path — SC-2 & SC-3 (footer caption)

**Goal**: Multiple comparable matches → synthesis runs (today's behavior), footer caption appears.

1. Set up (if needed): add two more curated Q&A rows with different wordings but related answers so that retrieval returns three comparable matches for some query, e.g.:
   - "how do I schedule a recurring inspection"
   - "recurring inspection scheduling procedure"
   - "setting up a recurring maintenance task"
2. Ask a query that hits all three: "can I set up recurring inspections".
3. Observe the answer card and inspect the JSON.

**Expected**:

- ✅ Answer is LLM-paraphrased (compare to any single stored answer — should differ).
- ✅ Green "Verified Answer" badge shown.
- ✅ Grey footer caption reads **"Synthesized from N verified sources"** where N matches `verified_source_count` in the JSON.
- ✅ `verification_mode: "synthesized"`.
- ✅ `verified_source_count` equals the count of **distinct underlying answers** (if two of the three rows share the exact same `validated_answer` text — spec-068 variants — N is the deduped count, not 3).
- ✅ Response latency ~10–15s (today's baseline).

**Telemetry check**: one new row with `detail = mode=synthesized;top1=0.XXX;top2=0.XXX`.

---

## 3. Boundary cases — edge-case coverage

Skip if short on time; these confirm threshold behavior.

### 3a. Top-1 exactly at floor, single match

Craft a query that matches a curated Q&A with similarity ≈ 0.85 and only one returned match (or, more practically, ask a question whose top match is ~0.85 and top-2 is very far). Expect **verbatim**.

### 3b. Gap exactly 0.05

Hard to craft by accident — usually requires two curated rows with known similarity ratios. Acceptable to skip in manual QA; covered by the helper unit tests.

### 3c. Top-1 below 0.85

Ask a question that is somewhat related but clearly off. Similarity will land 0.75–0.84. Expect **synthesized** (not verbatim — floor not met).

### 3d. Top-1 strong but gap < 0.05 (e.g., 0.90 vs 0.87)

Ask a question matched by multiple near-identical curated answers. Expect **synthesized**, and `verified_source_count` reflects distinct-answer dedup.

### 3e. No verified match at all

Ask something totally unrelated to any curated Q&A. Expect: non-verified path (no green badge). Response has `is_verified: false`, `verification_mode` absent/null, `verified_source_count` absent/null. Footer caption not shown.

### 3f. Direct-lookup trivial input (spec 067)

Type "hi" or "thanks". Expect the pre-existing canned greeting — no call to the verified-Q&A retrieval at all, and `verified_answer_served` event **not** written. (This is orthogonal per spec.)

---

## 4. Feedback targeting — SC-4

**Goal**: Thumbs-up on a verbatim response increments the correct curated row.

1. From step 1's verbatim response, click thumbs-up.
2. In Supabase, query:

```sql
SELECT id, thumbs_up_count, thumbs_down_count
FROM validated_qa
WHERE id = '<validated_qa_id from response.verified_source.validated_qa_id>';
```

Expected: `thumbs_up_count` incremented by 1 on the correct row.

3. Repeat on a synthesized response (step 2). Confirm the same behavior — feedback targets `verified_source.validated_qa_id` (row `abc-123` in the example), not some other row.

---

## 5. Non-regression — SC-5

| Check | Expected |
|---|---|
| Run existing backend tests: `pytest backend/tests/` | All pre-existing tests pass. New `test_verbatim_helper.py` also passes. |
| Grep for schema migrations in `supabase/migrations/` dated today | None for this feature. |
| Grep for new FastAPI routes in `backend/routers/` | None — only `manuals.py` touched, and only the existing `result` dict is extended. |
| Frontend static analysis: `dart analyze` | Clean. |

---

## 6. Post-deploy tuning visibility — SC-6

One week after deploy:

```sql
SELECT
  regexp_replace(detail, 'mode=(\w+);.*', '\1') AS mode,
  COUNT(*) AS events,
  AVG((regexp_replace(detail, '.*top1=([\d.]+);.*', '\1'))::numeric) AS avg_top1,
  AVG((regexp_replace(detail, '.*top2=([\d.]+).*', '\1'))::numeric) AS avg_top2
FROM user_activity_log
WHERE action = 'verified_answer_served'
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY 1
ORDER BY events DESC;
```

**Expected**: two rows (verbatim / synthesized) with meaningful counts. From the distribution you can decide whether to tighten (`VERBATIM_MIN_SIMILARITY` up to 0.90) or loosen (down to 0.80) the floor without any code change — just tune the constant and redeploy.

---

## 7. Rollback plan

If a regression surfaces:

1. Revert the `083-verbatim-verified-answers` merge commit on `main`.
2. Redeploy frontend (`scripts/deploy_frontend.sh`) and restart backend (`sudo systemctl restart document_server.service`).
3. The `user_activity_log` rows written during the broken window remain in-place (harmless; purely additive).
4. No schema state to undo.

This rollback is zero-risk because the feature adds no database state.

---

## Done

If steps 1–4 pass, the feature meets SC-1 through SC-7. Step 6 becomes possible one week after ship.
