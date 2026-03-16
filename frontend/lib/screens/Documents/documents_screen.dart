import 'dart:async';
import 'package:flutter/material.dart';
import '../../controllers/filter_controller.dart';
import '../../filters/document_filter_engine.dart';
import '../../models/document.dart';
import '../../models/folder_model.dart';
import '../../services/document_service.dart';
import '../../services/folder_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import '../../widgets/move_to_folder_dialog.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/deleting_overlay.dart';
import '../Documents/add_document_screen.dart';
import '../Documents/document_details_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  // Static cache — survives route pop/push so the screen doesn't spinner on re-entry
  static List<DocumentModel>? _docCache;
  static List<FolderModel>? _folderCache;

  List<DocumentModel> _allDocuments = [];
  List<FolderModel> _allFolders = [];
  final Set<String> _expandedFolderIds = {};

  final FilterController _filter = FilterController();
  final DocumentService _service = DocumentService();
  final FolderService _folderService = FolderService();
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _selectedDocs = {};
  Timer? _debounce;
  bool _selectionMode = false;

  bool _isDeleting = false;
  int _deleteProgress = 0;
  int _deleteTotal = 0;
  bool _fabExpanded = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (_docCache != null && _folderCache != null) {
      // Show cached data immediately, no spinner, then silently refresh
      _allDocuments = _docCache!;
      _allFolders = _folderCache!;
      _loading = false;
      _refresh(silent: true);
    } else {
      _refresh();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final docs = await _service.fetchDocuments();
      final folders = await _folderService.fetchAllFolders();
      if (!mounted) return;
      _docCache = docs;
      _folderCache = folders;
      setState(() {
        _allDocuments = docs;
        _allFolders = folders;
        _loading = false;
        _selectedDocs.removeWhere((id) => !_allDocuments.any((d) => d.id == id));
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to load: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Set<String> _collectDescendantIds(String folderId) {
    final ids = <String>{folderId};
    for (final f in _allFolders.where((f) => f.parentId == folderId)) {
      ids.addAll(_collectDescendantIds(f.id));
    }
    return ids;
  }

  List<FolderModel> _childFolders(String? parentId) {
    return _allFolders
        .where((f) => f.parentId == parentId)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<DocumentModel> _docsInFolder(String? folderId) {
    return _allDocuments.where((d) => d.folderId == folderId).toList();
  }

  List<String> get _docTypes {
    final types = _allDocuments.map((d) => d.documentType).toSet().toList()
      ..sort();
    return ['All', ...types];
  }

  Widget _highlight(String text, String query, {int maxLines = 2}) {
    if (query.isEmpty)
      return Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    final lText = text.toLowerCase(), lQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final idx = lText.indexOf(lQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(
            backgroundColor: Color(0xFFFEF08A), fontWeight: FontWeight.w500),
      ));
      start = idx + query.length;
    }
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
          style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              height: 1.4),
          children: spans),
    );
  }

  Future<void> _deleteSelected() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDialog(
        title: 'Delete ${_selectedDocs.length} document(s)?',
        message: 'This action cannot be undone.',
        confirmLabel: 'Delete',
      ),
    );
    if (confirm != true) return;

    final ids = _selectedDocs.toList();
    setState(() {
      _isDeleting = true;
      _deleteProgress = 0;
      _deleteTotal = ids.length;
    });

    final deletedIds = <String>{};
    int blocked = 0;
    for (final id in ids) {
      try {
        await _service.deleteDocument(id);
        deletedIds.add(id);
      } catch (_) {
        blocked++;
      }
      if (mounted) setState(() => _deleteProgress++);
    }

    if (!mounted) return;
    setState(() {
      _isDeleting = false;
      _deleteProgress = 0;
      _deleteTotal = 0;
      _selectionMode = false;
      _allDocuments.removeWhere((d) => deletedIds.contains(d.id));
      _selectedDocs.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(blocked == 0
          ? '${deletedIds.length} document(s) deleted'
          : '${deletedIds.length} deleted, $blocked skipped (not owner)'),
      behavior: SnackBarBehavior.floating,
      backgroundColor:
          blocked == 0 ? AppColors.closedText : AppColors.pendingText,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showRename(DocumentModel doc) {
    final ctrl = TextEditingController(text: doc.title);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Rename document',
            style:
                TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(labelText: 'Title')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await _service.renameDocument(doc.id, ctrl.text);
              if (!mounted) return;
              Navigator.pop(context);
              _refresh();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showEditType(DocumentModel doc) {
    final ctrl = TextEditingController(text: doc.documentType);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Edit document type',
            style:
                TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 13),
            decoration:
                const InputDecoration(labelText: 'Document type')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await _service.updateDocumentType(doc.id, ctrl.text);
              if (!mounted) return;
              Navigator.pop(context);
              _refresh();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDoc(DocumentModel doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDialog(
          title: 'Delete "${doc.title}"?',
          message: 'This action cannot be undone.',
          confirmLabel: 'Delete'),
    );
    if (confirm != true) return;
    try {
      await _service.deleteDocument(doc.id);
      if (!mounted) return;
      setState(() => _allDocuments.removeWhere((d) => d.id == doc.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _showMoveDocDialog(DocumentModel doc) async {
    final result = await MoveToFolderDialog.show(context,
        folderService: _folderService);
    if (result == null || !mounted) return;
    try {
      await _folderService.moveDocument(doc.id,
          folderId: result == 'root' ? null : result);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating));
    }
  }

  void _showCreateFolderDialog({String? parentId}) {
    final ctrl = TextEditingController();
    bool isPrivate = false;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final name = ctrl.text.trim();
          final siblings = _childFolders(parentId);
          final duplicate = siblings.any(
              (f) => f.name.toLowerCase() == name.toLowerCase());
          return AlertDialog(
            backgroundColor: AppColors.bgSurface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            title: const Text('New folder',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 13),
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Folder name',
                    errorText: duplicate
                        ? 'A folder with this name already exists'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.border, width: 0.5),
                  ),
                  child: SwitchListTile(
                    dense: true,
                    title: const Text('Private folder',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary)),
                    subtitle: const Text('Only you can see this',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary)),
                    value: isPrivate,
                    activeThumbColor: AppColors.accent,
                    onChanged: (v) =>
                        setDialogState(() => isPrivate = v),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: duplicate
                    ? null
                    : () async {
                        final n = ctrl.text.trim();
                        if (n.isEmpty) return;
                        try {
                          final newFolder = await _folderService.createFolder(
                              name: n, parentId: parentId, isPrivate: isPrivate);
                          if (!mounted) return;
                          Navigator.pop(context);
                          setState(() {
                            _allFolders = [..._allFolders, newFolder];
                            if (parentId != null) {
                              _expandedFolderIds.add(parentId);
                            }
                          });
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(
                            content: Text('Failed: $e'),
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRenameFolder(FolderModel folder) {
    final ctrl = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Rename folder',
            style:
                TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 13),
            decoration:
                const InputDecoration(labelText: 'Folder name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final n = ctrl.text.trim();
              if (n.isEmpty) return;
              await _folderService.renameFolder(folder.id, n);
              if (!mounted) return;
              Navigator.pop(context);
              _refresh();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFolderConfirm(FolderModel folder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDialog(
        title: 'Delete "${folder.name}"?',
        message:
            'Documents inside will be moved to root. Sub-folders will be deleted.',
        confirmLabel: 'Delete',
      ),
    );
    if (confirm != true) return;
    try {
      await _folderService.deleteFolder(folder.id);
      if (!mounted) return;
      final removedIds = _collectDescendantIds(folder.id);
      setState(() {
        _expandedFolderIds.removeAll(removedIds);
        _allFolders.removeWhere((f) => removedIds.contains(f.id));
        // Backend orphans docs inside deleted folders back to root
        _allDocuments = _allDocuments.map((d) {
          if (d.folderId != null && removedIds.contains(d.folderId)) {
            return DocumentModel(
              id: d.id, title: d.title, documentType: d.documentType,
              fileName: d.fileName, filePath: d.filePath,
              parsedText: d.parsedText, isPrivate: d.isPrivate,
              uploadedBy: d.uploadedBy, isShared: d.isShared,
              folderId: null,
            );
          }
          return d;
        }).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _showMoveFolderDialog(FolderModel folder) async {
    final result = await MoveToFolderDialog.show(context,
        folderService: _folderService, excludeFolderId: folder.id);
    if (result == null || !mounted) return;
    try {
      await _folderService.moveFolder(folder.id,
          newParentId: result == 'root' ? null : result);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating));
    }
  }

  Widget _buildSpeedDial() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedOpacity(
          opacity: _fabExpanded ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !_fabExpanded,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _SpeedDialItem(
                  icon: Icons.refresh_rounded,
                  label: 'Refresh',
                  onTap: () {
                    setState(() => _fabExpanded = false);
                    _refresh();
                  },
                ),
                const SizedBox(height: 10),
                _SpeedDialItem(
                  icon: Icons.create_new_folder_outlined,
                  label: 'New Folder',
                  onTap: () {
                    setState(() => _fabExpanded = false);
                    _showCreateFolderDialog();
                  },
                ),
                const SizedBox(height: 10),
                _SpeedDialItem(
                  icon: Icons.upload_file_outlined,
                  label: 'Add Document',
                  onTap: () async {
                    setState(() => _fabExpanded = false);
                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppColors.bgSurface,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(16))),
                      builder: (_) => const AddDocumentScreen(),
                    );
                    _refresh();
                  },
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
        FloatingActionButton(
          onPressed: () =>
              setState(() => _fabExpanded = !_fabExpanded),
          backgroundColor: AppColors.accent,
          elevation: 4,
          child: AnimatedRotation(
            turns: _fabExpanded ? 0.125 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add_rounded,
                color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }

  // ── Build the flat search results view ──────────────────────────────────

  Widget _buildSearchResults() {
    final docs = DocumentFilterEngine.applyFilters(_allDocuments, _filter);
    if (docs.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search_off_rounded,
              size: 48, color: AppColors.bgSurface3),
          const SizedBox(height: 10),
          const Text('No documents found',
              style: TextStyle(
                  fontSize: 14, color: AppColors.textTertiary)),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 80),
      itemCount: docs.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${docs.length} result(s)',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textTertiary)),
          );
        }
        final doc = docs[i - 1];
        return _DocRow(
          doc: doc,
          depth: 0,
          searchQuery: _filter.searchQuery,
          highlightBuilder: _highlight,
          selectionMode: _selectionMode,
          isSelected: _selectedDocs.contains(doc.id),
          onTap: () => _onDocTap(doc),
          onLongPress: () => _showDocActions(doc),
          onSelectionChanged: (v) {
            setState(() {
              if (v ?? false) {
                _selectedDocs.add(doc.id);
              } else {
                _selectedDocs.remove(doc.id);
              }
            });
          },
        );
      },
    );
  }

  // ── Build the tree view ──────────────────────────────────────────────────

  List<Widget> _buildTreeItems(String? parentId, int depth) {
    final items = <Widget>[];
    final folders = _childFolders(parentId);
    final docs = _docsInFolder(parentId);

    for (final folder in folders) {
      final isExpanded = _expandedFolderIds.contains(folder.id);
      items.add(_FolderRow(
        folder: folder,
        depth: depth,
        isExpanded: isExpanded,
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedFolderIds.remove(folder.id);
            } else {
              _expandedFolderIds.add(folder.id);
            }
          });
        },
        onLongPress: () => _showFolderActions(folder),
      ));
      if (isExpanded) {
        items.addAll(_buildTreeItems(folder.id, depth + 1));
      }
    }

    for (final doc in docs) {
      items.add(_DocRow(
        doc: doc,
        depth: depth,
        searchQuery: '',
        highlightBuilder: _highlight,
        selectionMode: _selectionMode,
        isSelected: _selectedDocs.contains(doc.id),
        onTap: () => _onDocTap(doc),
        onLongPress: () => _showDocActions(doc),
        onSelectionChanged: (v) {
          setState(() {
            if (v ?? false) {
              _selectedDocs.add(doc.id);
            } else {
              _selectedDocs.remove(doc.id);
            }
          });
        },
      ));
    }

    return items;
  }

  void _onDocTap(DocumentModel doc) {
    if (_selectionMode) {
      setState(() {
        if (_selectedDocs.contains(doc.id)) {
          _selectedDocs.remove(doc.id);
        } else {
          _selectedDocs.add(doc.id);
        }
      });
      return;
    }
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => DocumentDetailsScreen(
            document: doc, searchQuery: _filter.searchQuery),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _showDocActions(DocumentModel doc) {
    final currentUser =
        Supabase.instance.client.auth.currentUser?.email;
    final isOwner = doc.uploadedBy == currentUser;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(doc.title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(doc.documentType,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary)),
            const SizedBox(height: 14),
            const Divider(height: 0, thickness: 0.5),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.textPrimary),
              title: const Text('Rename',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              enabled: isOwner,
              onTap: isOwner
                  ? () {
                      Navigator.pop(context);
                      _showRename(doc);
                    }
                  : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.category_outlined,
                  size: 18, color: AppColors.textPrimary),
              title: const Text('Edit document type',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _showEditType(doc);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                  Icons.drive_file_move_outline,
                  size: 18,
                  color: AppColors.textPrimary),
              title: const Text('Move to folder',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              enabled: isOwner,
              onTap: isOwner
                  ? () {
                      Navigator.pop(context);
                      _showMoveDocDialog(doc);
                    }
                  : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AppColors.dangerText),
              title: const Text('Delete',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppColors.dangerText,
                      fontWeight: FontWeight.w500)),
              enabled: isOwner,
              onTap: isOwner
                  ? () {
                      Navigator.pop(context);
                      _deleteDoc(doc);
                    }
                  : null,
            ),
            const Divider(height: 0, thickness: 0.5),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.close_rounded,
                  size: 18, color: AppColors.textPrimary),
              title: const Text('Cancel',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showFolderActions(FolderModel folder) {
    final currentUser =
        Supabase.instance.client.auth.currentUser?.email;
    final isOwner = folder.createdBy == currentUser;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(folder.name,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            const Text('Folder',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary)),
            const SizedBox(height: 14),
            const Divider(height: 0, thickness: 0.5),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.create_new_folder_outlined,
                  size: 18, color: AppColors.textPrimary),
              title: const Text('New subfolder',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _showCreateFolderDialog(parentId: folder.id);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.textPrimary),
              title: const Text('Rename',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              enabled: isOwner,
              onTap: isOwner
                  ? () {
                      Navigator.pop(context);
                      _showRenameFolder(folder);
                    }
                  : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                  Icons.drive_file_move_outline,
                  size: 18,
                  color: AppColors.textPrimary),
              title: const Text('Move folder',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              enabled: isOwner,
              onTap: isOwner
                  ? () {
                      Navigator.pop(context);
                      _showMoveFolderDialog(folder);
                    }
                  : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AppColors.dangerText),
              title: const Text('Delete',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppColors.dangerText,
                      fontWeight: FontWeight.w500)),
              enabled: isOwner,
              onTap: isOwner
                  ? () {
                      Navigator.pop(context);
                      _deleteFolderConfirm(folder);
                    }
                  : null,
            ),
            const Divider(height: 0, thickness: 0.5),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.close_rounded,
                  size: 18, color: AppColors.textPrimary),
              title: const Text('Cancel',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _filter.searchQuery.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: AppColors.bgSurface,
              padding:
                  const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (!_selectionMode && Navigator.canPop(context))
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(Icons.arrow_back_ios_new_rounded,
                                size: 18, color: AppColors.textPrimary),
                          ),
                        ),
                      if (_selectionMode)
                        Expanded(
                          child: Text(
                              '${_selectedDocs.length} selected',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                        )
                      else
                        const Expanded(
                          child: Text('Documents',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.3)),
                        ),
                      if (_selectionMode)
                        TextButton.icon(
                          onPressed: (_selectedDocs.isEmpty ||
                                  _isDeleting)
                              ? null
                              : _deleteSelected,
                          icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                              color: AppColors.dangerText),
                          label: const Text('Delete',
                              style: TextStyle(
                                  color: AppColors.dangerText,
                                  fontSize: 12)),
                        ),
                      TextButton(
                        onPressed: _isDeleting
                            ? null
                            : () => setState(() {
                                  _selectionMode = !_selectionMode;
                                  _selectedDocs.clear();
                                }),
                        child: Text(
                            _selectionMode ? 'Cancel' : 'Select',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                  if (!_isDeleting) ...[
                    const SizedBox(height: 10),
                    ClaudeSearchBar(
                      controller: _searchCtrl,
                      hintText: 'Search documents…',
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(
                            const Duration(milliseconds: 350), () {
                          setState(() =>
                              _filter.setSearchQuery(v.trim()));
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    FilterChipRow(
                      filters: _docTypes,
                      selected:
                          _filter.selectedDocumentType ?? 'All',
                      onSelected: (t) => setState(() =>
                          _filter.setDocumentType(
                              t == 'All' ? null : t)),
                    ),
                  ],
                ],
              ),
            ),

            const Divider(
                height: 0,
                thickness: 0.5,
                color: AppColors.border),

            Expanded(
              child: _isDeleting
                  ? DeletingOverlay(
                      current: _deleteProgress,
                      total: _deleteTotal)
                  : _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.accent,
                              strokeWidth: 2))
                      : isSearching
                          ? _buildSearchResults()
                          : RefreshIndicator(
                              onRefresh: _refresh,
                              color: AppColors.accent,
                              child: _buildTree(),
                            ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          _isDeleting ? null : _buildSpeedDial(),
    );
  }

  Widget _buildTree() {
    final items = _buildTreeItems(null, 0);
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.folder_open_outlined,
              size: 48, color: AppColors.bgSurface3),
          const SizedBox(height: 10),
          const Text('No folders or documents yet',
              style: TextStyle(
                  fontSize: 14, color: AppColors.textTertiary)),
        ]),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 80),
      children: items,
    );
  }
}

