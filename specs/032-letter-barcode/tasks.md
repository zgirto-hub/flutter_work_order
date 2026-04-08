# Tasks: Letter Reference Barcode

**Feature**: 032-letter-barcode
**Branch**: `032-letter-barcode`
**Spec**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md)

Single user story (US1 — Scannable Reference on Generated Letters, P1). All implementation tasks belong to US1; no foundational or polish phases needed.

---

## Phase 1: Setup

- [X] T001 Add `python-barcode==0.15.1` to `backend/requirements.txt` and install it.

  - **File**: `backend/requirements.txt`
  - **Modify**: append line `python-barcode==0.15.1`
  - **Dependencies**: none
  - **Acceptance**: requirements.txt diff is exactly one added line; `python -c "import barcode; print(barcode.__version__)"` prints `0.15.1`.

---

## Phase 2: User Story 1 — Scannable Reference (P1)

**Goal**: Generated letter PDFs render a Code 128 barcode of `ishara` directly above the reference text. Empty `ishara` → no barcode, no broken image.

**Independent test**: Generate a letter with `ishara="2026-56634"`, open the PDF, scan the barcode → must decode to `2026-56634`. Generate one with empty `ishara` → no image element appears.

- [X] T002 [US1] Add helper `_generate_barcode_data_uri(value: str) -> str | None` in `backend/routers/letters_v2.py` directly after `_font_data_uri` (around line 69).

  - **File**: `backend/routers/letters_v2.py`
  - **Add**: function returning a `data:image/png;base64,...` URI for a Code 128 barcode of `value`, or `None` if `value` is empty/whitespace OR encoding raises any exception.
  - **Signature**: `def _generate_barcode_data_uri(value: str) -> str | None:`
  - **Behavior**:
    - If `not value or not value.strip()`: return `None`.
    - Lazy-import inside function: `from barcode import Code128`, `from barcode.writer import ImageWriter`.
    - Use already-imported `io` and `base64`.
    - Call `Code128(value, writer=ImageWriter()).write(buffer, options={"module_height": 8.0, "module_width": 0.25, "font_size": 8, "text_distance": 3.0, "quiet_zone": 2.0, "write_text": True})`.
    - Return `f"data:image/png;base64,{base64.b64encode(buffer.getvalue()).decode('ascii')}"`.
    - Wrap encoding block in `try/except Exception: return None`.
  - **Dependencies**: T001
  - **Acceptance**: `_generate_barcode_data_uri("2026-56634")` returns a string starting with `data:image/png;base64,`; `""` and `"   "` return `None`; no exception ever propagates.

- [X] T003 [US1] Wire barcode into both `template.render(...)` call sites in `backend/routers/letters_v2.py`.

  - **File**: `backend/routers/letters_v2.py`
  - **Modify**: Add kwarg `barcode_data_uri=_generate_barcode_data_uri(data.ishara),` to the render call inside `_build_letter_pdf_v2` (~line 184) AND the render call inside `preview_letter_html` (~line 300). Place immediately after `ishara=data.ishara,` in both.
  - **Dependencies**: T002
  - **Acceptance**: `grep -c "barcode_data_uri=_generate_barcode_data_uri" backend/routers/letters_v2.py` returns 2. No other kwargs reordered or removed.

- [X] T004 [US1] Add `<img class="ref-barcode">` and `.ref-barcode` CSS rule to `backend/templates/letter_template.html`.

  - **File**: `backend/templates/letter_template.html`
  - **Modify (HTML, ~line 313)**: Replace
    ```
      <div class="ref-right">رقم الإشارة: {{ishara}}</div>
    ```
    with
    ```
      <div class="ref-right">
        {% if barcode_data_uri %}<img src="{{barcode_data_uri}}" class="ref-barcode" />{% endif %}
        <div>رقم الإشارة: {{ishara}}</div>
      </div>
    ```
  - **Modify (CSS, ~line 177)**: Immediately after the existing `.ref-block .ref-right { ... }` rule, add:
    ```css
      .ref-barcode {
        display: block;
        height: 38px;
        margin-bottom: 4px;
        margin-left: auto;
      }
    ```
  - **Dependencies**: T003
  - **Acceptance**: `.ref-right` div now contains optional barcode `<img>` and the reference `<div>`; `.ref-barcode` rule appears exactly once. No other markup or CSS changed.

---

## Phase 3: Verification

- [X] T005 [US1] Manual end-to-end verification per [quickstart.md](quickstart.md): generate letter with `ishara="2026-56634"`, scan barcode, confirm decoded value matches; generate empty-ishara letter, confirm no broken image; re-export an existing letter, confirm layout unchanged.

  - **File**: none (manual test)
  - **Dependencies**: T001–T004
  - **Acceptance**: All three quickstart scenarios pass.

---

## Dependency Graph

```
T001 → T002 → T003 → T004 → T005
```

All sequential (same files / direct dependencies). No `[P]` parallel opportunities.

## MVP Scope

The entire feature **is** the MVP: T001–T004 (T005 is verification).

---

## Implementation Prompts

