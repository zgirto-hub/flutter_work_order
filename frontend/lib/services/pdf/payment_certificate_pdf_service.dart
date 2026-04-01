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

    final baseStyle = pw.TextStyle(font: calibri, fontSize: 9);
    final boldStyle = pw.TextStyle(
        font: calibriBold, fontSize: 9, fontWeight: pw.FontWeight.bold);
    final headerStyle = pw.TextStyle(
        font: calibriBold, fontSize: 14, fontWeight: pw.FontWeight.bold);
    final subHeaderStyle = pw.TextStyle(
        font: calibriBold, fontSize: 10, fontWeight: pw.FontWeight.bold);

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        theme: pw.ThemeData.withFont(base: calibri, bold: calibriBold),
        build: (context) => [
          // ── 1. Title (2 lines) ────────────────────────────────
          _buildTitle(cert, headerStyle, subHeaderStyle),
          pw.SizedBox(height: 12),

          // ── 2. Subject & Contract ─────────────────────────────
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
          _buildAttachmentsList(cert, baseStyle),
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
      {pw.Alignment alignment = pw.Alignment.centerRight}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      alignment: alignment,
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

    return pw.Column(children: widgets);
  }

  // ── 2. Subject & Contract ───────────────────────────────────────────

  static pw.Widget _buildSubjectRow(
      PaymentCertificate cert, pw.TextStyle bold) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(children: [
          _tcell('الموضوع: ${cert.subject}', bold),
          _tcell('عقد رقم ${cert.contractNumber}', bold),
        ]),
      ],
    );
  }

  // ── 3. Invoice Details ──────────────────────────────────────────────

  static pw.Widget _buildInvoiceTable(
      PaymentCertificate cert, pw.TextStyle bold, pw.TextStyle base) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(children: [
          _tcell('رقم الفاتورة:', bold),
          _tcell(cert.invoiceNumber, base),
          _tcell('مبلغ الفاتورة:', bold),
          _tcell('${_fmtNum(cert.invoiceAmount)} ${cert.currency}', base),
        ]),
        pw.TableRow(children: [
          _tcell('فترة الفاتورة:', bold),
          _tcell('من  ${_fmtDate(cert.periodFrom)}', base),
          _tcell('إلى', bold, alignment: pw.Alignment.center),
          _tcell(_fmtDate(cert.periodTo), base),
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
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
      },
      children: rows,
    );
  }

  static pw.TableRow _contractRow(String label1, String val1, String label2,
      String val2, pw.TextStyle bold, pw.TextStyle base) {
    return pw.TableRow(children: [
      _tcell(label1, bold),
      _tcell(val1, base),
      _tcell(label2, bold),
      _tcell(val2, base),
    ]);
  }

  // ── 5. Payment Table ────────────────────────────────────────────────

  static pw.Widget _buildPaymentTable(
      PaymentCertificate cert, pw.TextStyle bold, pw.TextStyle base) {
    final headerBg = PdfColor.fromHex('#E8E8E8');
    final hBold = bold.copyWith(fontSize: 8);
    final hSmall = bold.copyWith(fontSize: 7);
    final dStyle = base.copyWith(fontSize: 8);

    // Column widths: reason(2) + 6 numeric cols (1 each) = 8 flex total
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(2), // أسباب
      1: const pw.FlexColumnWidth(1), // صافي دينار
      2: const pw.FlexColumnWidth(1), // صافي فلس
      3: const pw.FlexColumnWidth(1), // خصم دينار
      4: const pw.FlexColumnWidth(1), // خصم فلس
      5: const pw.FlexColumnWidth(1), // مستحق دينار
      6: const pw.FlexColumnWidth(1), // مستحق فلس
    };

    // ── Group header row ──
    pw.Widget groupCell(String text) => pw.Container(
          padding: const pw.EdgeInsets.all(4),
          alignment: pw.Alignment.center,
          child: pw.Text(text,
              style: hBold,
              textAlign: pw.TextAlign.center,
              textDirection: pw.TextDirection.rtl),
        );

    final groupRow = pw.Container(
      decoration: pw.BoxDecoration(
        color: headerBg,
        border: pw.Border.all(width: 0.5),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(flex: 2, child: groupCell('الدفعة المستحقة')),
          pw.Container(width: 0.5, color: PdfColors.black),
          pw.Expanded(flex: 2, child: groupCell('الخصم')),
          pw.Container(width: 0.5, color: PdfColors.black),
          pw.Expanded(flex: 2, child: groupCell('الصافي')),
          pw.Container(width: 0.5, color: PdfColors.black),
          pw.Expanded(flex: 2, child: groupCell('أسباب (الاستحقاق/ الخصم)')),
        ],
      ),
    );

    // ── Sub-header row ──
    final subHeaderRow = pw.Container(
      decoration: pw.BoxDecoration(color: headerBg),
      child: pw.Table(
        columnWidths: colWidths,
        border: pw.TableBorder.all(width: 0.5),
        children: [
          pw.TableRow(children: [
            pw.SizedBox(), // empty under أسباب
            _headerCell('دينار', hSmall),
            _headerCell('فلس', hSmall),
            _headerCell('دينار', hSmall),
            _headerCell('فلس', hSmall),
            _headerCell('دينار', hSmall),
            _headerCell('فلس', hSmall),
          ]),
        ],
      ),
    );

    final header = pw.Column(children: [groupRow, subHeaderRow]);

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
    final dataRows = <List<String>>[
      for (final r in cert.paymentRows)
        [
          r.reason,
          _fmtNum(r.netDinar),
          _fmtNum(r.netFils),
          _fmtNum(r.deductionDinar),
          _fmtNum(r.deductionFils),
          _fmtNum(r.duePaymentDinar),
          _fmtNum(r.duePaymentFils),
        ],
      [
        'الاجمالي',
        _fmtNum(totalNetDinar),
        _fmtNum(totalNetFils),
        _fmtNum(totalDeductDinar),
        _fmtNum(totalDeductFils),
        _fmtNum(totalDueDinar),
        _fmtNum(totalDueFils),
      ],
    ];

    final dataTable = pw.Table(
      columnWidths: colWidths,
      border: pw.TableBorder.all(width: 0.5),
      children: [
        for (final row in dataRows)
          pw.TableRow(
            children: [
              for (int c = 0; c < row.length; c++)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 4, horizontal: 4),
                  alignment:
                      c == 0 ? pw.Alignment.centerRight : pw.Alignment.center,
                  child: pw.Text(row[c],
                      style: dStyle,
                      textAlign:
                          c == 0 ? pw.TextAlign.right : pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl),
                ),
            ],
          ),
      ],
    );

    return pw.Column(children: [header, dataTable]);
  }

  static pw.Widget _headerCell(String text, pw.TextStyle style) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(3),
      alignment: pw.Alignment.center,
      child: pw.Text(text,
          style: style,
          textAlign: pw.TextAlign.center,
          textDirection: pw.TextDirection.rtl),
    );
  }

  // ── 6. Attachments ──────────────────────────────────────────────────

  static pw.Widget _buildAttachmentsList(
      PaymentCertificate cert, pw.TextStyle base) {
    final checked = cert.attachmentChecklist.entries.toList();
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
      child: pw.Column(
        children: [
          for (int i = 0; i < checked.length; i++)
            pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 0.25)),
              ),
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: pw.Row(
                children: [
                  pw.Text('${i + 1}-',
                      style: base, textDirection: pw.TextDirection.rtl),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Text(checked[i].key,
                        style: base, textDirection: pw.TextDirection.rtl),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 7. Signatures ───────────────────────────────────────────────────

  static pw.Widget _buildSignaturesTable(
      PaymentCertificate cert, pw.TextStyle bold, pw.TextStyle base) {
    pw.Widget sigBlock(String title, String name) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Column(
            children: [
              pw.Text(title,
                  style: bold, textDirection: pw.TextDirection.rtl),
              pw.SizedBox(height: 20),
              pw.Text(name,
                  style: base, textDirection: pw.TextDirection.rtl),
              pw.SizedBox(height: 6),
              pw.Container(
                width: 80,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
      child: pw.Row(
        children: [
          sigBlock('رئيس القسم المختص', cert.deptHead),
          sigBlock('المراقب المختص', cert.controller),
          sigBlock('المدير المختص', cert.director),
          sigBlock('المدقق / المحاسب', cert.auditor),
        ],
      ),
    );
  }
}
