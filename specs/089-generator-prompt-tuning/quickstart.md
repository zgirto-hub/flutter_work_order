# Quickstart: Spec 089 — Generator Prompt Tuning

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Prompt contract**: [contracts/prompt-contract.md](./contracts/prompt-contract.md)
**Intended audience**: Implementation agent (opencode) + reviewer (Claude Code superpowers:code-reviewer)
**Date**: 2026-04-19

---

## 0. Prerequisites

- On branch `089-generator-prompt-tuning` (already created; `git status` should show clean tree on this branch).
- Backend deploys via `ssh zorin@zorin.taila92fe8.ts.net 'sudo systemctl restart document_server.service'`.
- Access to Supabase (via MCP, CLI, or dashboard) to query `validated_qa` and `rag_diagnostic_log`.
- Baseline reference: [backend/tests/rag_quality_results.json](../../backend/tests/rag_quality_results.json) committed in `c1997b9` — 33/87, 1 hallucination.

---

## 1. Read the current prompt

```bash
grep -n "DOCUMENT_QA_SYSTEM_PROMPT" backend/services/manual_rag_service.py
grep -n "_NOT_FOUND_" backend/services/manual_rag_service.py
```

Quote the full existing `DOCUMENT_QA_SYSTEM_PROMPT` block (lines 229–297) in the PR description under a "**Before:**" heading. This makes the diff auditable.

Also confirm:
- `ollama_generator.py` does NOT redefine `DOCUMENT_QA_SYSTEM_PROMPT` (`grep -c "DOCUMENT_QA_SYSTEM_PROMPT" backend/services/ollama_generator.py` returns `0`)
- `VALIDATED_QA_SYSTEM_PROMPT` (line 215) and the `_NOT_FOUND_*` constants (lines 210–212) will be preserved

---

## 2. Source three few-shot examples from `validated_qa`

Run this selection query:

```sql
SELECT id, question_text, validated_answer,
       (thumbs_up_count - thumbs_down_count) AS net_score,
       created_at
FROM validated_qa
WHERE is_reflagged = FALSE
  AND validated_answer NOT ILIKE 'I don''t have that information%'
  AND validated_answer NOT ILIKE 'This information is not in%'
  AND validated_answer NOT ILIKE 'المعلومات المطلوبة غير موجودة%'
ORDER BY net_score DESC, created_at DESC
LIMIT 20;
```

From the 20 returned rows, hand-pick 3 that together cover:

| Pattern | Selection hint |
|---|---|
| Terse procedural | `question_text` ≤ 10 words, `validated_answer` has 3+ numbered steps |
| Partial-information / gap-flagging | Answer references where a value lives without stating it (e.g., "consult the site password sheet") |
| Paraphrased / alias-heavy | Question uses abbreviations (ATS, pw, cmd, ack); answer resolves to formal names |

Record the 3 chosen `id` values in the PR description.

**Fallback**: If fewer than 3 rows fit after examining the top 20, widen the query to `LIMIT 50`. If still insufficient, halt and flag for re-scoping per spec §5.2.3 (do NOT substitute invented examples).

For each chosen row, also write a 1-line `Chunks:` summary — approximated from the manual section your validated_qa row's `source_chunks` references.

---

## 3. Apply the prompt edits

Edit [backend/services/manual_rag_service.py](../../backend/services/manual_rag_service.py). Per the [prompt contract](./contracts/prompt-contract.md):

1. Insert the **ANSWERING RULES** block (§1.1 of the contract) as the first numbered rule after the opening system description.
2. Insert the **EXAMPLES** block (§1.2) immediately after ANSWERING RULES — fill the 3 validated_qa rows verbatim, plus the synthetic "cloud database scaling" refusal example.
3. **Delete** the existing `INSUFFICIENT CONTEXT:` block (it contradicts the new REFUSE clause).
4. **Preserve byte-for-byte**: opening description, ANSWER FORMAT, SAFETY RULES, REGULATORY REFERENCES, CONFLICT HANDLING, LANGUAGE, SYSTEM AMBIGUITY blocks.

