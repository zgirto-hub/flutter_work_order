import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../services/document_service.dart';
import '../../config.dart';
import '../../theme/app_theme.dart';
import 'widgets/document_chunk_card.dart';

class DocumentChunkEditor extends StatefulWidget {
  final String documentId;
  final String displayName;
  final String userEmail;

  const DocumentChunkEditor({
    super.key,
    required this.documentId,
    required this.displayName,
    required this.userEmail,
  });

  @override
  State<DocumentChunkEditor> createState() => _DocumentChunkEditorState();
}

class _DocumentChunkEditorState extends State<DocumentChunkEditor> {
  final DocumentService _service = DocumentService();
  List<Map<String, dynamic>> _chunks = [];
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  String? _error;
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadChunks();
  }

  Future<void> _loadChunks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.listChunks(
        widget.documentId,
        widget.userEmail,
        page: _page,
      );
      setState(() {
        _chunks = List<Map<String, dynamic>>.from(result['chunks'] ?? []);
        _total = result['total'] as int? ?? 0;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _reEmbedAll() async {
    try {
      await _service.reEmbedAll(widget.documentId, widget.userEmail);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Re-embedding started')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Re-embed failed: $e')),
        );
      }
    }
  }

  Future<void> _editChunk(String chunkId, String currentContent) async {
    final controller = TextEditingController(text: currentContent);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Chunk'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Chunk content',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true) {
      try {
        await _service.updateChunk(
          widget.documentId,
          chunkId,
          controller.text,
          widget.userEmail,
        );
        _loadChunks();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Update failed: $e')),
          );
        }
      }
    }
  }

  Future<void> _splitChunk(String chunkId, String content) async {
    final positionController = TextEditingController();
    int? splitPos;
    bool confirmed = false;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Split Chunk'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              content.length > 300
                  ? '${content.substring(0, 300)}...'
                  : content,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: positionController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Split position (character index)',
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
          TextButton(
            onPressed: () {
              splitPos = int.tryParse(positionController.text);
              if (splitPos != null &&
                  splitPos! > 0 &&
                  splitPos! < content.length) {
                confirmed = true;
                Navigator.pop(context);
              }
            },
            child: const Text('Split'),
          ),
        ],
      ),
    );

    if (confirmed && splitPos != null) {
      try {
        await _service.splitChunk(
          widget.documentId,
          chunkId,
          splitPos!,
          widget.userEmail,
        );
        _loadChunks();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Split failed: $e')),
          );
        }
      }
    }
  }

  Future<void> _mergeChunk(String chunkId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge Chunk'),
        content: const Text(
            'Merge this chunk with the next sibling? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _service.mergeChunk(widget.documentId, chunkId, widget.userEmail);
        _loadChunks();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Merge failed: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteChunk(String chunkId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chunk'),
        content: const Text('Are you sure you want to delete this chunk?'),
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
        await _service.deleteChunk(
            widget.documentId, chunkId, widget.userEmail);
        _loadChunks();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }

  Future<void> _bulkDelete() async {
    if (_selectedIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected Chunks'),
        content: Text('Delete ${_selectedIds.length} selected chunks?'),
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
        await _service.bulkDeleteChunks(
          widget.documentId,
          _selectedIds.toList(),
          widget.userEmail,
        );
        setState(() {
          _selectedIds.clear();
          _selectionMode = false;
        });
        _loadChunks();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Bulk delete failed: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.displayName),
        actions: [
          IconButton(
            onPressed: _reEmbedAll,
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-embed All',
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _selectionMode = !_selectionMode;
                if (!_selectionMode) _selectedIds.clear();
              });
            },
            icon: Icon(_selectionMode ? Icons.close : Icons.checklist),
            tooltip: _selectionMode ? 'Cancel Selection' : 'Select',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadChunks,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Text(
                            '${_chunks.length} chunks',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const Spacer(),
                          if (_selectionMode && _selectedIds.isNotEmpty)
                            TextButton.icon(
                              onPressed: _bulkDelete,
                              icon: const Icon(Icons.delete, size: 18),
                              label: Text('Delete (${_selectedIds.length})'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _chunks.length,
                        itemBuilder: (context, index) {
                          final chunk = _chunks[index];
                          final chunkId = chunk['id'] as String;
                          final chunkType = chunk['chunk_type'] as String;
                          final isParent = chunkType == 'parent';
                          final isLast = index == _chunks.length - 1 ||
                              _chunks[index + 1]['chunk_type'] == 'parent';

                          return DocumentChunkCard(
                            chunk: chunk,
                            isParent: isParent,
                            onEdit: () =>
                                _editChunk(chunkId, chunk['content'] as String),
                            onDelete: () => _deleteChunk(chunkId),
                            onSplit: () => _splitChunk(
                                chunkId, chunk['content'] as String),
                            onMerge: (!isLast && !isParent)
                                ? () => _mergeChunk(chunkId)
                                : null,
                          );
                        },
                      ),
                    ),
                    if (_total > 20)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: _page > 1
                                  ? () {
                                      setState(() => _page--);
                                      _loadChunks();
                                    }
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text('Page $_page'),
                            IconButton(
                              onPressed: (_page * 20) < _total
                                  ? () {
                                      setState(() => _page++);
                                      _loadChunks();
                                    }
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}
