import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/manual_assistant_service.dart';
import '../../theme/app_theme.dart';

enum ChunkEditMode { edit, add, split }

class ChunkEditScreen extends StatefulWidget {
  final ChunkEditMode mode;
  final String manualId;
  final Map<String, dynamic>? chunk;
  final int? totalChunks;

  const ChunkEditScreen({
    super.key,
    required this.mode,
    required this.manualId,
    this.chunk,
    this.totalChunks,
  });

  @override
  State<ChunkEditScreen> createState() => _ChunkEditScreenState();
}

class _ChunkEditScreenState extends State<ChunkEditScreen> {
  final ManualAssistantService _service = ManualAssistantService();
  late TextEditingController _controller;
  bool _modified = false;
  bool _saving = false;
  int _insertAfter = -1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.chunk?['content'] as String? ?? '',
    );
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final original = widget.chunk?['content'] as String? ?? '';
    final nowModified = _controller.text != original;
    if (nowModified != _modified) {
      setState(() => _modified = nowModified);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.mode) {
      case ChunkEditMode.edit:
        return 'Edit Chunk #${widget.chunk?['chunk_index'] ?? 0}';
      case ChunkEditMode.add:
        return 'Add Chunk';
      case ChunkEditMode.split:
        return 'Split Chunk #${widget.chunk?['chunk_index'] ?? 0}';
    }
  }

  bool get _canSave {
    if (_saving) return false;
    if (_controller.text.trim().isEmpty) return false;
    if (widget.mode == ChunkEditMode.split) {
      final pos = _controller.selection.baseOffset;
      return pos > 0 && pos < _controller.text.length;
    }
    return _modified;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    try {
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';
      final content = _controller.text.trim();

      if (widget.mode == ChunkEditMode.edit) {
        await _service.updateChunk(
          widget.manualId,
          widget.chunk!['id'] as String,
          content,
          userEmail: email,
        );
      } else if (widget.mode == ChunkEditMode.add) {
        await _service.addChunk(
          widget.manualId,
          content,
          insertAfter: _insertAfter,
          userEmail: email,
        );
      } else if (widget.mode == ChunkEditMode.split) {
        final splitPos = _controller.selection.baseOffset;
        await _service.splitChunk(
          widget.manualId,
          widget.chunk!['id'] as String,
          splitPos,
          userEmail: email,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chunk saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_modified) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
            'You have unsaved changes. Are you sure you want to discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final chunkIndex = widget.chunk?['chunk_index'] as int?;
    final sourcePage = widget.chunk?['source_page'] as int?;

    return PopScope(
      canPop: !_modified,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          actions: [
            if (_saving)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              TextButton(
                onPressed: _canSave ? _save : null,
                child: const Text('Save'),
              ),
          ],
        ),
        body: Column(
          children: [
            if (widget.mode == ChunkEditMode.edit ||
                widget.mode == ChunkEditMode.split)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: AppColors.bgSurface2,
                child: Row(
                  children: [
                    if (chunkIndex != null) ...[
                      _MetadataChip(label: '#$chunkIndex'),
                      const SizedBox(width: 8),
                    ],
                    if (sourcePage != null) ...[
                      _MetadataChip(label: 'Page $sourcePage'),
                      const SizedBox(width: 8),
                    ],
                    _MetadataChip(label: '${_controller.text.length} chars'),
                  ],
                ),
              ),
            if (widget.mode == ChunkEditMode.add)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: AppColors.bgSurface2,
                child: Row(
                  children: [
                    const Text('Insert after chunk #'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _insertAfter,
                      items: [
                        const DropdownMenuItem(value: -1, child: Text('End')),
                        for (int i = 0; i < (widget.totalChunks ?? 0); i++)
                          DropdownMenuItem(value: i, child: Text('$i')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _insertAfter = value ?? -1;
                          _modified = true;
                        });
                      },
                    ),
                  ],
                ),
              ),
            if (widget.mode == ChunkEditMode.split)
              Container(
                padding: const EdgeInsets.all(12),
                color: AppColors.accentBg,
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tap in the text where you want to split, then press Save',
                        style: TextStyle(fontSize: 12, color: AppColors.accent),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 14, height: 1.5),
                decoration: const InputDecoration(
                  hintText: 'Enter chunk content...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  final String label;

  const _MetadataChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgSurface3,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
