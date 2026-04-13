import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/manual.dart';
import '../../services/manual_assistant_service.dart';
import 'widgets/upload_dialog.dart';
import 'chunk_editor_screen.dart';

class ManualsTab extends StatefulWidget {
  final bool isAdmin;
  const ManualsTab({super.key, this.isAdmin = false});

  @override
  State<ManualsTab> createState() => _ManualsTabState();
}

class _ManualsTabState extends State<ManualsTab> {
  final ManualAssistantService _service = ManualAssistantService();
  List<Manual> _manuals = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadManuals();
  }

  Future<void> _loadManuals() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _service.listManuals();
      setState(() {
        _manuals = result['manuals'] as List<Manual>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openUploadDialog() async {
    final manual = await showDialog<Manual>(
      context: context,
      builder: (context) => UploadDialog(service: _service),
    );

    if (manual != null) {
      _loadManuals();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              onPressed: _openUploadDialog,
              child: const Icon(Icons.upload_file),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadManuals,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_manuals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Your library is empty.',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the upload button to add your first manual.',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadManuals,
      child: ListView.builder(
        itemCount: _manuals.length,
        itemBuilder: (context, index) {
          final manual = _manuals[index];
          final dateStr = DateFormat('MMM d, yyyy').format(manual.createdAt);
          final subtitle =
              '${manual.fileName} · ${manual.uploadedByName ?? "Unknown"} · $dateStr · ${manual.chunkCount} chunks';

          return ListTile(
            title: Text(manual.title),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
            trailing: widget.isAdmin
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _showDeleteDialog(manual),
                  )
                : null,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChunkEditorScreen(
                    manual: manual,
                    isAdmin: widget.isAdmin,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showDeleteDialog(Manual manual) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete manual?'),
        content: const Text(
            'This manual and its indexed chunks will be removed. This cannot be undone.'),
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

    if (confirmed == true) {
      try {
        final email = Supabase.instance.client.auth.currentUser?.email ?? '';
        await _service.deleteManual(manual.id, userEmail: email);
        _loadManuals();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Manual deleted')),
          );
        }
      } catch (e) {
        _loadManuals();
      }
    }
  }
}
