import 'package:flutter/material.dart';
import '../models/folder_model.dart';
import '../services/folder_service.dart';
import '../theme/app_theme.dart';

/// Returns null = cancelled, "root" = move to root, or a folder id string.
class MoveToFolderDialog extends StatefulWidget {
  final FolderService folderService;
  final String? excludeFolderId; // exclude this folder and its subtree (when moving a folder)

  const MoveToFolderDialog({
    super.key,
    required this.folderService,
    this.excludeFolderId,
  });

  static Future<String?> show(
    BuildContext context, {
    required FolderService folderService,
    String? excludeFolderId,
  }) {
    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => MoveToFolderDialog(
        folderService: folderService,
        excludeFolderId: excludeFolderId,
      ),
    );
  }

  @override
  State<MoveToFolderDialog> createState() => _MoveToFolderDialogState();
}

class _MoveToFolderDialogState extends State<MoveToFolderDialog> {
  List<FolderModel> _allFolders = [];
  final Set<String> _expanded = {};
  String? _selected;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final folders = await widget.folderService.fetchAllFolders();
      if (!mounted) return;
      setState(() {
        _allFolders = folders.where((f) => f.id != widget.excludeFolderId).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  /// Returns direct children of [parentId] from the already-fetched list.
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
      final isSelected = _selected == folder.id;
      final hasKids = _hasChildren(folder.id);

      rows.add(
        InkWell(
          onTap: () => setState(() => _selected = folder.id),
          child: Container(
            color: isSelected ? AppColors.accentBg : Colors.transparent,
            padding: EdgeInsets.only(
              left: 16.0 + depth * 16.0,
              right: 16,
              top: 10,
              bottom: 10,
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: hasKids ? () => _toggleExpand(folder.id) : null,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 16,
                      color: hasKids ? AppColors.textTertiary : Colors.transparent,
                    ),
                  ),
                ),
                const Icon(Icons.folder_outlined, size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder.name,
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected ? AppColors.accent : AppColors.textPrimary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (isExpanded) {
        rows.addAll(_buildTree(folder.id, depth + 1));
      }
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final isRootSelected = _selected == 'root';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (_, scrollController) {
        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),

            // Title
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Move to folder', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
            ),

            const Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // Root option
            InkWell(
              onTap: () => setState(() => _selected = 'root'),
              child: Container(
                color: isRootSelected ? AppColors.accentBg : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.home_outlined, size: 16, color: isRootSelected ? AppColors.accent : AppColors.textTertiary),
                    const SizedBox(width: 8),
                    Text(
                      'Root (no folder)',
                      style: TextStyle(
                        fontSize: 13,
                        color: isRootSelected ? AppColors.accent : AppColors.textPrimary,
                        fontWeight: isRootSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // Folder tree
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
                  : _error != null
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.error_outline, color: AppColors.dangerText, size: 32),
                            const SizedBox(height: 8),
                            Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary), textAlign: TextAlign.center),
                            const SizedBox(height: 10),
                            TextButton(onPressed: _load, child: const Text('Retry')),
                          ]),
                        )
                  : _allFolders.isEmpty
                      ? const Center(
                          child: Text('No folders yet', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                        )
                      : ListView(
                          controller: scrollController,
                          children: _buildTree(null, 0),
                        ),
            ),

            const Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // Action buttons
            Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, null),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Move here'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
