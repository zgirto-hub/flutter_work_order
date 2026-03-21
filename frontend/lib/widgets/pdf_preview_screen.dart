import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../theme/app_theme.dart';

/// Shared PDF preview screen used by WorkOrderReportScreen and
/// MonthlyTaskReportScreen. Wraps the [printing] package's [PdfPreview]
/// widget with the app's standard chrome (AppBar, colours).
class PdfPreviewScreen extends StatelessWidget {
  final String title;

  /// Called by [PdfPreview] to obtain the PDF bytes.
  /// Return type is [dynamic] to accommodate both [Uint8List] and [Future<Uint8List>].
  final Future<dynamic> Function() buildPdf;

  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.buildPdf,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              size: 18, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PdfPreview(
        build: (format) async {
          final bytes = await buildPdf();
          return bytes as dynamic;
        },
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: '${title.replaceAll(' ', '_')}.pdf',
        actionBarTheme: PdfActionBarTheme(
          backgroundColor: AppColors.bgSurface,
          iconColor: AppColors.textSecondary,
          textStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
    );
  }
}
