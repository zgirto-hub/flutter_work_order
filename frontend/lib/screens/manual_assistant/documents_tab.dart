import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../config.dart';
import 'package:http/http.dart' as http;
import '../../services/document_service.dart';
import 'widgets/document_card.dart';
import 'document_chunk_editor.dart';

class DocumentsTab extends StatefulWidget {
  final String userEmail;

  const DocumentsTab({
    super.key,
    required this.userEmail,
  });

  @override
  State<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<DocumentsTab> {
  final DocumentService _documentService = DocumentService();
  List<Map<String, dynamic>> _documents = [];
  bool _loading = true;
  String? _error;
  bool _uploading = false;
  final Map<String, Timer> _statusPolling = {};

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  @override
  void dispose() {
    for (final timer in _statusPolling.values) {
      timer.cancel();
    }
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await _documentService.listDocuments(widget.userEmail);
      if (mounted) {
        setState(() {
          _documents = List<Map<String, dynamic>>.from(docs);
          _loading = false;
        });
        // Auto-poll any documents still processing (for all users, not just uploader)
        for (final doc in _documents) {
          final status = doc['status'] as String? ?? '';
          if (status == 'pending' ||
              status == 'preprocessing' ||
              status == 'indexing') {
            _startStatusPolling(doc['id']);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _handleUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read file')),
        );
      }
      return;
    }

    final displayNameController =
        TextEditingController(text: file.name.replaceAll('.pdf', ''));

    final displayName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: ${file.name}'),
            const SizedBox(height: 16),
            TextField(
              controller: displayNameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, displayNameController.text),
            child: const Text('Upload'),
          ),
        ],
      ),
    );

    if (displayName == null || displayName.isEmpty) return;

    setState(() => _uploading = true);

    try {
      final uploadResult = await _documentService.uploadDocument(
        filePath: file.path ?? '',
        fileName: file.name,
        fileBytes: file.bytes!.toList(),
        displayName: displayName,
        uploadedBy: widget.userEmail,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(uploadResult['message'] ?? 'Upload started')),
        );
      }

      _loadDocuments();
      _startStatusPolling(uploadResult['document_id']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  void _startStatusPolling(String documentId) {
    _statusPolling[documentId]?.cancel();
    _statusPolling[documentId] =
        Timer.periodic(const Duration(seconds: 3), (timer) async {
      // Guard: if timer was already cancelled by a concurrent callback, skip
      if (!_statusPolling.containsKey(documentId)) return;
      try {
        final status =
            await _documentService.getStatus(documentId, widget.userEmail);
        if (!mounted || !_statusPolling.containsKey(documentId)) {
          timer.cancel();
          return;
        }

        setState(() {
          final idx = _documents.indexWhere((d) => d['id'] == documentId);
          if (idx != -1) {
            _documents[idx] = {..._documents[idx], ...status};
          }
        });

        final docStatus = status['status'];
        if (docStatus == 'ready' || docStatus == 'failed') {
          timer.cancel();
          _statusPolling.remove(documentId);
          if (docStatus == 'ready' && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Document indexed successfully')),
            );
          } else if (docStatus == 'failed' && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Indexing failed: ${status['error_message'] ?? "Unknown error"}')),
            );
          }
        }
      } catch (e) {
        timer.cancel();
        _statusPolling.remove(documentId);
      }
    });
  }

  Future<void> _handleReindex(Map<String, dynamic> doc) async {
    try {
      final result =
          await _documentService.reindexDocument(doc['id'], widget.userEmail);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Re-indexing started')),
        );
      }
      _startStatusPolling(doc['id']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Re-index failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _handleDelete(Map<String, dynamic> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content:
            Text('Are you sure you want to delete "${doc['display_name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _documentService.deleteDocument(doc['id'], widget.userEmail);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document deleted')),
        );
        _loadDocuments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_uploading) {
      body = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Uploading document...'),
          ],
        ),
      );
    } else if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            TextButton(
              onPressed: _loadDocuments,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (_documents.isEmpty) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('No documents uploaded yet'),
            const SizedBox(height: 8),
            const Text(
              'Upload a PDF manual to expand the knowledge base.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    } else {
      body = ListView.builder(
        itemCount: _documents.length,
        itemBuilder: (context, index) {
          final doc = _documents[index];
          return DocumentCard(
            document: doc,
            onReindex: () => _handleReindex(doc),
            onDelete: () => _handleDelete(doc),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DocumentChunkEditor(
                    documentId: doc['id'],
                    displayName: doc['display_name'] ?? 'Document',
                    userEmail: widget.userEmail,
                  ),
                ),
              );
            },
          );
        },
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            _buildMigrationBanner(),
            Expanded(child: body),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _uploading ? null : _handleUpload,
            child: const Icon(Icons.upload_file),
          ),
        ),
      ],
    );
  }

  Widget _buildMigrationBanner() {
    return FutureBuilder<int>(
      future: _checkOldManuals(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final hasOldManuals = (snapshot.data ?? 0) > 0;
        if (!hasOldManuals) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.amber.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${snapshot.data} manuals in old Knowledge tab',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _startMigration,
                    child: const Text('Migrate All'),
                  ),
                  const SizedBox(width: 8),
                  if (_migrationStatus != null)
                    TextButton(
                      onPressed: _showMigrationStatus,
                      child: const Text('View Status'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<int> _checkOldManuals() async {
    try {
      final resp = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/count?user_email=${widget.userEmail}'),
      );
      if (resp.statusCode == 200) {
        return json.decode(resp.body)['count'] ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  Map<String, dynamic>? _migrationStatus;

  Future<void> _startMigration() async {
    try {
      final result = await _documentService.migrateAll(widget.userEmail);
      setState(() {
        _migrationStatus = result;
      });
      _pollMigrationStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Migration failed: $e')),
        );
      }
    }
  }

  void _pollMigrationStatus() {
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final status =
            await _documentService.getMigrationStatus(widget.userEmail);
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _migrationStatus = status;
        });
        if (status['status'] == 'completed') {
          timer.cancel();
          _showMigrationSummary(status);
        }
      } catch (_) {
        timer.cancel();
      }
    });
  }

  Future<void> _showMigrationStatus() async {
    if (_migrationStatus == null) return;

    final completed = _migrationStatus!['completed'] ?? 0;
    final total = _migrationStatus!['total'] ?? 0;
    final current = _migrationStatus!['current'] ?? '';
    final failed = _migrationStatus!['failed'] as List? ?? [];

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Migration Progress'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: total > 0 ? completed / total : 0),
            const SizedBox(height: 8),
            Text('Migrating: $completed of $total'),
            if (current.isNotEmpty) Text('Current: $current'),
            if (failed.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${failed.length} failed',
                  style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (_migrationStatus!['status'] == 'completed')
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showCleanupOption();
              },
              child: const Text('Cleanup'),
            ),
        ],
      ),
    );
  }

  void _showMigrationSummary(Map<String, dynamic> status) {
    final failed = status['failed'] as List? ?? [];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Migration Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total: ${status['total']}'),
            Text('Failed: ${failed.length}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (failed.isEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showCleanupOption();
              },
              child: const Text('Delete Old Data'),
            ),
        ],
      ),
    );
  }

  Future<void> _showCleanupOption() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Old Data'),
        content: const Text(
            'Delete all old Knowledge tab data? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _documentService.migrateCleanup(widget.userEmail);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Old data deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cleanup failed: $e')),
          );
        }
      }
    }
  }
}
