import 'package:flutter/material.dart';
import '../../models/document.dart';
import './Documents/document_viewer_screen.dart';
import '../../config.dart';
import '../../services/download_helper.dart';



class DocumentDetailsScreen extends StatefulWidget {
  final DocumentModel document;
  final String searchQuery;

  const DocumentDetailsScreen({
    super.key,
    required this.document,
    required this.searchQuery,
  });

  @override
  State<DocumentDetailsScreen> createState() => _DocumentDetailsScreenState();
}

class _DocumentDetailsScreenState extends State<DocumentDetailsScreen> {
  

  /*Future<void> _downloadFile(String url, String fileName) async {
    try {
      if (kIsWeb) {
        print("Download URL: $url");
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", fileName)
          ..click();
        return;
      }

      // Mobile / Desktop logic here (optional)
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Download failed: $e")),
      );
    }
  }*/
  Future<void> _downloadFile(String url, String fileName) async {
  try {
    await downloadFile(url, fileName);
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Download failed: $e")),
    );
  }
}

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
    final filePath = widget.document.filePath;
    final fileName = filePath?.split('/').last;
    final fileUrl =
        filePath != null ? "${AppConfig.downloadUrl}$filePath" : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.document.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.document.documentType,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.document.fileName ?? '',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            if (fileUrl != null)
              Row(
                children: [
                  Expanded(
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _downloadFile(fileUrl, fileName!);
                      },
                      child: const Text("Download File"),
                    ),
                  ),
                ],
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
                  widget.document.parsedText ?? "No content available",
                  widget.searchQuery,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
