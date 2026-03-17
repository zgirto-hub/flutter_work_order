import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/request_model.dart';
import '../../services/request_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';

// ── Pending attachment (before upload) ────────────────────────────────────────

class _PendingAttachment {
  final String name;
  final Uint8List bytes;

  const _PendingAttachment({required this.name, required this.bytes});

  bool get isImage {
    final ext = name.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AddRequestScreen extends StatefulWidget {
  final RequestModel? request; // null = create, non-null = edit
  const AddRequestScreen({super.key, this.request});

  @override
  State<AddRequestScreen> createState() => _AddRequestScreenState();
}

class _AddRequestScreenState extends State<AddRequestScreen> {
  final _service = RequestService();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  bool _loading = false;

  // Attachments
  final List<_PendingAttachment> _pendingAttachments = [];
  final List<Map<String, dynamic>> _existingAttachments = [];
  final Set<String> _removedAttachmentIds = {};

  bool get _isEditing => widget.request != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _titleCtrl.text = widget.request!.title;
      _descCtrl.text = widget.request!.description;
      _nameCtrl.text = widget.request!.requesterName;
      _locationCtrl.text = widget.request!.location;
      _loadExistingAttachments();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExistingAttachments() async {
    try {
      final list = await _service.fetchAttachments(widget.request!.id);
      if (mounted) setState(() => _existingAttachments.addAll(list));
    } catch (_) {}
  }

  // ── Attachment picker ──────────────────────────────────────────────────────

  Future<void> _showAttachmentPicker() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (!kIsWeb)
                _PickerOption(
                  icon: Icons.camera_alt_outlined,
                  label: 'Take Photo',
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickFromCamera();
                  },
                ),
              _PickerOption(
                icon: Icons.photo_library_outlined,
                label: 'Photo Library',
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromGallery();
                },
              ),
              _PickerOption(
                icon: Icons.attach_file_rounded,
                label: 'Choose File',
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      final name = xfile.name.isNotEmpty ? xfile.name : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      setState(() => _pendingAttachments.add(_PendingAttachment(name: name, bytes: bytes)));
    } catch (e) {
      _showError('Camera error: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      final name = xfile.name.isNotEmpty ? xfile.name : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      setState(() => _pendingAttachments.add(_PendingAttachment(name: name, bytes: bytes)));
    } catch (e) {
      _showError('Gallery error: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final pf = result.files.first;
      final bytes = pf.bytes;
      if (bytes == null) return;
      setState(() => _pendingAttachments.add(_PendingAttachment(name: pf.name, bytes: bytes)));
    } catch (e) {
      _showError('File picker error: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.dangerText,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (title.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Title and your name are required'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';

      String requestId;
      if (_isEditing) {
        await _service.updateRequest(
          id: widget.request!.id,
          title: title,
          description: _descCtrl.text.trim(),
          requesterName: name,
          location: _locationCtrl.text.trim(),
          email: email,
        );
        requestId = widget.request!.id;

        // Delete removed existing attachments
        for (final id in _removedAttachmentIds) {
          try {
            await _service.deleteAttachment(
              requestId: requestId,
              attachmentId: id,
              email: email,
            );
          } catch (_) {}
        }
      } else {
        requestId = await _service.createRequest(
          title: title,
          description: _descCtrl.text.trim(),
          createdBy: email,
          requesterName: name,
          location: _locationCtrl.text.trim(),
        );
      }

      // Upload pending attachments
      for (final att in _pendingAttachments) {
        try {
          await _service.uploadAttachment(
            requestId: requestId,
            uploadedBy: email,
            fileName: att.name,
            bytes: att.bytes,
          );
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to ${_isEditing ? 'update' : 'submit'}: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface2,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: AppColors.border2, width: 0.5),
                      ),
                      child: Icon(Icons.arrow_back_rounded,
                          size: 16, color: AppColors.textSecondary),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    _isEditing ? 'Edit Request' : 'New Request',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // ── Form ──────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionLabel(text: 'Request details'),
                    SurfaceCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _Field(
                            label: 'Title',
                            hint: 'Brief description of the issue',
                            controller: _titleCtrl,
                            showDivider: true,
                          ),
                          _Field(
                            label: 'Description',
                            hint: 'Provide more details (optional)',
                            controller: _descCtrl,
                            maxLines: 4,
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 12),

                    SectionLabel(text: 'Your info'),
                    SurfaceCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _Field(
                            label: 'Your name',
                            hint: 'Full name',
                            controller: _nameCtrl,
                            showDivider: true,
                          ),
                          _Field(
                            label: 'Location',
                            hint: 'Room, floor, or area (optional)',
                            controller: _locationCtrl,
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 12),

                    // ── Attachments ────────────────────────────────
                    _buildAttachmentsSection(),

                    SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: _loading
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _isEditing ? 'Save Changes' : 'Submit Request',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsSection() {
    final visibleExisting = _existingAttachments
        .where((a) => !_removedAttachmentIds.contains(a['id']))
        .toList();
    final hasItems = visibleExisting.isNotEmpty || _pendingAttachments.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(text: 'Attachments'),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              // Existing attachments (edit mode)
              for (int i = 0; i < _existingAttachments.length; i++)
                if (!_removedAttachmentIds.contains(_existingAttachments[i]['id']))
                  _ExistingAttachmentRow(
                    attachment: _existingAttachments[i],
                    onRemove: () => setState(() =>
                        _removedAttachmentIds.add(_existingAttachments[i]['id'] as String)),
                  ),

              // Pending attachments
              for (int i = 0; i < _pendingAttachments.length; i++)
                _PendingAttachmentRow(
                  attachment: _pendingAttachments[i],
                  onRemove: () => setState(() => _pendingAttachments.removeAt(i)),
                ),

              // Divider before Add button only when items exist
              if (hasItems)
                Divider(height: 0, thickness: 0.5, color: AppColors.border),

              // Add attachment button
              InkWell(
                onTap: _showAttachmentPicker,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: const [
                      Icon(Icons.add_circle_outline_rounded, size: 16, color: AppColors.accent),
                      SizedBox(width: 8),
                      Text(
                        'Add photo or file',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Attachment row widgets ─────────────────────────────────────────────────────

class _ExistingAttachmentRow extends StatelessWidget {
  final Map<String, dynamic> attachment;
  final VoidCallback onRemove;

  const _ExistingAttachmentRow({
    required this.attachment,
    required this.onRemove,
  });

  bool get _isImage {
    final ext = (attachment['file_name'] as String? ?? '').split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  @override
  Widget build(BuildContext context) {
    final fileName = attachment['file_name'] as String? ?? 'file';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.bgSurface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
              size: 15,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              fileName,
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 16, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _PendingAttachmentRow extends StatelessWidget {
  final _PendingAttachment attachment;
  final VoidCallback onRemove;

  const _PendingAttachmentRow({
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.bgSurface2,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: attachment.isImage
                ? Image.memory(attachment.bytes, fit: BoxFit.cover)
                : Icon(Icons.insert_drive_file_outlined,
                    size: 15, color: AppColors.textSecondary),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatBytes(attachment.bytes.length),
                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 16, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _PickerOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.bgSurface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppColors.textSecondary),
            ),
            SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Field ──────────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final int maxLines;
  final bool showDivider;

  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.maxLines = 1,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textTertiary,
          ),
        ),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13, color: AppColors.textTertiary),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
          ),
        ),
        if (showDivider)
          Divider(height: 12, thickness: 0.5, color: AppColors.border),
      ],
    );
  }
}
