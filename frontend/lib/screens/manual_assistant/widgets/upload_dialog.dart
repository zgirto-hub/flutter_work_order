import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import '../../../services/manual_assistant_service.dart';

const _EXTENSION_MIME_MAP = {
  'pdf': 'application/pdf',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'txt': 'text/plain',
  'md': 'text/markdown',
};

class UploadDialog extends StatefulWidget {
  final ManualAssistantService service;

  const UploadDialog({super.key, required this.service});

  @override
  State<UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<UploadDialog> {
  final _titleController = TextEditingController();
  Uint8List? _fileBytes;
  String? _fileName;
  String? _fileExtension;
  bool _uploading = false;
  String? _error;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'txt', 'md'],
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      setState(() {
        _fileBytes = file.bytes;
        _fileName = file.name;
        _fileExtension = file.extension;
      });
    }
  }

  Future<void> _upload() async {
    if (_fileBytes == null || _fileName == null || _fileExtension == null) {
      setState(() => _error = 'Please select a file');
      return;
    }

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Please enter a title');
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final mimeType =
          _EXTENSION_MIME_MAP[_fileExtension] ?? 'application/octet-stream';

      final email =
          Supabase.instance.client.auth.currentUser?.email ?? '';
      final manual = await widget.service.uploadManual(
        title,
        _fileBytes!,
        _fileName!,
        mimeType,
        userEmail: email,
      );

      if (mounted) {
        Navigator.pop(context, manual);
      }
    } on ManualUploadException catch (e) {
      setState(() {
        _uploading = false;
        _error = _getErrorMessage(e.code);
      });
    } catch (e) {
      setState(() {
        _uploading = false;
        _error = 'An unexpected error occurred';
      });
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'file_too_large':
        return 'File is too large (max 20 MB)';
      case 'corpus_full':
        return 'The manual library is full. Delete an existing manual to make room.';
      case 'no_extractable_text':
        return 'No extractable text found in the file.';
      case 'unsupported_media_type':
        return 'Unsupported file type. Use PDF, DOCX, TXT, or MD.';
      case 'embedder_unavailable':
        return 'The embedding service is temporarily unavailable.';
      default:
        return 'An error occurred: $code';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload Manual'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _uploading ? null : _pickFile,
              icon: const Icon(Icons.attach_file),
              label: Text(_fileName ?? 'Select File'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Enter a title for the manual',
              ),
              enabled: !_uploading,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            if (_uploading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _uploading ? null : _upload,
          child: const Text('Upload'),
        ),
      ],
    );
  }
}