Verify invariants:

```bash
grep -c "^DOCUMENT_QA_SYSTEM_PROMPT = " backend/services/manual_rag_service.py  # must return 1
grep -c "^VALIDATED_QA_SYSTEM_PROMPT = " backend/services/manual_rag_service.py  # must return 1
grep -n "_NOT_FOUND_" backend/services/manual_rag_service.py  # must show 3 constants at 210-212, unchanged
```

---

## 4. Apply the test-suite edits

Edit [backend/tests/test_rag_quality.py](../../backend/tests/test_rag_quality.py):

1. Add `must_refuse: bool = False` to the `TestQuestion` dataclass.
2. Set `must_refuse=True` on:
   - All Cat 6 (Hallucination Resistance) entries currently marked `expect="ungrounded"`.
   - Specifically: the entry with `question="amhs router login credentials"`.
3. In the runner loop:
   - On each response, after the existing pass/fail check, if the test's `must_refuse=True` and the response `grounded=True`, increment `regression_count` and print `REGRESSION: <question>` (not `FAIL:`).
   - After the RESULTS SUMMARY block, if `regression_count > 0`, print `SC-005 REGRESSION DETECTED — MERGE BLOCKED` and call `sys.exit(2)`.

---

## 5. Commit atomically

Single commit per spec §5.4:

```bash
git add backend/services/manual_rag_service.py backend/tests/test_rag_quality.py
git diff --cached  # final visual check
git commit -m "$(cat <<'EOF'
spec 089: rewrite DOCUMENT_QA_SYSTEM_PROMPT to reduce over-refusal

- Insert ANSWERING RULES + EXAMPLES blocks (few-shot sourced from
  validated_qa IDs <id1>, <id2>, <id3>).
- Delete contradictory INSUFFICIENT CONTEXT block (replaced by REFUSE
  clause in ANSWERING RULES).
- Preserve SAFETY RULES, REGULATORY REFERENCES, CONFLICT HANDLING,
  LANGUAGE, SYSTEM AMBIGUITY byte-for-byte.
- VALIDATED_QA_SYSTEM_PROMPT untouched (spec 083 verbatim path).
- Test suite: add must_refuse flag + sys.exit(2) on flipped Cat 6 entries.

Baseline: 33/87, 50/58 refusals = generator_refused_with_chunks.
Target: >=48/87 aggregate, Cat 6 >=8/9, generator_refused_with_chunks <=15.
EOF
)"
```

---

## 6. Deploy

```bash
git push -u origin 089-generator-prompt-tuning
ssh zorin@zorin.taila92fe8.ts.net 'cd ~/flutter_work_order && git fetch && git checkout 089-generator-prompt-tuning && git pull && sudo systemctl restart document_server.service'
sleep 10
curl -s https://zorin.taila92fe8.ts.net/api/health | jq .  # confirm backend up
```

---

## 7. Validate — iteration N (N ∈ {1, 2, 3})

### 7.1 Run the full suite

```bash
python backend/tests/test_rag_quality.py --base-url https://zorin.taila92fe8.ts.net \
  > backend/tests/results/089_iter_${N}_results.log 2>&1
echo "Exit code: $?"
```

**Expected exit codes**:
- `0` — all entries passed and no must-refuse regression → proceed to SC checks
- `2` — must-refuse regression (SC-005 failed) → iterate per §7.4
- Other non-zero — infrastructure error, investigate before counting this as an iteration

### 7.2 Capture the JSON

The suite writes `backend/tests/rag_quality_results.json`. Copy to `backend/tests/results/089_iter_${N}.json` for audit.

### 7.3 Run the SC-007 query

Via Supabase MCP or dashboard:

```sql
SELECT reason_code, COUNT(*) AS n
FROM rag_diagnostic_log
WHERE source = 'test_suite'
  AND created_at > now() - INTERVAL '2 hours'
GROUP BY reason_code
ORDER BY n DESC;
```

