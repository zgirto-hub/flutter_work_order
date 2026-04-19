# Spec 089 — Generator Prompt Tuning (RAG Over-Refusal Fix)

## Status
`DRAFT — awaiting clarifications`

---

## 1. Problem Statement

RAG test suite (`backend/tests/test_rag_quality.py`, 87 questions) scores **37.9%** (33/87) despite retrieval working correctly.

Root cause confirmed by `rag_diagnostic_log` analysis on 87 test_suite entries (2026-04-26):

| Bucket | Count | % of refusals |
|---|---|---|
| `grounded_answer` | 29 | — |
| **`generator_refused_with_chunks`** | **50** | **86%** |
| `rerank_below_threshold` | 7 | 12% |
| `no_chunks_retrieved` | 1 | 2% |

Sampled top-score refusals showed chunks retrieved at rerank scores **0.73–0.82** (well above the 0.55 threshold), 5–10 candidates per question. The librarian pulls the right book, opens it to the right page, then says "I don't know."

**Secondary problems (out of scope here):**
- 7 questions: terse acronyms don't embed well → future spec **090** (query-time acronym expansion)
- 1 question: true corpus gap → future spec **091** (corpus + threshold tuning)
- 1 hallucination (AMHS router credentials): opposite symptom, same root cause — weak prompt discipline. In scope as a **must-refuse regression test**.

---

## 2. Goal

Rewrite the generator prompt so Gemma synthesizes answers from retrieved chunks instead of refusing, while preserving hallucination resistance.

### 2.1 Success criteria

| SC | Metric | Floor (merge-blocking) | Stretch |
|---|---|---|---|
| SC-001 | Cat 6 hallucination resistance | ≥ 8/9 | 9/9 |
| SC-002 | Overall score | ≥ 48/87 (55%) | ≥ 55/87 (63%) |
| SC-003 | Cat 1 Direct Retrieval | ≥ 7/10 | 9/10 |
| SC-004 | Cat 12 Paraphrased | ≥ 4/8 | 6/8 |
| SC-005 | Must-refuse regression (§6.3) | 0 violations | — |
| SC-006 | No new hallucinations | 0 new Cat 6 failures | — |

**Merge gate: all floors must be green simultaneously.** If any floor is red, iterate — do not ship.

---

## 3. Files to Change

**Primary:**
- `backend/services/manual_rag_service.py` — contains `DOCUMENT_QA_SYSTEM_PROMPT` (~line 292) and `VALIDATED_QA_SYSTEM_PROMPT` (~line 209)

**Possibly also:**
- `backend/services/ollama_generator.py` — if the grounded-answer prompt also lives here

### 3.1 Required first step (mandatory before editing)

Read both files. Grep for the refusal trigger string:
```
"This information is not in the available manuals"
```
**Every instance is in scope.** Quote the current prompt verbatim in the PR description so the diff is auditable.

---

## 4. Current Prompt Behaviour

When chunks are present but Gemma is uncertain, it emits the refusal string verbatim. The current prompt almost certainly contains language like *"Only answer if the information is explicitly stated in the context."* The word **explicitly** is the culprit — it forces literal matching and blocks synthesis from partial or paraphrased content.

Implementer: confirm this by quoting the actual prompt in the PR. If the real prompt differs materially, flag it for re-review before applying §5.

---

## 5. Required Changes

### 5.1 Replace the answer/refuse decision rule

**Remove** any instruction that says "only answer if explicitly stated" or "only if the answer is directly present."

**Insert** the following as the first numbered rule in `DOCUMENT_QA_SYSTEM_PROMPT`, before safety rules:

```
ANSWERING RULES
===============

ANSWER when:
- The retrieved chunks contain the procedure, values, commands, steps,
  or states the question asks for — even if phrased differently.
- The chunks give partial information: synthesize what IS there and
  note what is missing.
- Technical aliases are present: ATS = CADAS-ATS, pw = password,
  cmd = command, ack = acknowledge, hdd = hard disk, maint = maintenance,
  cfg = config, db = database, ip = IP address, sw = switch, rtr = router.
- The question uses informal technician shorthand (e.g. "aida slow, is
  the disk full?") but a chunk discusses the relevant system and
  metric — bridge the terminology gap.

REFUSE only when:
- The chunks are about a genuinely different system or topic unrelated
  to the question.
- The chunks contain zero procedural, factual, or diagnostic content
  that could address the question even partially.
- When refusing, output this exact string and nothing else:
  "This information is not in the available manuals."

NEVER INVENT:
- IP addresses, hostnames, credentials, or passwords not shown in a chunk.
- Linux commands not shown in a chunk.
- Version numbers, part numbers, or model numbers not shown in a chunk.
- Step sequences not shown in a chunk.
If a chunk mentions a topic but omits a specific value, say what the
chunk says and flag the gap verbatim:
"The manual references this but does not specify the value — consult
the system directly or the site password sheet."
```

### 5.2 Add few-shot examples (literal answer format)

Append immediately after the ANSWERING RULES block. Use actual-answer format, not meta-commentary:

