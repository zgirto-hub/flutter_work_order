import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../../config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';

class AddDocumentScreen extends StatefulWidget {
  const AddDocumentScreen({super.key});

  @override
  State<AddDocumentScreen> createState() => _AddDocumentScreenState();
}

class _AddDocumentScreenState extends State<AddDocumentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _typeController = TextEditingController();

  bool isPrivate = false;
  bool _isLoading = false;

  // Single file mode
  PlatformFile? _selectedFile;

  // Multi file mode
  List<PlatformFile> _selectedFiles = [];
  int _uploadIndex = 0;
  int _totalUploads = 0;

  // Track which mode the user is in
  bool _isMultiMode = false;

  @override
  void dispose() {
    _titleController.dispose();
    _typeController.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────

  String _detectType(String filename) {
    final name = filename.toLowerCase();
    if (name.contains('invoice')) return 'Invoice';
    if (name.contains('drawing') || name.contains('plan')) return 'Drawing';
    if (name.contains('report')) return 'Report';
    if (name.contains('contract')) return 'Contract';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png')) return 'Image';
    return 'General';
  }

  String _extractTitle(String filename) {
    return filename.split('.').first.replaceAll('_', ' ').replaceAll('-', ' ');
  }

  String get _userEmail =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  // ── Single file pick ──────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'jpg', 'jpeg', 'png'],
      withData: kIsWeb,
    );
    if (result != null) {
      final file = result.files.single;
      setState(() {
        _isMultiMode = false;
        _selectedFiles = [];
        _selectedFile = file;
        _titleController.text = _extractTitle(file.name);
        _typeController.text = _detectType(file.name);
      });
    }
  }

  // ── Multi file pick ───────────────────────────────────────

  Future<void> _pickMultipleFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'jpg', 'jpeg', 'png'],
      withData: kIsWeb,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _isMultiMode = true;
        _selectedFile = null;
        _selectedFiles = result.files;
        // Auto-fill type from first file
        _typeController.text = _detectType(result.files.first.name);
        _titleController.text = '';
      });
    }
  }

  // ── Upload single ─────────────────────────────────────────

  Future<void> _uploadSingle() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFile == null) {
      _showSnack('Please select a file first');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/upload'),
      );

      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes(
          'file', _selectedFile!.bytes!,
          filename: _selectedFile!.name,
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath(
          'file', _selectedFile!.path!,
          filename: _selectedFile!.name,
        ));
      }

      request.fields['title'] = _titleController.text.trim();
      request.fields['document_type'] = _typeController.text.trim();
      request.fields['is_private'] = isPrivate ? '1' : '0';
      request.fields['uploaded_by'] = _userEmail;

      final response = await request.send();

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        Navigator.pop(context, true);
      } else {
        _showSnack('Upload failed (${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('Upload error: $e');
    }
  }

  // ── Upload multiple ───────────────────────────────────────

  Future<void> _uploadMultiple() async {
    if (_selectedFiles.isEmpty) {
      _showSnack('Please select files first');
      return;
    }
    if (_typeController.text.trim().isEmpty) {
      _showSnack('Please enter a document type');
      return;
    }

    setState(() {
      _isLoading = true;
      _uploadIndex = 0;
      _totalUploads = _selectedFiles.length;
    });

    int successCount = 0;

    for (final file in _selectedFiles) {
      setState(() => _uploadIndex++);

      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${AppConfig.baseUrl}/upload'),
        );

        if (kIsWeb) {
          request.files.add(http.MultipartFile.fromBytes(
            'file', file.bytes!,
            filename: file.name,
          ));
        } else {
          request.files.add(await http.MultipartFile.fromPath(
            'file', file.path!,
            filename: file.name,
          ));
        }

        // For multi-upload: use filename as title, shared document_type
        request.fields['title'] = _titleController.text.trim().isNotEmpty
            ? '${_titleController.text.trim()} (${file.name})'
            : _extractTitle(file.name);
        request.fields['document_type'] = _typeController.text.trim();
        request.fields['is_private'] = isPrivate ? '1' : '0';
        request.fields['uploaded_by'] = _userEmail;

        final response = await request.send();
        if (response.statusCode == 200) successCount++;

      } catch (e) {
        debugPrint('Failed to upload ${file.name}: $e');
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (successCount == _selectedFiles.length) {
      Navigator.pop(context, true);
    } else {
      _showSnack('$successCount/${_selectedFiles.length} files uploaded');
      if (successCount > 0) Navigator.pop(context, true);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Drag handle ──────────────────────────────
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface3,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              const Center(
                child: Text('Upload Document',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),

              const SizedBox(height: 20),

              // ── Title ────────────────────────────────────
              _Label('Title'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _titleController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: _isMultiMode ? 'Optional prefix for all files' : 'Document title',
                  prefixIcon: const Icon(Icons.title_rounded, size: 16),
                ),
                validator: _isMultiMode
                    ? null // title optional in multi mode
                    : (v) => v == null || v.isEmpty ? 'Enter a title' : null,
              ),

              const SizedBox(height: 14),

              // ── Document type ────────────────────────────
              _Label('Document type'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _typeController,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'e.g. Invoice, Report, Drawing…',
                  prefixIcon: Icon(Icons.category_outlined, size: 16),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Enter a document type' : null,
              ),

              const SizedBox(height: 14),

              // ── Private toggle ───────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: SwitchListTile(
                  dense: true,
                  title: const Text('Private document', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  subtitle: const Text('Only you can see this', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                  value: isPrivate,
                  activeColor: AppColors.accent,
                  onChanged: (v) => setState(() => isPrivate = v),
                ),
              ),

              const SizedBox(height: 20),

              // ── File selection area ───────────────────────
              _Label('File'),
              const SizedBox(height: 8),

              // Single file picker
              GestureDetector(
                onTap: _isLoading ? null : _pickFile,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _selectedFile != null && !_isMultiMode
                        ? AppColors.closedBg
                        : AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedFile != null && !_isMultiMode
                          ? AppColors.closedText.withOpacity(0.3)
                          : AppColors.border2,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedFile != null && !_isMultiMode
                            ? Icons.insert_drive_file_rounded
                            : Icons.attach_file_rounded,
                        size: 18,
                        color: _selectedFile != null && !_isMultiMode
                            ? AppColors.closedText
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedFile != null && !_isMultiMode
                              ? _selectedFile!.name
                              : 'Select a single file',
                          style: TextStyle(
                            fontSize: 13,
                            color: _selectedFile != null && !_isMultiMode
                                ? AppColors.closedText
                                : AppColors.textTertiary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Multi file picker
              GestureDetector(
                onTap: _isLoading ? null : _pickMultipleFiles,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isMultiMode && _selectedFiles.isNotEmpty
                        ? AppColors.inProgressBg
                        : AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isMultiMode && _selectedFiles.isNotEmpty
                          ? AppColors.inProgressText.withOpacity(0.3)
                          : AppColors.border2,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.file_copy_outlined,
                        size: 18,
                        color: _isMultiMode && _selectedFiles.isNotEmpty
                            ? AppColors.inProgressText
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _isMultiMode && _selectedFiles.isNotEmpty
                              ? '${_selectedFiles.length} file(s) selected'
                              : 'Select multiple files',
                          style: TextStyle(
                            fontSize: 13,
                            color: _isMultiMode && _selectedFiles.isNotEmpty
                                ? AppColors.inProgressText
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                      if (_isMultiMode && _selectedFiles.isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(() { _selectedFiles = []; _isMultiMode = false; }),
                          child: const Icon(Icons.close_rounded, size: 16, color: AppColors.inProgressText),
                        ),
                    ],
                  ),
                ),
              ),

              // Show selected file names in multi mode
              if (_isMultiMode && _selectedFiles.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _selectedFiles.map((f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file_outlined, size: 12, color: AppColors.textTertiary),
                          const SizedBox(width: 6),
                          Expanded(child: Text(f.name, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ],

              // Upload progress
              if (_isLoading && _totalUploads > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _uploadIndex / _totalUploads,
                          backgroundColor: AppColors.bgSurface3,
                          valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('$_uploadIndex / $_totalUploads', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                  ],
                ),
              ],

              const SizedBox(height: 20),

              // ── Upload buttons ───────────────────────────
              if (!_isMultiMode) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _uploadSingle,
                    icon: _isLoading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload_rounded, size: 16),
                    label: Text(_isLoading ? 'Uploading…' : 'Upload document'),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _uploadMultiple,
                    icon: _isLoading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload_rounded, size: 16),
                    label: Text(_isLoading
                        ? 'Uploading $_uploadIndex of $_totalUploads…'
                        : 'Upload ${_selectedFiles.length} file(s)'),
                  ),
                ),
              ],

              const SizedBox(height: 8),

            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary));
  }
}
