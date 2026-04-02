# Data Model: HTML/CSS Template PDF

**Feature**: 002-use-html-css | **Date**: 2026-04-02

## Entities

No new data entities are introduced. The existing `PaymentCertificate` and `PaymentRow` models remain unchanged.

### PaymentCertificate (unchanged)
- All fields remain as defined in `frontend/lib/models/payment_certificate.dart`
- The `build()` method signature (`Future<Uint8List>`) remains the same
- Callers (add_payment_certificate_screen.dart) are unaffected

### PaymentRow (unchanged)
- Fields: duePaymentDinar, duePaymentFils, deductionDinar, deductionFils, netDinar, netFils, reason

## New Artifacts

### HTML Template Asset
- **Location**: `frontend/assets/templates/payment_certificate.html`
- **Format**: Self-contained HTML with inline CSS and base64-embedded Calibri fonts
- **Placeholders**: Mustache-style `{{fieldName}}` tokens for simple fields
- **Dynamic sections**: Conditional blocks for extension rows, repeating blocks for payment rows and attachments — handled in Dart before passing to htmltopdfwidgets
- **Registered in**: `pubspec.yaml` under assets

## State Transitions

N/A — no state changes. This is a rendering pipeline replacement.

## Validation Rules

N/A — data validation is handled by the existing form and model layer.