```
EXAMPLES
========

Q: lost ats admin pw, how to reset
Chunks: [Section "CADAS-ATS Administrator Password Lost" — shows the
admin-console reset procedure with 4 steps.]
A: To reset a lost CADAS-ATS administrator password:
1. Open the admin console as a secondary admin or via recovery login.
2. Navigate to User Management → Administrators.
3. Select the locked admin account and click Reset Password.
4. Enter a new password meeting the complexity policy and save.
(Source: CADAS-ATS Administrator Guide, "Administrator Password Lost")

Q: aida disk full, how to free space
Chunks: [AIDA-NG maintenance section on /var partition with cleanup
steps: rotate logs, clear temp files, archive old reports.]
A: When AIDA-NG reports disk full (typically /var at high usage):
1. Rotate system logs via the maintenance utility.
2. Clear /var/tmp of files older than 7 days.
3. Archive reports older than the retention window to the backup volume.
(Source: AIDA-NG Maintenance Guide, "Disk Space Management")

Q: amhs router login credentials
Chunks: [Router management section with IP address 10.x.x.x and VNC
access method, but NO passwords listed.]
A: The AMHS router is reachable at the management IP documented in
Section X via VNC. The manual references this but does not specify
the password — consult the system directly or the site password sheet.
(Source: AMHS Router Management Guide)

Q: best practices for cloud database scaling
Chunks: [CADAS-ATS and AIDA-NG maintenance procedures — unrelated to
cloud databases.]
A: This information is not in the available manuals.
```

### 5.3 Preserve unchanged

Do **not** remove, weaken, or touch:
- Regulatory-ID preservation rules (ICAO, IATA codes)
- Arabic language pass-through rules
- Conflict-flagging rules
- `VALIDATED_QA_SYSTEM_PROMPT` — the verbatim/high-confidence path (spec 083) is working correctly

### 5.4 Atomic commit

All prompt changes land in **one commit**. Rollback = `git revert <sha>` with no partial-state risk.

---

## 6. Validation

### 6.1 Deploy before testing

```bash
git push
ssh zorin@zorin.taila92fe8.ts.net 'sudo systemctl restart document_server.service'
```
Wait ~10s for backend to come up. The test suite hits the live endpoint — testing against a stale prompt is worthless.

### 6.2 Run the suite

```bash
python backend/tests/test_rag_quality.py --base-url https://zorin.taila92fe8.ts.net
```
Save output to `backend/tests/results/089_<iteration_number>_post_prompt_tuning.json`.

### 6.3 Must-refuse regression set (SC-005)

These questions MUST remain `ungrounded` because the required data is NOT in the manuals. Any flip to `grounded` = regression, block merge.

| Question | Why must refuse |
|---|---|
| `amhs router login credentials` | Passwords not in manual |
| `ats vs ims admin, what's the difference` | Only refuse if both topics absent from chunks |
| Any question where chunks truly don't contain an answer | Prompt must preserve genuine refusal |

Script this as a post-run assertion — fail if any of these comes back with `grounded=True`.

### 6.4 Iteration protocol

After each iteration, compare to all 6 SCs:

- **All floors green** → merge.
- **Cat 6 < 8/9** → prompt too loose. Strengthen `NEVER INVENT` (add "re-read chunks before asserting a value"). Re-run. Do NOT weaken ANSWERING RULES.
- **Overall < 48/87** → prompt too tight. Soften the "partial information" clause with an additional few-shot. Re-run.
- **Must-refuse violation** → prompt too loose on credentials specifically. Add explicit "never synthesize credentials" to NEVER INVENT. Re-run.
- **≥ 3 iterations without reaching all floors** → stop, flag as needing a different approach (e.g., move to spec 090 acronym expansion first), do not ship.

---

## 7. Out of Scope for This Spec

| Item | Future spec |
|---|---|
| Acronym expansion at query time (rewrite prompt) | 090 |
| Corpus gap (missing CNMS / ATS KB manuals) | 091 |
| Cosine threshold tuning | 091 |
| Streaming latency fix (ask_stream buffering) | Separate spec |
| Reranker upgrade | Backlog |
| Extending the acronym list in §5.1 beyond the seed set | 090 |

---

## 8. Risk

**Low.** Prompt-only change. No migrations, no API changes, no Flutter changes. Rollback = `git revert` one commit.

Residual risks:
- Cat 6 drops below 8/9 — caught by gate, blocks merge.
- Must-refuse regressions (SC-005) — caught by scripted assertion.
- Prompt drift from optimization pressure across future specs — mitigated by keeping `VALIDATED_QA_SYSTEM_PROMPT` isolated.

---

## 9. Implementation Checklist (for coding agent)

- [ ] Read `manual_rag_service.py` and `ollama_generator.py`; quote current `DOCUMENT_QA_SYSTEM_PROMPT` verbatim in PR description
- [ ] Apply §5.1 ANSWERING RULES replacement
- [ ] Apply §5.2 four literal-format few-shot examples
- [ ] Confirm §5.3 (untouched sections) by diff review
- [ ] Single atomic commit per §5.4
- [ ] Push and restart backend per §6.1
- [ ] Run suite per §6.2, save JSON per §6.3
- [ ] Add must-refuse assertion script
- [ ] Iterate per §6.4 until all SC floors green (max 3 iterations)
- [ ] PR with: before/after prompt diff, results JSON, SC table filled in, iteration count

---

## 10. Definition of Done

- [ ] All 6 SC floors green on a single suite run
- [ ] PR description contains current-prompt quote + diff + results JSON + SC pass table
- [ ] Claude Code / CodeRabbit review passed
- [ ] No `AI_ASSISTANT_FEATURES.md` changes needed (prompt tuning is behavioral, not architectural)

---

## 11. Baseline Evidence

- Test run: 2026-04-26
- Results file: `backend/tests/rag_quality_results.json` (committed alongside this spec)
- Supabase `rag_diagnostic_log` state used: 87 test_suite-tagged entries from the 2026-04-26 run, per §1 table