--- IMPLEMENTATION PROMPT T001 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/requirements.txt
Task: Append a single new line `python-barcode==0.15.1` to the end of `backend/requirements.txt`. Do not reorder, edit, or remove any existing line.
Signatures required: none
Constraints: Only modification allowed is the addition of one line. No comments. Pin exactly to `0.15.1`. Preserve existing trailing-newline convention.
Acceptance criteria: `git diff backend/requirements.txt` shows exactly one added line `python-barcode==0.15.1`. After `pip install -r backend/requirements.txt`, `python -c "import barcode; print(barcode.__version__)"` prints `0.15.1`.
--- END PROMPT T001 ---

--- IMPLEMENTATION PROMPT T002 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: Add a new helper function `_generate_barcode_data_uri` directly after the existing `_font_data_uri` function (around line 69). The helper takes a string and returns a base64 PNG data URI of a Code 128 barcode encoding that string, or `None` when input is empty/whitespace or when barcode encoding raises any exception. Use lazy imports for `barcode.Code128` and `barcode.writer.ImageWriter` inside the function body — do NOT add module-level imports for them. Use the already-imported `io` and `base64`. Use these exact ImageWriter options: `module_height=8.0`, `module_width=0.25`, `font_size=8`, `text_distance=3.0`, `quiet_zone=2.0`, `write_text=True`. Wrap the entire encoding block in `try/except Exception: return None`.
Signatures required:
  def _generate_barcode_data_uri(value: str) -> str | None:
Constraints: Match existing style (4-space indent, double-quoted strings, type hints). Lazy imports only. Single short docstring. No logging or print. Do not modify any other function.
Acceptance criteria:
  - `_generate_barcode_data_uri("2026-56634")` returns a string starting with `"data:image/png;base64,"`.
  - `_generate_barcode_data_uri("")` and `_generate_barcode_data_uri("   ")` return `None`.
  - Any internal exception is swallowed; `None` is returned.
  - No other function in the file is touched.
--- END PROMPT T002 ---

--- IMPLEMENTATION PROMPT T003 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Python
File: backend/routers/letters_v2.py
Task: In `_build_letter_pdf_v2` (~line 168), inside the `template.render(...)` call at ~line 184, add a new keyword argument `barcode_data_uri=_generate_barcode_data_uri(data.ishara),` placed immediately after `ishara=data.ishara,`. Then perform the identical addition in the second `template.render(...)` call inside `preview_letter_html` at ~line 300, also immediately after its `ishara=data.ishara,`. Do not change any other kwargs, do not reorder, do not modify any other lines.
Signatures required: none (call-site edit only)
Constraints: Two edits only — one per render call site. Preserve trailing-comma style.
Acceptance criteria:
  - `grep -n "barcode_data_uri=_generate_barcode_data_uri(data.ishara)" backend/routers/letters_v2.py` returns exactly 2 lines.
  - All other arguments to both `template.render` calls remain unchanged in content and order.
  - `python -c "import ast; ast.parse(open('backend/routers/letters_v2.py').read())"` succeeds.
--- END PROMPT T003 ---

--- IMPLEMENTATION PROMPT T004 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: Jinja2 HTML template
File: backend/templates/letter_template.html
Task: Two edits.

Edit 1 (HTML, ~line 313): Replace the single line
    <div class="ref-right">رقم الإشارة: {{ishara}}</div>
with this 4-line block (preserve the original 2-space indentation level of surrounding markup):
    <div class="ref-right">
      {% if barcode_data_uri %}<img src="{{barcode_data_uri}}" class="ref-barcode" />{% endif %}
      <div>رقم الإشارة: {{ishara}}</div>
    </div>

Edit 2 (CSS, ~line 177): Immediately after the closing `}` of the existing `.ref-block .ref-right { ... }` rule, insert this new rule (matching sibling-rule indentation):
    .ref-barcode {
      display: block;
      height: 38px;
      margin-bottom: 4px;
      margin-left: auto;
    }

Do not change any other markup, CSS, or whitespace.
Signatures required: none
Constraints: Indentation must match surrounding lines. Do not reformat unrelated code. Do not remove or reorder any existing CSS rule.
Acceptance criteria:
  - Rendering with `barcode_data_uri="data:image/png;base64,XYZ"` and `ishara="2026-56634"` produces an `<img>` followed by the reference `<div>` inside `.ref-right`.
  - Rendering with `barcode_data_uri=None` produces only the reference `<div>` (no `<img>`).
  - The `.ref-barcode` rule appears exactly once in the stylesheet.
  - All other letter elements render unchanged.
--- END PROMPT T004 ---

--- IMPLEMENTATION PROMPT T005 ---
You are an expert Flutter/Python developer.
Implement the following task exactly as specified. Do not modify any file not listed. Do not add unrequested functionality.

Language: none (manual verification)
File: none
Task: Run the three verification scenarios from `specs/032-letter-barcode/quickstart.md`:
  1. Generate a letter via the running backend with `ishara="2026-56634"`. Open the PDF. Confirm a Code 128 barcode is rendered directly above "رقم الإشارة: 2026-56634" in the left reference column. Scan it with a phone barcode app and confirm the decoded value is exactly `2026-56634`.
  2. Generate a letter with empty `ishara`. Confirm the rendered PDF contains no barcode image and no broken-image placeholder.
  3. Re-export an existing letter from history. Confirm the date column, signatures, body, and header are visually unchanged aside from the added barcode.
Signatures required: none
Constraints: Read-only verification. Do not edit any file.
Acceptance criteria: All three scenarios pass and are recorded in the PR description.
--- END PROMPT T005 ---
