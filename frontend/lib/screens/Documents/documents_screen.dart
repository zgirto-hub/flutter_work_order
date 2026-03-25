import 'dart:async';
import 'dart:convert';
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import '../../controllers/filter_controller.dart';
import '../../filters/document_filter_engine.dart';
import '../../models/document.dart';
import '../../models/folder_model.dart';
import '../../services/document_service.dart';
import '../../services/folder_service.dart';
import '../../theme/app_theme.dart';
import '../../config.dart';
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

  // Currently selected folder id. null = "All files" root
  String? _selectedFolderId;

  // Which folders are expanded in the sidebar
  final Set<String> _expandedSidebarFolders = {};

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
  bool _homeExpanded = true;
  bool _loading = true;
  bool _navigatingForward = true;
  String _userRole = '';
  double _sidebarWidth = 116.0;

  String get _currentEmail =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  List<DocumentModel> get _visibleDocuments {
    if (_userRole == 'reporter') {
      return _allDocuments.where((d) => d.uploadedBy == _currentEmail).toList();
    }
    return _allDocuments;
  }

  List<FolderModel> get _visibleFolders {
    if (_userRole == 'reporter') {
      return _allFolders.where((f) => f.createdBy == _currentEmail).toList();
    }
    return _allFolders;
  }

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    if (_docCache != null && _folderCache != null) {
      _allDocuments = _docCache!;
      _allFolders = _folderCache!;
      _loading = false;
      _refresh(silent: true);
    } else {
      _refresh();
    }
  }

  Future<void> _loadUserRole() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null) return;
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/user-role?email=${Uri.encodeComponent(email)}'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() => _userRole = data['user_type'] ?? 'admin');
      }
    } catch (_) {}
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
    for (final f in _visibleFolders.where((f) => f.parentId == folderId)) {
      ids.addAll(_collectDescendantIds(f.id));
    }
    return ids;
  }

  List<FolderModel> _childFolders(String? parentId) {
    return _visibleFolders
        .where((f) => f.parentId == parentId)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<String> get _docTypes {
    final types = _visibleDocuments.map((d) => d.documentType).toSet().toList()
      ..sort();
    return ['All', ...types];
  }

  // ── New sidebar helpers ────────────────────────────────────────────────────

  Set<String> _descendantIds(String folderId) =>
      _collectDescendantIds(folderId);

  List<DocumentModel> _docsForSelectedFolder() {
    if (_selectedFolderId == null) return _visibleDocuments;
    final scope = {_selectedFolderId!, ..._descendantIds(_selectedFolderId!)};
    return _visibleDocuments.where((d) => scope.contains(d.folderId)).toList();
  }

  List<FolderModel> _breadcrumbPath() {
    if (_selectedFolderId == null) return [];
    final path = <FolderModel>[];
    String? id = _selectedFolderId;
    while (id != null) {
      final f = _visibleFolders.firstWhereOrNull((f) => f.id == id);
      if (f == null) break;
      path.insert(0, f);
      id = f.parentId;
    }
    return path;
  }

  int _folderDepth(String? folderId) {
    if (folderId == null) return 0;
    int depth = 0;
    String? id = folderId;
    while (id != null) {
      final f = _visibleFolders.firstWhereOrNull((f) => f.id == id);
      if (f == null) break;
      depth++;
      id = f.parentId;
    }
    return depth;
  }

  void _navigateTo(String? folderId) {
    final newDepth = _folderDepth(folderId);
    final currentDepth = _folderDepth(_selectedFolderId);
    setState(() {
      _navigatingForward = newDepth >= currentDepth;
      _selectedFolderId = folderId;
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _moveSelected() async {
    final result = await MoveToFolderDialog.show(context,
        folderService: _folderService);
    if (result == null || !mounted) return;

    final ids = _selectedDocs.toList();
    int moved = 0;
    int failed = 0;
    for (final id in ids) {
      try {
        await _folderService.moveDocument(id,
            folderId: result == 'root' ? null : result);
        moved++;
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedDocs.clear();
    });
    await _refresh(silent: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed == 0
          ? '$moved document(s) moved'
          : '$moved moved, $failed failed'),
      behavior: SnackBarBehavior.floating,
      backgroundColor:
          failed == 0 ? AppColors.closedText : AppColors.pendingText,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
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
        title: Text('Rename document',
            style:
                TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: TextField(
            controller: ctrl,
            style: TextStyle(fontSize: 13),
            decoration: InputDecoration(labelText: 'Title')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                await _service.renameDocument(doc.id, ctrl.text);
              } catch (_) {
                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Failed to rename document'),
                  behavior: SnackBarBehavior.floating,
                ));
                return;
              }
              if (!mounted) return;
              Navigator.pop(context);
              _refresh();
            },
            child: Text('Save'),
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
            title: Text('New folder',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: TextStyle(fontSize: 13),
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Folder name',
                    errorText: duplicate
                        ? 'A folder with this name already exists'
                        : null,
                  ),
                ),
                SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.border, width: 0.5),
                  ),
                  child: SwitchListTile(
                    dense: true,
                    title: Text('Private folder',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary)),
                    subtitle: Text('Only you can see this',
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
                  child: Text('Cancel')),
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
                              _expandedSidebarFolders.add(parentId);
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
                child: Text('Create'),
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
        title: Text('Rename folder',
            style:
                TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: TextField(
            controller: ctrl,
            style: TextStyle(fontSize: 13),
            decoration:
                InputDecoration(labelText: 'Folder name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final n = ctrl.text.trim();
              if (n.isEmpty) return;
              try {
                await _folderService.renameFolder(folder.id, n);
              } catch (_) {
                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Failed to rename folder'),
                  behavior: SnackBarBehavior.floating,
                ));
                return;
              }
              if (!mounted) return;
              Navigator.pop(context);
              _refresh();
            },
            child: Text('Save'),
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
        _expandedSidebarFolders.removeAll(removedIds);
        if (removedIds.contains(_selectedFolderId)) {
          _selectedFolderId = null;
        }
        _allFolders.removeWhere((f) => removedIds.contains(f.id));
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

  // ── Speed dial ────────────────────────────────────────────────────────────

  Widget _buildSpeedDial() {
    final fabColor =
        Theme.of(context).floatingActionButtonTheme.backgroundColor ??
            AppColors.accent;

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
                  color: fabColor,
                  onTap: () {
                    setState(() => _fabExpanded = false);
                    _refresh();
                  },
                ),
                SizedBox(height: 10),
                _SpeedDialItem(
                  icon: Icons.create_new_folder_outlined,
                  label: 'New Folder',
                  color: fabColor,
                  onTap: () {
                    setState(() => _fabExpanded = false);
                    _showCreateFolderDialog();
                  },
                ),
                SizedBox(height: 10),
                _SpeedDialItem(
                  icon: Icons.upload_file_outlined,
                  label: 'Add Document',
                  color: fabColor,
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
                SizedBox(height: 14),
              ],
            ),
          ),
        ),
        FloatingActionButton(
          onPressed: () =>
              setState(() => _fabExpanded = !_fabExpanded),
          backgroundColor: fabColor,
          elevation: 4,
          child: AnimatedRotation(
            turns: _fabExpanded ? 0.125 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.add_rounded,
                color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }

  // ── Search results ────────────────────────────────────────────────────────

  Widget _buildSearchResults() {
    final docs = DocumentFilterEngine.applyFilters(_visibleDocuments, _filter);
    if (docs.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off_rounded,
              size: 48, color: AppColors.bgSurface3),
          SizedBox(height: 10),
          Text('No documents found',
              style: TextStyle(
                  fontSize: 14, color: AppColors.textTertiary)),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 80),
      itemCount: docs.length + 1,
      separatorBuilder: (_, __) => SizedBox(height: 6),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${docs.length} result(s)',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textTertiary)),
          );
        }
        final doc = docs[i - 1];
        return _DocCard(
          doc: doc,
          onTap: () => _onDocTap(doc),
          onLongPress: () => _showDocActions(doc),
          selectionMode: _selectionMode,
          isSelected: _selectedDocs.contains(doc.id),
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

  // ── Doc tap ───────────────────────────────────────────────────────────────

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

  // ── Doc actions ───────────────────────────────────────────────────────────

  void _showDocActions(DocumentModel doc) {
    final caps = DocumentCapabilities.fromRole(doc.role);
    final currentUser = Supabase.instance.client.auth.currentUser?.email;
    final folderName = _visibleFolders
        .firstWhereOrNull((f) => f.id == doc.folderId)
        ?.name ?? 'Root';

    final roleLabel = doc.role ?? 'viewer';
    Color roleBg, roleFg;
    switch (doc.role) {
      case 'owner':
        roleBg = const Color(0xFFEAF3DE); roleFg = const Color(0xFF3B6D11); break;
      case 'editor':
        roleBg = const Color(0xFFE8F0FB); roleFg = const Color(0xFF185FA5); break;
      default:
        roleBg = const Color(0xFFF1EFE8); roleFg = const Color(0xFF5F5E5A);
    }

    final actions = [
      _DocAction(
        icon: Icons.visibility_outlined,
        label: 'Open / Download',
        desc: 'Always available',
        enabled: true,
        danger: false,
        onTap: () {
          Navigator.pop(context);
          _onDocTap(doc);
        },
      ),
      _DocAction(
        icon: Icons.edit_outlined,
        label: 'Rename',
        desc: caps.canRename ? 'You can rename' : 'Requires editor or owner',
        enabled: caps.canRename,
        danger: false,
        onTap: caps.canRename ? () { Navigator.pop(context); _showRename(doc); } : null,
      ),
      _DocAction(
        icon: Icons.drive_file_move_outline,
        label: 'Move to folder',
        desc: caps.canMove ? 'You can move' : 'Requires editor or owner',
        enabled: caps.canMove,
        danger: false,
        onTap: caps.canMove ? () { Navigator.pop(context); _showMoveDocDialog(doc); } : null,
      ),
      _DocAction(
        icon: Icons.share_outlined,
        label: 'Manage access',
        desc: caps.canShare ? 'Add or change roles' : 'Owner only',
        enabled: caps.canShare,
        danger: false,
        onTap: caps.canShare ? () { Navigator.pop(context); /* open share sheet */ } : null,
      ),
      _DocAction(
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        desc: caps.canDelete ? 'Permanently remove' : 'Owner only',
        enabled: caps.canDelete,
        danger: true,
        onTap: caps.canDelete ? () { Navigator.pop(context); _deleteDoc(doc); } : null,
      ),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Handle ──────────────────────────────────────────
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2)),
            ),

            // ── Sheet header row ─────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Owner',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                      SizedBox(height: 2),
                      Text(
                        doc.uploadedBy == currentUser
                            ? 'You'
                            : (doc.uploadedBy?.split('@').first ?? '—'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Your role',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                    SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: roleBg,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(roleLabel,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: roleFg)),
                    ),
                  ],
                ),
              ],
            ),

            SizedBox(height: 14),
            Divider(height: 0, thickness: 0.5, color: AppColors.border),
            SizedBox(height: 12),

            // ── Folder illustration + meta ───────────────────────
            Row(
              children: [
                Container(
                  width: 48, height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(10),
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Icon(Icons.folder_outlined,
                      size: 20, color: AppColors.textTertiary),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    folderName,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (doc.fileSize != null)
                  Text(
                    doc.fileSize! < 1024 * 1024
                        ? '${(doc.fileSize! / 1024).toStringAsFixed(0)} KB'
                        : '${(doc.fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
              ],
            ),

            SizedBox(height: 16),
            Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // ── Action rows ──────────────────────────────────────
            ...actions.map((a) => _buildActionRow(a)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(_DocAction a) {
    return Opacity(
      opacity: a.enabled ? 1.0 : 0.38,
      child: InkWell(
        onTap: a.enabled ? a.onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: a.danger
                      ? const Color(0xFFFEF2F2)
                      : AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(a.icon,
                    size: 15,
                    color: a.danger
                        ? const Color(0xFFDC2626)
                        : AppColors.textSecondary),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: a.danger
                                ? const Color(0xFFDC2626)
                                : AppColors.textPrimary)),
                    Text(a.desc,
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (a.enabled && !a.danger)
                Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  // ── Folder actions ────────────────────────────────────────────────────────

  void _showFolderActions(FolderModel folder) {
    final currentUser =
        Supabase.instance.client.auth.currentUser?.email;
    final isOwner = folder.createdBy == currentUser;
    final canEdit = isOwner || (_userRole == 'admin' && !folder.isPrivate);
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
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            SizedBox(height: 4),
            Text('Folder',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary)),
            SizedBox(height: 14),
            Divider(height: 0, thickness: 0.5),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.create_new_folder_outlined,
                  size: 18, color: AppColors.textPrimary),
              title: Text('New subfolder',
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
              leading: Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.textPrimary),
              title: Text('Rename',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              enabled: canEdit,
              onTap: canEdit
                  ? () {
                      Navigator.pop(context);
                      _showRenameFolder(folder);
                    }
                  : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                  Icons.drive_file_move_outline,
                  size: 18,
                  color: AppColors.textPrimary),
              title: Text('Move folder',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              enabled: canEdit,
              onTap: canEdit
                  ? () {
                      Navigator.pop(context);
                      _showMoveFolderDialog(folder);
                    }
                  : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AppColors.dangerText),
              title: Text('Delete',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppColors.dangerText,
                      fontWeight: FontWeight.w500)),
              enabled: canEdit,
              onTap: canEdit
                  ? () {
                      Navigator.pop(context);
                      _deleteFolderConfirm(folder);
                    }
                  : null,
            ),
            Divider(height: 0, thickness: 0.5),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.close_rounded,
                  size: 18, color: AppColors.textPrimary),
              title: Text('Cancel',
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

  // ── Permissions overview ──────────────────────────────────────────────────

  void _showPermissionsOverview() {
    int ownerCount = 0, editorCount = 0, viewerCount = 0;
    for (final doc in _visibleDocuments) {
      switch (doc.role) {
        case 'owner':  ownerCount++;  break;
        case 'editor': editorCount++; break;
        case 'viewer': viewerCount++; break;
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.85,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Permissions overview',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Icon(Icons.close_rounded,
                          size: 13, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 0, thickness: 0.5, color: AppColors.border),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  Row(
                    children: [
                      _StatCard(label: 'owner',  count: ownerCount),
                      SizedBox(width: 8),
                      _StatCard(label: 'editor', count: editorCount),
                      SizedBox(width: 8),
                      _StatCard(label: 'viewer', count: viewerCount),
                    ],
                  ),
                  SizedBox(height: 14),
                  Text('ALL DOCUMENTS',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textTertiary,
                          letterSpacing: 0.06)),
                  SizedBox(height: 8),
                  ..._visibleDocuments
                      .where((d) => d.role != null)
                      .map((doc) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              children: [
                                Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                    color: AppColors.accentBg,
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Icon(
                                      Icons.insert_drive_file_outlined,
                                      size: 14,
                                      color: AppColors.accent),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(doc.title,
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.textPrimary),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      Text(
                                        _visibleFolders
                                                .firstWhereOrNull(
                                                    (f) => f.id == doc.folderId)
                                                ?.name ??
                                            'Root',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                _RolePill(role: doc.role!),
                              ],
                            ),
                          )),
                  SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Folder permissions are inherited — editor access on a folder gives you rename & move rights on all documents inside it and its sub-folders.',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isSearching = _filter.searchQuery.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Divider(
                height: 0, thickness: 0.5, color: AppColors.border),
            Expanded(
              child: _isDeleting
                  ? DeletingOverlay(
                      current: _deleteProgress, total: _deleteTotal)
                  : _loading
                      ? Center(
                          child: CircularProgressIndicator(
                              color: AppColors.accent, strokeWidth: 2))
                      : Row(
                          children: [
                            _buildFolderSidebar(),
                            MouseRegion(
                              cursor: SystemMouseCursors.resizeColumn,
                              child: GestureDetector(
                                onHorizontalDragUpdate: (details) {
                                  setState(() {
                                    _sidebarWidth = (_sidebarWidth + details.delta.dx).clamp(60.0, 280.0);
                                  });
                                },
                                child: Container(
                                  width: 8,
                                  color: Colors.transparent,
                                  child: Center(
                                    child: Container(
                                      width: 0.5,
                                      color: AppColors.border,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: isSearching
                                  ? _buildSearchResults()
                                  : PageTransitionSwitcher(
                                      duration: const Duration(milliseconds: 280),
                                      reverse: !_navigatingForward,
                                      transitionBuilder: (child, animation, secondaryAnimation) =>
                                          SharedAxisTransition(
                                            animation: animation,
                                            secondaryAnimation: secondaryAnimation,
                                            transitionType: SharedAxisTransitionType.horizontal,
                                            child: child,
                                          ),
                                      child: KeyedSubtree(
                                        key: ValueKey(_selectedFolderId),
                                        child: _buildDocsArea(),
                                      ),
                                    ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isDeleting ? null : _buildSpeedDial(),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              if (!_selectionMode && Navigator.canPop(context))
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 34, height: 34,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppColors.border2, width: 0.5),
                    ),
                    child: Icon(Icons.arrow_back_rounded,
                        size: 16, color: AppColors.textSecondary),
                  ),
                ),
              if (_selectionMode)
                Expanded(
                  child: Text(
                      '${_selectedDocs.length} selected',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                )
              else
                Expanded(
                  child: Text('Documents',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3)),
                ),
              if (!_selectionMode) ...[
                GestureDetector(
                  onTap: _showPermissionsOverview,
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border2, width: 0.5),
                    ),
                    child: Icon(Icons.lock_outline_rounded,
                        size: 15, color: AppColors.textSecondary),
                  ),
                ),
                SizedBox(width: 6),
              ],
              if (_selectionMode) ...[
                TextButton.icon(
                  onPressed: (_selectedDocs.isEmpty || _isDeleting)
                      ? null
                      : _moveSelected,
                  icon: Icon(
                      Icons.drive_file_move_outline,
                      size: 16,
                      color: AppColors.accent),
                  label: Text('Move',
                      style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 12)),
                ),
                TextButton.icon(
                  onPressed: (_selectedDocs.isEmpty || _isDeleting)
                      ? null
                      : _deleteSelected,
                  icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: AppColors.dangerText),
                  label: Text('Delete',
                      style: TextStyle(
                          color: AppColors.dangerText,
                          fontSize: 12)),
                ),
              ],
              TextButton(
                onPressed: _isDeleting
                    ? null
                    : () => setState(() {
                          _selectionMode = !_selectionMode;
                          _selectedDocs.clear();
                        }),
                child: Text(
                    _selectionMode ? 'Cancel' : 'Select',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary)),
              ),
            ],
          ),
          if (!_isDeleting) ...[
            SizedBox(height: 10),
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
            SizedBox(height: 10),
            FilterChipRow(
              filters: _docTypes,
              selected:
                  _filter.selectedDocumentType ?? 'All',
              onSelected: (t) => setState(() =>
                  _filter.setDocumentType(
                      t == 'All' ? null : t)),
            ),
            SizedBox(height: 6),
            FilterChipRow(
              filters: const ['All', 'Expired', 'Expiring soon', 'Active'],
              selected: _filter.expirationFilter == null
                  ? 'All'
                  : _filter.expirationFilter == 'expired'
                      ? 'Expired'
                      : _filter.expirationFilter == 'expiring_soon'
                          ? 'Expiring soon'
                          : 'Active',
              onSelected: (t) => setState(() {
                switch (t) {
                  case 'Expired':
                    _filter.setExpirationFilter('expired');
                    break;
                  case 'Expiring soon':
                    _filter.setExpirationFilter('expiring_soon');
                    break;
                  case 'Active':
                    _filter.setExpirationFilter('active');
                    break;
                  default:
                    _filter.setExpirationFilter(null);
                }
              }),
            ),
          ],
        ],
      ),
    );
  }

  // ── Folder sidebar ────────────────────────────────────────────────────────

  Widget _buildFolderSidebar() {
    return SizedBox(
      width: _sidebarWidth,
      child: Container(
        color: AppColors.bgSurface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Home row — collapses/expands everything below
            GestureDetector(
              onTap: () => setState(() => _homeExpanded = !_homeExpanded),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                color: Colors.transparent,
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: _homeExpanded ? 0.25 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(Icons.chevron_right_rounded,
                          size: 13, color: AppColors.textTertiary),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.home_outlined, size: 13, color: AppColors.textTertiary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Home',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_homeExpanded) ...[
              _SidebarFolderRow(
                label: 'All files',
                depth: 0,
                isActive: _selectedFolderId == null,
                isExpanded: false,
                hasChildren: false,
                isPrivate: false,
                isShared: false,
                onTap: () => _navigateTo(null),
                onChevronTap: null,
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: _buildSidebarNodes(null, 0),
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSidebarNodes(String? parentId, int depth) {
    return _childFolders(parentId).map((folder) {
      final hasKids = _childFolders(folder.id).isNotEmpty;
      final isExpanded = _expandedSidebarFolders.contains(folder.id);
      final isActive = _selectedFolderId == folder.id;

      return _SidebarFolderNode(
        key: ValueKey(folder.id),
        folder: folder,
        depth: depth,
        isActive: isActive,
        isExpanded: isExpanded,
        hasChildren: hasKids,
        onTap: () => _navigateTo(folder.id),
        onToggle: hasKids
            ? () => setState(() {
                  if (isExpanded) {
                    _expandedSidebarFolders.remove(folder.id);
                  } else {
                    _expandedSidebarFolders.add(folder.id);
                  }
                })
            : null,
        onLongPress: () => _showFolderActions(folder),
        children: _buildSidebarNodes(folder.id, depth + 1),
      );
    }).toList();
  }

  // ── Docs area ─────────────────────────────────────────────────────────────

  Widget _buildDocsArea() {
    final crumbs = _breadcrumbPath();
    final subFolders = _childFolders(_selectedFolderId);
    final docs = _docsForSelectedFolder();

    return RefreshIndicator(
      onRefresh: () => _refresh(silent: true),
      color: AppColors.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 80),
        children: [
          // ── Breadcrumb ──────────────────────────────────────────────────
          if (crumbs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                children: [
                  GestureDetector(
                    onTap: () => _navigateTo(null),
                    child: Text('All files',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ),
                  ...crumbs.map((f) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(' › ',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.textSecondary)),
                      GestureDetector(
                        onTap: () => _navigateTo(f.id),
                        child: Text(
                          f.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: crumbs.last.id == f.id
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontWeight: crumbs.last.id == f.id
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  )),
                ],
              ),
            ),

          // ── Subfolder chips ─────────────────────────────────────────────
          if (subFolders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: subFolders.map((f) => GestureDetector(
                  onTap: () {
                    _expandedSidebarFolders.add(f.id);
                    _navigateTo(f.id);
                  },
                  onLongPress: () => _showFolderActions(f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_outlined,
                            size: 13, color: AppColors.accent),
                        SizedBox(width: 6),
                        Text(f.name,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                )).toList(),
              ),
            ),

          // ── Document cards ──────────────────────────────────────────────
          if (docs.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 28),
              child: Center(
                child: Text('No documents here',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textTertiary)),
              ),
            )
          else
            ...docs.map((doc) => _DocCard(
              doc: doc,
              onTap: () => _onDocTap(doc),
              onLongPress: () => _showDocActions(doc),
              selectionMode: _selectionMode,
              isSelected: _selectedDocs.contains(doc.id),
              onSelectionChanged: (v) => setState(() {
                if (v ?? false) {
                  _selectedDocs.add(doc.id);
                } else {
                  _selectedDocs.remove(doc.id);
                }
              }),
            )),
        ],
      ),
    );
  }
}

