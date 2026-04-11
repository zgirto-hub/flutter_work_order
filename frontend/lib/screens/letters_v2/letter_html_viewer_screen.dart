import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../Files/file_viewer_web.dart'
    if (dart.library.io) '../Files/file_viewer_stub.dart';

class LetterHtmlViewerScreen extends StatelessWidget {
  final String title;
  final String html;
  final VoidCallback? onGeneratePdf;

  const LetterHtmlViewerScreen({
    super.key,
    required this.title,
    required this.html,
    this.onGeneratePdf,
  });

  void _openInNewTab() {
    final bytes = Uint8List.fromList(utf8.encode(html));
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'text/html'),
    );
    final url = web.URL.createObjectURL(blob);
    web.window.open(url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        title: Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              size: 18, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (onGeneratePdf != null)
            IconButton(
              icon: Icon(Icons.picture_as_pdf_rounded,
                  size: 18, color: AppColors.textSecondary),
              tooltip: 'Generate PDF',
              onPressed: onGeneratePdf,
            ),
          IconButton(
            icon: Icon(Icons.open_in_new_rounded,
                size: 18, color: AppColors.textSecondary),
            tooltip: 'Open in new tab (for printing)',
            onPressed: _openInNewTab,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: HtmlBlobViewer(html: html),
    );
  }
}
