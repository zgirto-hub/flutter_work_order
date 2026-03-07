import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../models/work_order.dart';
class WorkOrderPdfService {

  static Future<void> exportReport({
    required String employeeName,
    required DateTime startDate,
    required DateTime endDate,
    required List<dynamic> results,
    required PdfColor primaryColor,
  }) async {

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [

              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                color: primaryColor,
                child: pw.Text(
                  "Work Order Report",
                  style: pw.TextStyle(
                    fontSize: 20,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.SizedBox(height: 15),

              pw.Text("Employee: $employeeName"),
              pw.Text(
                "Date Range: ${startDate.toString().split(' ')[0]} "
                "to ${endDate.toString().split(' ')[0]}",
              ),

              pw.SizedBox(height: 20),

              pw.Table.fromTextArray(
                headers: ["Title", "Location", "Closed"],
                data: results.map((r) {
                  return [
                    r.title,
                    r.location,
                    r.modifiedDate.toString().split(" ")[0],
                  ];
                }).toList(),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }
}