import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../models/payment_certificate.dart';

class PaymentCertificatePdfService {
  static Future<Uint8List> build(PaymentCertificate cert) async {
    final calibriData = await rootBundle.load('assets/fonts/calibri.ttf');
    final calibriBoldData = await rootBundle.load('assets/fonts/calibrib.ttf');
    final calibri = pw.Font.ttf(calibriData);
    final calibriBold = pw.Font.ttf(calibriBoldData);

    final baseStyle = pw.TextStyle(font: calibri, fontSize: 11);
    final boldStyle = pw.TextStyle(
        font: calibriBold, fontSize: 11, fontWeight: pw.FontWeight.bold);
    final headerStyle = pw.TextStyle(
        font: calibriBold, fontSize: 16, fontWeight: pw.FontWeight.bold);
    final subHeaderStyle = pw.TextStyle(
        font: calibriBold, fontSize: 12, fontWeight: pw.FontWeight.bold);

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        theme: pw.ThemeData.withFont(base: calibri, bold: calibriBold),
        build: (context) => [
          // ── 1. Title (centered) ───────────────────────────────
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [_buildTitle(cert, headerStyle, subHeaderStyle)],
          ),
          pw.SizedBox(height: 16),

          // ── 2. Subject & Contract ────────────────────────────
          _buildSubjectRow(cert, boldStyle),
          pw.SizedBox(height: 6),

          // ── 3. Invoice details ────────────────────────────────
          _buildInvoiceTable(cert, boldStyle, baseStyle),
          pw.SizedBox(height: 6),

          // ── 4. Contract info ──────────────────────────────────
          _buildContractTable(cert, boldStyle, baseStyle),
          pw.SizedBox(height: 6),

          // ── 5. Payment table ──────────────────────────────────
          _buildPaymentTable(cert, boldStyle, baseStyle),
          pw.SizedBox(height: 6),

          // ── 6. Attachments ────────────────────────────────────
          pw.Text('المرفقات:',
              style: subHeaderStyle,
              textDirection: pw.TextDirection.rtl),
          pw.SizedBox(height: 4),
          _buildAttachmentsList(cert, boldStyle),
          pw.SizedBox(height: 12),

          // ── 7. Signatures ─────────────────────────────────────
          _buildSignaturesTable(cert, boldStyle, baseStyle),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  static String _fmtDate(DateTime? d) {
    if (d == null) return '-';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${d.year}/$mm/$dd';
  }

  static String _fmtNum(double v) {
    if (v == 0) return '-';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  /// Table cell widget for pw.Table rows (no Expanded needed).
  static pw.Widget _tcell(String text, pw.TextStyle style,
      {pw.Alignment alignment = pw.Alignment.centerRight,
      PdfColor? bgColor}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      alignment: alignment,
      color: bgColor,
      child:
          pw.Text(text, style: style, textDirection: pw.TextDirection.rtl),
    );
  }

  // ── 1. Title ────────────────────────────────────────────────────────

  static pw.Widget _buildTitle(
      PaymentCertificate cert, pw.TextStyle header, pw.TextStyle sub) {
    final hasExtension = cert.extensionPeriodLabel.isNotEmpty;

    final line1 = hasExtension
        ? 'شهادة الدفع رقم ( ${cert.certificateNumber} – ${cert.extensionPeriodLabel} )'
        : 'شهادة الدفع رقم (${cert.certificateNumber})';

    final widgets = <pw.Widget>[
      pw.Center(
        child: pw.Text(line1,
            style: header, textDirection: pw.TextDirection.rtl),
      ),
    ];

    if (hasExtension) {
      final startDate = cert.extension2StartDate ??
          cert.extension1StartDate ??
          cert.periodFrom;
      final endDate = cert.extension2EndDate ??
          cert.extension1EndDate ??
          cert.periodTo;
      widgets.add(pw.Center(
        child: pw.Text(
          'لفترة التمديد من (${_fmtDate(startDate)}) إلى (${_fmtDate(endDate)})',
          style: sub,
          textDirection: pw.TextDirection.rtl,
        ),
      ));
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 1.5),
        color: PdfColor.fromHex('#DCE6F1'),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 8),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: widgets,
      ),
    );
  }

  // ── 2. Subject & Contract ───────────────────────────────────────────

  static pw.Widget _buildSubjectRow(
      PaymentCertificate cert, pw.TextStyle bold) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(3),
      },
      children: [
        pw.TableRow(children: [
          _tcell('عقد رقم ${cert.contractNumber}', bold),
          _tcell('الموضوع: ${cert.subject}', bold,
              bgColor: PdfColor.fromHex('#DCE6F1')),
        ]),
      ],
    );
  }

  // ── 3. Invoice Details ──────────────────────────────────────────────

  static pw.Widget _buildInvoiceTable(
      PaymentCertificate cert, pw.TextStyle bold, pw.TextStyle base) {
    final bg = PdfColor.fromHex('#DCE6F1');
    return pw.Table(
      border: pw.TableBorder(
        left: const pw.BorderSide(width: 2.5),
        right: const pw.BorderSide(width: 2.5),
        top: const pw.BorderSide(width: 2.5),
        bottom: const pw.BorderSide(width: 2.5),
        horizontalInside: const pw.BorderSide(width: 0.5),
        verticalInside: const pw.BorderSide(width: 0.5),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(children: [
          _tcell('${_fmtNum(cert.invoiceAmount)} ${cert.currency}', base),
          _tcell('مبلغ الفاتورة:', bold, bgColor: bg),
          _tcell(cert.invoiceNumber, base),
          _tcell('رقم الفاتورة:', bold, bgColor: bg),
        ]),
        pw.TableRow(children: [
          _tcell(_fmtDate(cert.periodTo), base),
          _tcell('إلى', bold, alignment: pw.Alignment.center, bgColor: bg),
          _tcell('من  ${_fmtDate(cert.periodFrom)}', base),
          _tcell('فترة الفاتورة:', bold, bgColor: bg),
        ]),
      ],
    );
  }

  // ── 4. Contract Info ────────────────────────────────────────────────

  static pw.Widget _buildContractTable(
      PaymentCertificate cert, pw.TextStyle bold, pw.TextStyle base) {
    final rows = <pw.TableRow>[
      _contractRow('الجهة المنفذة:', cert.executingEntity,
          'الجهة المشرفة:', cert.supervisingEntity, bold, base),
      _contractRow(
          'قيمة العقد الأصلي:',
          '(${_fmtNum(cert.originalValueKwd)} د.ك)',
          'قيمة التمديد:',
          '(${_fmtNum(cert.extensionValue)} د.ك)',
          bold,
          base),
      _contractRow('مدة العقد:', cert.contractDuration, 'مدة تمديد العقد:',
          cert.extensionDuration, bold, base),
      _contractRow(
          'توقيع العقد:',
          _fmtDate(cert.contractSigningDate),
          'تاريخ تسليم الموقع:',
          _fmtDate(cert.workCommencementDate),
          bold,
          base),
      _contractRow(
          'بداية العقد:',
          _fmtDate(cert.contractStartDate),
          'نهاية العقد:',
          _fmtDate(cert.contractEndDate),
          bold,
          base),
    ];

    // Extension 1 row (show if dates exist)
    if (cert.extension1StartDate != null || cert.extension1EndDate != null) {
      rows.add(_contractRow(
          'بداية التمديد:',
          _fmtDate(cert.extension1StartDate),
          'نهاية التمديد:',
          _fmtDate(cert.extension1EndDate),
          bold,
          base));
    }

    // Extension 2 row (show if dates exist)
    if (cert.extension2StartDate != null || cert.extension2EndDate != null) {
      rows.add(_contractRow(
          'بداية التمديد الثاني:',
          _fmtDate(cert.extension2StartDate),
          'نهاية التمديد الثاني:',
          _fmtDate(cert.extension2EndDate),
          bold,
          base));
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.0),
        1: const pw.FlexColumnWidth(0.8),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(0.8),
      },
      children: rows,
    );
  }

  static pw.TableRow _contractRow(String label1, String val1, String label2,
      String val2, pw.TextStyle bold, pw.TextStyle base) {
    final bgColor = PdfColor.fromHex('#DCE6F1');
    return pw.TableRow(
      children: [
        _tcell(val2, base, alignment: pw.Alignment.center),
        _tcell(label2, bold, bgColor: bgColor, alignment: pw.Alignment.center),
        _tcell(val1, base, alignment: pw.Alignment.center),
        _tcell(label1, bold, bgColor: bgColor, alignment: pw.Alignment.center),
      ],
    );
  }

  // ── 5. Payment Table ────────────────────────────────────────────────

  static pw.Widget _buildPaymentTable(
      PaymentCertificate cert, pw.TextStyle bold, pw.TextStyle base) {
    final headerBg = PdfColor.fromHex('#DCE6F1');
    final hBold = bold.copyWith(fontSize: 10);
    final hSmall = bold.copyWith(fontSize: 9);
    final dStyle = base.copyWith(fontSize: 10);

    // Column widths: reason(2) + 6 numeric cols (1 each) = 8 flex total
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(4), // أسباب
      1: const pw.FlexColumnWidth(1), // صافي دينار
      2: const pw.FlexColumnWidth(1), // صافي فلس
      3: const pw.FlexColumnWidth(1), // خصم دينار
      4: const pw.FlexColumnWidth(1), // خصم فلس
      5: const pw.FlexColumnWidth(1), // مستحق دينار
      6: const pw.FlexColumnWidth(1), // مستحق فلس
    };

    // ── Header (Row-based to avoid Table border gaps) ──
    pw.Widget hText(String text, pw.TextStyle style) => pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.all(3),
          child: pw.Text(text,
              style: style,
              textAlign: pw.TextAlign.center,
              textDirection: pw.TextDirection.rtl),
        );

    // Each numeric group: 2 sub-columns (دينار + فلس) with group label on top
    pw.Widget numGroup(String label) => pw.Expanded(
          flex: 2,
          child: pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(width: 0.5)),
            ),
            child: pw.Column(
              children: [
                hText(label, hBold),
                pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(width: 0.5)),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: hText('فلس', hSmall),
                      ),
                      pw.Expanded(
                        child: pw.Container(
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                                left: pw.BorderSide(width: 0.5)),
                          ),
                          child: hText('دينار', hSmall),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    final header = pw.Container(
      decoration: pw.BoxDecoration(
        color: headerBg,
        border: pw.Border.all(width: 0.5),
      ),
      child: pw.Row(
        children: [
          numGroup('الدفعة المستحقة'),
          numGroup('الخصم'),
          numGroup('الصافي'),
          // أسباب spans full height
          pw.Expanded(
            flex: 4,
            child: hText('أسباب (الاستحقاق/ الخصم)', hBold),
          ),
        ],
      ),
    );

    // ── Compute totals ──
    double totalDueDinar = 0, totalDueFils = 0;
    double totalDeductDinar = 0, totalDeductFils = 0;
    double totalNetDinar = 0, totalNetFils = 0;
    for (final r in cert.paymentRows) {
      totalDueDinar += r.duePaymentDinar;
      totalDueFils += r.duePaymentFils;
      totalDeductDinar += r.deductionDinar;
      totalDeductFils += r.deductionFils;
      totalNetDinar += r.netDinar;
      totalNetFils += r.netFils;
    }

    // ── Data rows ──
    final boldDStyle = hBold;
    final redStyle = boldDStyle.copyWith(color: PdfColors.red);

    // Build reason widgets with rich text
    final periodText =
        'من (${_fmtDate(cert.periodFrom)}) إلى (${_fmtDate(cert.periodTo)})';
    final certLabel = cert.extensionPeriodLabel.isNotEmpty
        ? '(الدفعة رقم ${cert.certificateNumber} – ${cert.extensionPeriodLabel}) بناء على شروط العقد'
        : '(الدفعة رقم ${cert.certificateNumber}) بناء على شروط العقد';

    // Row data: [reasonWidget, netD, netF, dedD, dedF, dueD, dueF, isTotalRow]
    final rows = <Map<String, dynamic>>[];

    for (final r in cert.paymentRows) {
      pw.Widget reasonWidget;
      if (r.reason.contains('المستحقة عن العقد')) {
        reasonWidget = pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text('قيمة الاعمال المستحقة عن العقد',
                style: boldDStyle, textDirection: pw.TextDirection.rtl),
            pw.Text(periodText,
                style: boldDStyle, textDirection: pw.TextDirection.rtl),
          ],
        );
      } else if (r.reason.contains('الغرامات')) {
        reasonWidget = pw.RichText(
          textDirection: pw.TextDirection.rtl,
          textAlign: pw.TextAlign.center,
          text: pw.TextSpan(children: [
            pw.TextSpan(text: 'قيمة الغرامات ', style: boldDStyle),
            pw.TextSpan(text: '– (ان وجد)', style: redStyle),
          ]),
        );
      } else if (r.reason.contains('المستحقة') &&
          r.reason.contains('الدفعة')) {
        reasonWidget = pw.Text(
            'قيمة الاعمال المستحقة $certLabel',
            style: boldDStyle,
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center);
      } else {
        reasonWidget = pw.Text(r.reason,
            style: dStyle, textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center);
      }

      rows.add({
        'reason': reasonWidget,
        'values': [
          _fmtNum(r.netDinar),
          _fmtNum(r.netFils),
          _fmtNum(r.deductionDinar),
          _fmtNum(r.deductionFils),
          _fmtNum(r.duePaymentDinar),
          _fmtNum(r.duePaymentFils),
        ],
        'isTotal': false,
      });
    }

    // Total row
    rows.add({
      'reason': pw.Text('الاجمالي',
          style: boldDStyle,
          textDirection: pw.TextDirection.rtl,
          textAlign: pw.TextAlign.center),
      'values': [
        _fmtNum(totalNetDinar),
        _fmtNum(totalNetFils),
        _fmtNum(totalDeductDinar),
        _fmtNum(totalDeductFils),
        _fmtNum(totalDueDinar),
        _fmtNum(totalDueFils),
      ],
      'isTotal': true,
    });

    final dataTable = pw.Table(
      columnWidths: colWidths,
      border: pw.TableBorder.all(width: 0.5),
      children: [
        for (final row in rows)
          pw.TableRow(
            decoration: (row['isTotal'] as bool)
                ? pw.BoxDecoration(color: headerBg)
                : null,
            children: [
              // Reason column (index 0 in table = rightmost visually)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    vertical: 4, horizontal: 4),
                alignment: pw.Alignment.center,
                child: row['reason'] as pw.Widget,
              ),
              // Value columns
              for (final v in (row['values'] as List<String>))
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 4, horizontal: 4),
                  alignment: pw.Alignment.center,
                  child: pw.Text(v,
                      style: dStyle,
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl),
                ),
            ],
          ),
      ],
    );

    return pw.Column(children: [header, dataTable]);
  }


  // ── 6. Attachments ──────────────────────────────────────────────────

  static pw.Widget _buildAttachmentsList(
      PaymentCertificate cert, pw.TextStyle base) {
    final checked = cert.attachmentChecklist.entries.toList();
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 300,
          child: pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FixedColumnWidth(40),
            },
            children: [
              for (int i = 0; i < checked.length; i++)
                pw.TableRow(
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(checked[i].key,
                          style: base, textDirection: pw.TextDirection.rtl),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      alignment: pw.Alignment.center,
                      child: pw.Text('.${i + 1}',
                          style: base, textDirection: pw.TextDirection.rtl),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 7. Signatures ───────────────────────────────────────────────────

  static pw.Widget _buildSignaturesTable(
      PaymentCertificate cert, pw.TextStyle bold, pw.TextStyle base) {
    pw.Widget sigBlock(String title, String name) {
      return pw.Expanded(
        child: pw.Container(
          height: 100,
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
          child: pw.Column(
            children: [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 4),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                      bottom: pw.BorderSide(width: 0.5)),
                ),
                child: pw.Text(title,
                    style: bold,
                    textAlign: pw.TextAlign.center,
                    textDirection: pw.TextDirection.rtl),
              ),
              pw.Spacer(),
            ],
          ),
        ),
      );
    }

    return pw.Row(
      children: [
        sigBlock('رئيس القسم المختص', cert.deptHead),
        pw.SizedBox(width: 10),
        sigBlock('المراقب المختص', cert.controller),
        pw.SizedBox(width: 10),
        sigBlock('المدير المختص', cert.director),
        pw.SizedBox(width: 10),
        sigBlock('المدقق / المحاسب', cert.auditor),
      ],
    );
  }
}
