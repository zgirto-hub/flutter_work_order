# Quickstart: Letter Reference Barcode

## Install

```bash
cd backend
pip install python-barcode==0.15.1
# (already added to requirements.txt)
```

## Verify

1. Start the backend (`uvicorn main:app --reload`).
2. From the Flutter app, generate a letter with reference number `2026-56634`.
3. Open the resulting PDF.
4. Confirm a Code 128 barcode appears directly above the "رقم الإشارة: 2026-56634" line on the left column, with `2026-56634` printed beneath the bars.
5. Scan the barcode with any phone barcode app → it must decode to exactly `2026-56634`.
6. Generate a second letter with an empty reference → confirm no barcode and no broken-image placeholder.
7. Open an existing letter from history and re-export → barcode appears, layout unchanged.

## Rollback

Remove the `<img>` line and `.ref-barcode` CSS rule from `letter_template.html`, drop the `_generate_barcode_data_uri` call from `_build_letter_pdf_v2()`, and `pip uninstall python-barcode`.
