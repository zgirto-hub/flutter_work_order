import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final Widget Function(String text, String query, {int maxLines})
      highlightBuilder;

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
    final currentUser =
        Supabase.instance.client.auth.currentUser?.email;

    final isOwner = document.uploadedBy == currentUser;

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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

          /// Document icon + indicators
          leading: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.description_outlined,
                size: 24,
                color: Colors.blueGrey,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (document.isPrivate)
                    const Tooltip(
                      message: "Private document",
                      child: Icon(
                        Icons.lock,
                        size: 14,
                        color: Colors.orange,
                      ),
                    ),
                  if (isOwner)
                    const Padding(
                      padding: EdgeInsets.only(left: 3),
                      child: Tooltip(
                        message: "Owned by you",
                        child: Icon(
                          Icons.person,
                          size: 14,
                          color: Colors.green,
                        ),
                      ),
                    ),
                ],
              ),
            ],
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
                if (document.parsedText != null &&
                    document.parsedText!.isNotEmpty)
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

                          /// Rename
                          ListTile(
                            leading: const Icon(Icons.edit),
                            title: const Text("Rename"),
                            enabled: isOwner,
                            onTap: isOwner
                                ? () {
                                    Navigator.pop(context);
                                    onRename();
                                  }
                                : null,
                          ),

                          /// Edit type
                          ListTile(
                            leading:
                                const Icon(Icons.category_outlined),
                            title:
                                const Text("Edit document type"),
                            onTap: () {
                              Navigator.pop(context);
                              onEditType();
                            },
                          ),

                          /// Delete
                          ListTile(
                            leading: const Icon(
                              Icons.delete,
                              color: Colors.red,
                            ),
                            title: const Text(
                              "Delete",
                              style: TextStyle(color: Colors.red),
                            ),
                            enabled: isOwner,
                            onTap: isOwner
                                ? () {
                                    Navigator.pop(context);
                                    onDelete();
                                  }
                                : null,
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