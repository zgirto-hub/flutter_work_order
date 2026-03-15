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
import '../../widgets/document_card.dart';
import '../../widgets/folder_card.dart';
import '../../widgets/move_to_folder_dialog.dart';
import '../../widgets/breadcrumb_row.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/deleting_overlay.dart';
import '../../widgets/folder_tree_view.dart';
import '../Documents/add_document_screen.dart';
import '../Documents/document_details_screen.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  List<DocumentModel> _allDocuments = [];
  List<FolderModel> _currentFolders = [];
  List<FolderModel> _breadcrumb = []; // navigation stack
  String? _currentFolderId;           // null = root

  final FilterController _filter = FilterController();
  final DocumentService _service = DocumentService();
  final FolderService _folderService = FolderService();
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _selectedDocs = {};
  Timer? _debounce;
  bool _selectionMode = false;
  bool _treeMode = false;
  int _folderVersion = 0; // incremented after any folder mutation to force FolderTreeView rebuild

  // Delete progress
  bool _isDeleting = false;
  int _deleteProgress = 0;
  int _deleteTotal = 0;
  bool _fabExpanded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final docs = await _service.fetchDocuments();
    final folders = await _folderService.fetchFolders(parentId: _currentFolderId);
    if (!mounted) return;
    setState(() {
      _allDocuments = docs;
      _currentFolders = folders;
      _selectedDocs.removeWhere((id) => !_allDocuments.any((d) => d.id == id));
    });
  }

  // ── Folder navigation ──────────────────────────────────────────────────────

  void _enterFolder(FolderModel folder) {
    setState(() {
      _breadcrumb.add(folder);
      _currentFolderId = folder.id;
      _treeMode = false; // always switch to list view after navigating into a folder
    });
    _refresh();
  }

  void _navigateToLevel(int index) {
    // index == -1 → root
    setState(() {
      if (index == -1) {
        _breadcrumb = [];
        _currentFolderId = null;
      } else {
        _breadcrumb = _breadcrumb.sublist(0, index + 1);
        _currentFolderId = _breadcrumb.last.id;
      }
    });
    _refresh();
  }

  // ── Document types for filter chips ───────────────────────────────────────

  List<String> get _docTypes {
    final types = _allDocuments.map((d) => d.documentType).toSet().toList()..sort();
    return ['All', ...types];
  }

  // ── Search highlight ───────────────────────────────────────────────────────

  Widget _highlight(String text, String query, {int maxLines = 2}) {
    if (query.isEmpty) return Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    final lText = text.toLowerCase(), lQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final idx = lText.indexOf(lQuery, start);
      if (idx == -1) { spans.add(TextSpan(text: text.substring(start))); break; }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(backgroundColor: Color(0xFFFEF08A), fontWeight: FontWeight.w500),
      ));
      start = idx + query.length;
    }
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4), children: spans),
    );
  }

  // ── Delete selected documents ──────────────────────────────────────────────

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

    int deleted = 0, blocked = 0;

    for (final id in ids) {
      try {
        await _service.deleteDocument(id);
        deleted++;
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
      _selectedDocs.clear();
    });

    await _refresh();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(blocked == 0
          ? '$deleted document(s) deleted'
          : '$deleted deleted, $blocked skipped (not owner)'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: blocked == 0 ? AppColors.closedText : AppColors.pendingText,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Document actions ───────────────────────────────────────────────────────

  void _showRename(DocumentModel doc) {
    final ctrl = TextEditingController(text: doc.title);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Rename document', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: TextField(controller: ctrl, style: const TextStyle(fontSize: 13), decoration: const InputDecoration(labelText: 'Title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Edit document type', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: TextField(controller: ctrl, style: const TextStyle(fontSize: 13), decoration: const InputDecoration(labelText: 'Document type')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
      builder: (_) => ConfirmDialog(title: 'Delete "${doc.title}"?', message: 'This action cannot be undone.', confirmLabel: 'Delete'),
    );
    if (confirm != true) return;
    try {
      await _service.deleteDocument(doc.id);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _showMoveDocDialog(DocumentModel doc) async {
    final result = await MoveToFolderDialog.show(
      context,
      folderService: _folderService,
    );
    if (result == null || !mounted) return;
    try {
      await _folderService.moveDocument(doc.id, folderId: result == 'root' ? null : result);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating));
    }
  }

  // ── Folder actions ─────────────────────────────────────────────────────────

  void _showCreateFolderDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('New folder', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(labelText: 'Folder name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              try {
                await _folderService.createFolder(name: name, parentId: _currentFolderId);
                if (!mounted) return;
                Navigator.pop(context);
                setState(() => _folderVersion++);
                _refresh();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Folder "$name" created'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.closedText,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Failed to create folder: $e'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.dangerText,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ));
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameFolder(FolderModel folder) {
    final ctrl = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Rename folder', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: TextField(controller: ctrl, style: const TextStyle(fontSize: 13), decoration: const InputDecoration(labelText: 'Folder name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              await _folderService.renameFolder(folder.id, name);
              if (!mounted) return;
              Navigator.pop(context);
              setState(() => _folderVersion++);
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
        message: 'Documents inside will be moved to root. Sub-folders will be deleted.',
        confirmLabel: 'Delete',
      ),
    );
    if (confirm != true) return;
    try {
      await _folderService.deleteFolder(folder.id);
      setState(() => _folderVersion++);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _showMoveFolderDialog(FolderModel folder) async {
    final result = await MoveToFolderDialog.show(
      context,
      folderService: _folderService,
      excludeFolderId: folder.id,
    );
    if (result == null || !mounted) return;
    try {
      await _folderService.moveFolder(folder.id, newParentId: result == 'root' ? null : result);
      setState(() => _folderVersion++);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating));
    }
  }

  // ── Speed-dial FAB ─────────────────────────────────────────────────────────

  Widget _buildSpeedDial() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Child actions
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
                  onTap: () { setState(() => _fabExpanded = false); _refresh(); },
                ),
                const SizedBox(height: 10),
                _SpeedDialItem(
                  icon: Icons.create_new_folder_outlined,
                  label: 'New Folder',
                  onTap: () { setState(() => _fabExpanded = false); _showCreateFolderDialog(); },
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
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
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
        // Main toggle button
        FloatingActionButton(
          onPressed: () => setState(() => _fabExpanded = !_fabExpanded),
          backgroundColor: AppColors.accent,
          elevation: 4,
          child: AnimatedRotation(
            turns: _fabExpanded ? 0.125 : 0.0, // 45° when expanded
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isSearching = _filter.searchQuery.isNotEmpty;

    // When searching: global across all documents. When browsing: current folder only.
    final docsForView = isSearching
        ? _allDocuments
        : _allDocuments.where((d) => d.folderId == _currentFolderId).toList();

    final docs = DocumentFilterEngine.applyFilters(docsForView, _filter);

    return PopScope(
      canPop: _breadcrumb.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _breadcrumb.isNotEmpty) {
          _navigateToLevel(_breadcrumb.length - 2);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [

              // Header
              Container(
                color: AppColors.bgSurface,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (_selectionMode)
                          Expanded(child: Text('${_selectedDocs.length} selected',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)))
                        else
                          const Expanded(child: Text('Documents',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: -0.3))),
                        if (_selectionMode)
                          TextButton.icon(
                            onPressed: (_selectedDocs.isEmpty || _isDeleting) ? null : _deleteSelected,
                            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.dangerText),
                            label: const Text('Delete', style: TextStyle(color: AppColors.dangerText, fontSize: 12)),
                          ),
                        if (!_selectionMode && !_isDeleting)
                          IconButton(
                            onPressed: () => setState(() => _treeMode = !_treeMode),
                            icon: Icon(
                              _treeMode ? Icons.list_rounded : Icons.account_tree_outlined,
                              size: 18,
                              color: _treeMode ? AppColors.accent : AppColors.textSecondary,
                            ),
                            tooltip: _treeMode ? 'List view' : 'Tree view',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        TextButton(
                          onPressed: _isDeleting ? null : () => setState(() { _selectionMode = !_selectionMode; _selectedDocs.clear(); }),
                          child: Text(_selectionMode ? 'Cancel' : 'Select',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ),
                      ],
                    ),

                    // Search + filters (hidden while deleting)
                    if (!_isDeleting) ...[
                      const SizedBox(height: 10),
                      ClaudeSearchBar(
                        controller: _searchCtrl,
                        hintText: 'Search documents…',
                        onChanged: (v) {
                          _debounce?.cancel();
                          _debounce = Timer(const Duration(milliseconds: 350), () {
                            setState(() => _filter.setSearchQuery(v.trim()));
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      FilterChipRow(
                        filters: _docTypes,
                        selected: _filter.selectedDocumentType ?? 'All',
                        onSelected: (t) => setState(() => _filter.setDocumentType(t == 'All' ? null : t)),
                      ),
                    ],
                  ],
                ),
              ),

              // Breadcrumb (hidden when searching or deleting)
              if (!isSearching && !_isDeleting && _breadcrumb.isNotEmpty)
                BreadcrumbRow(
                  breadcrumb: _breadcrumb,
                  onTapRoot: () => _navigateToLevel(-1),
                  onTapLevel: (i) => _navigateToLevel(i),
                ),

              if (!_isDeleting && _filter.searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${docs.length} result(s)',
                        style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ),
                ),

              const Divider(height: 0, thickness: 0.5, color: AppColors.border),

              // Body
              Expanded(
                child: _isDeleting
                    ? DeletingOverlay(current: _deleteProgress, total: _deleteTotal)
                    : _treeMode
                        ? FolderTreeView(
                            folderService: _folderService,
                            version: _folderVersion,
                            onFolderTap: _enterFolder,
                            onRename: _showRenameFolder,
                            onDelete: _deleteFolderConfirm,
                            onMove: _showMoveFolderDialog,
                          )
                    : (_currentFolders.isEmpty && docs.isEmpty)
                        ? Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(
                                isSearching ? Icons.search_off_rounded : Icons.folder_open_outlined,
                                size: 48, color: AppColors.bgSurface3,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                isSearching
                                    ? 'No documents found'
                                    : _breadcrumb.isEmpty
                                        ? 'No folders or documents yet'
                                        : 'This folder is empty',
                                style: const TextStyle(fontSize: 14, color: AppColors.textTertiary),
                              ),
                            ]),
                          )
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            color: AppColors.accent,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 80),
                              itemCount: isSearching
                                  ? docs.length
                                  : _currentFolders.length + docs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                // Folders first (only when not searching)
                                if (!isSearching && i < _currentFolders.length) {
                                  final folder = _currentFolders[i];
                                  return FolderCard(
                                    folder: folder,
                                    onTap: () => _enterFolder(folder),
                                    onRename: () => _showRenameFolder(folder),
                                    onDelete: () => _deleteFolderConfirm(folder),
                                    onMove: () => _showMoveFolderDialog(folder),
                                    selectionMode: _selectionMode,
                                  );
                                }
                                final doc = docs[isSearching ? i : i - _currentFolders.length];
                                return DocumentCard(
                                  document: doc,
                                  searchQuery: _filter.searchQuery,
                                  highlightBuilder: _highlight,
                                  selectionMode: _selectionMode,
                                  isSelected: _selectedDocs.contains(doc.id),
                                  onSelectionChanged: (v) {
                                    setState(() {
                                      if (v ?? false) { _selectedDocs.add(doc.id); } else { _selectedDocs.remove(doc.id); }
                                    });
                                  },
                                  onTap: () {
                                    if (_selectionMode) {
                                      setState(() {
                                        if (_selectedDocs.contains(doc.id)) { _selectedDocs.remove(doc.id); } else { _selectedDocs.add(doc.id); }
                                      });
                                      return;
                                    }
                                    Navigator.push(context, PageRouteBuilder(
                                      transitionDuration: const Duration(milliseconds: 220),
                                      pageBuilder: (_, __, ___) => DocumentDetailsScreen(document: doc, searchQuery: _filter.searchQuery),
                                      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
                                    ));
                                  },
                                  onRename: () => _showRename(doc),
                                  onEditType: () => _showEditType(doc),
                                  onMove: () => _showMoveDocDialog(doc),
                                  onDelete: () => _deleteDoc(doc),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
        floatingActionButton: _isDeleting ? null : _buildSpeedDial(),
      ),
    );
  }
}


class _SpeedDialItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SpeedDialItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
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
