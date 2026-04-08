# Phase 0 Research: Letter Reference Barcode

## Decision: `python-barcode==0.15.1` for Code 128 PNG generation

**Rationale**:
- Pure-Python; only runtime dependency is Pillow, which is already installed for the existing image-compression pipeline. No system packages (no Ghostscript, no libbarcode).
- Native Code 128 support with `write_text=True` to render the human-readable digits beneath the bars — matches government-document convention requested in the spec.
- Outputs to a `BytesIO` PNG buffer that can be base64-encoded into a data URI, identical to the existing `_logo_data_uri` and signature embedding pattern in `letters_v2.py`.
- Stable, MIT-licensed, last release compatible with Python 3.10.

**Alternatives considered**:
- **`reportlab.graphics.barcode`**: Already in the backend tree (used for the legacy reportlab letter PDF), but the project's letter v2 generator uses WeasyPrint + HTML/Jinja, not reportlab flowables. Embedding a reportlab Drawing into HTML would require rendering to PNG anyway, with more glue code and no benefit over `python-barcode`.
- **`treepoem`**: Supports many barcode symbologies but requires Ghostscript installed system-wide. Adds a deployment step on the production Linux server. Rejected — violates the spec's "no system dependencies" goal.
- **`qrcode`** (2D): Excluded by the spec — Code 128 is mandated.
- **Inline SVG generation (no library)**: Possible but reinventing Code 128 encoding for one use case violates YAGNI's opposite — under-engineering to the point of bugs. Rejected.

## Decision: Embed via base64 data URI in `<img src="...">`

**Rationale**: WeasyPrint resolves data URIs natively. Matches the existing logo embedding strategy in `letters_v2.py` (lines ~31-68, ~181). Avoids writing a temp file or serving the barcode through `/files/`.

**Alternatives**: Saving to `backend/uploaded_files/` — rejected as it would create per-letter image garbage with no lifecycle and violates the "in-memory only" simplicity of the feature.

## Decision: Helper returns `Optional[str]`; template uses `{% if barcode_data_uri %}`

**Rationale**: A single guard handles both empty `ishara` and any `python-barcode` encoding exception (caught and converted to `None`). Letters never fail to generate because of a barcode problem.

**Alternatives**: Raising on failure — rejected, would block letter generation for a non-essential decoration.
