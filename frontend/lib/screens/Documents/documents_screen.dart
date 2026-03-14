import 'dart:async';
import 'package:flutter/material.dart';
import '../../controllers/filter_controller.dart';
import '../../filters/document_filter_engine.dart';
import '../../models/document.dart';
import '../../services/document_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import '../../widgets/document_card.dart';
import '../Documents/add_document_screen.dart';
import '../Documents/document_details_screen.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  List<DocumentModel> _documents = [];
  final FilterController _filter = FilterController();
  final DocumentService _service = DocumentService();
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _selectedDocs = {};
  Timer? _debounce;
  bool _selectionMode = false;

  // Delete progress
  bool _isDeleting = false;
  int _deleteProgress = 0;
  int _deleteTotal = 0;

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
    if (!mounted) return;
    setState(() {
      _documents = docs;
      _selectedDocs.removeWhere((id) => !_documents.any((d) => d.id == id));
    });
  }

  List<String> get _docTypes {
    final types = _documents.map((d) => d.documentType).toSet().toList()..sort();
    return ['All', ...types];
  }

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

  Future<void> _deleteSelected() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
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
      builder: (_) => _ConfirmDialog(title: 'Delete "${doc.title}"?', message: 'This action cannot be undone.', confirmLabel: 'Delete'),
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

  @override
  Widget build(BuildContext context) {
    final docs = DocumentFilterEngine.applyFilters(_documents, _filter);

    return Scaffold(
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
                      TextButton(
                        onPressed: _isDeleting ? null : () => setState(() { _selectionMode = !_selectionMode; _selectedDocs.clear(); }),
                        child: Text(_selectionMode ? 'Cancel' : 'Select',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ),
                    ],
                  ),

                  // Show progress bar in header while deleting, otherwise show search+filters
                  if (_isDeleting) ...[
                    const SizedBox(height: 10),
                    _DeleteProgressBar(current: _deleteProgress, total: _deleteTotal),
                  ] else ...[
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
                  ? _DeletingOverlay(current: _deleteProgress, total: _deleteTotal)
                  : docs.isEmpty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.description_outlined, size: 48, color: AppColors.bgSurface3),
                            const SizedBox(height: 10),
                            Text(_filter.searchQuery.isEmpty ? 'No documents yet' : 'No documents found',
                                style: const TextStyle(fontSize: 14, color: AppColors.textTertiary)),
                          ]),
                        )
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          color: AppColors.accent,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 80),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final doc = docs[i];
                              return DocumentCard(
                                document: doc,
                                searchQuery: _filter.searchQuery,
                                highlightBuilder: _highlight,
                                selectionMode: _selectionMode,
                                isSelected: _selectedDocs.contains(doc.id),
                                onSelectionChanged: (v) {
                                  setState(() {
                                    if (v ?? false) _selectedDocs.add(doc.id); else _selectedDocs.remove(doc.id);
                                  });
                                },
                                onTap: () {
                                  if (_selectionMode) {
                                    setState(() {
                                      if (_selectedDocs.contains(doc.id)) _selectedDocs.remove(doc.id); else _selectedDocs.add(doc.id);
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
                                onDelete: () => _deleteDoc(doc),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isDeleting
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClaudeFAB(icon: Icons.refresh_rounded, onTap: _refresh),
                const SizedBox(height: 10),
                ClaudeFAB(
                  onTap: () async {
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
              ],
            ),
    );
  }
}

// Delete progress bar (shown inside header)
class _DeleteProgressBar extends StatelessWidget {
  final int current;
  final int total;
  const _DeleteProgressBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0.0 : current / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Deleting $current of $total…',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            Text('${(percent * 100).toInt()}%',
                style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 5,
            backgroundColor: AppColors.bgSurface3,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.dangerText),
          ),
        ),
      ],
    );
  }
}

// Full screen overlay shown in list area while deleting
class _DeletingOverlay extends StatelessWidget {
  final int current;
  final int total;
  const _DeletingOverlay({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0.0 : current / total;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.dangerBorder, width: 0.5),
              ),
              child: const Icon(Icons.delete_sweep_outlined, size: 26, color: AppColors.dangerText),
            ),
            const SizedBox(height: 20),
            Text('Deleting $current of $total',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text('Please wait…',
                style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 7,
                backgroundColor: AppColors.bgSurface3,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.dangerText),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$current deleted', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                Text('${(percent * 100).toInt()}%',
                    style: const TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
                Text('$total total', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  const _ConfirmDialog({required this.title, required this.message, required this.confirmLabel});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      content: Text(message, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerText),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