Record the `generator_refused_with_chunks` count.

### 7.4 Check gates

| SC | Metric | Floor | Source |
|---|---|---|---|
| SC-001 | Cat 6 hallucination resistance | ≥ 8/9 | `089_iter_${N}.json` per-category |
| SC-002 | Overall score | ≥ 48/87 (55%) | `089_iter_${N}.json` total |
| SC-003 | Cat 1 Direct Retrieval | ≥ 7/10 | `089_iter_${N}.json` per-category |
| SC-004 | Cat 12 Paraphrased | ≥ 4/8 | `089_iter_${N}.json` per-category |
| SC-005 | Must-refuse regression | exit code != 2 | runner stdout |
| SC-006 | No new Cat 6 hallucinations | 0 new vs baseline | diff against baseline JSON |
| SC-007 | `generator_refused_with_chunks` | ≤ 15 | SC-007 SQL query |

### 7.5 Decision branch

- **All 7 floors green** → skip to §8 (merge).
- **SC-001 < 8/9** → prompt too loose. Strengthen `NEVER INVENT`:
  - Add: "Before emitting a value, re-read the chunks. If you cannot locate it, flag it as missing."
  - Re-run from §5.
- **SC-002 < 48/87** → prompt too tight. Add a 5th few-shot example (another `validated_qa` row, partial-info style). Re-run.
- **SC-005 failed** → specific credential leak. Add to `NEVER INVENT`: "Never output a password, passphrase, or PIN — always say 'consult the site password sheet'." Re-run.
- **SC-007 > 15 but aggregate up** → prompt may not have deployed (caching). Re-deploy, verify live endpoint serves new prompt via `/api/manuals/ask` with a test question; re-run.
- **N == 3 and any floor still red** → abort:
  - `git checkout main`
  - `git branch -D 089-generator-prompt-tuning` (after confirming no useful sub-changes worth harvesting)
  - Scaffold spec 090: `git checkout main && git pull && /speckit.specify 090-acronym-query-expansion`
  - Stop. Do not ship 089.

---

## 8. Merge (once all floors green)

PR body template:

```markdown
## Summary
Spec 089: rewrite DOCUMENT_QA_SYSTEM_PROMPT to reduce generator over-refusal.

## Evidence
- Before: 33/87 (37.9%), 1 hallucination, 50/58 refusals = generator_refused_with_chunks
- After (iter N=?): X/87 (Y%), Z hallucinations, W/refusals = generator_refused_with_chunks

## SC Pass Table
| SC | Floor | Actual | Status |
| SC-001 | ≥ 8/9 | 9/9 | ✅ |
| ... (fill all 7) |

## Iteration count: N

## Changes
- `backend/services/manual_rag_service.py` — DOCUMENT_QA_SYSTEM_PROMPT rewritten
- `backend/tests/test_rag_quality.py` — must_refuse flag + regression exit code
- validated_qa rows used: `<id1>`, `<id2>`, `<id3>`

## Before prompt
<paste current prompt verbatim>

## After prompt
<paste new prompt verbatim>

## Results JSON
<link to 089_iter_N.json>
```

Then: `/pr review`, Claude Code superpowers:code-reviewer pass, merge to main.

---

## 9. Post-merge

- Delete local feature branch: `git checkout main && git pull && git branch -d 089-generator-prompt-tuning`.
- Update `MEMORY.md` entry `project_spec088_weekly_analysis.md` if the weekly review playbook's baseline (38/87) needs refreshing to the new post-089 number.
- Confirm no Flutter or docs changes needed (Constitution Check in plan.md covers this).

---

## 10. Rollback

Single-commit rollback:

```bash
git checkout main
git log --oneline --all | grep "spec 089:"  # find the commit SHA
git revert <sha>
git push
ssh zorin@zorin.taila92fe8.ts.net 'cd ~/flutter_work_order && git pull && sudo systemctl restart document_server.service'
```

No migrations to reverse, no data to clean up. Spec 088's `rag_diagnostic_log` continues to operate unchanged.