// ── Sidebar Folder Row ────────────────────────────────────────────────────────

class _SidebarFolderRow extends StatelessWidget {
  final String label;
  final int depth;
  final bool isActive;
  final bool isExpanded;
  final bool hasChildren;
  final bool isPrivate;
  final bool isShared;
  final VoidCallback onTap;
  final VoidCallback? onChevronTap;
  final VoidCallback? onLongPress;

  const _SidebarFolderRow({
    required this.label,
    required this.depth,
    required this.isActive,
    required this.isExpanded,
    required this.hasChildren,
    required this.isPrivate,
    required this.isShared,
    required this.onTap,
    required this.onChevronTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final leftPad = 10.0 + depth * 12.0;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: isActive ? AppColors.bgSurface2 : Colors.transparent,
          border: isActive
              ? const Border(
                  left: BorderSide(color: AppColors.accent, width: 2),
                )
              : null,
        ),
        padding: EdgeInsets.only(left: leftPad, right: 8),
        child: Row(
          children: [
            GestureDetector(
              onTap: onChevronTap,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 14,
                height: 34,
                child: hasChildren
                    ? AnimatedRotation(
                        turns: isExpanded ? 0.25 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(Icons.chevron_right_rounded,
                            size: 13, color: AppColors.textTertiary),
                      )
                    : SizedBox(),
              ),
            ),
            SizedBox(width: 4),
            Icon(
              isActive ? Icons.folder_rounded : Icons.folder_outlined,
              size: 13,
              color: isPrivate
                  ? AppColors.accent
                  : isShared
                      ? const Color(0xFF378ADD)
                      : AppColors.textTertiary,
            ),
            SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isActive
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight:
                      isActive ? FontWeight.w500 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isPrivate)
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
              )
            else if (isShared)
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: Color(0xFF378ADD),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Sidebar Folder Node (row + animated children) ─────────────────────────────

class _SidebarFolderNode extends StatelessWidget {
  final FolderModel folder;
  final int depth;
  final bool isActive;
  final bool isExpanded;
  final bool hasChildren;
  final List<Widget> children;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  final VoidCallback onLongPress;

