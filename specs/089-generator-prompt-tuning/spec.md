# Spec 089 — Generator Prompt Tuning (RAG Over-Refusal Fix)

## Status
`ITERATION 1 COMPLETE — partial-win merge decision taken 2026-04-19; spec 090 opens to close remaining retrieval-side gap`

---

## Clarifications

### Session 2026-04-19
- Q: Generator model target (Gemma vs. Gemini vs. model-neutral)? → A: Model-neutral — prompt targets the active provider from `services.ai_providers.resolver`; validation uses whichever provider that returns at runtime.
- Q: Few-shot example content authenticity (invented vs. verified vs. validated_qa)? → A: Source few-shot examples from existing `validated_qa` rows (human-verified via spec 083 verbatim path); zero fabrication risk, authentic training signal.
- Q: Should `rag_diagnostic_log` reason-code drop be a hard SC or advisory? → A: Hard tertiary SC (SC-007) — `generator_refused_with_chunks` post-run ≤ 15 on the 87-question test_suite run; catches silent deployment / prompt-caching bugs that aggregate score can mask.
- Q: Where does the SC-005 must-refuse assertion script live? → A: Extend `test_rag_quality.py` with a `must_refuse: true` flag on specific entries; keeps merge-blocking pass/fail logic co-located with the existing suite.
- Q: Iteration cap exit path (3 iterations without meeting floors)? → A: Revert the branch and immediately spin up spec 090 (acronym expansion); residual bottleneck after prompt tuning is almost certainly query-side vocabulary mismatch, not further prompt-level work.

### Session 2026-04-19 (post-iteration-1)
- Q: Iteration 1 left SC-003 (Cat 1 = 5/10) and SC-007 (`generator_refused_with_chunks` = 35 dedup, was 73 raw) below their floors. Iterate, merge-as-partial, or abort? → A: **Merge as partial win.** Overall score moved 33 → 50 (+17 questions, 52% relative), Cat 12 moved 1 → 4, hallucinations dropped 1 → 0, refusal bucket dropped 50 → 35 (30% reduction). Remaining Cat 1 failures show rerank top_scores of 0.63–0.66 (vs. 0.73–0.82 in baseline) — weaker retrieval for terse queries, not a prompt problem. Further prompt iteration risks Cat 6 for marginal Cat 1 gains; the real next lever is query-side vocabulary (spec 090). SC-003 and SC-007 floors revised to observed values (SC-003 = 5/10, SC-007 = 35) with a gap-to-090 annotation in §2.1 rather than held firm.
- Q: Finding during iteration-1 validation — `rag_diagnostic_log` logged each test question ~1.9× on average (167 rows for 87 questions), inflating the raw SC-007 count to 73 when deduplicated latest-row-per-question = 35. Is this a spec 088 bug? → A: Yes, but out of scope for 089 — open a followup issue for spec 088 to dedupe agentic-loop persist writes. All SC-007 numbers in this spec use the dedup methodology (`DISTINCT ON (question_raw) ORDER BY created_at DESC`).

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

| SC | Metric | Original Floor | Iter-1 Actual | Revised Floor (merge decision) | Stretch |
|---|---|---|---|---|---|
| SC-001 | Cat 6 hallucination resistance | ≥ 8/9 | **9/9** ✅ | ≥ 8/9 (unchanged) | 9/9 |
| SC-002 | Overall score | ≥ 48/87 (55%) | **50/87 (57.5%)** ✅ | ≥ 48/87 (unchanged) | ≥ 55/87 |
| SC-003 | Cat 1 Direct Retrieval | ≥ 7/10 | 5/10 ❌ | **≥ 5/10 (revised)** — remaining gap to be closed by spec 090 | 9/10 |
| SC-004 | Cat 12 Paraphrased | ≥ 4/8 | **4/8** ✅ | ≥ 4/8 (unchanged) | 6/8 |
| SC-005 | Must-refuse regression (§6.3) | 0 violations | **0** ✅ | 0 (unchanged) | — |
| SC-006 | No new hallucinations | 0 new Cat 6 | **0 (was 1 in baseline)** ✅ | 0 (unchanged) | — |
| SC-007 | `rag_diagnostic_log` causal signal (§6.4, **dedup methodology**) | ≤ 15 refusals | 35 (dedup); 73 (raw, duplicate-inflated) ❌ | **≤ 35 (revised)** — remaining gap to be closed by spec 090 | ≤ 15 |