// ── Folder Row ────────────────────────────────────────────────────────────────

class _FolderRow extends StatelessWidget {
  final FolderModel folder;
  final int depth;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FolderRow({
    required this.folder,
    required this.depth,
    required this.isExpanded,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: EdgeInsets.only(
          left: 12.0 + depth * 20.0,
          right: 16,
          top: 9,
          bottom: 9,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: AppColors.border.withOpacity(0.5),
                width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Chevron
            AnimatedRotation(
              turns: isExpanded ? 0.25 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 6),
            // Folder icon
            Icon(
              isExpanded
                  ? Icons.folder_open_outlined
                  : Icons.folder_outlined,
              size: 18,
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
          ],
        ),
      ),
    );
  }
}

// ── Document Row ──────────────────────────────────────────────────────────────

class _DocRow extends StatelessWidget {
  final DocumentModel doc;
  final int depth;
  final String searchQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selectionMode;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectionChanged;
  final Widget Function(String, String, {int maxLines}) highlightBuilder;

  const _DocRow({
    required this.doc,
    required this.depth,
    required this.searchQuery,
    required this.onTap,
    required this.onLongPress,
    required this.selectionMode,
    required this.isSelected,
    required this.onSelectionChanged,
    required this.highlightBuilder,
  });

  IconData _fileIcon(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image_outlined;
      case 'docx':
      case 'doc':
        return Icons.description_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ext = doc.fileName?.split('.').last;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: isSelected
            ? AppColors.accentBg
            : Colors.transparent,
        padding: EdgeInsets.only(
          left: 12.0 + depth * 20.0,
          right: 16,
          top: 8,
          bottom: 8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Indent spacer for chevron alignment
            const SizedBox(width: 24),
            // File icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.accentBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_fileIcon(ext),
                  size: 15, color: AppColors.accent),
            ),
            const SizedBox(width: 10),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          doc.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selectionMode)
                        Checkbox(
                          value: isSelected,
                          onChanged: onSelectionChanged,
                          activeColor: AppColors.accent,
                          side: const BorderSide(
                              color: AppColors.border2,
                              width: 0.5),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(doc.documentType,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary)),
                  if (doc.uploadedBy != null && doc.uploadedBy!.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      doc.uploadedBy ==
                              Supabase.instance.client.auth.currentUser?.email
                          ? 'Owner: Me'
                          : 'Owner: ${doc.uploadedBy}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (doc.isPrivate)
                        _Badge(
                            label: 'Private',
                            bg: AppColors.pendingBg,
                            fg: AppColors.pendingText),
                      if (doc.isShared) ...[
                        if (doc.isPrivate)
                          const SizedBox(width: 4),
                        _Badge(
                            label: 'Shared',
                            bg: AppColors.inProgressBg,
                            fg: AppColors.inProgressText),
                      ],
                    ],
                  ),
                  if (searchQuery.isNotEmpty &&
                      doc.parsedText != null &&
                      doc.parsedText!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    DefaultTextStyle(
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          height: 1.4),
                      child: highlightBuilder(
                          doc.parsedText!, searchQuery,
                          maxLines: 2),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _Badge(
      {required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(label,
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: fg)),
    );
  }
}

// ── Speed Dial Item ───────────────────────────────────────────────────────────

class _SpeedDialItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SpeedDialItem(
      {required this.icon,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary)),
        ),
        const SizedBox(width: 10),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onTap,
          backgroundColor: AppColors.bgSurface,
          elevation: 3,
          child: Icon(icon, size: 20, color: AppColors.accent),
        ),
      ],
    );
  }
}