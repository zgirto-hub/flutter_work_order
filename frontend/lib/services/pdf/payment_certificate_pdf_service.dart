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
          _buildTitle(cert, headerStyle, subHeaderStyle),
          pw.SizedBox(height: 16),
          _buildSubjectRow(cert, boldStyle),
          pw.SizedBox(height: 6),
          _buildInvoiceTable(cert, boldStyle, baseStyle),
          pw.SizedBox(height: 6),
          _buildContractTable(cert, boldStyle, baseStyle),
          pw.SizedBox(height: 20),
          _buildPaymentTable(cert, boldStyle, baseStyle),
          pw.SizedBox(height: 6),
          pw.Text('المرفقات:',
              style: subHeaderStyle,
              textDirection: pw.TextDirection.rtl),
          pw.SizedBox(height: 4),
          _buildAttachmentsList(cert, baseStyle),
          pw.SizedBox(height: 12),
          _buildSignaturesTable(boldStyle),
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
    return v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(2);
  }

  static pw.Widget _tcell(String text, pw.TextStyle style,
      {pw.TextAlign textAlign = pw.TextAlign.right,
      PdfColor? bgColor}) {
    return pw.Container(
      color: bgColor,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(text,
          style: style,
          textAlign: textAlign,
          textDirection: pw.TextDirection.rtl),
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

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 1.5),
            color: PdfColor.fromHex('#DCE6F1'),
          ),
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 8),
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: widgets,
          ),
        ),
      ],
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
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#DCE6F1')),
          children: [
            _tcell('عقد رقم ${cert.contractNumber}', bold, bgColor: PdfColors.white),
            _tcell('الموضوع: ${cert.subject}', bold),
          ],
        ),
      ],
    );
  }

  // ── 3. Invoice Details ──────────────────────────────────────────────

  static pw.Widget _buildInvoiceTable(
      PaymentCertificate cert, pw.TextStyle bold, pw.TextStyle base) {
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
          _tcell('${_fmtNum(cert.invoiceAmount)} ${cert.currency}', base, textAlign: pw.TextAlign.center),
          _tcell('مبلغ الفاتورة:', bold),
          _tcell(cert.invoiceNumber, base, textAlign: pw.TextAlign.center),
          _tcell('رقم الفاتورة:', bold),
        ]),
        pw.TableRow(children: [
          _tcell(_fmtDate(cert.periodTo), base, textAlign: pw.TextAlign.center),
          _tcell('إلى', bold),
          _tcell('من  ${_fmtDate(cert.periodFrom)}', base, textAlign: pw.TextAlign.center),
          _tcell('فترة الفاتورة:', bold),
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

    if (cert.extension1StartDate != null || cert.extension1EndDate != null) {
      rows.add(_contractRow(
          'بداية التمديد:',
          _fmtDate(cert.extension1StartDate),
          'نهاية التمديد:',
          _fmtDate(cert.extension1EndDate),
          bold,
          base));
    }

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
        _tcell(val2, base, textAlign: pw.TextAlign.center),
        _tcell(label2, bold,
            bgColor: bgColor, textAlign: pw.TextAlign.center),
        _tcell(val1, base, textAlign: pw.TextAlign.center),
        _tcell(label1, bold,
            bgColor: bgColor, textAlign: pw.TextAlign.center),
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

    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(4),
      1: const pw.FlexColumnWidth(1),
      2: const pw.FlexColumnWidth(1),
      3: const pw.FlexColumnWidth(1),
      4: const pw.FlexColumnWidth(1),
      5: const pw.FlexColumnWidth(1),
      6: const pw.FlexColumnWidth(1),
    };

    pw.Widget hCell(String text, pw.TextStyle style, {PdfColor? bg}) =>
        pw.Container(
          color: bg ?? headerBg,
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.all(3),
          child: pw.Text(text,
              style: style,
              textAlign: pw.TextAlign.center,
              textDirection: pw.TextDirection.rtl),
        );

    final headerRow1Widget = pw.Container(
      decoration: pw.BoxDecoration(
        color: headerBg,
        border: const pw.Border(
          top: pw.BorderSide(width: 0.5),
          left: pw.BorderSide(width: 0.5),
          right: pw.BorderSide(width: 0.5),
          bottom: pw.BorderSide(width: 1.5),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 2,
            child: pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(left: pw.BorderSide(width: 0.5)),
              ),
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.all(3),
              child: pw.Text('الصافي',
                  style: hBold,
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(left: pw.BorderSide(width: 0.5)),
              ),
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.all(3),
              child: pw.Text('الخصم',
                  style: hBold,
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(left: pw.BorderSide(width: 0.5)),
              ),
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.all(3),
              child: pw.Text('الدفعة المستحقة',
                  style: hBold,
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl),
            ),
          ),
          pw.Expanded(
            flex: 4,
            child: pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.all(3),
              child: pw.Text('أسباب (الاستحقاق/ الخصم)',
                  style: hBold,
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl),
            ),
          ),
        ],
      ),
    );

    final headerRow2 = pw.Table(
      columnWidths: colWidths,
      border: pw.TableBorder(
        left: const pw.BorderSide(width: 0.5),
        right: const pw.BorderSide(width: 0.5),
        bottom: const pw.BorderSide(width: 0.5),
        verticalInside: const pw.BorderSide(width: 0.5),
      ),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerBg),
          children: [
            hCell('', hSmall),
            hCell('دينار', hSmall),
            hCell('فلس', hSmall),
            hCell('دينار', hSmall),
            hCell('فلس', hSmall),
            hCell('دينار', hSmall),
            hCell('فلس', hSmall),
          ],
        ),
      ],
    );

    final header = pw.Column(children: [headerRow1Widget, headerRow2]);

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

    final boldDStyle = hBold;
    final redStyle = boldDStyle.copyWith(color: PdfColors.red);
    final periodText =
        'من (${_fmtDate(cert.periodFrom)}) إلى (${_fmtDate(cert.periodTo)})';
    final certLabel = cert.extensionPeriodLabel.isNotEmpty
        ? '(الدفعة رقم ${cert.certificateNumber} – ${cert.extensionPeriodLabel}) بناء على شروط العقد'
        : '(الدفعة رقم ${cert.certificateNumber}) بناء على شروط العقد';

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
        reasonWidget = pw.Text('قيمة الاعمال المستحقة $certLabel',
            style: boldDStyle,
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center);
      } else {
        reasonWidget = pw.Text(r.reason,
            style: dStyle,
            textDirection: pw.TextDirection.rtl,
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
                ? pw.BoxDecoration(color: PdfColor.fromHex('#FDE9D9'))
                : null,
            children: [
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                alignment: pw.Alignment.center,
                child: row['reason'] as pw.Widget,
              ),
              for (final v in (row['values'] as List<String>))
                pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
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
              1: const pw.FixedColumnWidth(30),
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
                          style: base,
                          textDirection: pw.TextDirection.rtl),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      alignment: pw.Alignment.center,
                      child: pw.Text('${i + 1}.',
                          style: base,
                          textDirection: pw.TextDirection.rtl),
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

  static pw.Widget _buildSignaturesTable(pw.TextStyle bold) {
    pw.Widget sigBlock(String title) {
      return pw.Expanded(
        child: pw.Container(
          height: 100,
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
          child: pw.Column(
            children: [
              pw.Container(
                width: double.infinity,
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
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
        sigBlock('رئيس القسم المختص'),
        pw.SizedBox(width: 10),
        sigBlock('المراقب المختص'),
        pw.SizedBox(width: 10),
        sigBlock('المدير المختص'),
        pw.SizedBox(width: 10),
        sigBlock('المدقق / المحاسب'),
      ],
    );
  }
}
