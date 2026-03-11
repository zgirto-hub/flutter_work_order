import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/filter_controller.dart';
import '../../filters/document_filter_engine.dart';
import '../../models/document.dart';
import '../../services/document_service.dart';
import '../../widgets/active_filters_row.dart';
import '../../widgets/animated_entity_list.dart';
import '../../widgets/document_card.dart';
import '../../widgets/search_appbar.dart';
import '../Documents/add_document_screen.dart';
import '../Documents/document_details_screen.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  List<DocumentModel> _documents = [];

  bool _selectionMode = false;
  final Set<String> _selectedDocuments = {};
  final FilterController filterController = FilterController();
  final DocumentService _service = DocumentService();

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _refreshDocuments();
  }

  List<String> getDocumentTypes() {
    final types = _documents.map((doc) => doc.documentType).toSet().toList();
    types.sort();
    return ["All", ...types];
  }

  Future<void> _refreshDocuments() async {
    final docs = await _service.fetchDocuments();
    if (!mounted) return;

    setState(() {
      _documents = docs;
      _selectedDocuments.removeWhere(
        (selectedId) => !_documents.any((doc) => doc.id == selectedId),
      );
    });
  }

  Widget highlightText(String text, String query, {int maxLines = 4}) {
    if (query.isEmpty) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);

      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }

      spans.add(
        TextSpan(
          text: text.substring(index, index + lowerQuery.length),
          style: const TextStyle(
            backgroundColor: Colors.yellow,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      start = index + query.length;
    }

    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(color: Colors.black),
        children: spans,
      ),
    );
  }

  Widget buildActiveFiltersRow() {
    final List<Widget> chips = [];

    if (filterController.searchQuery.isNotEmpty) {
      chips.add(
        FilterChip(
          label: Text("🔍 ${filterController.searchQuery}"),
          onSelected: (_) {
            setState(() {
              filterController.setSearchQuery("");
              _searchController.clear();
            });
          },
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox();

    chips.add(
      TextButton(
        onPressed: () {
          setState(() {
            filterController.clearAll();
            _searchController.clear();
          });
        },
        child: const Text("Clear"),
      ),
    );

    return ActiveFiltersRow(chips: chips);
  }

  void _showRenameDialog(DocumentModel doc) {
    final controller = TextEditingController(text: doc.title);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Rename Document"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "New Title"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              await _service.renameDocument(doc.id, controller.text);
              if (!mounted) return;
              Navigator.pop(context);
              _refreshDocuments();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showEditDocumentTypeDialog(DocumentModel doc) {
    final controller = TextEditingController(text: doc.documentType);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Document Type"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Document Type"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              await _service.updateDocumentType(doc.id, controller.text);
              if (!mounted) return;
              Navigator.pop(context);
              _refreshDocuments();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDocument(String id) async {
    await _service.deleteDocument(id);
    _refreshDocuments();
  }

  Future<void> _deleteSelectedDocuments() async {
    if (_selectedDocuments.isEmpty) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Selected Documents'),
        content: Text(
          'Delete ${_selectedDocuments.length} selected document(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    final idsToDelete = _selectedDocuments.toList();
    for (final id in idsToDelete) {
      await _service.deleteDocument(id);
    }

    if (!mounted) return;

    setState(() {
      _selectionMode = false;
      _selectedDocuments.clear();
    });

    await _refreshDocuments();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${idsToDelete.length} document(s) deleted')),
    );
  }

  Widget buildDocumentTypeFilters() {
    final types = getDocumentTypes();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: types.map((type) {
            final isSelected =
                filterController.selectedDocumentType == type ||
                (type == "All" && filterController.selectedDocumentType == null);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (type == "All") {
                      filterController.setDocumentType(null);
                    } else {
                      filterController.setDocumentType(type);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final documents = DocumentFilterEngine.applyFilters(
      _documents,
      filterController,
    );
    final int resultCount = documents.length;

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_selectionMode)
                    Text(
                      '${_selectedDocuments.length} selected',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  Row(
                    children: [
                      if (_selectionMode)
                        TextButton.icon(
                          onPressed: _selectedDocuments.isEmpty
                              ? null
                              : _deleteSelectedDocuments,
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text(
                            'Delete Selected',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectionMode = !_selectionMode;
                            _selectedDocuments.clear();
                          });
                        },
                        child: Text(_selectionMode ? 'Cancel' : 'Select'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SearchAppBar(
                controller: _searchController,
                hintText: 'Search Document...',
                onChanged: (value) {
                  if (_debounce?.isActive ?? false) _debounce!.cancel();

                  _debounce = Timer(const Duration(milliseconds: 400), () {
                    setState(() {
                      filterController.setSearchQuery(value.trim());
                    });
                  });
                },
              ),
            ),
            if (filterController.searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$resultCount document(s) found',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            buildDocumentTypeFilters(),
            buildActiveFiltersRow(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshDocuments,
                child: documents.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 200),
                          Center(
                            child: Text(
                              filterController.searchQuery.isEmpty
                                  ? 'No documents available'
                                  : 'No documents found for "${filterController.searchQuery}"',
                            ),
                          ),
                        ],
                      )
                    : AnimatedEntityList<DocumentModel>(
                        items: documents,
                        onRefresh: _refreshDocuments,
                        itemBuilder: (context, doc, index) {
                          final isSelected = _selectedDocuments.contains(doc.id);

                          return DocumentCard(
                            document: doc,
                            searchQuery: filterController.searchQuery,
                            highlightBuilder: highlightText,
                            selectionMode: _selectionMode,
                            isSelected: isSelected,
                            onSelectionChanged: (selected) {
                              setState(() {
                                if (selected ?? false) {
                                  _selectedDocuments.add(doc.id);
                                } else {
                                  _selectedDocuments.remove(doc.id);
                                }
                              });
                            },
                            onTap: () {
                              if (_selectionMode) {
                                setState(() {
                                  if (isSelected) {
                                    _selectedDocuments.remove(doc.id);
                                  } else {
                                    _selectedDocuments.add(doc.id);
                                  }
                                });
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DocumentDetailsScreen(
                                    document: doc,
                                    searchQuery: filterController.searchQuery,
                                  ),
                                ),
                              );
                            },
                            onRename: () => _showRenameDialog(doc),
                            onEditType: () => _showEditDocumentTypeDialog(doc),
                            onDelete: () => _deleteDocument(doc.id),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
        Positioned(
  bottom: 16,
  right: 16,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [

      // 🔄 REFRESH
      FloatingActionButton(
        heroTag: "refreshDocs",
        mini: true,
        onPressed: _refreshDocuments,
        child: const Icon(Icons.refresh),
      ),

      const SizedBox(height: 10),

      // ➕ ADD DOCUMENT
      FloatingActionButton(
        heroTag: "addDoc",
        mini: true,
        onPressed: () async {
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (context) => const AddDocumentScreen(),
          );

          _refreshDocuments();
        },
        child: const Icon(Icons.add),
      ),
    ],
  ),
),
      ],
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }
}
