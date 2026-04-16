import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/document_service.dart';
import 'widgets/document_card.dart';

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
      try {
        final status =
            await _documentService.getStatus(documentId, widget.userEmail);
        if (!mounted) {
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
          );
        },
      );
    }

    return Stack(
      children: [
        body,
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
}
