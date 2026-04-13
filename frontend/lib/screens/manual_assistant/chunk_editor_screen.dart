import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/manual.dart';
import '../../services/manual_assistant_service.dart';
import '../../theme/app_theme.dart';
import 'chunk_edit_screen.dart';
import 'widgets/chunk_card.dart';

class ChunkEditorScreen extends StatefulWidget {
  final Manual manual;

  const ChunkEditorScreen({super.key, required this.manual});

  @override
  State<ChunkEditorScreen> createState() => _ChunkEditorScreenState();
}

class _ChunkEditorScreenState extends State<ChunkEditorScreen> {
  final ManualAssistantService _service = ManualAssistantService();
  List<Map<String, dynamic>> _chunks = [];
  int _page = 1;
  int _totalPages = 1;
  int _totalChunks = 0;
  bool _loading = true;
  bool _selectionMode = false;
  Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadChunks(1);
  }

  Future<void> _loadChunks(int page) async {
    setState(() => _loading = true);

    try {
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';
      final result = await _service.listChunks(
        widget.manual.id,
        page: page,
        pageSize: 20,
        userEmail: email,
      );

      setState(() {
        _chunks = List<Map<String, dynamic>>.from(result['chunks'] ?? []);
        _totalChunks = result['total'] as int? ?? 0;
        _totalPages = result['total_pages'] as int? ?? 1;
        _page = result['page'] as int? ?? 1;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading chunks: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _deleteChunk(Map<String, dynamic> chunk) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete chunk?'),
        content: Text(
          'Delete chunk #${chunk['chunk_index']}? This cannot be undone.',
        ),
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
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';
      await _service.deleteChunk(widget.manual.id, chunk['id'] as String,
          userEmail: email);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chunk deleted')),
        );
      }

      int newPage = _page;
      if (_chunks.length == 1 && _page > 1) {
        newPage = _page - 1;
      }
      _loadChunks(newPage);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _mergeChunk(Map<String, dynamic> chunk) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge chunks?'),
        content: Text(
          'Merge chunk #${chunk['chunk_index']} with chunk #${(chunk['chunk_index'] as int) + 1}? '
          'The content of both chunks will be combined.',
        ),
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

    if (confirmed != true) return;

    try {
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';
      await _service.mergeChunk(widget.manual.id, chunk['id'] as String,
          userEmail: email);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chunks merged')),
        );
      }

      _loadChunks(_page);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _reEmbedAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-embed all chunks?'),
        content: const Text(
          'This will regenerate embeddings for all chunks. This may take a while for manuals with many chunks.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Re-embed'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';
      final result =
          await _service.reEmbedAll(widget.manual.id, userEmail: email);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Re-embedding ${result['chunk_count']} chunks...')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _bulkDelete() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete selected chunks?'),
        content: Text(
          'Delete ${_selectedIds.length} selected chunk(s)? This cannot be undone.',
        ),
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
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';
      await _service.bulkDeleteChunks(
        widget.manual.id,
        _selectedIds.toList(),
        userEmail: email,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted ${_selectedIds.length} chunks')),
        );
      }

      setState(() {
        _selectionMode = false;
        _selectedIds = {};
      });

      _loadChunks(_page);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedIds = {};
      }
    });
  }

  void _navigateToEdit(Map<String, dynamic> chunk) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChunkEditScreen(
          mode: ChunkEditMode.edit,
          manualId: widget.manual.id,
          chunk: chunk,
        ),
      ),
    ).then((result) {
      if (result == true) {
        _loadChunks(_page);
      }
    });
  }

  void _navigateToSplit(Map<String, dynamic> chunk) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChunkEditScreen(
          mode: ChunkEditMode.split,
          manualId: widget.manual.id,
          chunk: chunk,
        ),
      ),
    ).then((result) {
      if (result == true) {
        _loadChunks(_page);
      }
    });
  }

  void _navigateToAdd() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChunkEditScreen(
          mode: ChunkEditMode.add,
          manualId: widget.manual.id,
          totalChunks: _totalChunks,
        ),
      ),
    ).then((result) {
      if (result == true) {
        _loadChunks(_page);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.manual.title),
        actions: [
          IconButton(
            icon: Icon(_selectionMode ? Icons.close : Icons.checklist),
            onPressed: _toggleSelectionMode,
            tooltip: _selectionMode ? 'Cancel selection' : 'Select multiple',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _navigateToAdd,
            tooltip: 'Add chunk',
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _reEmbedAll,
            tooltip: 'Re-embed all',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.bgSurface2,
            child: Row(
              children: [
                Text(
                  '$_totalChunks chunks',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  'Page $_page of $_totalPages',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildBody(),
          ),
          if (_selectionMode && _selectedIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.dangerBg,
              child: Row(
                children: [
                  Text(
                    '${_selectedIds.length} selected',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: AppColors.dangerText,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _bulkDelete,
                    child: Text(
                      'Delete Selected',
                      style: TextStyle(color: AppColors.dangerText),
                    ),
                  ),
                ],
              ),
            )
          else if (_totalPages > 1)
            Container(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _page > 1 ? () => _loadChunks(_page - 1) : null,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Page $_page of $_totalPages',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _page < _totalPages
                        ? () => _loadChunks(_page + 1)
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_chunks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No chunks yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _navigateToAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add First Chunk'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadChunks(_page),
      child: ListView.builder(
        itemCount: _chunks.length,
        itemBuilder: (context, index) {
          final chunk = _chunks[index];
          final isLast = chunk['chunk_index'] == _totalChunks - 1;

          return ChunkCard(
            chunk: chunk,
            selectionMode: _selectionMode,
            selected: _selectedIds.contains(chunk['id']),
            isLast: isLast,
            onTap: () {
              if (_selectionMode) {
                setState(() {
                  if (_selectedIds.contains(chunk['id'])) {
                    _selectedIds.remove(chunk['id']);
                  } else {
                    _selectedIds.add(chunk['id'] as String);
                  }
                });
              } else {
                _navigateToEdit(chunk);
              }
            },
            onLongPress: () {
              if (!_selectionMode) {
                setState(() {
                  _selectionMode = true;
                  _selectedIds.add(chunk['id'] as String);
                });
              }
            },
            onEdit: () => _navigateToEdit(chunk),
            onDelete: () => _deleteChunk(chunk),
            onSplit: () => _navigateToSplit(chunk),
            onMerge: isLast ? null : () => _mergeChunk(chunk),
            onSelectChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedIds.add(chunk['id'] as String);
                } else {
                  _selectedIds.remove(chunk['id']);
                }
              });
            },
          );
        },
      ),
    );
  }
}
