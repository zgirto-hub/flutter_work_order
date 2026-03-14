// Mobile/desktop stub — these functions are never called on non-web
import 'dart:typed_data';
import 'package:flutter/material.dart';

String createBlobUrl(Uint8List bytes, String mimeType) {
  throw UnsupportedError('createBlobUrl is only supported on web');
}

class PdfWebViewer extends StatelessWidget {
  final String blobUrl;
  const PdfWebViewer({super.key, required this.blobUrl});

  @override
  Widget build(BuildContext context) => const SizedBox();
}
