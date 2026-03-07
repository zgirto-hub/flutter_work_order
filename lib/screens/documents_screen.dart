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
  List<DocumentModel> _documents = [];

  bool _selectionMode = false;
  final Set<String> _selectedDocuments = {};

  final DocumentService _service = DocumentService();

  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;
  String _currentSearch = "";

  @override
  void initState() {
    super.initState();
    _refreshDocuments();
  }

  // 🔄 Load documents
  Future<void> _refreshDocuments() async {
    final docs = await _service.fetchDocuments();

    if (!mounted) return;

    setState(() {
      _documents = docs;
    });
  }

  // 🔎 Highlight search
  Widget highlightText(String text, String query, {int maxLines = 4}) {
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
      final index = text.toLowerCase().indexOf(query.toLowerCase(), start);

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

  // 🗑 Delete single
  Future<void> _deleteDocument(String id) async {
    await _service.deleteDocument(id);
    _refreshDocuments();
  }

  @override
  Widget build(BuildContext context) {
    final documents = _documents;
    final int resultCount = documents.length;

    return Stack(
      children: [
        Column(
          children: [
            // SELECT BUTTON
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

            // SEARCH BAR
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

                  _debounce = Timer(const Duration(milliseconds: 400), () async {
                    if (value.isEmpty) {
                      final docs = await _service.fetchDocuments();

                      if (!mounted) return;

                      setState(() {
                        _currentSearch = "";
                        _documents = docs;
                      });
                    } else {
                      final docs =
                          await _service.searchDocuments(value.trim());

                      if (!mounted) return;

                      setState(() {
                        _currentSearch = value.trim();
                        _documents = docs;
                      });
                    }
                  });
                },
              ),
            ),

            // RESULT COUNT
            if (_currentSearch.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "$resultCount document(s) found",
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

            // DOCUMENT LIST
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshDocuments,
                child: documents.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 200),
                          Center(
                            child: Text(
                              _currentSearch.isEmpty
                                  ? "No documents available"
                                  : "No documents found for \"$_currentSearch\"",
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: documents.length,
                        itemBuilder: (context, index) {
                          final doc = documents[index];

                          return AnimatedContainer(
  duration: const Duration(milliseconds: 220),
  curve: Curves.easeOut,
  margin: const EdgeInsets.only(bottom: 12),
  child: Card(
    elevation: 2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

      leading: const Icon(
        Icons.description_outlined,
        size: 28,
        color: Colors.blueGrey,
      ),

      title: Text(
        doc.title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),

      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Text(
              doc.documentType,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 6),

            if (doc.parsedText != null && doc.parsedText!.isNotEmpty)
              highlightText(
                doc.parsedText!,
                _currentSearch,
                maxLines: 4,
              ),

          ],
        ),
      ),

      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DocumentDetailsScreen(
              document: doc,
              searchQuery: _currentSearch,
            ),
          ),
        );
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
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _deleteDocument(doc.id);
                  },
                ),

                const Divider(),

                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text("Cancel"),
                  onTap: () => Navigator.pop(context),
                ),

              ],
            ),
          ),
        );
      },
    ),
  ),
);
                        },
                      ),
              ),
            ),
          ],
        ),

        // ADD BUTTON
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
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