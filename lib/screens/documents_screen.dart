import 'package:flutter/material.dart';
import 'dart:async';

import '../models/document.dart';
import '../services/document_service.dart';
import 'document_details_screen.dart';
import 'add_document_screen.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  bool _selectionMode = false;
final Set<String> _selectedDocuments = {};
  final DocumentService _service = DocumentService();

  late Future<List<DocumentModel>> _documentsFuture;

  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;
  String _currentSearch = "";

  @override
  void initState() {
    super.initState();
    _documentsFuture = _service.fetchDocuments();
  }

  // 🔎 Highlight with max 4 lines
  Widget highlightText(
    String text,
    String query, {
    int maxLines = 4,
  }) {
    if (query.isEmpty) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = text.indexOf(query, start);

      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }

      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
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

  // 🔄 Refresh list
  Future<void> _refreshDocuments() async {
    setState(() {
      _documentsFuture = _service.fetchDocuments();
    });
  }

  // ✏ Rename
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
              Navigator.pop(context);
              _refreshDocuments();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // 🗑 Delete
  Future<void> _deleteDocument(String id) async {
    await _service.deleteDocument(id);
    _refreshDocuments();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
  children: [

    // SELECT / CANCEL BUTTON
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [

          if (_selectionMode)
            Text(
              "${_selectedDocuments.length} selected",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

          TextButton(
            onPressed: () {
              setState(() {
                _selectionMode = !_selectionMode;
                _selectedDocuments.clear();
              });
            },
            child: Text(_selectionMode ? "Cancel" : "Select"),
          ),
        ],
      ),
    ),
            // 🔎 SEARCH BAR
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "Search documents...",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  if (_debounce?.isActive ?? false) _debounce!.cancel();

                  _debounce = Timer(
                    const Duration(milliseconds: 400),
                    () {
                      if (value.isEmpty) {
                        setState(() {
                          _currentSearch = "";
                          _documentsFuture = _service.fetchDocuments();
                        });
                      } else {
                        setState(() {
                          _currentSearch = value.trim();
                          _documentsFuture =
                              _service.searchDocuments(_currentSearch);
                        });
                      }
                    },
                  );
                },
              ),
            ),

            // 📄 DOCUMENT LIST
            Expanded(
              child: FutureBuilder<List<DocumentModel>>(
                future: _documentsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text("Error loading documents"),
                    );
                  }

                  final documents = snapshot.data ?? [];
                  final int resultCount = documents.length;

                  if (documents.isEmpty) {
                    return Center(
                      child: Text(
                        _currentSearch.isEmpty
                            ? "No documents available"
                            : "No documents found for \"$_currentSearch\"",
                      ),
                    );
                  }

                  return Column(
                    children: [
                      if (_currentSearch.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "$resultCount document(s) found",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                        if (_selectionMode && _selectedDocuments.isNotEmpty)
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.delete),
        label: const Text("Delete Selected"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amberAccent,
        ),
        onPressed: () async {

  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Confirm Delete"),
        content: Text(
          "Are you sure you want to delete ${_selectedDocuments.length} document(s)?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
         /* ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),*/
          ElevatedButton(
  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
  onPressed: () => Navigator.pop(context, true),
  child: const Text("Delete"),
)
        ],
      );
    },
  );

  if (confirm == true) {
    for (var id in _selectedDocuments) {
      await _service.deleteDocument(id);
    }

    setState(() {
      _selectedDocuments.clear();
      _selectionMode = false;
    });

    _refreshDocuments();
  }
},
      ),
    ),
  ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refreshDocuments,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: documents.length,
                            itemBuilder: (context, index) {
                              final doc = documents[index];

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  leading: _selectionMode
                                  ? Checkbox(
                                      value: _selectedDocuments.contains(doc.id),
                                      onChanged: (value) {
                                        setState(() {
                                          if (value == true) {
                                            _selectedDocuments.add(doc.id);
                                          } else {
                                            _selectedDocuments.remove(doc.id);
                                          }
                                        });
                                      },
                                    )
                                  : const Icon(Icons.description),
                                  title: Text(doc.title),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        doc.documentType,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      if (doc.parsedText != null)
                                        SizedBox(
                                          width: double.infinity,
                                          child: highlightText(
                                            doc.parsedText ?? "",
                                            _currentSearch,
                                            maxLines: 4,
                                          ),
                                        ),
                                    ],
                                  ),
                                  onTap: () {
                                          if (_selectionMode) {
                                            setState(() {
                                              if (_selectedDocuments.contains(doc.id)) {
                                                _selectedDocuments.remove(doc.id);
                                              } else {
                                                _selectedDocuments.add(doc.id);
                                              }
                                            });
                                                } else {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => DocumentDetailsScreen(
                                                        document: doc,
                                                        searchQuery: _currentSearch,
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                  onLongPress: () {
                                    showModalBottomSheet(
                                      context: context,
                                      builder: (_) => SafeArea(
                                        child: Wrap(
                                          children: [
                                            ListTile(
                                              leading: const Icon(Icons.edit),
                                              title: const Text("Rename"),
                                              onTap: () {
                                                Navigator.pop(context);
                                                _showRenameDialog(doc);
                                              },
                                            ),
                                            ListTile(
                                              leading: const Icon(
                                                Icons.delete,
                                                color: Colors.red,
                                              ),
                                              title: const Text(
                                                "Delete",
                                                style: TextStyle(
                                                    color: Colors.red),
                                              ),
                                              onTap: () async {
                                                Navigator.pop(context);
                                                await _deleteDocument(doc.id);
                                              },
                                            ),
                                            ListTile(
                                              leading: const Icon(Icons.close),
                                              title: const Text("Cancel"),
                                              onTap: () =>
                                                  Navigator.pop(context),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),

        // ➕ FLOATING BUTTON
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AddDocumentScreen(),
                ),
              );

              if (result == true) {
                _refreshDocuments();
              }
            },
            child: const Icon(Icons.add),
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
