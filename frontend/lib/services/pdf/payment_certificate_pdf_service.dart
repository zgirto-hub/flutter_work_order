import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../models/payment_certificate.dart';

class PaymentCertificatePdfService {
  static Future<Uint8List> build(PaymentCertificate cert) async {
    // Load Calibri from bundled assets (supports Arabic + Latin)
    final calibriData = await rootBundle.load('assets/fonts/calibri.ttf');
    final calibriBoldData = await rootBundle.load('assets/fonts/calibrib.ttf');
    final calibri = pw.Font.ttf(calibriData);
    final calibriBold = pw.Font.ttf(calibriBoldData);

    final baseStyle = pw.TextStyle(font: calibri, fontSize: 9);
    final boldStyle =
        pw.TextStyle(font: calibriBold, fontSize: 9, fontWeight: pw.FontWeight.bold);
    final headerStyle =
        pw.TextStyle(font: calibriBold, fontSize: 14, fontWeight: pw.FontWeight.bold);
    final subHeaderStyle =
        pw.TextStyle(font: calibriBold, fontSize: 10, fontWeight: pw.FontWeight.bold);

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        theme: pw.ThemeData.withFont(base: calibri, bold: calibriBold),
        build: (context) => [
          // ── 1. Title ───────────────────────────────────────────
          pw.Center(
            child: pw.Text(
              'شهادة الدفع رقم (${cert.certificateNumber})',
              style: headerStyle,
              textDirection: pw.TextDirection.rtl,
            ),
          ),
          pw.SizedBox(height: 12),

          // ── 2. Subject & Contract ──────────────────────────────
          _borderedTable([
            [
              _cell('الموضوع: ${cert.subject}', boldStyle, flex: 3),
              _cell('عقد رقم ${cert.contractNumber}', boldStyle),
            ],
          ]),
          pw.SizedBox(height: 6),

          // ── 3. Invoice details ─────────────────────────────────
          _borderedTable([
            [
              _cell('رقم الفاتورة:', boldStyle),
              _cell(cert.invoiceNumber, baseStyle),
              _cell('مبلغ الفاتورة:', boldStyle),
              _cell('${_fmtNum(cert.invoiceAmount)}  ${cert.currency}', baseStyle),
            ],
            [
              _cell('فترة الفاتورة:', boldStyle),
              _cell('من  ${_fmtDate(cert.periodFrom)}', baseStyle),
              _cell('إلى  ${_fmtDate(cert.periodTo)}', baseStyle, flex: 2),
            ],
          ]),
          pw.SizedBox(height: 6),

          // ── 4. Contract info ───────────────────────────────────
          _borderedTable([
            [
              _cell('الجهة المنفذة:', boldStyle),
              _cell(cert.executingEntity, baseStyle),
              _cell('الجهة المشرفة:', boldStyle),
              _cell(cert.supervisingEntity, baseStyle),
            ],
            [
              _cell('قيمة العقد الأصلي:', boldStyle),
              _cell(
                '(${_fmtNum(cert.originalValueUsd)} دولار امريكي)  (${_fmtNum(cert.originalValueKwd)} د.ك)',
                baseStyle,
                flex: 3,
              ),
            ],
            [
              _cell('قيمة الاعمال الإضافية:', boldStyle),
              _cell(cert.additionalWorks.isEmpty ? 'لايوجد' : cert.additionalWorks, baseStyle, flex: 3),
            ],
            [
              _cell('تاريخ توقيع العقد:', boldStyle),
              _cell(_fmtDate(cert.contractSigningDate), baseStyle),
              _cell('مدة العقد:', boldStyle),
              _cell(cert.contractDuration, baseStyle),
            ],
            [
              _cell('تاريخ بداية العقد:', boldStyle),
              _cell(_fmtDate(cert.contractStartDate), baseStyle),
              _cell('تاريخ نهاية العقد:', boldStyle),
              _cell(_fmtDate(cert.contractEndDate), baseStyle),
            ],
            [
              _cell('تاريخ مباشرة الاعمال:', boldStyle),
              _cell(_fmtDate(cert.workCommencementDate), baseStyle),
              _cell('', baseStyle, flex: 2),
            ],
            [
              _cell('تجديد العقد:', boldStyle),
              _cell(cert.renewalInfo, baseStyle),
              _cell('تاريخ انتهاء التجديد:', boldStyle),
              _cell(_fmtDate(cert.renewalExpiryDate), baseStyle),
            ],
          ]),
          pw.SizedBox(height: 6),

          // ── 5. Payment table ───────────────────────────────────
          _paymentTable(cert, boldStyle, baseStyle),
          pw.SizedBox(height: 6),

          // ── 6. Attachments ─────────────────────────────────────
          pw.Text('المرفقات:', style: subHeaderStyle, textDirection: pw.TextDirection.rtl),
          pw.SizedBox(height: 4),
          _attachmentsList(cert, baseStyle),
          pw.SizedBox(height: 12),

          // ── 7. Signatures ──────────────────────────────────────
          _signaturesTable(cert, boldStyle, baseStyle),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  static String _fmtDate(DateTime? d) {
    if (d == null) return '';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  static String _fmtNum(double v) {
    if (v == 0) return '-';
    return v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(2);
  }

  static pw.Expanded _cell(String text, pw.TextStyle style, {int flex = 1}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(text, style: style, textDirection: pw.TextDirection.rtl),
      ),
    );
  }

  static pw.Widget _borderedTable(List<List<pw.Expanded>> rows) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.5),
      ),
      child: pw.Column(
        children: rows.map((cells) {
          return pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.25)),
            ),
            child: pw.Row(children: cells),
          );
        }).toList(),
      ),
    );
  }

  static pw.Widget _paymentTable(
      PaymentCertificate cert, pw.TextStyle bold, pw.TextStyle base) {
    final headerBg = PdfColor.fromHex('#E8E8E8');

    // Compute totals
    double totalDollars = 0, totalCents = 0;
    double totalDinar = 0, totalFils = 0;
    double totalNetDinar = 0, totalNetFils = 0;
    for (final r in cert.paymentRows) {
      totalDollars += r.duePaymentDollars;
      totalCents += r.duePaymentCents;
      totalDinar += r.deductionDinar;
      totalFils += r.deductionFils;
      totalNetDinar += r.netDinar;
      totalNetFils += r.netFils;
    }

    final hBold = bold.copyWith(fontSize: 8);
    final hSmall = bold.copyWith(fontSize: 7);
    final dStyle = base.copyWith(fontSize: 8);
    // Column widths: 7 data cols (1 flex each) + reason (2 flex) = 8 total
    // RTL order: reason(2), دينار, فلس, دينار, فلس, دولار, سنت
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(2), // reason
      1: const pw.FlexColumnWidth(1), // صافي دينار
      2: const pw.FlexColumnWidth(1), // صافي فلس
      3: const pw.FlexColumnWidth(1), // خصم دينار
      4: const pw.FlexColumnWidth(1), // خصم فلس
      5: const pw.FlexColumnWidth(1), // دولار
      6: const pw.FlexColumnWidth(1), // سنت
    };

    // ── Header section (merged group headers) ──
    // Row 1 uses pw.Row so each group header truly spans its columns
    // with no internal border. Row 2 uses pw.Table for sub-headers.
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
          pw.Expanded(flex: 2, child: groupCell('الصافي')),
          pw.Container(width: 0.5, color: PdfColors.black),
          pw.Expanded(flex: 2, child: groupCell('الخصم')),
          pw.Container(width: 0.5, color: PdfColors.black),
          pw.Expanded(flex: 2, child: groupCell('أسباب (الاستحقاق/ الخصم)')),
        ],
      ),
    );

    final subHeaderRow = pw.Container(
      decoration: pw.BoxDecoration(
        color: headerBg,
      ),
      child: pw.Table(
        columnWidths: colWidths,
        border: pw.TableBorder.all(width: 0.5),
        children: [
          pw.TableRow(children: [
            pw.SizedBox(), // empty under أسباب
            pw.Container(
              padding: const pw.EdgeInsets.all(3),
              alignment: pw.Alignment.center,
              child: pw.Text('دينار', style: hSmall,
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(3),
              alignment: pw.Alignment.center,
              child: pw.Text('فلس', style: hSmall,
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(3),
              alignment: pw.Alignment.center,
              child: pw.Text('دينار', style: hSmall,
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(3),
              alignment: pw.Alignment.center,
              child: pw.Text('فلس', style: hSmall,
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(3),
              alignment: pw.Alignment.center,
              child: pw.Text('دولار', style: hSmall,
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(3),
              alignment: pw.Alignment.center,
              child: pw.Text('سنت', style: hSmall,
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl),
            ),
          ]),
        ],
      ),
    );

    final header = pw.Column(children: [groupRow, subHeaderRow]);

    // ── Data rows (pw.Table ensures equal-height cells + full borders) ──
    List<List<String>> rows = [
      for (final r in cert.paymentRows)
        [
          r.reason,
          _fmtNum(r.netDinar), _fmtNum(r.netFils),
          _fmtNum(r.deductionDinar), _fmtNum(r.deductionFils),
          _fmtNum(r.duePaymentDollars), _fmtNum(r.duePaymentCents),
        ],
      [
        'الاجمالي',
        _fmtNum(totalNetDinar), _fmtNum(totalNetFils),
        _fmtNum(totalDinar), _fmtNum(totalFils),
        _fmtNum(totalDollars), _fmtNum(totalCents),
      ],
    ];

    final dataTable = pw.Table(
      columnWidths: colWidths,
      border: pw.TableBorder.all(width: 0.5),
      children: [
        for (final row in rows)
          pw.TableRow(
            children: [
              for (int c = 0; c < row.length; c++)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  alignment: c == 0 ? pw.Alignment.centerRight : pw.Alignment.center,
                  child: pw.Text(row[c], style: dStyle,
                      textAlign: c == 0 ? pw.TextAlign.right : pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl),
                ),
            ],
          ),
      ],
    );

    return pw.Column(children: [header, dataTable]);
  }

  static pw.Widget _attachmentsList(PaymentCertificate cert, pw.TextStyle base) {
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
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: pw.Row(
                children: [
                  pw.Text('${i + 1}-', style: base, textDirection: pw.TextDirection.rtl),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Text(
                      checked[i].key,
                      style: base,
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _signaturesTable(
      PaymentCertificate cert, pw.TextStyle bold, pw.TextStyle base) {
    pw.Widget sigBlock(String title, String name) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Column(
            children: [
              pw.Text(title, style: bold, textDirection: pw.TextDirection.rtl),
              pw.SizedBox(height: 20),
              pw.Text(name, style: base, textDirection: pw.TextDirection.rtl),
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
