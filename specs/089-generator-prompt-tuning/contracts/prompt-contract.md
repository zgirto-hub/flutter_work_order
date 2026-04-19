# Prompt Contract: Spec 089 — Generator Prompt Tuning

**Spec**: [../spec.md](../spec.md) | **Target symbol**: `backend/services/manual_rag_service.py :: DOCUMENT_QA_SYSTEM_PROMPT` (line 229)
**Date**: 2026-04-19

This is the *contract* the rewritten prompt must satisfy. It is NOT the final string literal (the few-shot examples must be hand-filled from `validated_qa` per spec §5.2.1 — there's no way to pre-commit those values until the implementer runs the selection query).

The contract specifies:
1. Structural sections the prompt MUST contain
2. Structural sections the prompt MUST preserve unchanged
3. Invariants the prompt MUST maintain

---

## 1. Required sections (in order, added / replaced by spec 089)

### 1.1 ANSWERING RULES (new — replaces "Only answer if explicitly stated" language)

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
  "{_NOT_FOUND_KNOWLEDGE_BASE}"

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

**Placement in file**: Inserted as the first numbered rule block in `DOCUMENT_QA_SYSTEM_PROMPT`, immediately after the opening system description (the existing opening 5 lines about "technical assistant for civil aviation maintenance... CADAS-ATS, CADAS-IMS, AIDA-NG, IRTOS..."). Replaces any existing `INSUFFICIENT CONTEXT` block using "only if explicitly stated" language.

**Python string form**: The prompt is an f-string-concatenated tuple; the `{_NOT_FOUND_KNOWLEDGE_BASE}` above is a placeholder — in the actual Python source, use `f'respond with exactly: "{_NOT_FOUND_KNOWLEDGE_BASE}"'` to preserve the constant substitution (see existing line 294).

### 1.2 EXAMPLES (new — few-shot block)

```
EXAMPLES
========

Q: <row-1.question_text>
Chunks: [<1-line summary of source section>]
A: <row-1.validated_answer verbatim>

Q: <row-2.question_text>
Chunks: [<1-line summary of source section>]
A: <row-2.validated_answer verbatim>

Q: <row-3.question_text>
Chunks: [<1-line summary of source section>]
A: <row-3.validated_answer verbatim>

Q: best practices for cloud database scaling
Chunks: [CADAS-ATS and AIDA-NG maintenance procedures — unrelated to
cloud databases.]
A: {_NOT_FOUND_KNOWLEDGE_BASE}
```

**Pattern requirements for row selection**:
- Row 1: terse procedural (question ≤ 10 words, answer has 3+ numbered steps)
- Row 2: partial-information (answer references gap without inventing value)
- Row 3: paraphrased / alias-heavy (question uses ATS/pw/cmd, answer resolves to formal name)

**Placement**: Immediately after the ANSWERING RULES block.

---

## 2. Required sections (preserved unchanged)

The rewritten prompt MUST retain the following sections byte-for-byte from the existing `DOCUMENT_QA_SYSTEM_PROMPT` (lines 229–297):

1. **Opening system description** — "You are a technical assistant for a civil aviation maintenance department operating under DGCA regulations. The department uses these systems: CADAS-ATS, CADAS-IMS, AIDA-NG, IRTOS, and others. Your job is to answer maintenance and operations questions using ONLY the context provided below. The context comes from uploaded technical manuals."
2. **ANSWER FORMAT** block — lead with direct answer, numbered steps only when manual is stepped, bullets for lists, etc.
3. **SAFETY RULES — CRITICAL** block — preserve safety warnings verbatim, hazmat precautions, never substitute parts/tools, never extrapolate across systems.
4. **REGULATORY REFERENCES** block — preserve AD/SB/AMM/DGCA identifiers verbatim.
5. **CONFLICT HANDLING** block — flag conflicts with the ⚠️ marker; never silently pick.
6. **LANGUAGE** block — reply in the same language as the question; Arabic RTL.
7. **SYSTEM AMBIGUITY** block — ask user to specify system only if history doesn't resolve.

---

## 3. Invariants

| # | Invariant | Verification |
|---|---|---|
| I-01 | `VALIDATED_QA_SYSTEM_PROMPT` (line 215) is NOT modified | `git diff` shows zero changes on lines 215–226 |
| I-02 | `_NOT_FOUND_*` constants (lines 210–212) are NOT modified | `git diff` shows zero changes on lines 210–212 |
| I-03 | `_SENTINEL_PHRASES` list (line ~300) is NOT modified | `git diff` shows zero changes on the sentinel list |
| I-04 | `DOCUMENT_QA_SYSTEM_PROMPT` remains a single Python string expression (no split into multiple module-level variables) | `grep -c "DOCUMENT_QA_SYSTEM_PROMPT ="` returns `1` |
| I-05 | The refusal trigger string inside DOCUMENT_QA_SYSTEM_PROMPT remains `f'"{_NOT_FOUND_KNOWLEDGE_BASE}"'` — do not hardcode the literal sentence | `grep "_NOT_FOUND_KNOWLEDGE_BASE" manual_rag_service.py` returns ≥ 1 match inside the prompt body |
| I-06 | Prompt is model-neutral: no Gemma-specific tokens (`<bos>`, `<end_of_turn>`), no Gemini-specific preambles (`I'll help you with...`) | `grep -Ei "bos>|end_of_turn|i'll help you"` on the prompt body returns zero matches |
| I-07 | Prompt length ≤ 4096 tokens (approximate — keep under 16 KB raw bytes) | `wc -c` on the prompt body is under 16384 |

---

## 4. Sample final-state prompt header (illustrative, pre-few-shot)

Implementers MAY use this as a template; column widths and exact whitespace are not load-bearing, but section ordering IS.

```python
DOCUMENT_QA_SYSTEM_PROMPT = (
    # Opening (UNCHANGED)
    "You are a technical assistant for a civil aviation maintenance "
    "department operating under DGCA regulations.\n"
    "The department uses these systems: CADAS-ATS, CADAS-IMS, "
    "AIDA-NG, IRTOS, and others.\n"
    "Your job is to answer maintenance and operations questions "
    "using ONLY the context provided below.\n"
    "The context comes from uploaded technical manuals.\n\n"

    # ANSWERING RULES (NEW — spec 089)
    "ANSWERING RULES\n"
    "===============\n\n"
    "ANSWER when:\n"
    "- The retrieved chunks contain the procedure, values, ...\n"
    # ... (see §1.1 above for the full block)

    # EXAMPLES (NEW — spec 089)
    "EXAMPLES\n"
    "========\n\n"
    # ... three validated_qa-sourced Q/Chunks/A triples + the synthetic refuse example

    # ANSWER FORMAT (UNCHANGED)
    "ANSWER FORMAT:\n"
    # ...

    # SAFETY RULES (UNCHANGED)
    # REGULATORY REFERENCES (UNCHANGED)
    # CONFLICT HANDLING (UNCHANGED)
    # LANGUAGE (UNCHANGED)
    # SYSTEM AMBIGUITY (UNCHANGED)

    # INSUFFICIENT CONTEXT block is REPLACED by the ANSWERING RULES "REFUSE only when" clause.
    # Do NOT retain both — they contradict each other.
)
```

---

## 5. Test contract changes (`backend/tests/test_rag_quality.py`)

Spec 089 also modifies the test suite. The contract for those changes:

### 5.1 Dataclass change

```python
@dataclass
class TestQuestion:
    question: str
    expect: str
    keywords: list[str]
    category: int
    category_name: str
    must_refuse: bool = False   # NEW — spec 089 merge-blocking flag
```

Default `False` to preserve existing behavior for all 87 current entries (they do not fail CI unless the flag is explicitly opted in).

### 5.2 Flag application

Entries with `must_refuse: True` at minimum:
- All existing Cat 6 (Hallucination Resistance) entries — promote from `expect="ungrounded"` to `must_refuse=True`.
- The single 2026-04-19 hallucination: `question="amhs router login credentials"`.

### 5.3 Runner contract

- For any entry with `must_refuse=True`:
  - If response returns `grounded=True`, print `REGRESSION:` prefix to the entry's failure line (distinct from `FAIL:`).
  - Accumulate a `regression_count` separately from `fail_count`.
  - At end of run, if `regression_count > 0`, exit with non-zero status code (suggest `2`), regardless of aggregate score.

### 5.4 Existing runner behavior

All other existing scoring logic (pass/fail tallies, per-category summary, RESULTS SUMMARY block) is preserved unchanged.

---

## 6. Non-contracts

The following are explicitly NOT part of this contract and must NOT be changed:

- FastAPI routes (`/api/manuals/ask`, `/api/manuals/ask/stream`, `/api/admin/rag-diagnostics/*`)
- Provider resolver logic (`services.ai_providers.resolver`)
- Embedder (`services.ollama_embedder`)
- Reranker thresholds (`MAX_CHUNK_DISTANCE`, 0.55)
- Verbatim short-circuit (spec 083 — `VALIDATED_QA_SYSTEM_PROMPT` + 0.85 similarity gate)
- Agentic loop (`services.agentic_tools`)
- Any Flutter / Dart code
- Any Supabase schema or RLS policy
