import 'package:flutter/material.dart';

import '../models/document.dart';

class DocumentCard extends StatelessWidget {
  final DocumentModel document;
  final String searchQuery;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onEditType;
  final VoidCallback onDelete;
  final bool selectionMode;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectionChanged;
  final Widget Function(String text, String query, {int maxLines}) highlightBuilder;

  const DocumentCard({
    super.key,
    required this.document,
    required this.searchQuery,
    required this.onTap,
    required this.onRename,
    required this.onEditType,
    required this.onDelete,
    required this.highlightBuilder,
    this.selectionMode = false,
    this.isSelected = false,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
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
          trailing: selectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: onSelectionChanged,
                )
              : null,
          title: Text(
            document.title,
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
                  document.documentType,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 6),
                if (document.parsedText != null && document.parsedText!.isNotEmpty)
                  highlightBuilder(
                    document.parsedText!,
                    searchQuery,
                    maxLines: 4,
                  ),
              ],
            ),
          ),
          onTap: onTap,
          onLongPress: selectionMode
              ? null
              : () {
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
                              onRename();
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.category_outlined),
                            title: const Text("Edit document type"),
                            onTap: () {
                              Navigator.pop(context);
                              onEditType();
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.delete, color: Colors.red),
                            title: const Text(
                              "Delete",
                              style: TextStyle(color: Colors.red),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              onDelete();
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
  }
}
