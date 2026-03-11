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
  final url = widget.fileUrl.toLowerCase();

  return Scaffold(
    appBar: AppBar(
      title: const Text("Document Viewer[*]"),
    ),
    body: Builder(
      builder: (_) {
        // 📄 PDF
        if (url.endsWith(".pdf")) {
          return SfPdfViewer.network(widget.fileUrl);
        }

        // 📝 TXT
        if (url.endsWith(".txt")) {
          return FutureBuilder(
            future: http.get(Uri.parse(widget.fileUrl)),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final response = snapshot.data as http.Response;

              return Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: SelectableText(response.body),
                ),
              );
            },
          );
        }

        // 🖼 IMAGE
        if (url.endsWith(".jpg") ||
            url.endsWith(".jpeg") ||
            url.endsWith(".png")) {
          return Center(
            child: InteractiveViewer(
              child: Image.network(widget.fileUrl),
            ),
          );
        }

        // ❌ Unsupported
        return const Center(
          child: Text("Unsupported file type"),
        );
      },
    ),
  );
}}