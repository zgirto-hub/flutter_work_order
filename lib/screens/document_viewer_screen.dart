import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:http/http.dart' as http;

class DocumentViewerScreen extends StatefulWidget {
  final String fileUrl;

  const DocumentViewerScreen({super.key, required this.fileUrl});

  @override
  State<DocumentViewerScreen> createState() =>
      _DocumentViewerScreenState();
}

class _DocumentViewerScreenState
    extends State<DocumentViewerScreen> {
  String? _textContent;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkFileType();
  }

  void _checkFileType() async {
    if (widget.fileUrl.toLowerCase().endsWith(".txt")) {
      setState(() => _isLoading = true);

      final response = await http.get(Uri.parse(widget.fileUrl));

      setState(() {
        _textContent = response.body;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPdf =
        widget.fileUrl.toLowerCase().endsWith(".pdf");

    return Scaffold(
      appBar: AppBar(
        title: const Text("Document Viewer"),
      ),
      body: isPdf
          ? SfPdfViewer.network(widget.fileUrl)
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _textContent != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: SingleChildScrollView(
                        child: SelectableText(_textContent!),
                      ),
                    )
                  : const Center(
                      child: Text("Unsupported file type"),
                    ),
    );
  }
}