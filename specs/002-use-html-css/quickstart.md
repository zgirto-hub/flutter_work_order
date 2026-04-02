# Quickstart: HTML/CSS Template PDF

**Feature**: 002-use-html-css

## What This Feature Does

Replaces the programmatic `pdf` package widget tree in `PaymentCertificatePdfService` with an HTML/CSS template approach. The template is stored as an asset file, populated with certificate data at runtime, and converted to PDF using `htmltopdfwidgets` (pure Dart). The complex payment table with merged headers continues to use direct `pdf` widgets.

## Key Files

| File | Purpose |
|------|---------|
| `frontend/assets/templates/payment_certificate.html` | HTML/CSS template (NEW) |
| `frontend/lib/services/pdf/payment_certificate_pdf_service.dart` | Service rewrite — loads template, populates data, builds PDF |
| `frontend/lib/models/payment_certificate.dart` | Data model (UNCHANGED) |
| `frontend/lib/screens/payment_certificate/add_payment_certificate_screen.dart` | Export trigger (UNCHANGED — same `build()` call) |
| `frontend/pubspec.yaml` | Add `htmltopdfwidgets` dependency + register template asset |

## How to Test

1. Fill in a payment certificate form with sample data (including extension periods)
2. Tap "Export PDF"
3. Verify: Arabic RTL text, Calibri font, merged payment table headers, color-coded rows, attachments list, signature blocks
4. Test on: Android, iOS, iOS PWA (standalone), web browser
5. Compare output visually against the current direct-PDF output

## Architecture Notes

- The HTML template handles: title block, subject row, invoice table, contract table, attachments list, signature blocks
- The payment table (with colspan merged headers) is built programmatically using `pdf` widgets — HTML conversion packages cannot reliably handle complex table merges
- Font embedding: Calibri fonts are base64-encoded in the HTML template's `@font-face` CSS for self-containment
- The `build()` method signature (`Future<Uint8List>`) is unchanged — callers are not affected
