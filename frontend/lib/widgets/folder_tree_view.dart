import 'package:flutter/material.dart';
import '../models/folder_model.dart';
import '../services/folder_service.dart';
import '../theme/app_theme.dart';

class FolderTreeView extends StatefulWidget {
  final FolderService folderService;
  final void Function(FolderModel) onFolderTap;
  final void Function(FolderModel) onRename;
  final Future<void> Function(FolderModel) onDelete;
  final Future<void> Function(FolderModel) onMove;
  final int version;

  const FolderTreeView({
    super.key,
    required this.folderService,
    required this.onFolderTap,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
    this.version = 0,
  });

  @override
  State<FolderTreeView> createState() => _FolderTreeViewState();
}

class _FolderTreeViewState extends State<FolderTreeView> {
  List<FolderModel> _allFolders = [];
  final Set<String> _expanded = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FolderTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.version != widget.version) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final folders = await widget.folderService.fetchAllFolders();
      if (!mounted) return;
      setState(() { _allFolders = folders; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  List<FolderModel> _childrenOf(String? parentId) =>
      _allFolders.where((f) => f.parentId == parentId).toList();

  bool _hasChildren(String folderId) =>
      _allFolders.any((f) => f.parentId == folderId);

  void _toggleExpand(String folderId) {
    setState(() {
      if (_expanded.contains(folderId)) {
        _expanded.remove(folderId);
      } else {
        _expanded.add(folderId);
      }
    });
  }

  List<Widget> _buildTree(String? parentId, int depth) {
    final folders = _childrenOf(parentId);
    final rows = <Widget>[];

    for (final folder in folders) {
      final isExpanded = _expanded.contains(folder.id);
      final hasChildren = _hasChildren(folder.id);

      rows.add(_FolderTreeRow(
        folder: folder,
        depth: depth,
        isExpanded: isExpanded,
        isLoadingChildren: false,
        hasChildren: hasChildren,
        onExpandTap: () => _toggleExpand(folder.id),
        onFolderTap: () => widget.onFolderTap(folder),
        onLongPress: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: AppColors.bgSurface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (_) => _TreeFolderActionSheet(
              folder: folder,
              onRename: () { Navigator.pop(context); widget.onRename(folder); },
              onMove: () { Navigator.pop(context); widget.onMove(folder); },
              onDelete: () { Navigator.pop(context); widget.onDelete(folder); },
            ),
          );
        },
      ));

      if (isExpanded) {
        rows.addAll(_buildTree(folder.id, depth + 1));
      }
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2));
    }

    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 40, color: AppColors.dangerText),
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.textTertiary), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }

    if (_allFolders.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.account_tree_outlined, size: 48, color: AppColors.bgSurface3),
          const SizedBox(height: 10),
          const Text('No folders yet', style: TextStyle(fontSize: 14, color: AppColors.textTertiary)),
        ]),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 80),
      children: _buildTree(null, 0),
    );
  }
}

class _FolderTreeRow extends StatelessWidget {
  final FolderModel folder;
  final int depth;
  final bool isExpanded;
  final bool isLoadingChildren;
  final bool hasChildren;
  final VoidCallback onExpandTap;
  final VoidCallback onFolderTap;
  final VoidCallback onLongPress;

  const _FolderTreeRow({
    required this.folder,
    required this.depth,
    required this.isExpanded,
    required this.isLoadingChildren,
    required this.hasChildren,
    required this.onExpandTap,
    required this.onFolderTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onFolderTap,
      onLongPress: onLongPress,
      child: Container(
        padding: EdgeInsets.only(
          left: 8.0 + depth * 20.0,
          right: 16,
          top: 10,
          bottom: 10,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.4), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Expand/collapse arrow
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onExpandTap,
              child: SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: isLoadingChildren
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.accent),
                        )
                      : Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_right_rounded,
                          size: 18,
                          color: hasChildren ? AppColors.textSecondary : AppColors.bgSurface3,
                        ),
                ),
              ),
            ),

            // Folder icon
            Icon(
              isExpanded ? Icons.folder_open_outlined : Icons.folder_outlined,
              size: 17,
              color: AppColors.accent,
            ),
            const SizedBox(width: 10),

            // Name
            Expanded(
              child: Text(
                folder.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _TreeFolderActionSheet extends StatelessWidget {
  final FolderModel folder;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  const _TreeFolderActionSheet({
    required this.folder,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(folder.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          const Text('Folder', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          const SizedBox(height: 14),
          const Divider(height: 0, thickness: 0.5),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textPrimary),
            title: const Text('Rename', style: TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
            onTap: onRename,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.drive_file_move_outline, size: 18, color: AppColors.textPrimary),
            title: const Text('Move to folder', style: TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
            onTap: onMove,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.dangerText),
            title: const Text('Delete', style: TextStyle(fontSize: 13, color: AppColors.dangerText, fontWeight: FontWeight.w500)),
            onTap: onDelete,
          ),
          const Divider(height: 0, thickness: 0.5),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.close_rounded, size: 18, color: AppColors.textPrimary),
            title: const Text('Cancel', style: TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
