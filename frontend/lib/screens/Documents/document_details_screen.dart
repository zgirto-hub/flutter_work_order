import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/document.dart';
import 'document_viewer_screen.dart';
import '../../config.dart';
import '../../services/download_helper.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

// Conditional import — dart:html only exists on web
import 'package:work_order/services/platform_ua.dart';

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

  bool get isIosWeb => kIsWeb && PlatformUA.isIos;

  // Email-only list used to filter available users in the share dialog
  List<String> sharedUsers = [];
  // Full share records with role info for display
  List<Map<String, String>> _shares = [];
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

    final availableUsers = users
        .where((user) => !sharedUsers.contains(user) && user != currentUser)
        .toList();

    final Set<String> selectedUsers = {};
    String selectedRole = 'viewer';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: AppColors.bgSurface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text('Share Document',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Role selector
                    Row(
                      children: [
                        Text('Access level',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary)),
                        SizedBox(width: 10),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedRole,
                            borderRadius: BorderRadius.circular(12),
                            dropdownColor: AppColors.bgSurface,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary),
                            items: const [
                              DropdownMenuItem(
                                  value: 'viewer', child: Text('Viewer')),
                              DropdownMenuItem(
                                  value: 'editor', child: Text('Editor')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setStateDialog(() => selectedRole = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    // User list
                    if (availableUsers.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No users to share with.',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textTertiary)),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView(
                          shrinkWrap: true,
                          children: availableUsers.map((user) {
                            return CheckboxListTile(
                              title: Text(user,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textPrimary)),
                              value: selectedUsers.contains(user),
                              activeColor: AppColors.accent,
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
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedUsers.isEmpty
                      ? null
                      : () async {
                          Navigator.pop(context);
                          for (final user in selectedUsers) {
                            await shareDocument(user, selectedRole);
                          }
                          await loadSharedUsers();
                        },
                  child: Text('Share'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> shareDocument(String email, String role) async {
    final owner =
        Supabase.instance.client.auth.currentUser?.email ?? "";

    final request = http.MultipartRequest(
      'POST',
      Uri.parse("${AppConfig.baseUrl}/share-document"),
    );

    request.fields['document_id'] = widget.document.id;
    request.fields['owner_email'] = owner;
    request.fields['share_with'] = email;
    request.fields['role'] = role;

    final response = await request.send();

    if (!mounted) return;
    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Document shared with $email as $role")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to share document")),
      );
    }
  }

  Future<void> loadUsers() async {
    final response = await http.get(
      Uri.parse("${AppConfig.baseUrl}/users"),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (mounted) {
        setState(() {
          users = List<String>.from(data["users"]);
        });
      }
    }
  }

  Future<void> loadSharedUsers() async {
    final response = await http.get(
      Uri.parse(
          "${AppConfig.baseUrl}/document-shares/${widget.document.id}"),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (mounted) {
        final sharesList = (data["shares"] as List? ?? []);
        setState(() {
          sharedUsers = List<String>.from(data["users"] ?? []);
          _shares = sharesList
              .map((s) => {
                    'email': s['email'].toString(),
                    'role': s['role'].toString(),
                  })
              .toList();
        });
      }
    }
  }

  Future<void> _downloadFile(String url, String fileName) async {
    try {
      await downloadFile(url, fileName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Download failed: $e")),
      );
    }
  }

  Widget highlightFullText(String text, String query) {
    if (query.isEmpty) return Text(text);

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
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: TextStyle(
          backgroundColor: Colors.yellow,
          fontWeight: FontWeight.bold,
        ),
      ));
      start = index + query.length;
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(color: Colors.black, fontSize: 14),
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filePath = widget.document.filePath;
    final fileName = filePath?.split('/').last ?? 'file';
    final fileUrl =
        filePath != null ? "${AppConfig.downloadUrl}$filePath" : null;
    final isOwner = widget.document.uploadedBy ==
        Supabase.instance.client.auth.currentUser?.email;

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
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              widget.document.fileName ?? '',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            if (widget.document.fileSize != null) ...[
              SizedBox(height: 2),
              Text(
                '${(widget.document.fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            SizedBox(height: 16),

            // ── Open / Download buttons ──────────────────────────────────
            if (fileUrl != null)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (kIsWeb && !isIosWeb) {
                          openInNewTab(fileUrl);
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DocumentViewerScreen(
                                fileUrl: fileUrl,
                                fileName: widget.document.fileName,
                              ),
                            ),
                          );
                        }
                      },
                      child: Text("Open File"),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _downloadFile(fileUrl, fileName),
                      child: Text(isIosWeb ? "Share / Save" : "Download"),
                    ),
                  ),
                ],
              ),

            SizedBox(height: 16),
            Divider(),

            // ── Shared users ─────────────────────────────────────────────
            if (_shares.isNotEmpty) ...[
              Text(
                "Shared with:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              for (final share in _shares)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text("• ${share['email']}",overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 8),
                      _RoleBadge(role: share['role'] ?? 'viewer'),
                      if (isOwner) ...[
                        SizedBox(width: 4),
                        TextButton(
                          onPressed: () => removeAccess(share['email']!),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text("Remove",
                              style: TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                ),
            ],

            SizedBox(height: 12),

            // ── Share with user button (owner only) ──────────────────────
            if (isOwner)
              ElevatedButton.icon(
                onPressed: showShareDialog,
                icon: Icon(Icons.person_add),
                label: Text("Share with user"),
              ),

            SizedBox(height: 16),
            Text(
              "Document Content",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),

            // ── Parsed text ──────────────────────────────────────────────
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

    final url = "${AppConfig.baseUrl}/remove-share"
        "?document_id=${widget.document.id}"
        "&owner_email=$owner"
        "&remove_user=$userEmail";

    final response = await http.delete(Uri.parse(url));

    if (!mounted) return;
    if (response.statusCode == 200) {
      setState(() {
        sharedUsers.remove(userEmail);
        _shares.removeWhere((s) => s['email'] == userEmail);
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

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isEditor = role == 'editor';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isEditor
            ? Colors.orange.withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isEditor ? 'Editor' : 'Viewer',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isEditor ? Colors.orange.shade800 : Colors.grey.shade700,
        ),
      ),
    );
  }
}