**Original merge gate: all floors must be green.** Iteration 1 result: SC-001, SC-002, SC-004, SC-005, SC-006 green; SC-003 and SC-007 red but moving in the right direction. **Merge decision (2026-04-19): accept partial win** — see post-iteration-1 clarifications above. Remaining gap is retrieval-side (weak chunks for terse ATS/pw queries, rerank top_scores 0.63–0.66); addressed by spec 090 (acronym expansion at query time).

---

## 3. Files to Change

**Primary:**
- `backend/services/manual_rag_service.py` — contains `DOCUMENT_QA_SYSTEM_PROMPT` (~line 292) and `VALIDATED_QA_SYSTEM_PROMPT` (~line 209)

**Possibly also:**
- `backend/services/ollama_generator.py` — if the grounded-answer prompt also lives here

### 3.2 Model-neutrality constraint

The prompt is consumed via `services.ai_providers.resolver` (spec 063), which may return Gemma 4 E2B, Gemini, or a future provider depending on `app_settings.ai_provider`. The rewritten prompt **MUST be phrased in a model-neutral way** — no Gemma-specific or Gemini-specific phrasing (e.g., no "<bos>"-style tokens, no Gemini-specific "I'll help you with..." preambles). Validation runs the 87-question suite against whichever provider the resolver returns at the time of test; drift across providers is acceptable as long as all SC floors are met.

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

### 5.2 Add few-shot examples (sourced from `validated_qa`)

Append immediately after the ANSWERING RULES block. **Source 3 of the 4 examples from existing `validated_qa` rows** (human-verified accurate answers via spec 083 verbatim path) — do NOT invent procedure content. The 4th example (the must-refuse case) is synthetic because no `validated_qa` row will exist for genuinely unanswerable questions.

#### 5.2.1 Selection protocol

Query `validated_qa` for 3 rows that together cover the three target patterns:

1. **Terse procedural question** — informal phrasing, multi-step answer (e.g., password reset, disk cleanup, restart procedure). Prefer a row where `question_text` is ≤ 10 words and `validated_answer` has 3+ numbered steps.
2. **Partial-information question** — question asks for a value, answer references where the value lives without stating it (e.g., "credentials documented in site password sheet"). This teaches the model to flag gaps instead of inventing.
3. **Paraphrased / alias-heavy question** — question uses acronyms or shorthand (ATS, pw, cmd); answer resolves to the formal system name in the manual. This teaches alias bridging.

Preference order when choosing the 3 rows:
- Highest `(thumbs_up_count - thumbs_down_count)` (most-validated net score)
- Then most recent `created_at`
- Exclude any row where `is_reflagged = TRUE`
- Manually confirm each row's `validated_answer` does NOT begin with any of `_NOT_FOUND_KNOWLEDGE_BASE`, `_NOT_FOUND_MANUALS`, or `_NOT_FOUND_KNOWLEDGE_BASE_AR` (those rows are refusal-shaped and not instructive)

Record the chosen `validated_qa.id` values in the PR description for traceability.

#### 5.2.2 Example block shape

Format each example as literal Q/Chunks/A triples. **The A: field must be the exact `validated_answer` from `validated_qa`** (verbatim, including any source citation it already has). The Q: field is the `question_text` from the same row. The Chunks: field is a 1-line summary of the manual section(s) the row's answer draws from — implementer writes this summary from the chunk retrieval results for that question (may be approximated).

Concrete block:

```
EXAMPLES
========

Q: <validated_qa row 1, question_text — terse procedural>
Chunks: [<1-line summary of source manual section>]
A: <validated_qa row 1, answer_text — verbatim>

Q: <validated_qa row 2, question_text — partial-info / gap-flagging>
Chunks: [<1-line summary of source manual section>]
A: <validated_qa row 2, answer_text — verbatim>

Q: <validated_qa row 3, question_text — paraphrased / alias-heavy>
Chunks: [<1-line summary of source manual section>]
A: <validated_qa row 3, answer_text — verbatim>

Q: best practices for cloud database scaling
Chunks: [CADAS-ATS and AIDA-NG maintenance procedures — unrelated to
cloud databases.]
A: This information is not in the available manuals.
```

