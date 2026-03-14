import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/document.dart';
import '../theme/app_theme.dart';

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

  IconData _fileIcon(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'pdf': return Icons.picture_as_pdf_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png': return Icons.image_outlined;
      case 'docx':
      case 'doc': return Icons.description_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser?.email;
    final isOwner = document.uploadedBy == currentUser;

    return GestureDetector(
      onTap: onTap,
      onLongPress: selectionMode
          ? null
          : () {
              showModalBottomSheet(
                context: context,
                backgroundColor: AppColors.bgSurface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (_) => _DocActionSheet(
                  document: document,
                  isOwner: isOwner,
                  onRename: () { Navigator.pop(context); onRename(); },
                  onEditType: () { Navigator.pop(context); onEditType(); },
                  onDelete: () { Navigator.pop(context); onDelete(); },
                ),
              );
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentBg : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.accent.withOpacity(0.3) : AppColors.border,
            width: isSelected ? 1 : 0.5,
          ),
        ),
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── File icon ─────────────────────────────────────
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.accentBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_fileIcon(document.fileName?.split('.').last), size: 17, color: AppColors.accent),
            ),

            const SizedBox(width: 12),

            // ── Content ───────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Title + selection
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          document.title,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selectionMode)
                        Checkbox(
                          value: isSelected,
                          onChanged: onSelectionChanged,
                          activeColor: AppColors.accent,
                          side: const BorderSide(color: AppColors.border2, width: 0.5),
                        ),
                    ],
                  ),

                  const SizedBox(height: 2),

                  // Type
                  Text(document.documentType, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),

                  const SizedBox(height: 4),

                  // Badges row
                  Row(
                    children: [
                      if (document.isPrivate) _DocBadge(label: 'Private', color: AppColors.pendingBg, textColor: AppColors.pendingText),
                      if (document.isShared) ...[
                        if (document.isPrivate) const SizedBox(width: 4),
                        _DocBadge(label: 'Shared', color: AppColors.inProgressBg, textColor: AppColors.inProgressText),
                      ],
                      if (isOwner) ...[
                        if (document.isPrivate || document.isShared) const SizedBox(width: 4),
                        _DocBadge(label: 'Mine', color: AppColors.closedBg, textColor: AppColors.closedText),
                      ],
                    ],
                  ),

                  // Snippet
                  if (document.parsedText != null && document.parsedText!.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    DefaultTextStyle(
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4),
                      child: highlightBuilder(document.parsedText!, searchQuery, maxLines: 2),
                    ),
                  ],

                  // Shared by
                  if (document.isShared && document.uploadedBy != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Shared by ${document.uploadedBy}',
                      style: const TextStyle(fontSize: 10, color: AppColors.textTertiary, fontStyle: FontStyle.italic),
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

class _DocBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _DocBadge({required this.label, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: textColor)),
    );
  }
}

class _DocActionSheet extends StatelessWidget {
  final DocumentModel document;
  final bool isOwner;
  final VoidCallback onRename;
  final VoidCallback onEditType;
  final VoidCallback onDelete;

  const _DocActionSheet({
    required this.document,
    required this.isOwner,
    required this.onRename,
    required this.onEditType,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(document.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(document.documentType, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          const SizedBox(height: 14),
          const Divider(height: 0, thickness: 0.5),
          _ActionRow(icon: Icons.edit_outlined, label: 'Rename', enabled: isOwner, onTap: isOwner ? onRename : null),
          _ActionRow(icon: Icons.category_outlined, label: 'Edit document type', onTap: onEditType),
          _ActionRow(icon: Icons.delete_outline_rounded, label: 'Delete', enabled: isOwner, danger: true, onTap: isOwner ? onDelete : null),
          const Divider(height: 0, thickness: 0.5),
          _ActionRow(icon: Icons.close_rounded, label: 'Cancel', onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final bool danger;

  const _ActionRow({required this.icon, required this.label, this.onTap, this.enabled = true, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.dangerText : enabled ? AppColors.textPrimary : AppColors.textTertiary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 18, color: color),
      title: Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500)),
      onTap: enabled ? onTap : null,
    );
  }
}
