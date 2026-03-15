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
  // null key = root level
  final Map<String?, List<FolderModel>> _cache = {};
  final Set<String> _expanded = {};
  final Set<String> _loading = {};

  // "root" sentinel or a folder id
  String? _selected;
  bool _initialLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLevel(null);
  }

  Future<void> _loadLevel(String? parentId) async {
    if (_cache.containsKey(parentId)) return;
    setState(() => _loading.add(parentId ?? '_root_'));
    try {
      final folders = await widget.folderService.fetchFolders(parentId: parentId);
      if (!mounted) return;
      setState(() {
        _cache[parentId] = folders
            .where((f) => f.id != widget.excludeFolderId)
            .toList();
        _loading.remove(parentId ?? '_root_');
        if (parentId == null) _initialLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cache[parentId] = [];
        _loading.remove(parentId ?? '_root_');
        if (parentId == null) _initialLoading = false;
      });
    }
  }

  void _toggleExpand(String folderId) {
    setState(() {
      if (_expanded.contains(folderId)) {
        _expanded.remove(folderId);
      } else {
        _expanded.add(folderId);
        _loadLevel(folderId);
      }
    });
  }

  List<Widget> _buildTree(String? parentId, int depth) {
    final folders = _cache[parentId] ?? [];
    final rows = <Widget>[];

    for (final folder in folders) {
      final isExpanded = _expanded.contains(folder.id);
      final isLoadingChildren = _loading.contains(folder.id);
      final isSelected = _selected == folder.id;

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
                  onTap: () => _toggleExpand(folder.id),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: isLoadingChildren
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.accent),
                          )
                        : Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.keyboard_arrow_right_rounded,
                            size: 16,
                            color: AppColors.textTertiary,
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

      if (isExpanded && _cache.containsKey(folder.id)) {
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
              child: _initialLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
                  : (_cache[null] ?? []).isEmpty
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