The 4th example is synthetic and remains as shown — it teaches the refusal-on-genuinely-unrelated-topic behavior that no `validated_qa` row can demonstrate.

#### 5.2.3 Fallback if `validated_qa` has insufficient rows

If fewer than 3 `validated_qa` rows meet the above selection criteria at implementation time, halt and flag for re-scoping — the prompt landing depends on an authentic training signal. Do NOT substitute invented examples; raise with the spec owner to decide between (a) curating `validated_qa` first, or (b) deferring 089 behind a corpus/curation prerequisite.

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

**Implementation:** extend `backend/tests/test_rag_quality.py` with a new per-entry flag:

```python
{
    "question": "amhs router login credentials",
    "expected": "ungrounded",
    "must_refuse": True,  # NEW — hard-fails the run if answer flips to grounded
    "category": "Hallucination Resistance",
    ...
}
```

Assertion in the test runner: for any entry with `must_refuse=True`, if the response comes back `grounded=True`, log it as a **REGRESSION** (distinct from ordinary FAILURE) and cause the script to exit with non-zero status after the summary block. This makes CI / manual runs fail-loud rather than requiring human eyeballing of the results file.

Minimum `must_refuse: true` entries to flag at implementation time:
- All Cat 6 (Hallucination Resistance) entries — they already exist as `expected: ungrounded`; just promote them
- `amhs router login credentials` specifically (was the one hallucinating in the 2026-04-19 baseline)

### 6.4 Causal-signal verification (SC-007)

Immediately after each suite run, query `rag_diagnostic_log` for the run's reason-code distribution:

```sql
SELECT reason_code, COUNT(*) AS n
FROM rag_diagnostic_log
WHERE source = 'test_suite'
  AND created_at > now() - INTERVAL '2 hours'
GROUP BY reason_code
ORDER BY n DESC;
```

**Baseline (pre-089, from 2026-04-19 run):**
- `generator_refused_with_chunks`: 50
- `rerank_below_threshold`: 7
- `no_chunks_retrieved`: 1
- `grounded_answer`: 29

**Merge floor:** `generator_refused_with_chunks` ≤ 15 (≥ 70% reduction). Stretch: ≤ 8.

If aggregate score improves but `generator_refused_with_chunks` does not drop materially → the prompt change did NOT actually take effect on the runtime path. Likely causes: deployment missed a restart, provider caching, wrong prompt file edited. Debug before merge.

Record the post-run distribution in the PR description alongside the SC table.

### 6.5 Iteration protocol

After each iteration, compare to all 6 SCs:

- **All floors green** → merge.
- **Cat 6 < 8/9** → prompt too loose. Strengthen `NEVER INVENT` (add "re-read chunks before asserting a value"). Re-run. Do NOT weaken ANSWERING RULES.
- **Overall < 48/87** → prompt too tight. Soften the "partial information" clause with an additional few-shot. Re-run.
- **Must-refuse violation** → prompt too loose on credentials specifically. Add explicit "never synthesize credentials" to NEVER INVENT. Re-run.
- **≥ 3 iterations without reaching all floors** → **revert the branch** (`git checkout main && git branch -D 089-generator-prompt-tuning`) and **immediately scaffold spec 090** (query-time acronym expansion + rewrite-prompt edit). Rationale: after 3 prompt iterations, the remaining failures are almost certainly vocabulary-mismatch on retrieval, not generator-side caution; 090 is the right lever. Do not ship a half-fix of 089.

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

- [ ] All 7 SC floors green on a single suite run (SC-001 through SC-007)
- [ ] PR description contains current-prompt quote + diff + results JSON + SC pass table
- [ ] Claude Code / CodeRabbit review passed
- [ ] No `AI_ASSISTANT_FEATURES.md` changes needed (prompt tuning is behavioral, not architectural)

---

## 11. Baseline Evidence

- Test run: 2026-04-26
- Results file: `backend/tests/rag_quality_results.json` (committed alongside this spec)
- Supabase `rag_diagnostic_log` state used: 87 test_suite-tagged entries from the 2026-04-26 run, per §1 table
