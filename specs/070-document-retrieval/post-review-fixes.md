# Post-Review Fixes for Spec 070

**Branch**: `070-document-retrieval`
**Commit after all 4 fixes with message**: `fix(spec-070): post-review — indexed_at timestamp, remove off-topic gate, section index lookup, pdfplumber context manager`

Read each fix completely before making changes. All 4 are in `backend/services/`.

---

## Fix 1: `indexed_at` uses string `"now()"` instead of real timestamp

**File**: `backend/services/document_service.py`, line 101

**Problem**: `"indexed_at": "now()"` sends the literal string `"now()"` to Supabase PostgREST. This is NOT interpreted as a SQL function — it either fails or stores garbage in a `timestamptz` column.

**Fix**:

1. Add import at top of file (after `import os` on line 2):
   ```python
   from datetime import datetime, timezone
   ```

2. Replace line 101:
   ```python
   # BEFORE (broken):
   "indexed_at": "now()",

   # AFTER (correct):
   "indexed_at": datetime.now(timezone.utc).isoformat(),
   ```

---

## Fix 2: Remove unplanned off-topic threshold gate

**File**: `backend/services/manual_rag_service.py`

**Problem**: Lines 86, 831-834, 850, 981, and 1212-1232 add a `RAG_OFFTOPIC_THRESHOLD = 0.40` + `_best_vqa_score` tracking that was NOT in the plan. Critical bug: when `validated_qa` table is empty, `_best_vqa_score` stays 0.0, which is < 0.40, so ALL queries short-circuit and never reach the manual-chunks pipeline — breaking the entire existing RAG.

**Fix** — remove all 6 locations:

1. **Delete line 86** (the constant):
   ```python
   # DELETE this line:
   RAG_OFFTOPIC_THRESHOLD = 0.40  # Score below this → skip manual-chunks pipeline entirely
   ```

2. **Delete lines 831-834** (the variable init + comments):
   ```python
   # DELETE these lines:
       # Track best VQA similarity across both pre- and post-rewrite checks.
       # If the best score stays below RAG_OFFTOPIC_THRESHOLD, the question is
       # clearly off-topic and we skip the expensive manual-chunks pipeline entirely.
       _best_vqa_score = 0.0
   ```

3. **Delete line 850** (tracking in pre-rewrite block):
   ```python
   # DELETE this line:
               _best_vqa_score = max(_best_vqa_score, max_score)
   ```
   This line is inside the pre-rewrite `if vqa_matches:` block, right after the `logger.info("[validated-qa] pre-rewrite check: ...")` call.

4. **Delete line 981** (tracking in post-rewrite block):
   ```python
   # DELETE this line:
               _best_vqa_score = max(_best_vqa_score, max_score)
   ```
   This line is inside the post-rewrite `if vqa_matches:` block, right after the `logger.info("[validated-qa] post-rewrite check: ...")` call.

5. **Delete lines 1212-1232** (the entire early-exit block between `# --- End Layer 2 ---` and `# HyDE:`):
   ```python
   # DELETE this entire block:
       # Early exit: if the best VQA score across both checks is below the
       # off-topic threshold, the question is clearly unrelated to the knowledge
       # base. Skip the entire manual-chunks pipeline (HyDE + embed + retrieval)
       # to save ~15-20s of wasted compute.
       if _best_vqa_score < RAG_OFFTOPIC_THRESHOLD:
           logger.info(
               "[off-topic] best VQA score %.2f < %.2f — skipping manual-chunks pipeline",
               _best_vqa_score,
               RAG_OFFTOPIC_THRESHOLD,
           )
           breakdown["total_ms"] = round((time.perf_counter() - _total_start) * 1000)
           return {
               "answer": "This information is not in the available manuals.",
               "grounded": False,
               "sources": [],
               "confidence": "low",
               "score": round(_best_vqa_score, 2),
               "session_summary": None,
               "retrieval_info": retrieval_info,
               "latency_breakdown": breakdown,
           }
   ```

After deletion, `# --- End Layer 2 ---` should be followed directly by a blank line and then `# HyDE: generate hypothetical answer for better embedding`.

---

## Fix 3: Section content lookup by title — use index instead

**File**: `backend/services/document_service.py`, lines 47-64

**Problem**: `next(s["content"] for s in sections if s["title"] == parent["title"])` matches by title string. If two sections share the same title (e.g., "Introduction"), it silently returns the wrong content.

**Fix**:

1. In the parent_chunks loop (line 33), store the section index:
   ```python
   # BEFORE:
   parent_chunks.append(
       {
           "id": parent_resp.data[0]["id"],
           "title": section["title"],
           "page_number": section["page_number"],
       }
   )

   # AFTER:
   parent_chunks.append(
       {
           "id": parent_resp.data[0]["id"],
           "title": section["title"],
           "page_number": section["page_number"],
           "section_index": i,
       }
   )
   ```

2. In the child creation loop (lines 56-64), use the index:
   ```python
   # BEFORE:
   for parent in parent_chunks:
       children = _split_into_children(
           {
               "title": parent["title"],
               "content": next(
                   s["content"] for s in sections if s["title"] == parent["title"]
               ),
               "page_number": parent["page_number"],
           }
       )

   # AFTER:
   for parent in parent_chunks:
       children = _split_into_children(sections[parent["section_index"]])
   ```

   This is simpler AND correct — `sections[i]` already has `title`, `content`, and `page_number` keys, which is exactly what `_split_into_children()` expects.

---

## Fix 4: pdfplumber not used as context manager

**File**: `backend/services/document_service.py`, lines 18-24

**Problem**: If an exception occurs between `pdfplumber.open()` and `pdf.close()`, the file handle leaks.

**Fix**:

```python
# BEFORE:
        pdf = pdfplumber.open(file_path)
        pages = []
        for page in pdf.pages:
            text = page.extract_text()
            if text:
                pages.append((page.page_number, text))
        pdf.close()

# AFTER:
        with pdfplumber.open(file_path) as pdf:
            pages = []
            for page in pdf.pages:
                text = page.extract_text()
                if text:
                    pages.append((page.page_number, text))
```

Delete the `pdf.close()` line — the `with` block handles it.

---

## Verification

After all 4 fixes, run:
```bash
python -c "import ast; ast.parse(open('backend/services/document_service.py').read()); print('document_service.py: OK')"
python -c "import ast; ast.parse(open('backend/services/manual_rag_service.py').read()); print('manual_rag_service.py: OK')"
```

Both should print OK (no syntax errors).

Also confirm with `git diff` that ONLY these two files changed and the changes match the 4 fixes described above.
