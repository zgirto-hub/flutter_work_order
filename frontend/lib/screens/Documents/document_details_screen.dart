import 'package:flutter/material.dart';
import '../../models/document.dart';
import '../Documents/document_viewer_screen.dart';
import '../../config.dart';
import '../../services/download_helper.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  
List<String> sharedUsers = [];

@override
void initState() {
  super.initState();
  loadSharedUsers();
}
Future<void> loadSharedUsers() async {

  print("LOADING SHARES FOR: ${widget.document.id}");

 /* final response = await http.get(
    Uri.parse("${AppConfig.baseUrl}/document-shares/${widget.document.id}")
  );*/
    final response = await http.get(
    Uri.parse("https://zorin.taila92fe8.ts.net/api/document-shares/${widget.document.id}")
  );

  print("SHARE RESPONSE: ${response.body}");

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    setState(() {
      sharedUsers = List<String>.from(data["users"]);
    });
  }
}
  
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
            if (sharedUsers.isNotEmpty) ...[
  const SizedBox(height: 20),
  const Text(
    "Shared with:",
    style: TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 16,
    ),
  ),
  const SizedBox(height: 8),

  for (final user in sharedUsers)
    Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text("• $user"),
    ),
],
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
