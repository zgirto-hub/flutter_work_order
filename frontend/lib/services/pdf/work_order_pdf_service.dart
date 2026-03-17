import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import '../../models/workorder_report.dart';

// ── Claude.ai-inspired palette ─────────────────────────────────────────────
const _terracotta  = PdfColor(0.800, 0.471, 0.361);   // #CC785C
const _terracottaL = PdfColor(0.859, 0.549, 0.416);   // #DA8C6A
const _cream       = PdfColor(0.980, 0.976, 0.969);   // #FAF9F7
const _surface     = PdfColor(0.961, 0.957, 0.941);   // #F5F4F0
const _surface2    = PdfColor(0.925, 0.922, 0.902);   // #ECEBE6
const _textDark    = PdfColor(0.102, 0.098, 0.082);   // #1A1915
const _textMid     = PdfColor(0.420, 0.408, 0.376);   // #6B6860
const _textLight   = PdfColor(0.608, 0.604, 0.588);   // #9B9A96
const _borderColor = PdfColor(0.910, 0.906, 0.890);   // #E8E7E4
const _white       = PdfColors.white;

class WorkOrderPdfService {
  static Future<Uint8List> buildReport({
    required String employeeName,
    required DateTime startDate,
    required DateTime endDate,
    required List<WorkOrderReport> results,
    required PdfColor primaryColor,
  }) async {
    final pdf = pw.Document();

    final logoBytes = await rootBundle.load('assets/images/logo.png');
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    final generatedStr = _fmtLong(DateTime.now());
    final startStr     = _fmtLong(startDate);
    final endStr       = _fmtLong(endDate);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(0, 0, 0, 32),
        footer: (ctx) => _footer(ctx, generatedStr),
        build: (ctx) => [
          _header(employeeName, startStr, endStr, results.length, logoImage),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(40, 28, 40, 0),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _sectionLabel('Work Orders'),
                pw.SizedBox(height: 12),
                _table(results),
                pw.SizedBox(height: 20),
                _summaryCard(results.length, employeeName),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Date formatters ────────────────────────────────────────────────────────

  static String _fmtLong(DateTime d) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month]} ${d.year}';
  }

  static String _fmtShort(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Logo mark ─────────────────────────────────────────────────────────────

  static pw.Widget _logoMark(pw.ImageProvider logo, {double size = 40}) {
    return pw.SizedBox(
      height: size,
      child: pw.Image(logo, fit: pw.BoxFit.contain),
    );
  }

  // ── Header block ──────────────────────────────────────────────────────────

  static pw.Widget _header(
    String employee,
    String start,
    String end,
    int total,
    pw.ImageProvider logo,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [

        // ── Top strip: terracotta gradient bar ────────────────────────────
        pw.Container(
          height: 5,
          decoration: const pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [_terracottaL, _terracotta],
            ),
          ),
        ),

        // ── Cream header block ────────────────────────────────────────────
        pw.Container(
          color: _cream,
          padding: const pw.EdgeInsets.fromLTRB(40, 28, 40, 24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [

              // Logo + brand row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      _logoMark(logo, size: 40),
                      pw.SizedBox(width: 12),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Work Order System',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: _textDark,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Operations Report',
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: _textLight,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Date badge
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: _white,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: _borderColor),
                    ),
                    child: pw.Text(
                      'Generated ${_fmtLong(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 8.5, color: _textMid),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 22),

              // Report title
              pw.Text(
                'Work Order Report',
                style: pw.TextStyle(
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                  color: _textDark,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '$start  to  $end',
                style: const pw.TextStyle(fontSize: 11, color: _textMid),
              ),

              pw.SizedBox(height: 20),

              // Info cards row
              pw.Row(
                children: [
                  _infoCard('Employee',    employee, flex: 3),
                  pw.SizedBox(width: 10),
                  _infoCard('Start Date',  start,    flex: 2),
                  pw.SizedBox(width: 10),
                  _infoCard('End Date',    end,      flex: 2),
                  pw.SizedBox(width: 10),
                  _infoCard('Total',       '$total work orders', flex: 2, highlight: true),
                ],
              ),
            ],
          ),
        ),

        // ── Subtle border under header ────────────────────────────────────
        pw.Container(height: 0.8, color: _borderColor),
      ],
    );
  }

  static pw.Widget _infoCard(String label, String value, {int flex = 1, bool highlight = false}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: pw.BoxDecoration(
          color: highlight ? _terracotta : _white,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: highlight ? _terracotta : _borderColor),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: highlight ? PdfColor(1, 1, 1, 0.75) : _textLight,
                letterSpacing: 0.6,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: highlight ? _white : _textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────

  static pw.Widget _sectionLabel(String text) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 3,
          height: 16,
          decoration: pw.BoxDecoration(
            color: _terracotta,
            borderRadius: pw.BorderRadius.circular(2),
          ),
        ),
        pw.SizedBox(width: 9),
        pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: _textDark,
          ),
        ),
      ],
    );
  }

  // ── Table (borderless, horizontal lines only) ─────────────────────────────

  static pw.Widget _table(List<WorkOrderReport> results) {
    return pw.Column(
      children: [

        // Header row
        pw.Container(
          decoration: pw.BoxDecoration(
            color: _surface,
            borderRadius: const pw.BorderRadius.only(
              topLeft: pw.Radius.circular(8),
              topRight: pw.Radius.circular(8),
            ),
          ),
          child: pw.Row(
            children: [
              _thCell('Title',       flex: 4),
              _thCell('Location',    flex: 2),
              _thCell('Closed Date', flex: 2),
            ],
          ),
        ),

        pw.Container(height: 0.6, color: _borderColor),

        // Data rows
        ...List.generate(results.length, (i) {
          final r = results[i];
          final isLast = i == results.length - 1;
          return pw.Column(
            children: [
              pw.Container(
                color: i.isOdd ? _cream : _white,
                child: pw.Row(
                  children: [
                    _tdCell(r.title,                               flex: 4),
                    _tdCell(r.location,                            flex: 2),
                    _tdCell(_fmtShort(r.modifiedDate),             flex: 2),
                  ],
                ),
              ),
              if (!isLast)
                pw.Container(height: 0.4, color: _borderColor),
            ],
          );
        }),

        // Bottom rounded cap
        pw.Container(
          height: 6,
          decoration: const pw.BoxDecoration(
            color: _surface,
            borderRadius: pw.BorderRadius.only(
              bottomLeft: pw.Radius.circular(8),
              bottomRight: pw.Radius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _thCell(String text, {int flex = 1}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: pw.Text(
          text.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: _textMid,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  static pw.Widget _tdCell(String text, {int flex = 1}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: pw.Text(
          text,
          style: const pw.TextStyle(fontSize: 10, color: _textDark),
        ),
      ),
    );
  }

  // ── Summary card ──────────────────────────────────────────────────────────

  static pw.Widget _summaryCard(int total, String employee) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: pw.BoxDecoration(
        color: _cream,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _borderColor),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Report Summary',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _textDark,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                employee,
                style: const pw.TextStyle(fontSize: 9, color: _textMid),
              ),
            ],
          ),
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: pw.BoxDecoration(
                  color: _terracotta,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  '$total completed',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  static pw.Widget _footer(pw.Context ctx, String generatedStr) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(40, 12, 40, 0),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _borderColor, width: 0.6),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Work Order System  ·  $generatedStr',
            style: const pw.TextStyle(fontSize: 8, color: _textLight),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _textLight),
          ),
        ],
      ),
    );
  }
}
