import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/file_model.dart';
import '../../models/department.dart';
import '../../services/department_service.dart';
import 'file_viewer_screen.dart';
import '../../config.dart';
import '../../services/download_helper.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../services/file_service.dart';

// Conditional import — dart:html only exists on web
import 'package:work_order/services/platform_ua.dart';

class FileDetailsScreen extends StatefulWidget {
  final FileModel document;
  final String searchQuery;

  const FileDetailsScreen({
    super.key,
    required this.document,
    required this.searchQuery,
  });

  @override
  State<FileDetailsScreen> createState() => _FileDetailsScreenState();
}

class _FileDetailsScreenState extends State<FileDetailsScreen> {

  bool get isIosWeb => kIsWeb && PlatformUA.isIos;

  // Email-only list used to filter available users in the share dialog
  List<String> sharedUsers = [];
  // Full share records with role info for display
  List<Map<String, String>> _shares = [];
  List<String> users = [];
  String _userRole = '';

  @override
  void initState() {
    super.initState();
    loadSharedUsers();
    loadUsers();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null) return;
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/user-role?email=${Uri.encodeComponent(email)}'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() => _userRole = (data['user_type'] ?? '').toString());
      }
    } catch (_) {}
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
              title: Text('Share File',
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
                            await shareFile(user, selectedRole);
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

  Future<void> shareFile(String email, String role) async {
    final owner =
        Supabase.instance.client.auth.currentUser?.email ?? "";

    final request = http.MultipartRequest(
      'POST',
      Uri.parse("${AppConfig.baseUrl}/share-file"),
    );

    request.fields['file_id'] = widget.document.id;
    request.fields['owner_email'] = owner;
    request.fields['share_with'] = email;
    request.fields['role'] = role;

    final response = await request.send();

    if (!mounted) return;
    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("File shared with $email as $role")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to share file")),
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
          "${AppConfig.baseUrl}/file-shares/${widget.document.id}"),
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
              widget.document.fileType,
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

            // ── Expiration date ──────────────────────────────────────────
            SizedBox(height: 12),
            _ExpirationRow(
              document: widget.document,
              isOwner: isOwner,
            ),

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
                              builder: (_) => FileViewerScreen(
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

            // ── Change department (admin only) ──────────────────
            if (_userRole == 'admin')
              ElevatedButton.icon(
                onPressed: () => _showChangeDepartmentDialog(context, widget.document),
                icon: Icon(Icons.business_outlined),
                label: Text("Change department"),
              ),

            SizedBox(height: 16),
            Text(
              "File Content",
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

  void _showChangeDepartmentDialog(BuildContext context, FileModel doc) {
    String? selectedDeptId = doc.departmentId;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.bgSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Change department',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FutureBuilder<List<Department>>(
                    future: DepartmentService().fetchDepartments(isActive: true),
                    builder: (_, snap) {
                      if (!snap.hasData) {
                        return const SizedBox(height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                      }
                      final depts = snap.data!;
                      return DropdownButtonFormField<String?>(
                        initialValue: selectedDeptId,
                        decoration: InputDecoration(
                          hintText: 'None (global)',
                          prefixIcon: Icon(Icons.business_outlined, size: 16),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('None (global)'),
                          ),
                          ...depts.map((d) => DropdownMenuItem<String?>(
                            value: d.id,
                            child: Text(d.name, overflow: TextOverflow.ellipsis),
                          )),
                        ],
                        onChanged: (v) => setDialogState(() => selectedDeptId = v),
                      );
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await FileService().updateFileDepartment(doc.id, selectedDeptId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Department updated'), behavior: SnackBarBehavior.floating),
                        );
                        Navigator.pop(context, true);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed: $e'), behavior: SnackBarBehavior.floating),
                        );
                      }
                    }
                  },
                  child: Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> removeAccess(String userEmail) async {
    final owner =
        Supabase.instance.client.auth.currentUser?.email ?? "";

    final url = "${AppConfig.baseUrl}/remove-share"
        "?file_id=${widget.document.id}"
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

class _ExpirationRow extends StatefulWidget {
  final FileModel document;
  final bool isOwner;

  const _ExpirationRow({required this.document, required this.isOwner});

  @override
  State<_ExpirationRow> createState() => _ExpirationRowState();
}

class _ExpirationRowState extends State<_ExpirationRow> {
  late DateTime? _expDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _expDate = widget.document.expirationDate;
  }

  bool get _isExpired => _expDate != null && _expDate!.isBefore(DateTime.now());
  bool get _isExpiringSoon =>
      _expDate != null &&
      !_isExpired &&
      _expDate!.isBefore(DateTime.now().add(const Duration(days: 7)));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    setState(() => _saving = true);
    try {
      await FileService().updateExpirationDate(widget.document.id, picked);
      if (mounted) setState(() { _expDate = picked; _saving = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update expiration: $e')),
        );
      }
    }
  }

  Future<void> _clearDate() async {
    setState(() => _saving = true);
    try {
      await FileService().updateExpirationDate(widget.document.id, null);
      if (mounted) setState(() { _expDate = null; _saving = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear expiration: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    final String statusText;

    if (_expDate == null) {
      statusColor = Colors.grey;
      statusText = 'No expiration date';
    } else if (_isExpired) {
      statusColor = Colors.red;
      statusText = 'Expired on ${_expDate!.day}/${_expDate!.month}/${_expDate!.year}';
    } else if (_isExpiringSoon) {
      statusColor = Colors.orange;
      statusText = 'Expiring soon: ${_expDate!.day}/${_expDate!.month}/${_expDate!.year}';
    } else {
      statusColor = Colors.green;
      statusText = 'Expires: ${_expDate!.day}/${_expDate!.month}/${_expDate!.year}';
    }

    return Row(
      children: [
        Icon(Icons.event_outlined, size: 16, color: statusColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            statusText,
            style: TextStyle(fontSize: 13, color: statusColor, fontWeight: FontWeight.w500),
          ),
        ),
        if (_saving)
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        else if (widget.isOwner) ...[
          IconButton(
            icon: Icon(Icons.edit_calendar_outlined, size: 18, color: Colors.grey.shade600),
            onPressed: _pickDate,
            tooltip: 'Set expiration date',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
          if (_expDate != null)
            IconButton(
              icon: Icon(Icons.clear_rounded, size: 18, color: Colors.grey.shade600),
              onPressed: _clearDate,
              tooltip: 'Remove expiration',
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
            ),
        ],
      ],
    );
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
