import 'package:flutter/material.dart';
import '../models/folder_model.dart';
import '../services/folder_service.dart';
import '../theme/app_theme.dart';

class MoveToFolderDialog extends StatefulWidget {
  final FolderService folderService;
  final String? excludeFolderId;

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final folders = await widget.folderService.fetchAllFolders();
      if (!mounted) return;

      final excludedIds = <String>{};
      if (widget.excludeFolderId != null) {
        _collectDescendants(widget.excludeFolderId!, folders, excludedIds);
      }

      setState(() {
        _allFolders =
            folders.where((f) => !excludedIds.contains(f.id)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _collectDescendants(
      String id, List<FolderModel> all, Set<String> out) {
    out.add(id);
    for (final f in all.where((f) => f.parentId == id)) {
      _collectDescendants(f.id, all, out);
    }
  }

  List<FolderModel> _childrenOf(String? parentId) {
    return _allFolders
        .where((f) => f.parentId == parentId)
        .toList()
      ..sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  bool _hasChildren(String folderId) =>
      _allFolders.any((f) => f.parentId == folderId);

  List<Widget> _buildTree(String? parentId, int depth) {
    final folders = _childrenOf(parentId);
    final rows = <Widget>[];

    for (final folder in folders) {
      final isExpanded = _expanded.contains(folder.id);
      final isSelected = _selected == folder.id;
      final hasKids = _hasChildren(folder.id);

      rows.add(
        Container(
          color: isSelected ? AppColors.accentBg : Colors.transparent,
          child: Row(
            children: [
              // ── Chevron zone (expand/collapse only) ──────────
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (!hasKids) return;
                  setState(() {
                    if (_expanded.contains(folder.id)) {
                      _expanded.remove(folder.id);
                    } else {
                      _expanded.add(folder.id);
                    }
                  });
                },
                child: SizedBox(
                  width: 20.0 + depth * 20.0 + 28,
                  height: 44,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: AnimatedRotation(
                        turns: isExpanded ? 0.25 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          // Always show chevron — gray if no children
                          color: hasKids
                              ? AppColors.textSecondary
                              : AppColors.bgSurface3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Folder name zone (select only) ────────────────
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selected = folder.id),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        Icon(
                          isExpanded
                              ? Icons.folder_open_outlined
                              : Icons.folder_outlined,
                          size: 17,
                          color: AppColors.accent,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            folder.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSelected)
                          Padding(
                            padding: EdgeInsets.only(right: 16),
                            child: Icon(Icons.check_rounded,
                                size: 16, color: AppColors.accent),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      // Divider
      rows.add(Divider(
          height: 0,
          thickness: 0.5,
          color: AppColors.border,
          indent: 16,
          endIndent: 16));

      // Children (inline, only when expanded)
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
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),

            // Title
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Move to folder',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
            ),

            Divider(
                height: 0, thickness: 0.5, color: AppColors.border),

            // Root option
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _selected = 'root'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                color: isRootSelected
                    ? AppColors.accentBg
                    : Colors.transparent,
                height: 44,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Spacer matching chevron width at depth 0
                    SizedBox(width: 32),
                    Icon(Icons.home_outlined,
                        size: 17,
                        color: isRootSelected
                            ? AppColors.accent
                            : AppColors.textTertiary),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Root (no folder)',
                        style: TextStyle(
                          fontSize: 13,
                          color: isRootSelected
                              ? AppColors.accent
                              : AppColors.textPrimary,
                          fontWeight: isRootSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (isRootSelected)
                      Icon(Icons.check_rounded,
                          size: 16, color: AppColors.accent),
                  ],
                ),
              ),
            ),

            Divider(
                height: 0, thickness: 0.5, color: AppColors.border),

            // Tree
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent, strokeWidth: 2))
                  : _error != null
                      ? Center(
                          child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                color: AppColors.dangerText,
                                size: 32),
                            SizedBox(height: 8),
                            Text(_error!,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textTertiary),
                                textAlign: TextAlign.center),
                            SizedBox(height: 10),
                            TextButton(
                                onPressed: _load,
                                child: Text('Retry')),
                          ],
                        ))
                      : _allFolders.isEmpty
                          ? Center(
                              child: Text('No folders yet',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textTertiary)),
                            )
                          : ListView(
                              controller: scrollController,
                              children: _buildTree(null, 0),
                            ),
            ),

            Divider(
                height: 0, thickness: 0.5, color: AppColors.border),

            // Buttons
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, null),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: AppColors.border),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                      ),
                      child: Text('Cancel',
                          style: TextStyle(
                              color: AppColors.textSecondary)),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selected == null
                          ? null
                          : () =>
                              Navigator.pop(context, _selected),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                      ),
                      child: Text('Move here'),
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