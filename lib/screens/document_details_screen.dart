import 'package:flutter/material.dart';
import '../models/document.dart';
import 'document_viewer_screen.dart';

class DocumentDetailsScreen extends StatelessWidget {
  final DocumentModel document;
  final String searchQuery;

  const DocumentDetailsScreen({
    super.key,
    required this.document,
    required this.searchQuery,
  });

  Widget highlightFullText(String text, String query) {
    if (query.isEmpty) {
      return Text(text);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);

      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }

      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: const TextStyle(
            backgroundColor: Colors.yellow,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      start = index + query.length;
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black, fontSize: 14),
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName =
        document.filePath != null ? document.filePath!.split('/').last : null;

    final fileUrl = fileName != null
        ? "http://100.92.159.81:8000/files/$fileName"
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(document.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              document.documentType,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              document.fileName ?? '',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),

            if (fileUrl != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            DocumentViewerScreen(fileUrl: fileUrl),
                      ),
                    );
                  },
                  child: const Text("Open Attached File"),
                ),
              ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            const Text(
              "Document Content",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: SingleChildScrollView(
                child: highlightFullText(
                  document.parsedText ?? "No content available",
                  searchQuery,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}