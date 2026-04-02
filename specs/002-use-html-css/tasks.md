# Tasks: HTML/CSS Template PDF for Payment Certificate

**Input**: Design documents from `/specs/002-use-html-css/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: Not requested — manual visual testing only.

**Organization**: Tasks grouped by user story. Each task includes exact file paths, explicit instructions, and reference code so a less capable LLM can implement without ambiguity.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1, US2, US3)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add dependency and create asset directory

- [X] T001 Add `htmltopdfwidgets` dependency to `frontend/pubspec.yaml`. Open the file, find the `dependencies:` section, and add `htmltopdfwidgets: ^1.0.0` (use latest version from pub.dev). Then run `cd frontend && flutter pub get` to install. Verify it resolves without errors.

- [X] T002 Register the new template asset in `frontend/pubspec.yaml`. Find the `assets:` section (around line 55-61) and add a new line: `    - assets/templates/payment_certificate.html`. This tells Flutter to bundle the HTML template file.

**Checkpoint**: `flutter pub get` succeeds, no errors.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the HTML/CSS template file that all user stories depend on

**CRITICAL**: The template must be created before the service can be rewritten.

- [X] T003 Create the HTML/CSS template file at `frontend/assets/templates/payment_certificate.html`. This is the core template asset. Create the `templates/` directory if it doesn't exist.

**DETAILED INSTRUCTIONS FOR T003**:

The HTML file must contain the following structure. Use `{{placeholder}}` tokens for dynamic data. The file must be valid HTML5 with all CSS inline in a `<style>` block. DO NOT include the payment table — that is built in Dart code.

```html
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="UTF-8">
<style>
  @font-face {
    font-family: 'Calibri';
    src: url(data:font/ttf;base64,{{CALIBRI_REGULAR_BASE64}}) format('truetype');
    font-weight: normal;
  }
  @font-face {
    font-family: 'Calibri';
    src: url(data:font/ttf;base64,{{CALIBRI_BOLD_BASE64}}) format('truetype');
    font-weight: bold;
  }
  body {
    font-family: 'Calibri', sans-serif;
    font-size: 11px;
    direction: rtl;
    margin: 0;
    padding: 0;
  }
  table { border-collapse: collapse; width: 100%; }
  td, th { padding: 3px 4px; }
  .header-bg { background-color: #DCE6F1; }
  .title-box {
    border: 1.5px solid black;
    background-color: #DCE6F1;
    padding: 8px 30px;
    text-align: center;
    display: inline-block;
  }
  .title-text { font-size: 16px; font-weight: bold; }
  .subtitle-text { font-size: 12px; font-weight: bold; }
  .bold { font-weight: bold; }
  .center { text-align: center; }
  .border-thin { border: 0.5px solid black; }
  .border-thick { border: 2.5px solid black; }
  .sig-block {
    border: 0.5px solid black;
    height: 100px;
    display: inline-block;
    vertical-align: top;
  }
  .sig-title {
    font-weight: bold;
    text-align: center;
    padding: 4px 6px;
    border-bottom: 0.5px solid black;
  }
</style>
</head>
<body>
```

**Section 1 — Title Block** (centered, inside `.title-box`):
- Line 1: `شهادة الدفع رقم ({{certificateNumber}})` — use `.title-text` class
- If extension exists (controlled by Dart — see T006): add line 2 with extension period label and date range using `.subtitle-text`
- The Dart code will handle the conditional: if no extension, the extension subtitle HTML is removed before conversion

**Section 2 — Subject Row** (table with 2 columns, `.border-thin`):
- Column 1 (flex 3, `.header-bg`): `الموضوع: {{subject}}`
- Column 2 (flex 1): `عقد رقم {{contractNumber}}`

**Section 3 — Invoice Table** (table with 4 columns, thick outer border `.border-thick`, thin inner borders):
- Row 1: `رقم الفاتورة:` (header-bg) | `{{invoiceNumber}}` | `مبلغ الفاتورة:` (header-bg) | `{{invoiceAmount}} {{currency}}`
- Row 2: `فترة الفاتورة:` (header-bg) | `من  {{periodFrom}}` | `إلى` (header-bg, centered) | `{{periodTo}}`

**Section 4 — Contract Info Table** (table with 4 columns, `.border-thin`):
Each row has: label1 (header-bg, centered) | value1 (centered) | label2 (header-bg, centered) | value2 (centered)
- Row: `الجهة المشرفة:` | `{{supervisingEntity}}` | `الجهة المنفذة:` | `{{executingEntity}}`
- Row: `قيمة العقد الأصلي:` | `({{originalValueKwd}} د.ك)` | `قيمة التمديد:` | `({{extensionValue}} د.ك)`
- Row: `مدة العقد:` | `{{contractDuration}}` | `مدة تمديد العقد:` | `{{extensionDuration}}`
- Row: `توقيع العقد:` | `{{contractSigningDate}}` | `تاريخ تسليم الموقع:` | `{{workCommencementDate}}`
- Row: `بداية العقد:` | `{{contractStartDate}}` | `نهاية العقد:` | `{{contractEndDate}}`
- `{{extensionRows}}` — placeholder for conditionally injected extension date rows (Dart inserts HTML `<tr>` elements or empty string)

**Section 5 — Payment Table**: NOT IN TEMPLATE. The Dart code inserts a `<!-- PAYMENT_TABLE_PLACEHOLDER -->` comment here. The service will split the HTML at this marker and insert `pdf` widgets between the two halves.

**Section 6 — Attachments** (after payment table placeholder):
- Heading: `المرفقات:` (font-size 12px, bold)
- `{{attachmentsTable}}` — placeholder for dynamically built attachment rows (Dart generates `<table>` HTML)

**Section 7 — Signatures** (4 equal-width signature blocks in a row):
- Each block uses `.sig-block` with `.sig-title` header
- Blocks (right to left): `المدقق / المحاسب` | `المدير المختص` | `المراقب المختص` | `رئيس القسم المختص`
- Use a 4-column table for layout, each cell contains a sig-block

```html
</body>
</html>
```

**Checkpoint**: The HTML file exists at `frontend/assets/templates/payment_certificate.html` and is valid HTML.

---

## Phase 3: User Story 1 - Export Payment Certificate as PDF via HTML Template (Priority: P1) MVP

**Goal**: Rewrite `PaymentCertificatePdfService` to load the HTML template, populate it with data, convert HTML sections to PDF widgets using `htmltopdfwidgets`, and compose the final PDF with the payment table built using direct `pdf` widgets.

**Independent Test**: Fill in a payment certificate form with sample data, tap "Export PDF", verify the output contains all 7 sections with correct Arabic RTL text, Calibri font, merged payment table headers, and color-coded rows.

### Implementation for User Story 1

- [X] T004 [US1] Rewrite `PaymentCertificatePdfService.build()` method in `frontend/lib/services/pdf/payment_certificate_pdf_service.dart`. This is the main task. The rewritten method must:

**STEP-BY-STEP INSTRUCTIONS FOR T004**:

1. **Keep these existing imports and add new ones**:
   ```dart
   import 'dart:convert'; // NEW — for base64 encoding
   import 'dart:typed_data';
   import 'package:flutter/services.dart' show rootBundle;
   import 'package:pdf/pdf.dart';
   import 'package:pdf/widgets.dart' as pw;
   import 'package:htmltopdfwidgets/htmltopdfwidgets.dart'; // NEW
   import '../../models/payment_certificate.dart';
   ```

2. **Rewrite `build()` method** — new implementation flow:
   ```
   a. Load Calibri font TTF bytes from assets (same as current code lines 9-12)
   b. Load HTML template string: rootBundle.loadString('assets/templates/payment_certificate.html')
   c. Base64-encode the font bytes:
      - final calibriBase64 = base64Encode(calibriData.buffer.asUint8List());
      - final calibriBoldBase64 = base64Encode(calibriBoldData.buffer.asUint8List());
   d. Replace font placeholders in template:
      - html = html.replaceAll('{{CALIBRI_REGULAR_BASE64}}', calibriBase64);
      - html = html.replaceAll('{{CALIBRI_BOLD_BASE64}}', calibriBoldBase64);
   e. Replace simple field placeholders (see list below)
   f. Build conditional extension title subtitle (see T005)
   g. Build conditional extension rows HTML (see T006)
   h. Build attachments table HTML (see T007)
   i. Split HTML at '<!-- PAYMENT_TABLE_PLACEHOLDER -->' into topHtml and bottomHtml
   j. Convert topHtml → List<pw.Widget> using htmltopdfwidgets
   k. Build payment table using _buildPaymentTable (kept from current code)
   l. Convert bottomHtml → List<pw.Widget> using htmltopdfwidgets
   m. Compose all widgets into pw.Document with pw.MultiPage
   n. Return pdf.save()
   ```

3. **Simple field replacements** (step 2e) — replace each `{{placeholder}}` with the formatted value:
   - `{{certificateNumber}}` → `cert.certificateNumber`
   - `{{subject}}` → `cert.subject`
   - `{{contractNumber}}` → `cert.contractNumber`
   - `{{invoiceNumber}}` → `cert.invoiceNumber`
   - `{{invoiceAmount}}` → `_fmtNum(cert.invoiceAmount)`
   - `{{currency}}` → `cert.currency`
   - `{{periodFrom}}` → `_fmtDate(cert.periodFrom)`
   - `{{periodTo}}` → `_fmtDate(cert.periodTo)`
   - `{{executingEntity}}` → `cert.executingEntity`
   - `{{supervisingEntity}}` → `cert.supervisingEntity`
   - `{{originalValueKwd}}` → `_fmtNum(cert.originalValueKwd)`
   - `{{extensionValue}}` → `_fmtNum(cert.extensionValue)`
   - `{{contractDuration}}` → `cert.contractDuration`
   - `{{extensionDuration}}` → `cert.extensionDuration`
   - `{{contractSigningDate}}` → `_fmtDate(cert.contractSigningDate)`
   - `{{workCommencementDate}}` → `_fmtDate(cert.workCommencementDate)`
   - `{{contractStartDate}}` → `_fmtDate(cert.contractStartDate)`
   - `{{contractEndDate}}` → `_fmtDate(cert.contractEndDate)`

4. **Keep these existing methods UNCHANGED** — they are still needed:
   - `_fmtDate(DateTime? d)` — formats date as YYYY/MM/DD
   - `_fmtNum(double v)` — formats number, returns '-' for 0
   - `_tcell(String text, pw.TextStyle style, ...)` — table cell widget
   - `_buildPaymentTable(cert, boldStyle, baseStyle)` — the full payment table builder with merged headers (lines 282-549 of current file)

5. **Remove these methods** — they are replaced by the HTML template:
   - `_buildTitle` (replaced by Section 1 in HTML)
   - `_buildSubjectRow` (replaced by Section 2 in HTML)
   - `_buildInvoiceTable` (replaced by Section 3 in HTML)
   - `_buildContractTable` and `_contractRow` (replaced by Section 4 in HTML)
   - `_buildAttachmentsList` (replaced by Section 6 in HTML)
   - `_buildSignaturesTable` (replaced by Section 7 in HTML)

6. **htmltopdfwidgets conversion** — to convert an HTML string to pw.Widget list:
   ```dart
   final List<pw.Widget> widgets = await HTMLToPdf().convert(htmlString);
   ```
   Pass the font theme so Calibri is used. Check the `htmltopdfwidgets` package API — it may accept a `pw.ThemeData` or require fonts to be set on the document. The converted widgets are added to the `pw.MultiPage.build` list.

7. **pw.Document composition**:
   ```dart
   final pdf = pw.Document();
   final topWidgets = await HTMLToPdf().convert(topHtml);
   final bottomWidgets = await HTMLToPdf().convert(bottomHtml);
   
   pdf.addPage(pw.MultiPage(
     textDirection: pw.TextDirection.rtl,
     pageFormat: PdfPageFormat.a4,
     margin: const pw.EdgeInsets.all(30),
     theme: pw.ThemeData.withFont(base: calibri, bold: calibriBold),
     build: (context) => [
       ...topWidgets,
       pw.SizedBox(height: 6),
       _buildPaymentTable(cert, boldStyle, baseStyle),
       pw.SizedBox(height: 6),
       ...bottomWidgets,
     ],
   ));
   return pdf.save();
   ```

- [X] T005 [US1] Implement extension title conditional logic in `frontend/lib/services/pdf/payment_certificate_pdf_service.dart`. Inside the `build()` method, BEFORE replacing placeholders:

**INSTRUCTIONS FOR T005**:

The HTML template has a subtitle line in the title box for extension periods. The Dart code must conditionally include or remove it.

Option A (recommended): Use a placeholder `{{extensionSubtitle}}` in the template's title box area. In Dart:
```dart
if (cert.extensionPeriodLabel.isNotEmpty) {
  final startDate = cert.extension2StartDate ?? cert.extension1StartDate ?? cert.periodFrom;
  final endDate = cert.extension2EndDate ?? cert.extension1EndDate ?? cert.periodTo;
  final subtitle = '<div class="subtitle-text">لفترة التمديد من (${_fmtDate(startDate)}) إلى (${_fmtDate(endDate)})</div>';
  html = html.replaceAll('{{extensionSubtitle}}', subtitle);
  
  // Also update the title line to include extension label
  final titleLine = 'شهادة الدفع رقم ( ${cert.certificateNumber} – ${cert.extensionPeriodLabel} )';
  html = html.replaceAll('شهادة الدفع رقم ({{certificateNumber}})', titleLine);
} else {
  html = html.replaceAll('{{extensionSubtitle}}', '');
}
```

This logic mirrors the current `_buildTitle` method (lines 100-142 of the current file).

- [X] T006 [US1] Implement extension rows conditional logic in `frontend/lib/services/pdf/payment_certificate_pdf_service.dart`. Inside the `build()` method:

**INSTRUCTIONS FOR T006**:

The contract info table has a `{{extensionRows}}` placeholder. Build HTML `<tr>` rows for extension dates if they exist:

```dart
String extensionRowsHtml = '';

// Extension 1 row
if (cert.extension1StartDate != null || cert.extension1EndDate != null) {
  extensionRowsHtml += '''
    <tr>
      <td class="border-thin header-bg center bold">بداية التمديد:</td>
      <td class="border-thin center">${_fmtDate(cert.extension1StartDate)}</td>
      <td class="border-thin header-bg center bold">نهاية التمديد:</td>
      <td class="border-thin center">${_fmtDate(cert.extension1EndDate)}</td>
    </tr>''';
}

// Extension 2 row
if (cert.extension2StartDate != null || cert.extension2EndDate != null) {
  extensionRowsHtml += '''
    <tr>
      <td class="border-thin header-bg center bold">بداية التمديد الثاني:</td>
      <td class="border-thin center">${_fmtDate(cert.extension2StartDate)}</td>
      <td class="border-thin header-bg center bold">نهاية التمديد الثاني:</td>
      <td class="border-thin center">${_fmtDate(cert.extension2EndDate)}</td>
    </tr>''';
}

html = html.replaceAll('{{extensionRows}}', extensionRowsHtml);
```

This mirrors the current `_buildContractTable` logic (lines 234-253 of the current file).

- [X] T007 [US1] Implement attachments table builder in `frontend/lib/services/pdf/payment_certificate_pdf_service.dart`. Inside the `build()` method:

**INSTRUCTIONS FOR T007**:

The template has `{{attachmentsTable}}` placeholder. Build HTML table rows from the checklist:

```dart
final checked = cert.attachmentChecklist.entries.toList();
final attachmentRows = StringBuffer();
attachmentRows.write('<table style="border-collapse: collapse; width: 300px;">');
for (int i = 0; i < checked.length; i++) {
  attachmentRows.write('''
    <tr>
      <td class="border-thin" style="padding: 3px 6px; text-align: right;">${checked[i].key}</td>
      <td class="border-thin" style="padding: 3px 6px; text-align: center; width: 40px;">.${i + 1}</td>
    </tr>''');
}
attachmentRows.write('</table>');
html = html.replaceAll('{{attachmentsTable}}', attachmentRows.toString());
```

This mirrors the current `_buildAttachmentsList` method (lines 555-594 of the current file).

- [X] T008 [US1] Verify the `build()` method return type is still `Future<Uint8List>` and the method signature is `static Future<Uint8List> build(PaymentCertificate cert) async` in `frontend/lib/services/pdf/payment_certificate_pdf_service.dart`. The caller in `frontend/lib/screens/payment_certificate/add_payment_certificate_screen.dart` calls `PaymentCertificatePdfService.build(model)` and passes the result to `Printing.sharePdf(bytes: bytes)` on web or `Printing.layoutPdf(onLayout: (_) => bytes)` on native. **DO NOT modify the screen file** — it must work unchanged.

**Checkpoint**: MVP complete. Export a payment certificate on web browser — verify all 7 sections render correctly with Arabic RTL text, Calibri fonts, merged payment table headers (#DCE6F1 blue headers, #FDE9D9 orange totals row), attachments list, and 4 signature blocks.

---

## Phase 4: User Story 2 - Consistent Layout Across Platforms (Priority: P1)

**Goal**: Verify the HTML template approach produces identical PDFs on Android, iOS, iOS PWA, and web. Since the implementation uses pure Dart (`htmltopdfwidgets` + `pdf` package), there should be no platform-specific rendering differences.

**Independent Test**: Export the same certificate on iOS PWA (standalone) and web browser, compare the PDFs visually.

### Implementation for User Story 2

- [ ] T009 [US2] Verify iOS PWA export works in `frontend/lib/screens/payment_certificate/add_payment_certificate_screen.dart`. **DO NOT modify this file.** Simply confirm that the existing platform-split logic (lines 237-248) still works:
  - On web (`kIsWeb`): calls `Printing.sharePdf(bytes: bytes, filename: fileName)` → triggers blob URL download
  - On native: calls `Printing.layoutPdf(onLayout: (_) => bytes)`
  - The `bytes` variable comes from `PaymentCertificatePdfService.build(model)` which returns `Uint8List` — this is unchanged.
  - **Action**: Test on iOS PWA by adding the app to home screen on an iOS device, then exporting a certificate. Verify the PDF downloads successfully and opens with correct layout.

- [X] T010 [US2] Verify the HTML template's base64-embedded fonts work correctly in the PDF output. The `@font-face` CSS in the template references `{{CALIBRI_REGULAR_BASE64}}` and `{{CALIBRI_BOLD_BASE64}}` which are replaced at runtime with actual base64-encoded font data. This ensures the PDF has embedded Calibri glyphs regardless of platform. **Note**: Since `htmltopdfwidgets` converts HTML to `pdf` package widgets, the fonts are actually applied via `pw.ThemeData.withFont()` on the `pw.Document`, not via CSS `@font-face`. The base64 font placeholders in the HTML are for self-containment if a browser-based renderer is ever used. For the current implementation, ensure the `pw.ThemeData.withFont(base: calibri, bold: calibriBold)` is set on the `pw.MultiPage` (already done in T004 step 7).

**Checkpoint**: PDF exported from iOS PWA matches PDF exported from Chrome web browser.

---

## Phase 5: User Story 3 - Maintainable Template (Priority: P2)

**Goal**: Confirm that layout changes can be made by editing only the HTML template file without touching Dart code.

**Independent Test**: Change a color in the HTML template (e.g., header background from `#DCE6F1` to `#E2EFDA`), rebuild, export — verify the color change appears in the PDF.

### Implementation for User Story 3

- [X] T011 [US3] Add inline code comments to the HTML template file at `frontend/assets/templates/payment_certificate.html` explaining each section and which placeholders are available. Add an HTML comment at the top of the `<body>`:
  ```html
  <!--
    Payment Certificate HTML Template
    ==================================
    This template is loaded by PaymentCertificatePdfService.build() and populated with data.
    
    Placeholders (replaced at runtime):
    - {{CALIBRI_REGULAR_BASE64}} / {{CALIBRI_BOLD_BASE64}} — font data (auto-injected)
    - {{certificateNumber}}, {{subject}}, {{contractNumber}} — identity fields
    - {{invoiceNumber}}, {{invoiceAmount}}, {{currency}} — invoice fields
    - {{periodFrom}}, {{periodTo}} — date range
    - {{executingEntity}}, {{supervisingEntity}} — parties
    - {{originalValueKwd}}, {{extensionValue}} — monetary values
    - {{contractDuration}}, {{extensionDuration}} — durations
    - {{contractSigningDate}}, {{workCommencementDate}} — dates
    - {{contractStartDate}}, {{contractEndDate}} — dates
    - {{extensionSubtitle}} — conditional extension subtitle (auto-generated)
    - {{extensionRows}} — conditional extension date rows (auto-generated)
    - {{attachmentsTable}} — attachment list table (auto-generated)
    
    Sections editable via CSS:
    - .header-bg — table header background color (currently #DCE6F1)
    - .title-box — title block styling
    - .sig-block / .sig-title — signature block styling
    - Font sizes, padding, border widths — all in <style> block
    
    NOT in this template:
    - Payment table (section 5) — built programmatically in Dart due to colspan limitations
  -->
  ```

**Checkpoint**: A developer can read the template comments and understand how to make layout changes. Changing a CSS color value and rebuilding the app produces a PDF with the updated color.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup and edge case handling

- [X] T012 Remove unused methods from `frontend/lib/services/pdf/payment_certificate_pdf_service.dart`. After T004 is complete, verify and remove these methods that are now replaced by the HTML template:
  - `_buildTitle` (was lines 100-142)
  - `_buildSubjectRow` (was lines 146-162)
  - `_buildInvoiceTable` (was lines 166-199)
  - `_buildContractTable` (was lines 203-265)
  - `_contractRow` (was lines 267-278)
  - `_buildAttachmentsList` (was lines 555-594)
  - `_buildSignaturesTable` (was lines 598-638)
  
  **Keep these methods** — still used by the payment table:
  - `_fmtDate` (line 73)
  - `_fmtNum` (line 80)
  - `_tcell` (line 86)
  - `_buildPaymentTable` (lines 282-549)

- [X] T013 Handle edge case: empty payment rows. In the `_buildPaymentTable` method (kept from current code), verify it handles `cert.paymentRows` being an empty list. Currently the totals row always shows — this is correct behavior (shows zeros). No code change needed if current behavior is acceptable; just verify.

- [X] T014 Handle edge case: null/empty optional fields. Verify that when extension dates are null, `{{extensionRows}}` is replaced with empty string (done in T006). Verify that when `extensionPeriodLabel` is empty, `{{extensionSubtitle}}` is replaced with empty string (done in T005). Verify that when attachmentChecklist is empty, `{{attachmentsTable}}` produces an empty table (done in T007). **No code change expected — just verification.**

- [X] T015 Run `flutter analyze` in `frontend/` directory to check for any Dart analysis warnings or errors in the modified files. Fix any issues found.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 (T001, T002 must complete first so the dependency and asset path are registered)
- **Phase 3 (US1)**: Depends on Phase 2 (T003 — the HTML template must exist before the service can load it)
  - Within Phase 3: T004 is the main task; T005, T006, T007 are sub-parts of T004 (can be done as part of T004 or separately)
  - T008 is verification only — depends on T004-T007 being complete
- **Phase 4 (US2)**: Depends on Phase 3 (need working export to test cross-platform)
- **Phase 5 (US3)**: Depends on Phase 2 (only needs the template to exist)
- **Phase 6 (Polish)**: Depends on Phase 3 (cleanup after main implementation)

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational only — this is the MVP
- **US2 (P1)**: Depends on US1 completion (needs working export to verify)
- **US3 (P2)**: Can start after Foundational (only needs template file), but verification requires US1

### Parallel Opportunities

- T001 and T002 can run in parallel (different sections of same file, but recommend sequential to avoid conflicts)
- T005, T006, T007 are independent conditional logic builders — can be developed in parallel if T004's skeleton is in place
- T012, T013, T014 can run in parallel (different concerns)

---

## Parallel Example: User Story 1

```bash
# After T003 (template) is complete, these can be developed in parallel as separate functions:
Task T005: "Extension title conditional logic"
Task T006: "Extension rows conditional logic"  
Task T007: "Attachments table builder"

# Then T004 integrates them all into the build() method
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T002) — add dependency + register asset
2. Complete Phase 2: Foundational (T003) — create HTML template
3. Complete Phase 3: User Story 1 (T004-T008) — rewrite service, verify export works
4. **STOP and VALIDATE**: Export a payment certificate on web browser, verify all sections
5. If PDF looks correct → MVP is done

### Incremental Delivery

1. Setup + Foundational → dependency ready, template exists
2. US1 → core export works → validate on web browser (MVP!)
3. US2 → verify iOS PWA + cross-platform → validate on iOS device
4. US3 → add template comments → developer documentation complete
5. Polish → cleanup old code, verify edge cases, run analyzer

---

## Notes

- The `htmltopdfwidgets` package API may differ from the examples in T004. Check the package's README/API docs for the exact conversion method. Common patterns: `HTMLToPdf().convert(html)` or `HtmlToPdfWidgets().convert(html)`.
- If `htmltopdfwidgets` does not render the HTML correctly (wrong fonts, missing styles), the fallback is to parse the HTML template manually in Dart and build all sections with `pdf` widgets — but use the HTML file as the source of truth for layout values (colors, text, structure).
- The payment table (`_buildPaymentTable`) is kept exactly as-is from the current implementation. Do not attempt to convert it to HTML — colspan support is unreliable in `htmltopdfwidgets`.
- All Arabic text must be RTL. The `pw.TextDirection.rtl` on the `pw.MultiPage` handles this for `pdf` widgets. For HTML sections, the `dir="rtl"` attribute on the `<html>` tag handles it.
- Commit after each task or logical group of tasks.
