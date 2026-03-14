import 'package:flutter/material.dart';
import '../../models/document.dart';
import '../Documents/document_viewer_screen.dart';
import '../../config.dart';
import '../../services/download_helper.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

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
List<String> users = [];
@override
void initState() {
  super.initState();
  loadSharedUsers();
  loadUsers();
}
void showShareDialog() {

  final currentUser =
      Supabase.instance.client.auth.currentUser?.email ?? "";

  final availableUsers = users.where((user) =>
      !sharedUsers.contains(user) && user != currentUser).toList();

  final Set<String> selectedUsers = {};

  showDialog(
    context: context,
    builder: (context) {

      return StatefulBuilder(
        builder: (context, setStateDialog) {

          return AlertDialog(
            title: const Text("Share Document"),

            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: availableUsers.map((user) {

                  return CheckboxListTile(
                    title: Text(user),
                    value: selectedUsers.contains(user),

                    onChanged: (checked) {

                      setStateDialog(() {

                        if (checked == true) {
                          selectedUsers.add(user);
                        } else {
                          selectedUsers.remove(user);
                        }

                      });
                    },
                  );

                }).toList(),
              ),
            ),

            actions: [

              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),

              ElevatedButton(
                onPressed: selectedUsers.isEmpty
                    ? null
                    : () async {

                        Navigator.pop(context);

                        for (final user in selectedUsers) {
                          await shareDocument(user);
                        }

                        await loadSharedUsers();
                      },
                child: const Text("Share"),
              ),

            ],
          );
        },
      );
    },
  );
}
Future<void> shareDocument(String email) async {

  final owner =
      Supabase.instance.client.auth.currentUser?.email ?? "";

  final request = http.MultipartRequest(
    'POST',
    Uri.parse("https://zorin.taila92fe8.ts.net/api/share-document"),
  );

  request.fields['document_id'] = widget.document.id;
  request.fields['owner_email'] = owner;
  request.fields['share_with'] = email;

  final response = await request.send();

  if (response.statusCode == 200) {

    setState(() {
      sharedUsers.add(email);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Document shared")),
    );

  } else {

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Failed to share document")),
    );

  }
}
Future<void> loadUsers() async {

  final response = await http.get(
    Uri.parse("https://zorin.taila92fe8.ts.net/api/users"),
  );

  if (response.statusCode == 200) {

    final data = json.decode(response.body);

    setState(() {
      users = List<String>.from(data["users"]);
    });

  }
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

    print("DOC OWNER: ${widget.document.uploadedBy}");
print("CURRENT USER: ${Supabase.instance.client.auth.currentUser?.email}");
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
    /// Shared users section
if (sharedUsers.isNotEmpty) ...[
  const Text(
    "Shared with:",
    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
  ),
  const SizedBox(height: 8),

  for (final user in sharedUsers)
    Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [

          Text("• $user"),

          if (widget.document.uploadedBy ==
              Supabase.instance.client.auth.currentUser?.email)
            TextButton(
              onPressed: () => removeAccess(user),
              child: const Text(
                "Remove",
                style: TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    ),
        
],

/// Share button (always visible for owner)
const SizedBox(height: 12),

if (widget.document.uploadedBy ==
    Supabase.instance.client.auth.currentUser?.email)

  ElevatedButton.icon(
    onPressed: showShareDialog,
    icon: const Icon(Icons.person_add),
    label: const Text("Share with user"),
  ),


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

  Future<void> removeAccess(String userEmail) async {

  final owner =
      Supabase.instance.client.auth.currentUser?.email ?? "";

  final url =
      "https://zorin.taila92fe8.ts.net/api/remove-share"
      "?document_id=${widget.document.id}"
      "&owner_email=$owner"
      "&remove_user=$userEmail";

  final response = await http.delete(Uri.parse(url));

  if (response.statusCode == 200) {

    setState(() {
      sharedUsers.remove(userEmail);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Access removed")),
    );

  } else {

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Failed to remove access")),
    );

  }
}
}
