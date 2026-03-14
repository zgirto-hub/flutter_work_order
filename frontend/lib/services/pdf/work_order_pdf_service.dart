import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../models/workorder_report.dart';

// Claude.ai-inspired palette — light, clean, minimal
const _orange = PdfColor(0.855, 0.467, 0.224);        // #da7739
const _orangeLight = PdfColor(1.0, 0.957, 0.933);     // #fff4ed
const _textDark = PdfColor(0.118, 0.118, 0.137);      // #1e1e23
const _textMid = PdfColor(0.38, 0.38, 0.42);          // #616169
const _textLight = PdfColor(0.60, 0.60, 0.64);        // #999aa3
const _border = PdfColor(0.878, 0.878, 0.894);        // #e0e0e4
const _rowAlt = PdfColor(0.969, 0.969, 0.976);        // #f7f7f9
const _headerRowBg = PdfColor(0.941, 0.941, 0.953);   // #f0f0f3
const _white = PdfColors.white;

class WorkOrderPdfService {
  static Future<void> exportReport({
    required String employeeName,
    required DateTime startDate,
    required DateTime endDate,
    required List<WorkOrderReport> results,
    required PdfColor primaryColor,
  }) async {
    final pdf = pw.Document();

    final generatedStr = _fmt(DateTime.now());
    final startStr = _fmt(startDate);
    final endStr = _fmt(endDate);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 0, 40, 40),
        footer: (ctx) => _footer(ctx, generatedStr),
        build: (ctx) => [
          _header(employeeName, startStr, endStr, results.length),
          pw.SizedBox(height: 28),
          _sectionLabel("Work Orders"),
          pw.SizedBox(height: 10),
          _table(results),
          pw.SizedBox(height: 20),
          _summaryCard(results.length),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  static String _fmt(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  // ── Header ─────────────────────────────────────────────────────────────────

  static pw.Widget _header(
    String employee,
    String start,
    String end,
    int total,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Top orange accent bar
        pw.Container(height: 4, color: _orange),
        pw.SizedBox(height: 24),

        // Title row
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "Work Order Report",
                  style: pw.TextStyle(
                    fontSize: 26,
                    fontWeight: pw.FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  "$start  to  $end",
                  style: const pw.TextStyle(fontSize: 11, color: _textMid),
                ),
              ],
            ),
            pw.Text(
              "Work Order System",
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _orange,
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 20),

        // Info bar
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: pw.BoxDecoration(
            color: _rowAlt,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: _border),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _infoItem("Employee", employee),
              _divider(),
              _infoItem("Start Date", start),
              _divider(),
              _infoItem("End Date", end),
              _divider(),
              _infoItem("Total Orders", total.toString()),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _infoItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: const pw.TextStyle(fontSize: 8.5, color: _textLight)),
        pw.SizedBox(height: 3),
        pw.Text(value,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: _textDark,
            )),
      ],
    );
  }

  static pw.Widget _divider() {
    return pw.Container(width: 0.8, height: 32, color: _border);
  }

  // ── Section label ───────────────────────────────────────────────────────────

  static pw.Widget _sectionLabel(String text) {
    return pw.Row(
      children: [
        pw.Container(width: 3, height: 16, color: _orange),
        pw.SizedBox(width: 8),
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

  // ── Table ───────────────────────────────────────────────────────────────────

  static pw.Widget _table(List<WorkOrderReport> results) {
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.5),
        1: pw.FlexColumnWidth(1.8),
        2: pw.FlexColumnWidth(1.7),
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _headerRowBg),
          children: [
            _th("Title"),
            _th("Location"),
            _th("Closed Date"),
          ],
        ),
        // Rows
        ...List.generate(results.length, (i) {
          final r = results[i];
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i % 2 == 0 ? _white : _rowAlt,
            ),
            children: [
              _td(r.title),
              _td(r.location),
              _td(_fmt(r.modifiedDate)),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _th(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: _textDark,
        ),
      ),
    );
  }

  static pw.Widget _td(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 10, color: _textDark),
      ),
    );
  }

  // ── Summary card ────────────────────────────────────────────────────────────

  static pw.Widget _summaryCard(int total) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: pw.BoxDecoration(
        color: _orangeLight,
        borderRadius: pw.BorderRadius.circular(7),
        border: pw.Border.all(color: PdfColor(0.855, 0.467, 0.224, 0.3)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            "Report Summary",
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _textDark,
            ),
          ),
          pw.Text(
            "$total work orders completed",
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _orange,
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer ──────────────────────────────────────────────────────────────────

  static pw.Widget _footer(pw.Context ctx, String generatedStr) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            "Generated $generatedStr",
            style: const pw.TextStyle(fontSize: 8, color: _textLight),
          ),
          pw.Text(
            "Page ${ctx.pageNumber} of ${ctx.pagesCount}",
            style: const pw.TextStyle(fontSize: 8, color: _textLight),
          ),
        ],
      ),
    );
  }
}