  const _SidebarFolderNode({
    super.key,
    required this.folder,
    required this.depth,
    required this.isActive,
    required this.isExpanded,
    required this.hasChildren,
    required this.children,
    required this.onTap,
    required this.onToggle,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SidebarFolderRow(
          label: folder.name,
          depth: depth,
          isActive: isActive,
          isExpanded: isExpanded,
          hasChildren: hasChildren,
          isPrivate: folder.isPrivate,
          isShared: false,
          onTap: onTap,
          onChevronTap: onToggle,
          onLongPress: onLongPress,
        ),
        if (hasChildren)
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: isExpanded ? children : const [],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Document Card ─────────────────────────────────────────────────────────────

class _DocCard extends StatelessWidget {
  final DocumentModel doc;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selectionMode;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectionChanged;

  const _DocCard({
    required this.doc,
    required this.onTap,
    required this.onLongPress,
    required this.selectionMode,
    required this.isSelected,
    required this.onSelectionChanged,
  });

  IconData _fileIcon(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'pdf': return Icons.picture_as_pdf_outlined;
      case 'jpg': case 'jpeg': case 'png': return Icons.image_outlined;
      case 'docx': case 'doc': return Icons.description_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  Color _iconColor(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'pdf': return AppColors.accent;
      case 'jpg': case 'jpeg': case 'png': return const Color(0xFF3B6D11);
      case 'docx': case 'doc': return const Color(0xFF185FA5);
      default: return AppColors.textTertiary;
    }
  }

  Color _iconBg(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'pdf': return AppColors.accentBg;
      case 'jpg': case 'jpeg': case 'png': return const Color(0xFFEAF3DE);
      case 'docx': case 'doc': return const Color(0xFFE6F1FB);
      default: return AppColors.bgSurface2;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final ext = doc.fileName?.split('.').last;
    final role = doc.role;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentBg : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: _iconBg(ext),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(_fileIcon(ext), size: 16, color: _iconColor(ext)),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          doc.title,
                          style: TextStyle(
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
                          side: BorderSide(
                              color: AppColors.border2, width: 0.5),
                        ),
                    ],
                  ),
                  SizedBox(height: 3),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      if (role != null)
                        _RolePill(role: role),
                      if (doc.isPrivate)
                        _Pill(
                            label: 'private',
                            bg: AppColors.accentBg,
                            fg: Color(0xFF993C1D)),
                      if (doc.isShared && role == 'owner')
                        _Pill(
                            label: 'shared',
                            bg: AppColors.inProgressBg,
                            fg: AppColors.inProgressText),
                      if (doc.fileSize != null)
                        Text(
                          _formatSize(doc.fileSize!),
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!selectionMode)
              Icon(Icons.chevron_right_rounded,
                  size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ── Role Pill ─────────────────────────────────────────────────────────────────

class _RolePill extends StatelessWidget {
  final String role;
  const _RolePill({required this.role});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (role) {
      case 'owner':
        bg = const Color(0xFFEAF3DE);
        fg = const Color(0xFF3B6D11);
        break;
      case 'editor':
        bg = const Color(0xFFE8F0FB);
        fg = const Color(0xFF185FA5);
        break;
      default:
        bg = const Color(0xFFF1EFE8);
        fg = const Color(0xFF5F5E5A);
    }
    return _Pill(label: role, bg: bg, fg: fg);
  }
}

// ── Pill ──────────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  _Pill({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w500, color: fg)),
    );
  }
}

// ── Stat Card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  const _StatCard({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgSurface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text('$count',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary)),
            SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ── Speed Dial Item ───────────────────────────────────────────────────────────

class _SpeedDialItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SpeedDialItem(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white)),
        ),
        SizedBox(width: 10),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onTap,
          backgroundColor: color,
          elevation: 4,
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ],
    );
  }
}

// ── Doc Action Data ───────────────────────────────────────────────────────────

class _DocAction {
  final IconData icon;
  final String label;
  final String desc;
  final bool enabled;
  final bool danger;
  final VoidCallback? onTap;

  const _DocAction({
    required this.icon,
    required this.label,
    required this.desc,
    required this.enabled,
    required this.danger,
    required this.onTap,
  });
}
