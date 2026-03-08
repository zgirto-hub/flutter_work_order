import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../models/workorder_report.dart';

class WorkOrderPdfService {
  static Future<void> exportReport({
    required String employeeName,
    required DateTime startDate,
    required DateTime endDate,
    required List<WorkOrderReport> results,
    required PdfColor primaryColor,
  }) async {
    final pdf = pw.Document();

    final labelStyle = pw.TextStyle(
      fontSize: 10,
      color: PdfColors.grey700,
    );

    final valueStyle = pw.TextStyle(
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),

        footer: (context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              "Page ${context.pageNumber} / ${context.pagesCount}",
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey600,
              ),
            ),
          );
        },

        build: (context) {
          return [

            /// TITLE
            pw.Text(
              "Work Order Report",
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: primaryColor,
              ),
            ),

            pw.SizedBox(height: 6),

            /// ACCENT LINE
            pw.Container(
              height: 2,
              width: 120,
              color: primaryColor,
            ),

            pw.SizedBox(height: 20),

            /// REPORT INFO
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [

                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("Employee", style: labelStyle),
                      pw.Text(employeeName, style: valueStyle),
                    ],
                  ),

                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("Start Date", style: labelStyle),
                      pw.Text(startDate.toString().split(' ')[0], style: valueStyle),
                    ],
                  ),

                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("End Date", style: labelStyle),
                      pw.Text(endDate.toString().split(' ')[0], style: valueStyle),
                    ],
                  ),

                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("Total Orders", style: labelStyle),
                      pw.Text(results.length.toString(), style: valueStyle),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 25),

            /// TABLE
            pw.Table(
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
              ),

              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(2),
              },

              children: [

                /// HEADER
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                  ),
                  children: [
                    _tableHeader("Title"),
                    _tableHeader("Location"),
                    _tableHeader("Closed Date"),
                  ],
                ),

                /// ROWS
                ...List.generate(results.length, (index) {
                  final r = results[index];

                  final bgColor = index % 2 == 0
                      ? PdfColors.white
                      : PdfColors.grey100;

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: bgColor),
                    children: [
                      _tableCell(r.title),
                      _tableCell(r.location),
                      _tableCell(r.modifiedDate.toString().split(" ")[0]),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 25),

            /// FOOTER NOTE
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                "Generated on ${DateTime.now().toString().split(' ')[0]}",
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
    );
  }

  static pw.Widget _tableCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 10),
      ),
    );
  }
}