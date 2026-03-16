// Web implementation - renders PDF via blob URL in an iframe
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

/// Creates a blob URL from bytes — web only
String createBlobUrl(Uint8List bytes, String mimeType) {
  final jsArray = bytes.toJS;
  final blob = web.Blob(
    [jsArray].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  return web.URL.createObjectURL(blob);
}

/// Renders a PDF blob URL inside an iframe (non-iOS web)
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

    ui.platformViewRegistry.registerViewFactory(_viewId, (int id) {
      final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement
        ..src = widget.blobUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block';
      iframe.setAttribute('allowfullscreen', 'true');
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(child: HtmlElementView(viewType: _viewId));
  }
}

/// Renders a PDF via <embed> using the direct URL.
/// iOS Safari WKWebView only renders the first page of blob-URL iframes;
/// <embed> with a direct URL invokes the native iOS PDF viewer which
/// supports full multi-page scrolling.
class PdfEmbedViewer extends StatefulWidget {
  final String url;
  const PdfEmbedViewer({super.key, required this.url});

  @override
  State<PdfEmbedViewer> createState() => _PdfEmbedViewerState();
}

class _PdfEmbedViewerState extends State<PdfEmbedViewer> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'pdf-embed-${widget.url.hashCode}';

    ui.platformViewRegistry.registerViewFactory(_viewId, (int id) {
      final embed = web.document.createElement('embed') as web.HTMLEmbedElement
        ..src = widget.url
        ..type = 'application/pdf'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block';
      return embed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(child: HtmlElementView(viewType: _viewId));
  }
}
