// Web implementation - renders PDF via blob URL in an iframe
import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

/// Creates a blob URL from bytes — web only
String createBlobUrl(Uint8List bytes, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  return html.Url.createObjectUrlFromBlob(blob);
}

/// Renders a PDF blob URL inside an iframe
class PdfWebViewer extends StatefulWidget {
  final String blobUrl;
  const PdfWebViewer({super.key, required this.blobUrl});

  @override
  State<PdfWebViewer> createState() => _PdfWebViewerState();
}

class _PdfWebViewerState extends State<PdfWebViewer> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'pdf-viewer-${widget.blobUrl.hashCode}';

    // Register the iframe as a platform view
    ui.platformViewRegistry.registerViewFactory(_viewId, (int id) {
      final iframe = html.IFrameElement()
        ..src = widget.blobUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}
